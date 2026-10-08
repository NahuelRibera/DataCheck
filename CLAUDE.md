# CLAUDE.md

## What this is

DataCheck is a portfolio project: an internal HR data migration/validation
workbench (legacy CSV -> preflight -> dry run -> execute -> verify -> audit
trail). All data is synthetic, deterministically generated. See
`docs/architecture.md` for the full picture and `README.md` for setup/demo
instructions.

## Stack

Rails 7.1 monolith (Sprockets, no importmap/jsbundling-rails gem) +
PostgreSQL + Python 3 (stdlib only) + TypeScript (esbuild, hand-rolled build,
no Node framework) + RSpec + GraphQL (read-only, small).

## Key paths

- `app/services/imports/` -- the pipeline: `PreflightService`,
  `MigrationPlan` (shared by dry run and execute), `DryRunService`,
  `ExecuteService`, `VerificationService`.
- `scripts/profile_import.py` -- the real data-quality analysis (Python,
  stdlib only, invoked via `Open3` with an argv array, never a shell
  string).
- `scripts/generate_demo_data.py` -- deterministic synthetic data (seed
  `20260101`), writes `data/demo/{clean,bad}_employees.csv` and a
  `manifest.json` with measured issue counts.
- `lib/tasks/demo.rake` (`bin/rails demo:seed`) -- resets and reseeds the
  demo company/departments/employees/import runs.
- `app/javascript/src/` -- TypeScript, built with `npm run build` to
  `public/builds/application.js` (served with a plain `<script>` tag, not
  through Sprockets -- see the note in `config/initializers/assets.rb`
  about why `app/assets/builds` doesn't work as a `link_tree` target).
- `app/services/payroll/export_query.rb` + `docs/incident-case-study.md` --
  the duplicate-employees-in-payroll-export incident writeup and its fix.

## Commands

- Setup: `bin/setup` (installs gems/npm deps, prepares the DB, builds JS,
  seeds demo data).
- Tests: `bundle exec rspec` (Ruby), `cd scripts && python3 -m unittest
  discover -s tests` (Python), `tools/legacy-export-converter/test/run.sh`
  (Java, optional).
- Regenerate demo data only: `python3 scripts/generate_demo_data.py`.
- Reseed the demo DB: `bin/rails demo:seed` (destructive to the demo
  company only -- drops and recreates it; safe to run repeatedly).

## Invariants (do not break these)

- Dry run (`Imports::DryRunService` / `MigrationPlan.new(..., persist:
  false)`) never writes to `employees`. It's the same classification code
  as execute, just not persisted.
- `Imports::ExecuteService` refuses to run while `import_run.blocked?` is
  true (`blocking_issue_count > 0`), inside the service itself -- not only
  in the controller.
- Imports are idempotent: running the identical clean CSV twice must
  produce `create: 0` the second time. `(company_id, external_id)`
  uniqueness on `employees` is enforced at the database level as the final
  guarantee, not only in Rails validations.
- `Imports::VerificationService` checks are computed from the database
  after the fact -- never hardcoded, never trusted from in-memory counters.
- Logs and `ImportIssue`/`AuditEvent` messages never contain raw salary,
  email, or name values -- only safe references (external_id, row number,
  field name, a generic description).
- Rails is the only thing that writes to the database. Python only reads
  the source CSV and writes a normalized CSV + JSON to stdout.
- `employees.manager_id` is self-referential with no `ON DELETE` clause on
  purpose (see `docs/architecture.md`). Don't "fix" a company-teardown FK
  violation by weakening that constraint -- `Company#destroy` already
  clears manager references first (`before_destroy ...,  prepend: true`).
- `ImportRun#storage_dir` is environment-scoped (`storage/test/...` in
  test). Both dev and test share one `Rails.root` on disk, so this is the
  only thing stopping the RSpec suite's cleanup from deleting real demo
  uploads -- don't hardcode `storage/import_runs` anywhere new.
- No frontend framework (React/Vue/etc.), no Redis, no background job
  queue, no external APIs. If a task seems to need one of these, that's a
  sign to reconsider the approach rather than add the dependency.

## Scope boundaries

- GraphQL is intentionally read-only and small (`ImportRun`/`ImportIssue`
  queries only). Don't add mutations there -- writes go through the REST
  API/controllers, which own the audit trail.
- `tools/legacy-export-converter/` is a standalone Java CLI (plain `javac`,
  no Maven/Gradle/Spring), not wired into the Rails runtime. It's a
  demonstration piece, not a dependency of the import pipeline.

## Contributions and automation

- Work happens on branches and pull requests; `main` is protected. No force pushes and no
  history rewriting. Commit dates are never altered.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`,
  `docs:`, `perf:`, `chore:`, `ci:`, `build:`), in English, one coherent change per commit.
- Every change keeps the invariants above and comes with specs; run `bundle exec rspec`,
  the Python unittest suite and `npm run typecheck && npm run build` before proposing it.
- Keep `README.md` and `docs/` accurate when behaviour, setup, schema or commands change.
  Describe only what is implemented and verified; no promotional text or tool attributions.
- Automated changes are produced by the autodev system: the agent runs in an isolated
  GitHub Actions job and publishes through the autodev GitHub App, so its commits and pull
  requests are attributed to that bot and labelled `autodev`.
- Automated sessions must not modify `.github/`, this file, destructive migrations or the
  dependency rules in "Invariants" without an explicit task approved by the owner. The
  product is planned to grow into a general data-quality platform; until the owner approves
  that direction's dependency changes, the "no job queue / no Redis / no frontend framework /
  no external APIs" invariant stays in force.
