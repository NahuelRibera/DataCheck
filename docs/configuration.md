# Configuration reference

This page lists the environment variables the application reads and the limits
that are built into the code. Each entry names the file that defines it.

## Environment variables

### Application

| Variable | Default | Effect | Defined in |
| --- | --- | --- | --- |
| `IMPORT_MAX_UPLOAD_BYTES` | `20971520` (20 MB) | Maximum size of an uploaded CSV, in bytes. Uploads larger than this are refused with a "file is too large" message. A value that is not a positive integer is ignored and the default is used. | `app/services/imports/upload_validator.rb` |
| `PYTHON_BIN` | `python3` | Python executable used to run `scripts/profile_import.py` during preflight. It is read once when the app loads, so changing it requires a restart. | `app/services/imports/preflight_service.rb` |

### Database

| Variable | Default | Effect | Defined in |
| --- | --- | --- | --- |
| `RAILS_MAX_THREADS` | `5` | Database connection pool size and Puma maximum thread count. | `config/database.yml`, `config/puma.rb` |
| `DATA_CHECK_DATABASE_PASSWORD` | none | Password for the `data_check` user of the `data_check_production` database. Only used in the production environment. | `config/database.yml` |

The development and test databases (`data_check_development`, `data_check_test`)
use the default PostgreSQL role and have no variables of their own. Rails
itself also honours `DATABASE_URL` when it is set.

### Server and runtime

| Variable | Default | Effect | Defined in |
| --- | --- | --- | --- |
| `RAILS_ENV` | `development` | Environment Puma starts in. | `config/puma.rb` |
| `RAILS_MIN_THREADS` | value of `RAILS_MAX_THREADS` | Puma minimum thread count. | `config/puma.rb` |
| `WEB_CONCURRENCY` | `1` | Number of Puma worker processes. | `config/puma.rb` |
| `PORT` | `3000` | Port Puma listens on. | `config/puma.rb` |
| `PIDFILE` | `tmp/pids/server.pid` | Puma PID file path. | `config/puma.rb` |
| `RAILS_LOG_LEVEL` | `info` | Log level in production. | `config/environments/production.rb` |
| `CI` | unset | When non-empty, the test environment eager-loads the application. | `config/environments/test.rb` |
| `REDIS_URL` | `redis://localhost:6379/1` | Action Cable Redis URL in the production cable configuration (`config/cable.yml`). The application does not use Action Cable features itself; development uses the `async` adapter and test uses the `test` adapter. | `config/cable.yml` |

## Limits built into the code

These are not configurable through environment variables.

### Uploads

`Imports::UploadValidator` checks each upload before it is stored or profiled,
in this order. The first failing check produces the error shown to the user.

1. A file must be present.
2. The filename must have a `.csv` extension (case-insensitive). The content
   type sent by the client is not used.
3. The size must not exceed the cap: 20 MB by default, or
   `IMPORT_MAX_UPLOAD_BYTES` when set to a positive integer.
4. A text check on the first 8192 bytes: the sample must not be empty, must not
   contain a NUL byte, and must be valid UTF-8 (after an optional UTF-8 byte
   order mark; a multi-byte character cut off at the end of the sample is
   tolerated).

Error messages do not include file contents or the client-supplied filename.
The text check only inspects the beginning of the file; it does not validate the
CSV structure, which is the job of preflight.

### GraphQL

The GraphQL schema (`app/graphql/data_check_schema.rb`) is read-only and sets
these limits through graphql-ruby:

| Limit | Value | Meaning |
| --- | --- | --- |
| `max_complexity` | 200 | Every field costs 1, and list fields are not multiplied. A query whose total cost is above 200 is rejected before execution. A full `ImportRun` plus issues selection costs about 22. |
| `max_depth` | 6 | Queries nested deeper than 6 levels are rejected. The schema itself is 3 levels deep (`importRuns` > `issues` > fields). |
| `max_query_string_tokens` | 5000 | Queries with more than 5000 tokens are rejected at parse time. |
| `validate_max_errors` | 100 | Static validation stops after 100 errors. |

No other GraphQL limits, such as rate limiting or pagination caps, are
configured in the schema.
