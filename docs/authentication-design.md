# Authentication and authorisation design

Status: **proposal for owner review. Nothing described here is implemented.**
No code, schema or dependency has changed with this document.

## 1. Problem

Today every page (`/`, `/companies`, `/import_runs`), every REST endpoint
(`/api/v1/import_runs/...`, including `execute`) and `POST /graphql` is open
to anyone who can reach the server. Consequences:

- Anyone can upload a CSV, run `execute` and write to `employees`.
- Issues, verification results and audit events are readable by anyone.
- `AuditEvent` rows record *what* happened to an import run but not *who*
  caused it, so the audit trail cannot answer accountability questions.

Relevant current facts (from the code):

- `ApplicationController` (HTML) inherits Rails default CSRF protection;
  `Api::V1::BaseController` inherits `ActionController::API` (no sessions,
  no CSRF); `GraphqlController` calls `skip_forgery_protection` and says in
  a comment that it "doesn't use session-based auth". That comment becomes
  wrong once sessions exist and must be revisited.
- `audit_events` has `import_run_id`, `event_type`, `message`, `metadata`
  (jsonb), `created_at`; no actor column.
- `import_runs` belongs to a `company`; there is no user model, no
  `bcrypt` gem (the `Gemfile` line is commented out) and no session store
  configuration beyond the Rails default cookie store.
- `ExecuteService` already refuses blocked runs internally; this is the
  pattern authorisation should follow (enforce in the service/policy layer,
  not only in controllers).

## 2. Goals and non-goals

Goals

- Every UI page, REST endpoint and GraphQL query requires an authenticated
  principal, except `/up` (health check).
- Three capabilities, enforced server side: **view**, **import**, **execute**.
- Every state-changing action is attributed to a principal in the audit trail.
- Keep the stack: Rails monolith, PostgreSQL, no frontend framework, no
  Redis, no job queue, no external APIs (see section 9 for the one
  invariant that does need to change).
- No raw personal values (email, name, salary) or secrets (passwords,
  tokens) in logs, `ImportIssue` or `AuditEvent` messages.

Non-goals (for this design)

- SSO / SAML / OIDC, MFA, self-service sign-up, password reset by e-mail
  (needs an outbound mail service; see open questions).
- Per-company tenancy isolation. Users are global in phase 1; see open
  questions.
- Authentication for the standalone Java converter tool.

## 3. Approaches compared

### Option A: `has_secure_password` + hand-written sessions

Add the `bcrypt` gem (already present as a commented line in the `Gemfile`),
a `users` table with `password_digest`, a `SessionsController` and a
`current_user` helper in `ApplicationController`. Rails 7.1 ships
`has_secure_password`, `generates_token_for` and `authenticate_by`
(timing-attack-resistant lookup), which cover most of what is needed.

| Aspect | Assessment |
| --- | --- |
| New dependencies | One gem (`bcrypt`), a compiled extension but long established and Rails-endorsed. |
| Code size | Roughly 200-300 lines: model, sessions controller, concern, login view, rate limiting. |
| Control over audit/logging | Full. Easy to guarantee no email or password reaches logs (`filter_parameters`). |
| Security burden | Ours: session fixation (`reset_session` on login), lockout, throttling, timing, password policy. Each needs a spec. |
| Fits "small, explainable" | Yes; every line is reviewable by the owner. |
| Rails 7.1 fit | Native. Rails 7.2+ ships an authentication generator that produces essentially this design, so it also migrates forward cleanly. |
| Rate limiting | Rails 7.2 `rate_limit` is not in 7.1; needs a small DB-backed counter (see 5.4) or a gem. |

### Option B: Devise

Established authentication gem: `devise` (+ `bcrypt` transitively, `warden`,
`orm_adapter`, `responders`).

| Aspect | Assessment |
| --- | --- |
| New dependencies | Several gems, with a large surface (modules, routes, mailers, views, generators). |
| Code size | Small to wire up; large amount of behaviour hidden in the gem. |
| Built-in features | Lockable, timeoutable, trackable, recoverable, rememberable. Many of those (recoverable, confirmable) need outbound email, which the project does not have. |
| Control over audit/logging | Good but indirect: Warden hooks are needed to record login success/failure events. |
| Security burden | Shared with the gem's maintainers, who patch known issues. We still own configuration correctness. |
| API auth | Not provided for token auth; needs `devise-jwt`, `devise_token_auth` or custom code, which adds yet more dependencies or reintroduces custom code. |
| Fits "small, explainable" | Less so; the project is a portfolio piece that is meant to show reasoning about the code it ships. |

