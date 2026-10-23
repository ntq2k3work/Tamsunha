#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${TAMSUNHA_TEST_DATABASE_URL:-}" ]]; then
  printf '%s\n' 'Set TAMSUNHA_TEST_DATABASE_URL to a fresh, disposable vanilla PostgreSQL database.' >&2
  exit 2
fi

database_name="$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc 'select current_database()')"
case "$database_name" in
  tamsunha_test_*) ;;
  *) printf '%s\n' 'Refusing to modify a database not named tamsunha_test_*.' >&2; exit 2 ;;
esac

is_empty="$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc \
  "select to_regclass('public.profiles') is null and to_regclass('app_private.app_settings') is null")"
if [[ "$is_empty" != "t" ]]; then
  printf '%s\n' 'The test database is not empty. Recreate it before running this migration smoke test.' >&2
  exit 2
fi

psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/support/vanilla_postgres_stubs.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
  psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done
psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/core_workflows.sql"
