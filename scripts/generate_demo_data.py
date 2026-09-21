#!/usr/bin/env python3
"""Deterministic synthetic HR data generator for DataCheck demos and tests.

Generates a clean, fully-importable employee CSV and a "bad" variant that
injects a fixed, documented set of realistic legacy-migration problems into
copies of the same underlying rows. Both files derive from one seeded random
stream so their relationship is easy to explain: same people, same seed,
different (and counted) defects.

Never touches real data -- everything here is fabricated.
"""
from __future__ import annotations

import csv
import json
import random
from pathlib import Path

from collections import Counter

from demo_reference_data import DEPARTMENT_CODES
from profile_import import profile

SEED = 20260101
EMPLOYEE_COUNT = 2000
MANAGER_COUNT = 80  # first N employees (in shuffle order) are managers

FIRST_NAMES = [
    "Ava", "Liam", "Noah", "Emma", "Oliver", "Sophia", "Elijah", "Mia",
    "Lucas", "Amelia", "Mason", "Harper", "Ethan", "Evelyn", "James",
    "Abigail", "Benjamin", "Emily", "Henry", "Ella", "Theo", "Grace",
    "Leo", "Chloe", "Sam", "Zoe", "Jack", "Lily", "Owen", "Nora",
    "Daniel", "Hazel", "Matthew", "Aria", "Aiden", "Layla", "Nathan",
    "Scarlett", "Isaac", "Victoria",
]
LAST_NAMES = [
    "Johnson", "Smith", "Williams", "Brown", "Jones", "Garcia", "Miller",
    "Davis", "Rodriguez", "Martinez", "Wilson", "Anderson", "Taylor",
    "Thomas", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
    "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson",
    "Walker", "Young", "Allen", "King", "Wright", "Scott", "Torres",
    "Nguyen", "Hill", "Flores", "Green", "Adams", "Nelson",
]

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "demo"


def make_person(random_generator: random.Random, index: int) -> dict:
    first = random_generator.choice(FIRST_NAMES)
    last = random_generator.choice(LAST_NAMES)
    department = random_generator.choice(DEPARTMENT_CODES)
    year = random_generator.randint(2016, 2025)
    month = random_generator.randint(1, 12)
    day = random_generator.randint(1, 28)
    salary = random_generator.randint(3_000_000, 12_000_000) / 100  # 30,000.00 - 120,000.00
    status = random_generator.choices(
        ["active", "active", "active", "active", "inactive", "terminated"], k=1
    )[0]

    return {
        "external_id": f"EMP-{index:05d}",
        "first_name": first,
        "last_name": last,
        "email": f"{first.lower()}.{last.lower()}{index}@example.com",
        "department_external_id": department,
        "manager_external_id": "",
        "start_date": f"{year:04d}-{month:02d}-{day:02d}",
        "gross_salary": f"{salary:.2f}",
        "status": status,
    }


def assign_managers(rng: random.Random, people: list[dict]) -> None:
    order = list(range(len(people)))
    rng.shuffle(order)
    manager_indices = order[:MANAGER_COUNT]
    managers_by_department: dict[str, list[int]] = {}
    for idx in manager_indices:
        managers_by_department.setdefault(people[idx]["department_external_id"], []).append(idx)

    manager_index_set = set(manager_indices)
    for idx, person in enumerate(people):
        if idx in manager_index_set:
            continue
        candidates = managers_by_department.get(person["department_external_id"]) or manager_indices
        manager_idx = rng.choice(candidates)
        person["manager_external_id"] = people[manager_idx]["external_id"]


def reformat_salary(amount_str: str, variant: int) -> str:
    amount = float(amount_str)
    whole = int(amount)
    cents = round((amount - whole) * 100)
    grouped = f"{whole:,d}"
    if variant == 0:
        # US-style thousands separator: 32,500.50
        return f"{grouped}.{cents:02d}"
    if variant == 1:
        # European decimal comma: 32500,50
        return f"{whole},{cents:02d}"
    # Currency-prefixed, whole-number rounded: €42,000
    return f"€{grouped}"


def reformat_date(iso_date: str, variant: int) -> str:
    year, month, day = iso_date.split("-")
    if variant == 0:
        return f"{month}/{day}/{year}"
    return f"{day}-{month}-{year}"


INVALID_DATES = ["31/02/2024", "0000-00-00", "not-a-date", "2024-13-45"]
INVALID_SALARIES = ["N/A", "-500.00", "abc", ""]
INVALID_EMAILS = ["not-an-email", "missing-at-symbol.com", "user@@example.com", "broken@"]


