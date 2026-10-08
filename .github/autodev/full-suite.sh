#!/usr/bin/env bash
# Full verification suite for an agent patch (run by the secret-free `verify` job).
set -euo pipefail

echo "::group::PostgreSQL"
export RAILS_ENV=test
if [ -z "${DATABASE_URL:-}" ]; then
  # No database provided: start a throwaway PostgreSQL 16 bound to localhost.
  DB_PORT="${DB_PORT:-5432}"
  DB_CONTAINER="datacheck-ci-db-$$"
  trap 'docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true' EXIT
  docker run -d --name "$DB_CONTAINER" -p "127.0.0.1:${DB_PORT}:5432" \
    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=data_check_test postgres:16 >/dev/null
  # The image restarts once after initialisation: wait for the second "ready" message.
  for _ in $(seq 1 60); do
    [ "$(docker logs "$DB_CONTAINER" 2>&1 | grep -c 'ready to accept connections')" -ge 2 ] && break; sleep 1
  done
  export DATABASE_URL="postgres://postgres:postgres@127.0.0.1:${DB_PORT}/data_check_test"
fi
echo "::endgroup::"

echo "::group::Ruby dependencies and TypeScript"
bundle config set --local path vendor/bundle
bundle install --jobs 4 --quiet
npm ci --no-audit --no-fund
npm run typecheck
npm run build
echo "::endgroup::"

echo "::group::RSpec"
bin/rails db:schema:load
bundle exec rspec
echo "::endgroup::"

echo "::group::Python profiler"
(cd scripts && python3 -m unittest discover -s tests)
echo "::endgroup::"

echo "::group::Legacy export converter (Java)"
tools/legacy-export-converter/test/run.sh
echo "::endgroup::"
