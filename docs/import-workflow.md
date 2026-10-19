# Import workflow

This document describes how an import moves through DataCheck, what the upload
accepts, and what each verification check proves. All example values are
synthetic. It describes the current behaviour of the code, not a compliance
certification of any kind.

## Workflow steps and statuses

An `ImportRun` has one of these statuses: `uploaded`, `profiling`, `blocked`,
`ready`, `dry_run_completed`, `importing`, `completed`, `failed`.

| Step | Action | Status afterwards |
| --- | --- | --- |
| Upload | The file is validated (see below), stored, and an audit event `import_uploaded` is recorded. | `uploaded` |
| Preview | The detail page shows a per-column profile and the first rows of the file, with sensitive values masked inside the Python profiler. Read-only; the status does not change. | unchanged |
| Preflight | `Imports::PreflightService` sets `profiling`, runs `scripts/profile_import.py` against the company's existing departments and employees, and stores the issues it finds. | `blocked` if there is at least one blocking issue, otherwise `ready`; `failed` if the profiler cannot process the file |
| Dry run | `Imports::DryRunService` classifies every row as create, update, skip or reject using the same `MigrationPlan` as execution, with `persist: false`. Nothing is written to `employees`. Allowed from `ready`, `blocked` and `dry_run_completed`. | `dry_run_completed` (`failed` on error) |
| Execute | `Imports::ExecuteService` sets `importing` and applies the plan in a transaction. It refuses to run while blocking issues exist, and the controller only allows it from `dry_run_completed`. The interface asks for the word `EXECUTE` as confirmation. | `completed`; `failed` if the transaction is rolled back |
| Verify | `Imports::VerificationService` runs right after a successful execution and stores its results on the run. | unchanged (`completed`) |
| Audit | Each step records an audit event, shown as a timeline on the run page. | unchanged |

A `blocked` run can still be dry run to preview the impact, but it can never be
executed. Re-running the identical clean file is idempotent: the second run
reports `create: 0`, because rows are matched on `(company_id, external_id)`,
which is also a unique index in PostgreSQL.

## Upload limits and accepted files

`Imports::UploadValidator` runs before the file is stored or profiled:

- The filename must end in `.csv` (case-insensitive).
- The default size limit is 20 MB (`20 * 1024 * 1024` bytes). Set the
  `IMPORT_MAX_UPLOAD_BYTES` environment variable to a positive integer number
  of bytes to override it. A missing, non-numeric, zero or negative value falls
  back to the default.
- The first 8192 bytes must be non-empty, contain no NUL bytes, and be valid
  UTF-8 (an optional BOM is accepted).

Error messages never include file contents or the client-supplied filename.

## CSV expectations

The header must contain these required columns: `external_id`, `first_name`,
`last_name`, `department_external_id`, `start_date`, `gross_salary`. Optional
columns are `email`, `manager_external_id` and `status` (`active`, `inactive` or
`terminated`). A file missing a required column cannot be processed and the run
becomes `failed`.

```csv
external_id,first_name,last_name,email,department_external_id,manager_external_id,start_date,gross_salary,status
EMP-00001,Ada,Example,ada.example@example.com,DEPT-ENG,,2020-01-15,85000.00,active
EMP-00002,Sam,Sample,sam.sample@example.com,DEPT-ENG,EMP-00001,2021-03-01,72000.00,active
```

Unambiguous formats (for example a date written as `03/14/2019`) are normalized.
Unresolvable problems such as duplicate external IDs, unknown departments or
managers, invalid dates or salaries, and missing identifiers are blocking
issues. A malformed email is a warning and does not block the row. Issues
reference the row number, field name and external ID, never the raw value.

## Verification checks

Verification reads the database after execution; the results are not taken from
in-memory counters. Each check is stored with a `pass` or `fail` status and a
details string, and the audit event `verification_completed` records the
passed and failed counts and the names of any failed checks.

| Check | What it verifies |
| --- | --- |
| `counts_reconcile` | The run's recorded create + update + skip equals the number of non-blocked rows in the normalized CSV, and the recorded reject count equals the number of blocked rows. Passes trivially if the normalized file is absent. |
| `required_fields_present` | No employee in the company has an empty `first_name`, `last_name` or `external_id`. |
| `no_cross_company_departments` | No employee in the company is linked to a department belonging to another company. |
| `no_cross_company_managers` | No employee in the company reports to a manager belonging to another company. |
| `all_employees_have_start_date` | No employee in the company has a missing `start_date`. |
| `no_duplicate_external_ids` | No `external_id` appears more than once within the company. |
| `imported_rows_now_exist` | Every accepted (non-blocked) row's `external_id` from the normalized CSV is present in the company's employees. Passes trivially if the normalized file is absent. |

The checks cover the integrity properties above only. They do not prove that
the source data was correct, only that the migration left the database
consistent with what preflight accepted.