def build_bad_rows(rng: random.Random, clean_rows: list[dict]) -> tuple[list[dict], dict]:
    rows = [dict(row) for row in clean_rows]  # deep-enough copy (flat dicts)
    pool = list(range(len(rows)))
    rng.shuffle(pool)

    slices = {
        "duplicate_external_id": pool[0:15],
        "unknown_department": pool[15:35],
        "orphan_manager": pool[35:55],
        "invalid_date": pool[55:70],
        "missing_external_id": pool[70:80],
        "invalid_salary": pool[80:95],
        "invalid_email": pool[95:115],
        "salary_format_normalized": pool[115:155],
        "date_format_normalized": pool[155:195],
        "whitespace_normalized": pool[195:225],
    }

    for i, idx in enumerate(slices["unknown_department"]):
        rows[idx]["department_external_id"] = "DEPT-999"

    for i, idx in enumerate(slices["orphan_manager"]):
        rows[idx]["manager_external_id"] = "EMP-99999"

    for i, idx in enumerate(slices["invalid_date"]):
        rows[idx]["start_date"] = INVALID_DATES[i % len(INVALID_DATES)]

    for i, idx in enumerate(slices["missing_external_id"]):
        rows[idx]["external_id"] = ""

    for i, idx in enumerate(slices["invalid_salary"]):
        rows[idx]["gross_salary"] = INVALID_SALARIES[i % len(INVALID_SALARIES)]

    for i, idx in enumerate(slices["invalid_email"]):
        rows[idx]["email"] = INVALID_EMAILS[i % len(INVALID_EMAILS)]

    for i, idx in enumerate(slices["salary_format_normalized"]):
        rows[idx]["gross_salary"] = reformat_salary(rows[idx]["gross_salary"], i % 3)

    for i, idx in enumerate(slices["date_format_normalized"]):
        rows[idx]["start_date"] = reformat_date(rows[idx]["start_date"], i % 2)

    for idx in slices["whitespace_normalized"]:
        rows[idx]["first_name"] = f"  {rows[idx]['first_name'].upper()}  "
        rows[idx]["last_name"] = f" {rows[idx]['last_name'].lower()} "

    duplicated_rows = []
    for idx in slices["duplicate_external_id"]:
        clone = dict(rows[idx])
        # Slightly different payload so the ambiguity is realistic: which
        # version is authoritative is exactly the question we can't answer
        # automatically.
        clone["gross_salary"] = f"{float(clone['gross_salary']) + 100:.2f}"
        duplicated_rows.append(clone)

    all_rows = rows + duplicated_rows

    counts = {issue_type: len(indices) for issue_type, indices in slices.items()}
    counts["duplicate_external_id_rows_total"] = len(slices["duplicate_external_id"]) * 2
    counts["total_rows"] = len(all_rows)
    return all_rows, counts


FIELDNAMES = [
    "external_id", "first_name", "last_name", "email",
    "department_external_id", "manager_external_id",
    "start_date", "gross_salary", "status",
]


def write_csv(path: Path, rows: list[dict]) -> None:
    # csv.writer defaults to CRLF line endings per RFC 4180. This repo is
    # cross-language and these files are committed, so force LF explicitly --
    # otherwise every checked-in row shows up as a "trailing whitespace" diff
    # error in a plain Unix git config.
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def generate() -> dict:
    rng = random.Random(SEED)
    people = [make_person(rng, i) for i in range(1, EMPLOYEE_COUNT + 1)]
    assign_managers(rng, people)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    write_csv(DATA_DIR / "clean_employees.csv", people)

    bad_rows, injected_counts = build_bad_rows(rng, people)
    bad_path = DATA_DIR / "bad_employees.csv"
    write_csv(bad_path, bad_rows)

    # The preflight profiler is the source of truth for what actually gets
    # detected (a missing_external_id mutation on a manager row, for example,
    # cascades into extra orphan_manager issues for that manager's reports).
    # Re-run it here so the manifest -- and anything that asserts against it
    # -- reflects reality rather than the naive injection counts above.
    known_departments = set(DEPARTMENT_CODES)
    profiled = profile(str(bad_path), known_departments, known_employees=set())
    measured_counts = dict(Counter(issue["issue_type"] for issue in profiled["issues"]))

    manifest = {
        "seed": SEED,
        "clean_employee_count": len(people),
        "manager_count": MANAGER_COUNT,
        "bad_row_count": len(bad_rows),
        "injected_issue_counts": injected_counts,
        "measured_issue_counts": measured_counts,
        "measured_totals": {
            "source_count": profiled["source_count"],
            "valid_count": profiled["valid_count"],
            "warning_count": profiled["warning_count"],
            "blocking_count": profiled["blocking_count"],
        },
    }
    (DATA_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    result = generate()
    print(json.dumps(result, indent=2))
