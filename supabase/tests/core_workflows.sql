-- Integration-style transaction smoke tests for the SQL API.
-- Run only against the disposable empty vanilla PostgreSQL database described
-- by scripts/test-supabase-smoke.sh. Every fixture is rolled back.
begin;

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'b@example.invalid'),
  ('33333333-3333-4333-8333-333333333333', 'mod@example.invalid'),
  ('44444444-4444-4444-8444-444444444444', 'c@example.invalid');
insert into app_private.admin_roles (user_id, role)
values ('33333333-3333-4333-8333-333333333333', 'moderator');

do $$
declare
  a constant uuid := '11111111-1111-4111-8111-111111111111';
  b constant uuid := '22222222-2222-4222-8222-222222222222';
  moderator constant uuid := '33333333-3333-4333-8333-333333333333';
  c constant uuid := '44444444-4444-4444-8444-444444444444';
  response jsonb;
  first_response jsonb;
  note_a uuid;
  note_b uuid;
  note_c uuid;
  v_conversation_id uuid;
  message_id uuid;
  report_id uuid;
  message_report_id uuid;
  user_report_id uuid;
  conversation_user_report_id uuid;
  deletion_request_id uuid;
  tile_data jsonb;
begin
  if has_table_privilege('anon', 'public.notes', 'select')
     or has_table_privilege('authenticated', 'public.notes', 'select')
     or has_table_privilege('anon', 'public.messages', 'select')
     or has_table_privilege('authenticated', 'public.messages', 'select') then
    raise exception 'Direct anonymous/authenticated access to protected content tables is granted';
  end if;
  if has_function_privilege('anon', 'public.report_and_block_message(uuid,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.report_and_block_message(uuid,text,text)', 'execute') then
    raise exception 'Message report/block RPC grants are not restricted to authenticated users';
  end if;
  if has_function_privilege('anon', 'public.report_user_from_note(uuid,text,text)', 'execute')
     or has_function_privilege('anon', 'public.report_user_from_conversation(uuid,text,text)', 'execute')
     or has_function_privilege('anon', 'public.report_and_block_user_from_note(uuid,text,text)', 'execute')
     or has_function_privilege('anon', 'public.report_and_block_user_from_conversation(uuid,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.report_user_from_note(uuid,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.report_user_from_conversation(uuid,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.report_and_block_user_from_note(uuid,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.report_and_block_user_from_conversation(uuid,text,text)', 'execute') then
    raise exception 'User report and block RPC grants are not restricted to authenticated users';
  end if;
  if has_function_privilege('anon', 'app_private.report_content_internal(text,uuid,text,text)', 'execute')
     or has_function_privilege('authenticated', 'app_private.report_content_internal(text,uuid,text,text)', 'execute') then
    raise exception 'Private report helper is directly executable by app roles';
  end if;
  if has_function_privilege('authenticated', 'public.claim_push_deliveries(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.complete_push_delivery(uuid,text,text)', 'execute')
     or not has_function_privilege('service_role', 'public.claim_push_deliveries(integer)', 'execute')
     or not has_function_privilege('service_role', 'public.complete_push_delivery(uuid,text,text)', 'execute') then
    raise exception 'Push outbox functions are not restricted to the service role';
  end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.complete_onboarding(true, true, true, true, true,
    'terms-v1', 'privacy-v1', 'community-v1', 'onboarding-v1');
  if response #>> '{data,eligible}' <> 'true' then raise exception 'A onboarding failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.complete_onboarding(true, true, true, true, true,
    'terms-v1', 'privacy-v1', 'community-v1', 'onboarding-v1');
  if response #>> '{data,eligible}' <> 'true' then raise exception 'B onboarding failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.complete_onboarding(true, true, true, true, true,
    'terms-v1', 'privacy-v1', 'community-v1', 'onboarding-v1');
  if response #>> '{data,eligible}' <> 'true' then raise exception 'Moderator onboarding failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', c::text, true);
  response := public.complete_onboarding(true, true, true, true, true,
    'terms-v1', 'privacy-v1', 'community-v1', 'onboarding-v1');
  if response #>> '{data,eligible}' <> 'true' then raise exception 'C onboarding failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  first_response := public.place_note('Một ngày bình yên.', 'sage', true, 5, 6,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  if first_response #>> '{data,status}' <> 'pending_review' then raise exception 'Expected pending note: %', first_response; end if;
  note_a := (first_response #>> '{data,note_id}')::uuid;
  response := public.place_note('Một ngày bình yên.', 'sage', true, 5, 6,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  if response <> first_response then raise exception 'Placement retry changed result: % / %', first_response, response; end if;
  response := public.place_note('Nội dung khác.', 'sage', true, 5, 6,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  if response #>> '{error,code}' <> 'IDEMPOTENCY_CONFLICT' then raise exception 'Expected placement idempotency conflict: %', response; end if;

  response := public.edit_note(note_a, 'Nội dung đã sửa.', 'aaaaaaaa-eeee-4aaa-8aaa-aaaaaaaaaaaa');
  if response #>> '{data,status}' <> 'pending_review'
     or response #>> '{data,content_version}' <> '2'
     or response #>> '{data,content}' <> 'Nội dung đã sửa.' then
    raise exception 'Edit failed to update and requeue the note: %', response;
  end if;
  first_response := response;
  response := public.edit_note(note_a, 'Nội dung đã sửa.', 'aaaaaaaa-eeee-4aaa-8aaa-aaaaaaaaaaaa');
  if response <> first_response then raise exception 'Edit retry changed result: % / %', first_response, response; end if;
  response := public.edit_note(note_a, 'Nội dung khác.', 'aaaaaaaa-eeee-4aaa-8aaa-aaaaaaaaaaaa');
  if response #>> '{error,code}' <> 'IDEMPOTENCY_CONFLICT' then raise exception 'Expected edit idempotency conflict: %', response; end if;

  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.get_moderation_queue(20);
  if response #>> '{error,code}' <> 'NOT_AUTHORIZED' then raise exception 'Non-moderator accessed moderation queue: %', response; end if;
  response := public.place_note('Tờ giấy thứ hai.', 'pink', true, 5, 6,
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if response #>> '{error,code}' <> 'SLOT_OCCUPIED' then raise exception 'Expected cell collision: %', response; end if;
  response := public.place_note('Một lời nhắn nhỏ.', 'pink', true, 7, 6,
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  if response #>> '{data,status}' <> 'pending_review' then raise exception 'Failed placement after rolled-back collision: %', response; end if;
  note_b := (response #>> '{data,note_id}')::uuid;

  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.moderate_note(note_b, 'publish', 'Smoke test approval');
  if response #>> '{data,status}' <> 'published' then raise exception 'Moderation failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  first_response := public.send_encouragement(note_b, 'LISTEN',
    '12121212-1212-4121-8121-121212121212');
  if first_response #>> '{data,id}' is null then raise exception 'Encouragement failed: %', first_response; end if;
  response := public.send_encouragement(note_b, 'LISTEN',
    '12121212-1212-4121-8121-121212121212');
  if response <> first_response then raise exception 'Encouragement retry changed result: % / %', first_response, response; end if;
  response := public.send_encouragement(note_b, 'HUG',
    '12121212-1212-4121-8121-121212121212');
  if response #>> '{error,code}' <> 'IDEMPOTENCY_CONFLICT' then raise exception 'Expected encouragement idempotency conflict: %', response; end if;
  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.get_inbox('encouragements', null, null, 20);
  if jsonb_array_length(response #> '{data,items}') <> 1
     or response #> '{data,items,0,notification_id}' is null
     or response #>> '{data,items,0,is_read}' <> 'false' then
    raise exception 'Encouragement inbox record or unread status invalid: %', response;
  end if;
  response := public.mark_notification_read((response #>> '{data,items,0,notification_id}')::uuid);
  if response #>> '{data,read}' <> 'true' then raise exception 'Could not mark encouragement as read: %', response; end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.get_wall_tiles(0, 16, 0, 16, null, null, null, 200);
  tile_data := response #> '{data,items,0}';
  if tile_data is null or tile_data ? 'content' or tile_data ? 'author_id' then
    raise exception 'Wall DTO missing or leaked protected fields: %', response;
  end if;
  response := public.get_note_detail(note_b);
  if response #>> '{data,can_start_chat}' <> 'true' or response #> '{data,author_id}' is not null
     or response #>> '{data,already_encouraged}' <> 'true' then
    raise exception 'Detail DTO invalid or leaked author: %', response;
  end if;
  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.get_note_detail(note_b);
  if response #>> '{data,already_encouraged}' <> 'false' then raise exception 'Owner DTO leaked another sender state: %', response; end if;
  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.start_conversation_from_note(note_b, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  v_conversation_id := (response #>> '{data,conversation_id}')::uuid;
  if response #>> '{data,remaining_outbound}' <> '3' then raise exception 'Wrong initial quota: %', response; end if;
  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.edit_note(note_b, 'Sửa sau khi đã mở chat.', 'bbbbbbbb-eeee-4bbb-8bbb-bbbbbbbbbbbb');
  if response #>> '{error,code}' <> 'NOTE_ALREADY_INTERACTED' then raise exception 'Edit succeeded after conversation creation: %', response; end if;
  perform set_config('request.jwt.claim.sub', a::text, true);

  update app_private.app_settings set setting_value = 'review_clean' where setting_key = 'moderation_mode';
  response := public.send_message(v_conversation_id, 'Tin nhắn thứ nhất.', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
  if response #>> '{data,remaining_outbound}' <> '2' then raise exception 'Wrong quota after first send: %', response; end if;
  response := public.send_message(v_conversation_id, 'Tin nhắn thứ hai.', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
  if response #>> '{data,remaining_outbound}' <> '1' then raise exception 'Wrong quota after second send: %', response; end if;
  response := public.send_message(v_conversation_id, 'Tin nhắn thứ ba.', 'ffffffff-ffff-4fff-8fff-ffffffffffff');
  if response #>> '{data,remaining_outbound}' <> '0' then raise exception 'Wrong quota after third send: %', response; end if;
  response := public.send_message(v_conversation_id, 'Tin nhắn thứ tư.', '00000000-0000-4000-8000-000000000004');
  if response #>> '{error,code}' <> 'MESSAGE_LIMIT_REACHED' then raise exception 'Expected streak limit: %', response; end if;

  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.send_message(v_conversation_id, 'Mình đã nhận được lời bạn.', '00000000-0000-4000-8000-000000000005');
  if response #>> '{data,remaining_outbound}' <> '2' then raise exception 'Other participant did not reset streak: %', response; end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.get_inbox('chats', null, null, 20);
  if jsonb_array_length(response #> '{data,items}') <> 1 then raise exception 'Conversation missing from inbox: %', response; end if;
  if response #>> '{data,items,0,unread_count}' <> '1' then raise exception 'Incoming message unread count missing: %', response; end if;
  response := public.get_messages(v_conversation_id, null, null, 30);
  if jsonb_array_length(response #> '{data,items}') <> 4 or response #>> '{data,can_send}' <> 'true'
     or response #>> '{data,status}' <> 'active'
     or response #>> '{data,source_note_content}' <> 'Một lời nhắn nhỏ.' then
    raise exception 'Message history, source note context, or send status invalid: %', response;
  end if;
  response := public.get_inbox('chats', null, null, 20);
  if response #>> '{data,items,0,unread_count}' <> '0' then raise exception 'Opening messages did not clear own inbox unread count: %', response; end if;

  perform set_config('request.jwt.claim.sub', b::text, true);
  select m.id into message_id from public.messages m
   where m.conversation_id = v_conversation_id and m.sender_id = a
   order by m.created_at, m.id limit 1;
  response := public.report_and_block_message(message_id, 'harassment', 'Smoke test message report');
  if response #>> '{data,blocked}' <> 'true'
     or response #> '{data,report_id}' is null
     or (select status::text from public.conversations where id = v_conversation_id) <> 'blocked' then
    raise exception 'Message report and block were not atomic: %', response;
  end if;
  report_id := (response #>> '{data,report_id}')::uuid;
  message_report_id := report_id;
  response := public.report_and_block_message(message_id, 'harassment', 'Duplicate smoke test message report');
  if response #>> '{data,report_id}' <> report_id::text then
    raise exception 'Duplicate message report did not reuse the report: %', response;
  end if;

  response := public.report_and_block_note(note_b, 'spam', 'Own content must not report or block');
  if response #>> '{error,code}' <> 'NOTE_NOT_FOUND'
     or exists (select 1 from public.reports where reporter_id = b and target_type = 'note' and target_id = note_b) then
    raise exception 'Invalid report-and-block left a partial report: %', response;
  end if;
  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.report_and_block_note(note_b, 'spam', 'Smoke test report');
  if response #>> '{data,blocked}' <> 'true' then raise exception 'Atomic report and block failed: %', response; end if;
  report_id := (response #>> '{data,report_id}')::uuid;
  if report_id is null then raise exception 'Report creation failed: %', response; end if;
  response := public.report_and_block_note(note_b, 'spam', 'Duplicate smoke test report');
  if response #>> '{data,report_id}' <> report_id::text then raise exception 'Duplicate report was not idempotent: %', response; end if;
  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.review_report(report_id, 'hide_content', 'Smoke test content action');
  if response #>> '{data,status}' <> 'resolved'
     or (select status::text from public.notes where id = note_b) <> 'hidden' then
    raise exception 'Report content action did not atomically hide the note: %', response;
  end if;
  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.get_messages(v_conversation_id, null, null, 30);
  if response #>> '{data,source_note_content}' is not null then
    raise exception 'Hidden source note content remained visible in conversation: %', response;
  end if;

  response := public.block_from_conversation(v_conversation_id);
  if response #>> '{data,blocked}' <> 'true' then raise exception 'Block failed: %', response; end if;
  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.send_message(v_conversation_id, 'Tin sau khi bị chặn.', '00000000-0000-4000-8000-000000000006');
  if response #>> '{error,code}' not in ('BLOCKED', 'CLOSED') then raise exception 'Blocked participant could still send: %', response; end if;

  perform set_config('request.jwt.claim.sub', a::text, true);
  response := public.delete_note(note_a, '11111111-aaaa-4aaa-8aaa-111111111111');
  if response #>> '{data,deleted}' <> 'true' then raise exception 'Owner delete failed: %', response; end if;
  first_response := response;
  response := public.delete_note(note_a, '11111111-aaaa-4aaa-8aaa-111111111111');
  if response <> first_response then raise exception 'Delete retry changed result: % / %', first_response, response; end if;
  response := public.place_note('Quota must remain used.', 'blue', false, 8, 6,
    '11111111-bbbb-4bbb-8bbb-111111111111');
  if response #>> '{error,code}' <> 'DAILY_LIMIT' then raise exception 'Delete reset daily quota: %', response; end if;
  response := public.get_my_notes(null, null, 20);
  if response #>> '{data,daily_quota_used}' <> 'true' then raise exception 'My notes DTO omitted daily quota state: %', response; end if;

  if has_table_privilege('authenticated', 'public.notes', 'select') then
    raise exception 'Authenticated role has direct raw note SELECT';
  end if;
  if has_function_privilege('anon', 'public.place_note(text,text,boolean,bigint,bigint,uuid)', 'execute') then
    raise exception 'Anon role can execute place_note';
  end if;

  response := public.request_account_deletion(true, '22222222-aaaa-4aaa-8aaa-222222222222');
  if response #>> '{data,status}' <> 'pending' then raise exception 'Account deletion request failed: %', response; end if;
  deletion_request_id := (response #>> '{data,request_id}')::uuid;
  if (select account_status from public.profiles where user_id = a) <> 'deletion_requested' then
    raise exception 'Account was not immediately disabled';
  end if;
  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.process_deletion_request(deletion_request_id,
    'start_processing', 'Smoke test queued retention work');
  if response #>> '{data,status}' <> 'processing' then raise exception 'Deletion queue action failed: %', response; end if;
  response := public.process_deletion_request(deletion_request_id,
    'hold', 'Smoke test hold action');
  if response #>> '{data,status}' <> 'held' then raise exception 'Deletion hold failed: %', response; end if;
  response := public.process_deletion_request(deletion_request_id,
    'start_processing', 'Must not resume held request without a new workflow');
  if response #>> '{error,code}' <> 'INVALID_STATE' then raise exception 'Held deletion request was restarted: %', response; end if;

  perform set_config('request.jwt.claim.sub', c::text, true);
  response := public.place_note('A note from account C.', 'sage', false, 50, 50,
    '44444444-aaaa-4aaa-8aaa-444444444444');
  if response #>> '{data,note_id}' is null then raise exception 'C could not create a report fixture: %', response; end if;
  note_c := (response #>> '{data,note_id}')::uuid;
  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.moderate_note(note_c, 'publish', 'Smoke test report fixture');
  if response #>> '{data,status}' <> 'published' then raise exception 'Could not publish C report fixture: %', response; end if;
  perform set_config('request.jwt.claim.sub', c::text, true);
  response := public.get_account_settings();
  if response #>> '{data,notifications_enabled}' <> 'false' then
    raise exception 'Push preference must start disabled: %', response;
  end if;
  response := public.register_device(repeat('c', 64), 'test_push_token_for_suspend_cleanup_001', 'android');
  if response #>> '{error,code}' <> 'PUSH_DISABLED'
     or exists (select 1 from public.user_devices where user_id = c) then
    raise exception 'A disabled account preference accepted a push token: %', response;
  end if;
  response := public.update_settings(null, true);
  if response #>> '{data,notifications_enabled}' <> 'true' then
    raise exception 'Push opt-in preference failed to save: %', response;
  end if;
  response := public.register_device(repeat('c', 64), 'test_push_token_for_suspend_cleanup_001', 'android');
  if response #>> '{data,registered}' <> 'true' then raise exception 'C device setup failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.send_encouragement(note_c, 'THANKS',
    '12121212-1212-4121-8121-121212121213');
  if response #>> '{data,id}' is null then raise exception 'Push outbox fixture encouragement failed: %', response; end if;
  if not exists (
    select 1 from app_private.push_delivery_outbox outbox
    join public.notifications notification on notification.id = outbox.notification_id
    join public.user_devices device on device.id = outbox.device_id
    where notification.recipient_id = c and device.user_id = c
  ) then
    raise exception 'A notification for an opted-in device was not added to the push outbox';
  end if;

  perform set_config('request.jwt.claim.sub', c::text, true);
  response := public.update_settings(null, false);
  if response #>> '{data,notifications_enabled}' <> 'false'
     or exists (select 1 from public.user_devices where user_id = c)
     or exists (
       select 1 from app_private.push_delivery_outbox outbox
       join public.notifications notification on notification.id = outbox.notification_id
       where notification.recipient_id = c
     ) then
    raise exception 'Disabling push did not revoke tokens and pending delivery: %', response;
  end if;
  response := public.update_settings(null, true);
  if response #>> '{data,notifications_enabled}' <> 'true' then
    raise exception 'Push re-enable failed after revocation: %', response;
  end if;
  response := public.register_device(repeat('c', 64), 'test_push_token_for_suspend_cleanup_001', 'android');
  if response #>> '{data,registered}' <> 'true' then raise exception 'C device re-registration failed: %', response; end if;

  perform set_config('request.jwt.claim.sub', b::text, true);
  response := public.report_content('user', c, 'harassment', 'Must resolve user from context');
  if response #>> '{error,code}' <> 'INVALID_INPUT'
     or exists (select 1 from public.reports where reporter_id = b and target_type = 'user' and target_id = c) then
    raise exception 'Direct user-ID report API must be rejected without creating a report: %', response;
  end if;
  response := public.report_user_from_note(note_c, 'harassment', 'Smoke test account report from note');
  if response #>> '{data,report_id}' is null then raise exception 'Could not create user report: %', response; end if;
  user_report_id := (response #>> '{data,report_id}')::uuid;
  response := public.report_and_block_user_from_note(
    note_c, 'harassment', 'Smoke test report and block note author');
  if response #>> '{data,report_id}' <> user_report_id::text
     or response #>> '{data,blocked}' <> 'true'
     or not exists (select 1 from public.blocks where blocker_id = b and blocked_id = c) then
    raise exception 'Could not report and block note author as a user: %', response;
  end if;
  response := public.report_user_from_conversation(
    v_conversation_id, 'harassment', 'Smoke test account report from conversation');
  if response #>> '{data,report_id}' is null then raise exception 'Could not report conversation partner: %', response; end if;
  conversation_user_report_id := (response #>> '{data,report_id}')::uuid;
  response := public.report_and_block_user_from_conversation(
    v_conversation_id, 'harassment', 'Smoke test account report and block from conversation');
  if response #>> '{data,report_id}' <> conversation_user_report_id::text
     or response #>> '{data,blocked}' <> 'true' then
    raise exception 'Could not report and block conversation partner as a user: %', response;
  end if;
  perform set_config('request.jwt.claim.sub', moderator::text, true);
  response := public.get_reports_queue(50);
  if not exists (
    select 1
      from jsonb_array_elements(response #> '{data,items}') item
     where item ->> 'report_id' = user_report_id::text
       and item -> 'target_id' = 'null'::jsonb
  ) then
    raise exception 'User report queue exposed its target ID or omitted the report: %', response;
  end if;
  if not exists (
    select 1
      from jsonb_array_elements(response #> '{data,items}') item
     where item ->> 'report_id' = conversation_user_report_id::text
       and item -> 'target_id' = 'null'::jsonb
  ) then
    raise exception 'Conversation user report exposed its target ID or was omitted: %', response;
  end if;
  response := public.review_report(message_report_id, 'suspend_user', 'Must not suspend from a message report');
  if response #>> '{error,code}' <> 'INVALID_INPUT' then
    raise exception 'A message report was incorrectly allowed to suspend an account: %', response;
  end if;
  response := public.review_report(user_report_id, 'suspend_user', 'Smoke test account suspension');
  if response #>> '{data,status}' <> 'resolved'
     or (select account_status from public.profiles where user_id = c) <> 'suspended' then
    raise exception 'User report did not suspend the target account: %', response;
  end if;
  if not exists (
    select 1 from app_private.admin_audit_logs
     where actor_id = moderator
       and action = 'suspend_account_from_report'
       and target_type = 'user'
       and target_id = c
  ) then
    raise exception 'User suspension from a report was not audited against the target account';
  end if;
  if exists (select 1 from public.user_devices where user_id = c) then
    raise exception 'Suspending an account did not remove its push tokens';
  end if;
  perform set_config('request.jwt.claim.sub', c::text, true);
  response := public.place_note('Suspended accounts cannot publish.', 'sage', false, 50, 50,
    '44444444-aaaa-4aaa-8aaa-444444444444');
  if response #>> '{error,code}' <> 'NOT_ELIGIBLE' then
    raise exception 'Suspended account could still publish content: %', response;
  end if;
  response := public.register_device(repeat('d', 64), 'test_push_token_for_suspended_user_002', 'android');
  if response #>> '{error,code}' <> 'NOT_ELIGIBLE' then
    raise exception 'Suspended account could register a push token: %', response;
  end if;
end;
$$;

rollback;
