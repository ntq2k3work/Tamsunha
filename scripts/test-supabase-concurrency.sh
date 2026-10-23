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
  printf '%s\n' 'The test database is not empty. Recreate it before running this concurrency test.' >&2
  exit 2
fi

psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/support/vanilla_postgres_stubs.sql"
for migration in "$repo_root"/supabase/migrations/*.sql; do
  psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done
psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f "$repo_root/supabase/tests/concurrency_setup.sql"

test_dir="$(mktemp -d /tmp/tamsunha-concurrency.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

place_concurrently() {
  local actor_id="$1"
  local request_id="$2"
  local content="$3"
  PGOPTIONS="-c request.jwt.claim.sub=$actor_id" psql "$TAMSUNHA_TEST_DATABASE_URL" \
    -v ON_ERROR_STOP=1 -q -c "
      insert into public.tamsunha_test_results(test_name, actor_id, response)
      select 'placement_collision', auth.uid(), public.place_note(
        '$content', 'lilac', true, 500, 500, '$request_id'::uuid
      );"
}

place_concurrently 33333333-3333-4333-8333-333333333333 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc 'Concurrent placement C' \
  >"$test_dir/place-c.out" 2>&1 &
place_c_pid=$!
place_concurrently 44444444-4444-4444-8444-444444444444 \
  dddddddd-dddd-4ddd-8ddd-dddddddddddd 'Concurrent placement D' \
  >"$test_dir/place-d.out" 2>&1 &
place_d_pid=$!
if ! wait "$place_c_pid"; then cat "$test_dir/place-c.out" "$test_dir/place-d.out" >&2; exit 1; fi
if ! wait "$place_d_pid"; then cat "$test_dir/place-c.out" "$test_dir/place-d.out" >&2; exit 1; fi

placement_outcomes="$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc "
  select count(*) filter (where response #> '{data,note_id}' is not null),
         count(*) filter (where response #>> '{error,code}' = 'SLOT_OCCUPIED')
    from public.tamsunha_test_results where test_name = 'placement_collision'")"
if [[ "$placement_outcomes" != "1|1" ]]; then
  printf 'Expected exactly one collision winner and one SLOT_OCCUPIED; got %s\n' "$placement_outcomes" >&2
  exit 1
fi

conversation_query="(select value from public.tamsunha_test_handles where handle = 'conversation_id')"
send_concurrently() {
  local request_id="$1"
  PGOPTIONS='-c request.jwt.claim.sub=22222222-2222-4222-8222-222222222222' \
    psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "
      insert into public.tamsunha_test_results(test_name, actor_id, response)
      select 'message_streak', auth.uid(), public.send_message(
        $conversation_query, 'Concurrent message $request_id', '$request_id'::uuid
      );"
}

message_request_ids=(
  eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee
  ffffffff-ffff-4fff-8fff-ffffffffffff
  00000000-0000-4000-8000-000000000001
  00000000-0000-4000-8000-000000000002
)
message_pids=()
for request_id in "${message_request_ids[@]}"; do
  send_concurrently "$request_id" >"$test_dir/message-$request_id.out" 2>&1 &
  message_pids+=("$!")
done
for pid in "${message_pids[@]}"; do
  if ! wait "$pid"; then
    cat "$test_dir"/message-*.out >&2
    exit 1
  fi
done

message_outcomes="$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc "
  select count(*) filter (where response #> '{data,message_id}' is not null),
         count(*) filter (where response #>> '{error,code}' = 'MESSAGE_LIMIT_REACHED')
    from public.tamsunha_test_results where test_name = 'message_streak'")"
if [[ "$message_outcomes" != "3|1" ]]; then
  printf 'Expected three accepted sends and one MESSAGE_LIMIT_REACHED; got %s\n' "$message_outcomes" >&2
  exit 1
fi
if [[ "$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc "
  select count(*) || '|' || max(c.streak_count)::text
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where c.id = $conversation_query")" != "3|3" ]]; then
  printf '%s\n' 'Message rows/streak count do not match the 3-message cap.' >&2
  exit 1
fi

duplicate_request_id=77777777-7777-4777-8777-777777777777
place_duplicate_concurrently() {
  PGOPTIONS='-c request.jwt.claim.sub=55555555-5555-4555-8555-555555555555' \
    psql "$TAMSUNHA_TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "
      insert into public.tamsunha_test_results(test_name, actor_id, response)
      select 'placement_idempotency', auth.uid(), public.place_note(
        'Same concurrent request', 'sage', true, 700, 700, '$duplicate_request_id'::uuid
      );"
}
place_duplicate_concurrently >"$test_dir/duplicate-1.out" 2>&1 &
duplicate_one_pid=$!
place_duplicate_concurrently >"$test_dir/duplicate-2.out" 2>&1 &
duplicate_two_pid=$!
if ! wait "$duplicate_one_pid"; then cat "$test_dir/duplicate-1.out" "$test_dir/duplicate-2.out" >&2; exit 1; fi
if ! wait "$duplicate_two_pid"; then cat "$test_dir/duplicate-1.out" "$test_dir/duplicate-2.out" >&2; exit 1; fi

duplicate_outcomes="$(psql "$TAMSUNHA_TEST_DATABASE_URL" -Atqc "
  select count(*) || '|' || count(distinct response #>> '{data,note_id}')
    from public.tamsunha_test_results
   where test_name = 'placement_idempotency'
     and response #> '{data,note_id}' is not null")"
if [[ "$duplicate_outcomes" != "2|1" ]]; then
  printf 'Expected two identical successful retries for one note; got %s\n' "$duplicate_outcomes" >&2
  exit 1
fi

printf '%s\n' 'PASS: concurrent cell collision, 3-message streak limit, and identical-request idempotency.'
