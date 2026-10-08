#!/usr/bin/env bash
# Full verification suite for an agent patch (run by the secret-free `verify` job).
set -euo pipefail

echo "::group::PostgreSQL"
docker run -d --name datacheck-ci-db -p 5432:5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=data_check_test postgres:16 >/dev/null
for _ in $(seq 1 30); do docker exec datacheck-ci-db pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done
export RAILS_ENV=test DATABASE_URL=postgres://postgres:postgres@localhost:5432/data_check_test
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
