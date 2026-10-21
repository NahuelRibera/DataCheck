#!/usr/bin/env bash
# autodev-rspec [rspec arguments...]: runs DataCheck's RSpec suite against a throwaway PostgreSQL.
#
# Installed by the agent job's project setup as /usr/local/bin/autodev-rspec (root-owned, outside the
# working tree) before Claude runs, so the session can run specs but cannot change this script.
# Everything happens inside the one calling command, because each sandboxed command gets its own
# network namespace: the cluster is created in a private temporary directory, listens on TCP
# 127.0.0.1 only (Claude Code's sandbox refuses new Unix sockets), trusts local connections, holds
# nothing but the test schema, and is stopped and deleted on exit. No secret and no production data
# is involved. The verify job does not use this: it runs its own full suite from main.
set -euo pipefail

PG_BIN="${AUTODEV_PG_BIN:-}"
if [ -z "$PG_BIN" ]; then
  PG_BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -n 1)"
  [ -n "$PG_BIN" ] || PG_BIN="$(pg_config --bindir 2>/dev/null || true)"
fi
[ -x "$PG_BIN/initdb" ] && [ -x "$PG_BIN/pg_ctl" ] || {
  echo "autodev-rspec: PostgreSQL server binaries not found (set AUTODEV_PG_BIN)" >&2; exit 2; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/autodev-pg.XXXXXX")"
cleanup() {
  "$PG_BIN/pg_ctl" -D "$ROOT/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$ROOT"
}
trap cleanup EXIT

# LC_ALL only for the server tools (PostgreSQL refuses to start without a valid locale on some hosts);
# Ruby and RSpec keep the caller's locale and encoding.
LC_ALL=C "$PG_BIN/initdb" -D "$ROOT/data" -U postgres --auth=trust --no-locale -E UTF8 --no-sync \
  > "$ROOT/initdb.log" 2>&1 || { cat "$ROOT/initdb.log" >&2; exit 2; }

# A free port on this command's loopback; retried because another command may take it first.
started=""
for _ in 1 2 3 4 5; do
  PORT=$(( 20000 + RANDOM % 20000 ))
  if LC_ALL=C "$PG_BIN/pg_ctl" -D "$ROOT/data" -l "$ROOT/server.log" -w -t 60 -o \
      "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories= -c dynamic_shared_memory_type=mmap -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
      start >/dev/null 2>&1; then
    started=1; break
  fi
done
[ -n "$started" ] || { echo "autodev-rspec: PostgreSQL did not start" >&2; cat "$ROOT/server.log" >&2; exit 2; }

export RAILS_ENV=test
export DATABASE_URL="postgres://postgres@127.0.0.1:${PORT}/data_check_test"
bin/rails db:create db:schema:load > "$ROOT/schema.log" 2>&1 || { cat "$ROOT/schema.log" >&2; exit 2; }
bundle exec rspec "$@"
