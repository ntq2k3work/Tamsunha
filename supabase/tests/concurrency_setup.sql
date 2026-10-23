-- Persistent fixtures for test-supabase-concurrency.sh.
-- Apply only to a fresh database whose name starts with tamsunha_test_.
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a-concurrency@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'b-concurrency@example.invalid'),
  ('33333333-3333-4333-8333-333333333333', 'c-concurrency@example.invalid'),
  ('44444444-4444-4444-8444-444444444444', 'd-concurrency@example.invalid'),
  ('55555555-5555-4555-8555-555555555555', 'e-concurrency@example.invalid'),
  ('66666666-6666-4666-8666-666666666666', 'mod-concurrency@example.invalid');

insert into app_private.admin_roles (user_id, role)
values ('66666666-6666-4666-8666-666666666666', 'moderator');

create table public.tamsunha_test_handles (
  handle text primary key,
  value uuid not null
);

create table public.tamsunha_test_results (
  test_name text not null,
  actor_id uuid not null,
  response jsonb not null
);

do $$
declare
  account_id uuid;
  response jsonb;
  note_id uuid;
  conversation_id uuid;
begin
  foreach account_id in array array[
    '11111111-1111-4111-8111-111111111111'::uuid,
    '22222222-2222-4222-8222-222222222222'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '55555555-5555-4555-8555-555555555555'::uuid,
    '66666666-6666-4666-8666-666666666666'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub', account_id::text, true);
    response := public.complete_onboarding(
      true, true, true, true, true,
      'terms-v1', 'privacy-v1', 'community-v1', 'onboarding-v1'
    );
    if response #>> '{data,eligible}' <> 'true' then
      raise exception 'Test account onboarding failed: %', response;
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  response := public.place_note(
    'Context note for the concurrency test.', 'sage', true, 100, 100,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  );
  if response #>> '{data,status}' <> 'pending_review' then
    raise exception 'Could not queue the shared-note fixture: %', response;
  end if;
  note_id := (response #>> '{data,note_id}')::uuid;
  insert into public.tamsunha_test_handles(handle, value)
  values ('source_note_id', note_id);

  perform set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
  response := public.moderate_note(note_id, 'publish', 'Prepare chat fixture');
  if response #>> '{data,status}' <> 'published' then
    raise exception 'Could not publish the shared-note fixture: %', response;
  end if;

  perform set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
  response := public.start_conversation_from_note(
    note_id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  );
  if response #>> '{data,conversation_id}' is null then
    raise exception 'Could not create the conversation fixture: %', response;
  end if;
  conversation_id := (response #>> '{data,conversation_id}')::uuid;
  insert into public.tamsunha_test_handles(handle, value)
  values ('conversation_id', conversation_id);
end;
$$;
