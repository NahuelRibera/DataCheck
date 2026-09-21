# legacy-export-converter

A tiny standalone Java CLI that converts a legacy on-prem HR export
(semicolon-delimited, its own column order) into DataCheck's canonical
employee CSV format -- the format `scripts/profile_import.py` expects.

This is **not** wired into the Rails runtime or the import pipeline. It
exists on its own as a small, readable example of the kind of one-off
legacy-format conversion tool this role involves touching. No server, no
Spring, no build tool beyond `javac` -- one class is not worth a Maven
project.

## Format

Legacy input (semicolon-delimited, header row required):

```
EmployeeID;GivenName;FamilyName;Email;Dept;Manager;HireDate;Salary;Status
```

Canonical output (matches `data/demo/*.csv`):

```
external_id,first_name,last_name,email,department_external_id,manager_external_id,start_date,gross_salary,status
```

The converter reshapes columns and normalizes `MM/DD/YYYY` dates to ISO
(`YYYY-MM-DD`). It does **not** validate department/manager references,
salary parseability, or duplicates -- that's `scripts/profile_import.py`'s
job, run as the next step after conversion.

## Usage

```bash
./build.sh
./run.sh sample/input.txt /tmp/converted.csv
```

`sample/input.txt` -> `sample/output.csv` is a checked-in example of the
expected transformation.

## Tests

```bash
test/run.sh
```

Runs a small dependency-free assertion suite (no JUnit) covering field
mapping, date normalization, status lowercasing, CSV quoting, malformed-row
rejection, and header/blank-line handling.