### Option C (considered, not recommended): Rodauth / OmniAuth / external IdP

Rodauth-rails is excellent but pulls in a Roda-based middleware stack.
OmniAuth/OIDC needs an external provider, which contradicts the "no
external APIs" invariant. Reasonable future direction, out of scope now.

### Recommendation

**Option A** for the browser UI and for API tokens. Reasons: the needed
feature set is small (password login, session, logout, personal API tokens,
three roles), no feature of Devise we would actually use is missing from A,
the dependency change is one gem instead of several, and every security
behaviour is covered by specs that live in this repository. Revisit Option B
only if requirements grow to include MFA, password reset by e-mail and
account lockout workflows at once.

The remainder of the document describes Option A. Where Option B would
differ, it is noted.

## 4. Data model

New tables (additive migrations only; none is destructive).

`users`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint | |
| `username` | string, not null | Login identifier. Unique index on `lower(username)`. Not an e-mail, so no personal address is needed. |
| `display_name` | string, not null | Shown in UI. Never written to logs or audit messages (the audit trail stores `user_id`). |
| `password_digest` | string, not null | bcrypt via `has_secure_password`. |
| `role` | string, not null | `viewer`, `importer`, `executor`, or `admin`; check constraint at DB level. |
| `active` | boolean, not null, default true | Deactivation instead of deletion so audit references stay valid. |
| `failed_login_count` | integer, default 0 | Lockout support. |
| `locked_until` | datetime | |
| `last_login_at` | datetime | |
| `created_at`, `updated_at` | datetime | |

`api_tokens`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | bigint | |
| `user_id` | bigint, FK, not null | Token inherits the role of its user (cannot exceed it). |
| `name` | string, not null | Human label, e.g. "ci-reporting". |
| `token_digest` | string, not null, unique | SHA-256 of the token. The plaintext is shown once at creation and never stored. |
| `scope` | string, not null | Optional narrowing: `read` or `write`. A token can only be narrower than its user. |
| `expires_at` | datetime, not null | Mandatory expiry (default 90 days). |
| `last_used_at` | datetime | |
| `revoked_at` | datetime | |
| `created_at` | datetime | |

`audit_events` gets nullable `actor_type` (`user`, `api_token`, `system`) and
`actor_id` columns, plus a new table-independent event stream for
authentication events (see section 7).

## 5. Roles and authorisation

### 5.1 Roles

Roles are cumulative and fixed in code (a constant mapping, not a
configurable permission table; simplest thing that is explainable).

| Capability | viewer | importer | executor | admin |
| --- | --- | --- | --- | --- |
| View companies, import runs, issues, verification, audit events (UI, REST, GraphQL) | yes | yes | yes | yes |
| Upload a CSV; run preflight; run dry run | no | yes | yes | yes |
| Execute a migration (the only action that writes `employees`) | no | no | yes | yes |
| Manage users and API tokens of others | no | no | no | yes |

Rationale for separating `execute` from `import`: dry run never writes to
`employees`, so letting importers prepare and review a run while a distinct,
smaller set of people can commit it matches the existing pipeline stages and
supports a four-eyes practice.

Optional later hardening (not in the phases below unless the owner asks):
require that the executing user differs from the uploader.

### 5.2 Enforcement points

1. A single `Authorization` module (plain Ruby, e.g. `app/services/auth/policy.rb`)
   with `can?(user, :view | :import | :execute | :admin)`. All controllers
   and services call it; the role matrix lives in one place and is unit
   tested exhaustively.
2. Controllers: `before_action :require_authentication` in
   `ApplicationController` and `Api::V1::BaseController` (secure by default;
   public routes opt out explicitly with `skip_before_action`), then a
   per-action `authorize!(:capability)`.
3. Services: `Imports::ExecuteService` takes an `actor:` and raises
   `NotAuthorizedError` unless the actor may execute, in the same spirit as
   its existing `blocked?` check, so that a future caller (rake task,
   console) cannot bypass the controller. Rake tasks such as
   `demo:seed` use an explicit `System` actor.
