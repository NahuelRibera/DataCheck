import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from profile_import import preview, profile, write_normalized_csv

FIELDNAMES = [
    "external_id", "first_name", "last_name", "email",
    "department_external_id", "manager_external_id",
    "start_date", "gross_salary", "status",
]

KNOWN_DEPARTMENTS = {"DEPT-ENG", "DEPT-SAL"}


def write_csv(rows):
    handle = tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, newline="")
    writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    handle.close()
    return handle.name


def base_row(**overrides):
    row = {
        "external_id": "EMP-001",
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
        "department_external_id": "DEPT-ENG",
        "manager_external_id": "",
        "start_date": "2024-01-01",
        "gross_salary": "50000.00",
        "status": "active",
    }
    row.update(overrides)
    return row


class ProfileImportTests(unittest.TestCase):
    def test_clean_row_has_no_issues(self):
        path = write_csv([base_row()])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["source_count"], 1)
        self.assertEqual(result["valid_count"], 1)
        self.assertEqual(result["blocking_count"], 0)
        self.assertEqual(result["warning_count"], 0)

    def test_duplicate_external_id_is_blocking(self):
        rows = [base_row(), base_row(first_name="Duplicate")]
        path = write_csv(rows)
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        issue_types = [issue["issue_type"] for issue in result["issues"]]
        self.assertEqual(issue_types.count("duplicate_external_id"), 2)
        self.assertEqual(result["blocking_count"], 2)
        self.assertEqual(result["valid_count"], 0)

    def test_unknown_department_is_blocking(self):
        path = write_csv([base_row(department_external_id="DEPT-DOES-NOT-EXIST")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "unknown_department")
        self.assertEqual(result["issues"][0]["severity"], "blocking")

    def test_orphan_manager_is_blocking(self):
        path = write_csv([base_row(manager_external_id="EMP-999")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "orphan_manager")

    def test_manager_resolves_against_known_employees(self):
        path = write_csv([base_row(manager_external_id="EMP-EXISTING")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees={"EMP-EXISTING"})
        self.assertEqual(result["blocking_count"], 0)

    def test_manager_resolves_within_same_csv(self):
        rows = [
            base_row(external_id="EMP-BOSS", manager_external_id=""),
            base_row(external_id="EMP-002", manager_external_id="EMP-BOSS"),
        ]
        path = write_csv(rows)
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["blocking_count"], 0)

    def test_invalid_date_is_blocking(self):
        path = write_csv([base_row(start_date="not-a-date")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "invalid_date")

    def test_missing_external_id_is_blocking(self):
        path = write_csv([base_row(external_id="")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "missing_external_id")

    def test_invalid_salary_is_blocking(self):
        path = write_csv([base_row(gross_salary="not-a-number")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "invalid_salary")

    def test_invalid_email_is_warning_and_dropped(self):
        path = write_csv([base_row(email="not-an-email")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["issues"][0]["issue_type"], "invalid_email")
        self.assertEqual(result["issues"][0]["severity"], "warning")
        self.assertEqual(result["valid_count"], 1)  # warning-only rows are still valid

    def test_alternate_salary_format_is_normalized_without_an_issue(self):
        path = write_csv([base_row(gross_salary="32,500.50")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        self.assertEqual(result["blocking_count"], 0)
        self.assertEqual(len(result["issues"]), 0)

    def test_issue_metadata_never_contains_raw_salary(self):
        path = write_csv([base_row(gross_salary="broken")])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        payload = str(result["issues"])
        self.assertNotIn("broken", payload)

    def test_missing_required_column_raises(self):
        handle = tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, newline="")
        handle.write("first_name,last_name\nAda,Lovelace\n")
        handle.close()
        with self.assertRaises(ValueError):
            profile(handle.name, KNOWN_DEPARTMENTS, known_employees=set())

    def test_normalized_csv_is_written(self):
        path = write_csv([base_row()])
        result = profile(path, KNOWN_DEPARTMENTS, known_employees=set())
        out = tempfile.NamedTemporaryFile(suffix=".csv", delete=False).name
        write_normalized_csv(result["normalized_rows"], out)
        with open(out) as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["gross_salary_cents"], "5000000")


class PreviewTest(unittest.TestCase):
    def test_column_profile_counts_and_types(self):
        path = write_csv([
            base_row(external_id="EMP-1", email="a@example.com", manager_external_id="M"),
            base_row(external_id="EMP-2", email="", manager_external_id="M"),
            base_row(external_id="EMP-2", email="b@example.com", manager_external_id=""),
        ])
        result = preview(path)
        columns = {column["name"]: column for column in result["columns"]}

        self.assertEqual(result["row_count"], 3)
        self.assertEqual(columns["external_id"]["distinct_count"], 2)
        self.assertEqual(columns["external_id"]["duplicate_count"], 1)
        self.assertEqual(columns["email"]["null_count"], 1)
        self.assertEqual(columns["email"]["inferred_type"], "email")
        self.assertEqual(columns["start_date"]["inferred_type"], "date")
        self.assertEqual(columns["gross_salary"]["inferred_type"], "decimal")
        self.assertEqual(columns["manager_external_id"]["null_count"], 1)

    def test_sensitive_values_are_masked_in_preview(self):
        path = write_csv([base_row()])
        result = preview(path)
        self.assertEqual(len(result["preview_rows"]), 1)
        serialized = json.dumps(result)
        for raw in ("Ada", "Lovelace", "ada@example.com", "50000.00", "EMP-001"):
            self.assertNotIn(raw, serialized)
        row = dict(zip([c["name"] for c in result["columns"]], result["preview_rows"][0]))
        self.assertEqual(row["first_name"], "***")
        self.assertEqual(row["department_external_id"], "DEPT-ENG")
        self.assertEqual(row["status"], "active")

    def test_unknown_columns_are_masked_and_missing_columns_tolerated(self):
        handle = tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False, newline="")
        handle.write("ssn,status\n123-45-6789,active\n")
        handle.close()
        result = preview(handle.name)
        self.assertEqual(result["preview_rows"], [["***", "active"]])

    def test_preview_row_limit(self):
        path = write_csv([base_row(external_id=f"EMP-{i}") for i in range(10)])
        result = preview(path, preview_rows=3)
        self.assertEqual(len(result["preview_rows"]), 3)
        self.assertEqual(result["row_count"], 10)

    def test_empty_file_is_an_error(self):
        handle = tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False)
        handle.close()
        with self.assertRaises(ValueError):
            preview(handle.name)


if __name__ == "__main__":
    unittest.main()
