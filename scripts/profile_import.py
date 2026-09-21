#!/usr/bin/env python3
"""DataCheck preflight profiler.

Reads a legacy HR CSV export and produces a structured JSON report of what
is wrong with it, plus (optionally) a normalized intermediate CSV that the
Rails import services use for dry-run and execution.

This script does the real analytical work of the pipeline -- Rails invokes
it as a subprocess and treats its JSON output as the source of truth for
ImportIssue records. It never mutates the target database and never prints
raw PII (names, emails, salaries) to its output.

Exit codes:
  0 - profiling completed (the dataset may still contain validation issues)
  2 - the file could not be processed at all (missing columns, unreadable
      CSV, etc.) -- this is an operational failure, not a data-quality one.

Usage:
  python3 scripts/profile_import.py \\
      --csv path/to/employees.csv \\
      --known-departments-file path/to/departments.txt \\
      --known-employees-file path/to/employees.txt \\
      [--normalized-output path/to/normalized.csv]
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path

from salary_date_parsing import ParseError, is_valid_email, parse_date, parse_salary_to_cents

REQUIRED_COLUMNS = {
    "external_id",
    "first_name",
    "last_name",
    "department_external_id",
    "start_date",
    "gross_salary",
}
OPTIONAL_COLUMNS = {"email", "manager_external_id", "status"}
ALLOWED_STATUSES = {"active", "inactive", "terminated"}


def read_id_list(path: str | None) -> set[str]:
    if not path:
        return set()
    text = Path(path).read_text(encoding="utf-8")
    return {line.strip() for line in text.splitlines() if line.strip()}


def emit_error(message: str) -> None:
    print(json.dumps({"error": message}))


def profile(csv_path: str, known_departments: set[str], known_employees: set[str]) -> dict:
    with open(csv_path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError("CSV file has no header row")

        header = {name.strip() for name in reader.fieldnames}
        missing = REQUIRED_COLUMNS - header
        if missing:
            raise ValueError(f"missing required columns: {', '.join(sorted(missing))}")

        rows = list(reader)

    external_id_counts = Counter(
        (row.get("external_id") or "").strip()
        for row in rows
        if (row.get("external_id") or "").strip()
    )
    csv_external_ids = set(external_id_counts.keys())
    manager_targets = known_employees | csv_external_ids

    issues: list[dict] = []
    normalized_rows: list[dict] = []

    def add_issue(row_number, external_id, issue_type, severity, field, message):
        issues.append(
            {
                "row_number": row_number,
                "external_id": external_id or None,
                "issue_type": issue_type,
                "severity": severity,
                "field": field,
                "message": message,
            }
        )

    for index, row in enumerate(rows, start=1):
        external_id = (row.get("external_id") or "").strip()
        first_name = (row.get("first_name") or "").strip()
        last_name = (row.get("last_name") or "").strip()
        email = (row.get("email") or "").strip()
        department_external_id = (row.get("department_external_id") or "").strip()
        manager_external_id = (row.get("manager_external_id") or "").strip()
        raw_status = (row.get("status") or "").strip().lower()
        status = raw_status if raw_status in ALLOWED_STATUSES else "active"

        row_blocked = False

        if not external_id:
            add_issue(index, None, "missing_external_id", "blocking", "external_id",
                       "A stable external_id is required to safely match this record to an employee.")
            normalized_rows.append({
                "row_number": index, "external_id": "", "first_name": first_name,
                "last_name": last_name, "email": "", "department_external_id": "",
                "manager_external_id": "", "start_date": "", "gross_salary_cents": "",
                "status": status, "blocked": True,
            })
            continue

        if external_id_counts[external_id] > 1:
            row_blocked = True
            add_issue(index, external_id, "duplicate_external_id", "blocking", "external_id",
                       f"external_id appears {external_id_counts[external_id]} times in this import; "
                       "the correct record cannot be determined automatically.")

        if department_external_id and department_external_id not in known_departments:
            row_blocked = True
            add_issue(index, external_id, "unknown_department", "blocking", "department_external_id",
                       "Department reference does not exist in the target company.")

        if manager_external_id and manager_external_id not in manager_targets:
            row_blocked = True
            add_issue(index, external_id, "orphan_manager", "blocking", "manager_external_id",
                       "Manager reference does not exist in this import or the target company.")

        start_date_iso = ""
        try:
            start_date_iso, _ = parse_date(row.get("start_date") or "")
        except ParseError:
            row_blocked = True
            add_issue(index, external_id, "invalid_date", "blocking", "start_date",
                       "Start date is missing or could not be parsed as a known date format.")

        gross_salary_cents = ""
        try:
            gross_salary_cents, _ = parse_salary_to_cents(row.get("gross_salary") or "")
        except ParseError:
            row_blocked = True
            add_issue(index, external_id, "invalid_salary", "blocking", "gross_salary",
                       "Salary value is missing or could not be parsed to a monetary amount.")

        normalized_email = email
        if email and not is_valid_email(email):
            add_issue(index, external_id, "invalid_email", "warning", "email",
                       "Email format is invalid; the value was dropped rather than guessed.")
            normalized_email = ""

        normalized_rows.append({
            "row_number": index,
            "external_id": external_id,
            "first_name": first_name,
            "last_name": last_name,
            "email": normalized_email,
            "department_external_id": department_external_id,
            "manager_external_id": manager_external_id,
            "start_date": start_date_iso,
            "gross_salary_cents": gross_salary_cents,
            "status": status,
            "blocked": row_blocked,
        })

    blocking_count = sum(1 for issue in issues if issue["severity"] == "blocking")
    warning_count = sum(1 for issue in issues if issue["severity"] == "warning")
    valid_count = sum(1 for row in normalized_rows if not row["blocked"])

    return {
        "source_count": len(rows),
        "valid_count": valid_count,
        "warning_count": warning_count,
        "blocking_count": blocking_count,
        "issues": issues,
        "normalized_rows": normalized_rows,
    }


def write_normalized_csv(rows: list[dict], output_path: str) -> None:
    fieldnames = [
        "row_number", "external_id", "first_name", "last_name", "email",
        "department_external_id", "manager_external_id", "start_date",
        "gross_salary_cents", "status", "blocked",
    ]
    with open(output_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description="DataCheck preflight profiler")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--known-departments-file")
    parser.add_argument("--known-employees-file")
    parser.add_argument("--normalized-output")
    args = parser.parse_args()

    try:
        known_departments = read_id_list(args.known_departments_file)
        known_employees = read_id_list(args.known_employees_file)
        result = profile(args.csv, known_departments, known_employees)
    except FileNotFoundError as error:
        emit_error(f"file not found: {error.filename}")
        return 2
    except (ValueError, csv.Error) as error:
        emit_error(str(error))
        return 2

    if args.normalized_output:
        write_normalized_csv(result["normalized_rows"], args.normalized_output)
        result["normalized_output"] = args.normalized_output
    else:
        result["normalized_output"] = None

    output = {key: value for key, value in result.items() if key != "normalized_rows"}
    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