4. Views hide buttons the user cannot use. That is cosmetic only; the server
   checks are authoritative.

Denials return 403 (authenticated, not permitted) or 401 (not
authenticated; for HTML, redirect to login). Resource lookups that fail
return the existing 404 behaviour; the 401/403 check runs first so that
unauthenticated callers cannot probe for existing IDs.

### 5.3 GraphQL

`GraphqlController` passes `current_user` into the query context (the
placeholder comment is already there). Every root field requires `view`.
GraphQL stays read-only; no mutations are added. Existing depth and
complexity limits stay in place and unauthenticated requests are rejected
before the query is parsed. Anonymous introspection is disabled in
production.

### 5.4 Brute-force protection

- `User.authenticate_by(username:, password:)` for constant-time-ish lookup.
- Per-account lockout: after 5 consecutive failures set `locked_until` to
  now + 15 minutes; reset on success. Responses are identical for unknown
  user, wrong password and locked account (generic "invalid credentials") to
  avoid username enumeration.
- Per-IP throttle on `POST /session` and on token-authenticated 401s. Rails
  7.1 has no built-in `rate_limit`; options are a small
  `login_attempts` table counted in a time window (no new dependency, chosen
  default) or `rack-attack` with the Rails cache (new dependency; needs
  owner approval if preferred).

## 6. Sessions, CSRF and transport security

Browser UI

- Cookie session (Rails encrypted cookie store, which already needs only
  `secret_key_base`; no Redis, no server-side store). Cookie flags:
  `httponly`, `secure` (production already sets `force_ssl`), `same_site:
  :lax` (`:strict` is preferable if the UI never needs cross-site
  navigation links to authenticated pages; decide in review).
- `reset_session` on login (prevents session fixation) and on logout.
- Absolute lifetime (e.g. 8 h) and idle timeout (e.g. 30 min) stored in the
  session as timestamps and checked in `require_authentication`.
- Session stores only `user_id` and timestamps, never the role; the role is
  read from the database each request so deactivation and demotion take
  effect immediately.
- Logout is `DELETE /session` (not a GET).
- CSRF: keep `protect_from_forgery with: :exception` for all HTML
  controllers; the TypeScript code that calls routes must send the token
  from `csrf_meta_tags` (already in the layout). Add a spec that disables
  the test-environment default and proves a POST without a token is
  rejected. Today forgery protection is off in tests, so CSRF regressions
  are invisible to the suite.
- Responses for authenticated pages send `Cache-Control: no-store`.
- Passwords: minimum length 12, no composition rules, bcrypt cost default,
  `password` and `password_digest` in `filter_parameters`.

REST API (`/api/v1`)

- No cookies. `Authorization: Bearer <token>` only, resolved by hashing the
  presented token and looking it up by `token_digest` (indexed equality;
  tokens are 256-bit random so a timing difference leaks nothing useful).
- Because the API does not read the session cookie, CSRF does not apply to
  it, and a browser cannot be tricked into making an authenticated API call.
  This must be enforced by a spec: an API request carrying only a session
  cookie gets 401.
- A browser JavaScript client that needs the API (the existing TypeScript)
  keeps using the HTML controllers with CSRF tokens and session cookies,
  not API tokens.
- Tokens: shown once, mandatory expiry, revocable, `last_used_at` recorded,
  never logged (`Authorization` header added to `filter_parameters`/header
  filtering; check that request logging does not print it).
- `execute` over the API requires an executor-level user and a `write`
  scope token.

GraphQL

- Accepts either a Bearer token (programmatic clients) or the session cookie.
  Because the cookie is accepted, CSRF protection must be re-enabled for
  cookie-authenticated GraphQL requests: simplest rule is *remove
  `skip_forgery_protection`, and accept only the Bearer token on
  `/graphql`*, which preserves the current curl-friendly behaviour. The
  recommendation is Bearer-only for GraphQL.

## 7. Audit attribution

- `audit_events.actor_type` / `actor_id` are set for every event written
  through the pipeline services. The services receive `actor:` explicitly
  (no `Current` global that can silently be nil).
- Events that today have no human (e.g. `demo:seed`) record
  `actor_type: "system"`.
- `metadata` records the way of authentication (`session` or
  `api_token`) and the token's `id`, never the token or the username's
  password-related data.
