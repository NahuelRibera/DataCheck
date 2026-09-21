# Incident case study: duplicate employees in the payroll export

**Status:** synthetic support scenario, written for this portfolio project. It
did not happen at a real company, but the query bug and fix are real and
reproducible in this codebase (`spec/services/payroll/export_query_spec.rb`).

## Customer-visible symptom

A support ticket comes in from an HR admin: "I exported our payroll file for
this month and Ada Lovelace appears twice, with two different salary
figures. Did we overpay her?"

Looking at the export, a handful of employees appear more than once. Nobody
else looks duplicated. The employees who show up twice all have one thing in
common once you dig in: they've been re-contracted recently (a raise, a
promotion, a renewal after a fixed-term contract ended).

## Reproduction

The payroll export was built on top of a simple join:

```ruby
Employee.joins(:employee_contracts).where(company: company)
```

Given one employee with two contract rows (an old one and a current one),
this returns **two rows** for that employee -- one per contract, not one per
person. `spec/services/payroll/export_query_spec.rb` reproduces this exactly:

```ruby
naive_join_row_count = Employee.joins(:employee_contracts).where(company: company).count
expect(naive_join_row_count).to eq(2) # one employee, two rows
```

## Root cause

`employee_contracts` is a one-to-many history table: every raise, renewal,
or contract change adds a new row rather than overwriting the old one (this
is deliberate -- it's how the system keeps a compensation history at all).
A plain join between `employees` and `employee_contracts` produces one
result row per matching row on the "many" side. For an employee with a
single contract, that's one row and the bug is invisible. For anyone with
contract history, it's one row *per contract*, and the export -- which
assumed one row per employee -- silently fans out.

This is a classic one-to-many join fan-out. It wasn't caught earlier because
most employees only have a single contract row at any given time, so the bug
only shows up for people who've actually had a compensation change, which is
easy to miss in a spot check of a few rows.

## Fix

Select each employee's *current* contract (the one with the latest
`start_date`) before joining, instead of joining against the whole history
table. Postgres's `DISTINCT ON` does this in a single query:

```ruby
# app/services/payroll/export_query.rb
latest_contract_ids =
  EmployeeContract
    .where(employee_id: company.employees.select(:id))
    .select("DISTINCT ON (employee_id) id")
    .order(:employee_id, start_date: :desc)

EmployeeContract.where(id: latest_contract_ids).includes(:employee).order(:employee_id)
```

This returns exactly one row per employee -- their current contract -- no
matter how many historical contract rows they have, and it does it without
pulling every historical row into Ruby just to discard all but the latest.

## Regression test

`spec/services/payroll/export_query_spec.rb` covers, in order:

1. the original bug, reproduced directly against the naive join (so the test
   suite documents the failure mode, not just the fix);
2. `Payroll::ExportQuery` returns exactly one row per employee even when an
   employee has multiple contracts;
3. the row returned is the contract with the latest `start_date`, not an
   arbitrary one;
4. the query is company-scoped (no cross-company leakage).

## Customer-facing explanation

> We found the cause: employees who've had a raise or contract renewal were
> briefly showing up twice in the payroll export, once for their old
> contract and once for their new one. This was a reporting bug only -- no
> duplicate payments were made, and no data was lost. We've shipped a fix so
> the export always reflects one row per employee, their current contract.
> Past exports generated before the fix should be re-run if they're still
> being used for reconciliation.

## Engineering notes

- The bug is a one-to-many join fan-out, not a data integrity problem --
  `employee_contracts` is behaving exactly as designed (an append-only
  history table). The defect was entirely in the query that read it.
- `DISTINCT ON` was chosen over a `GROUP BY` + `MAX(start_date)` subquery
  join because it's a single pass, reads naturally ("distinct on employee,
  ordered by start_date descending"), and is idiomatic Postgres -- no need
  to reach for a window function here.
- This pattern generalizes: any time a query joins a parent table to a
  history/versioned child table without first narrowing the child side to
  "current record," the same fan-out bug is waiting to happen. It's worth
  grepping for other joins against `employee_contracts` if that table grows
  more consumers.
