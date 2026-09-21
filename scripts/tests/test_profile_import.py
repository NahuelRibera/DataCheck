import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from profile_import import profile, write_normalized_csv

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


if __name__ == "__main__":
    unittest.main()