- Messages keep using safe references only. The actor is referenced by
  `user_id`; display names and usernames are resolved at render time and are
  not copied into `message` or `metadata`.
- New event types for the import-run audit trail where an import run is
  involved: `authorization_denied` (for a denied execute/import attempt on
  a specific run, with capability name only). Authentication events that
  have no import run (login success/failure, lockout, token created/revoked,
  role change) do not fit `audit_events.import_run_id NOT NULL`. Proposal:
  a separate `security_events` table (`event_type`, `actor_*`,
  `ip_address` truncated per the owner's privacy decision, `created_at`,
  `metadata`) rather than weakening the existing NOT NULL constraint.
- `ImportRun` gets nullable `created_by_id` and `executed_by_id`
  (FK to `users`, `on_delete: :nullify` is **not** used; users are
  deactivated, never deleted).

## 8. Migration of existing data

All migrations are additive and reversible; no existing column is dropped or
rewritten.

1. Create `users`, `api_tokens`, `security_events`.
2. Add nullable `actor_type`/`actor_id` to `audit_events` and nullable
   `created_by_id`/`executed_by_id` to `import_runs`. Existing rows stay
   `NULL`, which the UI renders as "before authentication was introduced".
   No backfill with invented users: fabricating attribution would corrupt
   the audit trail.
3. Bootstrap the first admin without a default password: a rake task
   `bin/rails users:create_admin USERNAME=...` that prompts for or reads the
   password from the TTY/environment variable, prints nothing sensitive and
   fails if any admin exists unless forced. No credentials are checked into
   the repository, seeds or fixtures.
4. `demo:seed` creates three synthetic users (viewer, importer, executor)
   with a documented, obviously fake password **only** when
   `Rails.env.development?` or `demo`; refuses to run those lines in
   production.
5. Rollout order matters: ship the schema and the unenforced code first
   (phase 1-2), create the admin, then switch enforcement on (phase 3)
   behind an environment flag that is removed once stable, so there is never
   a window where the app is locked with no usable account.

## 9. Invariant and policy changes requiring owner approval

`CLAUDE.md` forbids autonomous sessions from changing these; each item below
needs an explicit decision.

1. **Dependency rule.** Add the `bcrypt` gem (uncomment the existing
   `Gemfile` line). This is the only new dependency in Option A. If
   `rack-attack` is preferred for throttling, or Option B (Devise) is
   chosen, the list of gems grows accordingly. The "no Redis / no job queue
   / no frontend framework / no external APIs" invariant itself is **not**
   changed by this design.
2. **"Rails is the only thing that writes to the database"** is unaffected,
   but add: *authentication state (sessions, tokens, lockout counters) is
   also written by Rails only.*
3. **New invariant to add:** `Imports::ExecuteService` also refuses to run
   without an authorised actor, inside the service, alongside the existing
   `blocked?` refusal.
4. **New invariant to add:** logs, `ImportIssue`, `AuditEvent` and
   `SecurityEvent` messages never contain passwords, API tokens, session
   identifiers or usernames/display names; actors are referenced by id.
5. **Scope boundary change:** GraphQL stays read-only, but its comment
   "doesn't use session-based auth" and the `skip_forgery_protection`
   justification change (Bearer-only recommended).
6. **Audit trail:** `audit_events` gets nullable actor columns, and a new
   `security_events` table is introduced for events that have no import run.
   Existing audit rows are never rewritten.
7. **Non-destructive migrations only.** No migration in this plan is
   destructive; if the owner wants `NOT NULL` actor columns later, that is a
   separate task after historical rows are handled.
8. **`.github/` and `CLAUDE.md`.** CI needs no new secrets (tests use
   factories). `CLAUDE.md` should be updated by the owner, not by an
   automated session, to reflect items 1-5.
9. **Demo/portfolio exposure.** Whether the public demo may run with
   authentication disabled (a `DATACHECK_AUTH=off` development-only switch)
   or must always authenticate. Recommendation: no off switch outside
   `development`/`test`.

## 10. Phased implementation plan

Each phase is a separate pull request, passes `bundle exec rspec`, the
Python unittest suite and `npm run typecheck && npm run build`, and updates
`README.md` and `docs/architecture.md`.

### Phase 0: owner decisions

Approve section 9, choose Option A or B, answer the open questions below.

### Phase 1: users, roles, policy (no behaviour change)

- Uncomment `bcrypt`; migrations for `users`; `User` model; `Auth::Policy`.
- Specs: model validations (unique case-insensitive username, role check
  constraint at the database level), password digest never equals the
  password, `authenticate_by` behaviour with unknown user, policy matrix
  exhaustively (every role x capability), `filter_parameters` include
  `password`.

### Phase 2: browser login and sessions

- `SessionsController` (new/create/destroy), login view, `current_user`,
  `require_authentication`, idle and absolute timeouts, lockout, throttle,
  admin bootstrap rake task, `security_events` table and login events.
- Specs (request): login success sets the session and rotates the session id
  (fixation); wrong password and unknown user are indistinguishable;
  lockout after N failures and unlock after the window; throttling;
  idle/absolute expiry (travel_to); logout destroys the session; deactivated
  user is rejected on the next request; cookie flags in production config;
  CSRF: with `allow_forgery_protection = true`, POST without token is
  rejected; rake task refuses to create a second admin and never prints the
  password; `spec/security/personal_data_leakage_spec.rb` extended so
  logs for login contain no password or username.
- Enforcement behind a temporary flag, default on in production.

### Phase 3: enforce on the UI and attribute actions

- `before_action` in `ApplicationController`; `authorize!` per action
  (`view` for index/show, `import` for new/create/preflight/dry_run,
  `execute` for execute); `ExecuteService` requires `actor:`.
- Add `actor_*` to `audit_events`, `created_by_id`/`executed_by_id` to
  `import_runs`; services record the actor; UI shows who did what.
- Specs: every route x role matrix (anonymous 302 to login / 401, viewer
  403 on upload and execute, importer 403 on execute, executor 200);
  `ExecuteService` raises for a non-executor even when called directly, and
  still raises for blocked runs when authorised; dry run still writes no
  `employees` rows; idempotency spec still passes with an executor actor;
  each audit event created by a request carries the right actor; historical
  rows with NULL actor render; `authorization_denied` events carry no
  personal values; the existing `demo:seed` still works (system actor).

### Phase 4: API tokens and GraphQL

- `api_tokens`, admin/user token management UI (create shown once, revoke),
  `Api::V1::BaseController` Bearer authentication, `write` scope on
  mutating actions, GraphQL Bearer-only with `current_user` in context,
  introspection off in production, remove `skip_forgery_protection` from the
  HTML side only (it stays for the Bearer-only GraphQL endpoint with an
  updated justification comment).
- Specs: no header -> 401; malformed, unknown, expired, revoked token -> 401;
  read token cannot call `execute`; token never exceeds its user's role;
  a token's plaintext is not retrievable after creation and not present in
  the log or in any audit/security event; session cookie alone does not
  authenticate `/api/v1` or `/graphql`; GraphQL depth/complexity limit specs
  still pass authenticated; unauthenticated GraphQL does not reach the query
  parser; `last_used_at` updates.

### Phase 5: hardening and docs

- Remove the enforcement flag; add a security response headers review;
  update `CLAUDE.md` (by the owner), `README.md`, `docs/architecture.md`
  (new "Authentication and authorisation" section) and the demo
  instructions (demo credentials).
- Specs: smoke spec asserting that every route in `Rails.application.routes`
  except `/up` and the login routes rejects anonymous access (route
  enumeration, so a newly added route that forgets authentication fails CI).

## 11. Open questions for the owner

1. Option A (recommended) or Option B?
2. Are users global, or scoped to companies? (If the product grows into a
   multi-customer platform, a `memberships(user, company, role)` table is
   cleaner than a global `users.role`; this changes sections 4 and 5.)
3. Is password reset needed in phase 1? It requires outbound e-mail, which
   conflicts with the "no external APIs" invariant; the proposed alternative
   is admin-initiated reset.
4. Session lifetimes and lockout parameters (defaults above are proposals).
5. Throttling: DB-backed counter (no dependency) or `rack-attack`?
6. Should the uploader be prevented from executing their own import
   (four-eyes)?
7. Should IP addresses be stored in `security_events` at all, given the
   personal-data posture (store truncated, hashed, or not at all)?
8. Retention period for `security_events`.
