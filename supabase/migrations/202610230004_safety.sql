begin;

create type app_private.report_status as enum (
  'pending',
  'reviewing',
  'resolved',
  'dismissed'
);

create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete restrict,
  source_note_id uuid references public.notes (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint blocks_distinct_users check (blocker_id <> blocked_id),
  unique (blocker_id, blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete restrict,
  target_type text not null check (target_type in ('note', 'message', 'conversation', 'user')),
  target_id uuid not null,
  reason text not null check (reason in (
    'harassment', 'hate', 'sexual_content', 'self_harm_concern',
    'personal_info', 'spam', 'other'
  )),
  description text,
  status app_private.report_status not null default 'pending',
  moderator_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint reports_description_byte_limit check (description is null or octet_length(description) <= 3072),
  unique (reporter_id, target_type, target_id)
);

create index reports_queue_idx on public.reports (status, created_at, id);
create index reports_reporter_idx on public.reports (reporter_id, created_at desc, id desc);

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'held')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolution_code text,
  unique (user_id)
);

create table public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_key_hash text not null,
  push_token text not null,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_key_hash),
  constraint user_device_token_length check (length(push_token) between 20 and 4096)
);

create index user_devices_user_idx on public.user_devices (user_id);

create table app_private.moderation_queue (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('note', 'message')),
  target_id uuid not null,
  reason_code text not null,
  queue_status text not null default 'pending' check (queue_status in ('pending', 'reviewing', 'resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (target_type, target_id)
);

create function app_private.update_note_queue_reason()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app_private
as $$
begin
  if new.note_id is not null then
    update app_private.moderation_queue
       set reason_code = new.reason_code, updated_at = now()
     where target_type = 'note' and target_id = new.note_id and queue_status = 'pending';
  end if;
  return new;
end;
$$;

create function app_private.update_message_queue_reason()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app_private
as $$
begin
  if new.message_id is not null then
    update app_private.moderation_queue
       set reason_code = new.reason_code, updated_at = now()
     where target_type = 'message' and target_id = new.message_id and queue_status = 'pending';
  end if;
  return new;
end;
$$;

create trigger moderation_events_update_note_queue
after insert on app_private.moderation_events
for each row execute function app_private.update_note_queue_reason();

create trigger message_moderation_events_update_queue
after insert on app_private.message_moderation_events
for each row execute function app_private.update_message_queue_reason();

create index moderation_queue_pending_idx
  on app_private.moderation_queue (created_at, id)
  where queue_status in ('pending', 'reviewing');

alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.account_deletion_requests enable row level security;
alter table public.user_devices enable row level security;

revoke all on table public.blocks from public, anon, authenticated;
revoke all on table public.reports from public, anon, authenticated;
revoke all on table public.account_deletion_requests from public, anon, authenticated;
revoke all on table public.user_devices from public, anon, authenticated;
revoke all on table app_private.moderation_queue from public, anon, authenticated;

create function app_private.is_blocked_between(p_user_a uuid, p_user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private
as $$
  select exists (
    select 1 from public.blocks b
     where (b.blocker_id = p_user_a and b.blocked_id = p_user_b)
        or (b.blocker_id = p_user_b and b.blocked_id = p_user_a)
  )
$$;

create function app_private.is_moderator(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, app_private
as $$
  select exists (select 1 from app_private.admin_roles r where r.user_id = p_user_id)
$$;

create function public.can_access_private_wall_signals()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
  select app_private.profile_is_eligible(auth.uid())
$$;

create function app_private.enqueue_note_moderation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  reason_value text;
begin
  if new.status = 'pending_review' then
    select coalesce(m.reason_code, 'HOLD_ALL') into reason_value
      from app_private.moderation_events m
     where m.note_id = new.id
     order by m.created_at desc limit 1;
    insert into app_private.moderation_queue (target_type, target_id, reason_code)
    values ('note', new.id, coalesce(reason_value, 'HOLD_ALL'))
    on conflict (target_type, target_id) do update
      set queue_status = 'pending', reason_code = excluded.reason_code, updated_at = now();
  elsif tg_op = 'UPDATE' and old.status = 'pending_review' then
    update app_private.moderation_queue
       set queue_status = 'resolved', updated_at = now()
     where target_type = 'note' and target_id = new.id;
  end if;
  return new;
end;
$$;

create function app_private.enqueue_message_moderation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  reason_value text;
begin
  if new.status = 'pending_review' then
    select coalesce(m.reason_code, 'HOLD_ALL_MESSAGE') into reason_value
      from app_private.message_moderation_events m
     where m.message_id = new.id
     order by m.created_at desc limit 1;
    insert into app_private.moderation_queue (target_type, target_id, reason_code)
    values ('message', new.id, coalesce(reason_value, 'HOLD_ALL_MESSAGE'))
    on conflict (target_type, target_id) do update
      set queue_status = 'pending', reason_code = excluded.reason_code, updated_at = now();
  elsif tg_op = 'UPDATE' and old.status = 'pending_review' then
    update app_private.moderation_queue
       set queue_status = 'resolved', updated_at = now()
     where target_type = 'message' and target_id = new.id;
  end if;
  return new;
end;
$$;

create trigger notes_enqueue_moderation
after insert or update of status on public.notes
for each row execute function app_private.enqueue_note_moderation();

create trigger messages_enqueue_moderation
after insert or update of status on public.messages
for each row execute function app_private.enqueue_message_moderation();

create function app_private.broadcast_wall_region_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'kind', 'wall_revision',
      'id', new.tile_x::text || ':' || new.tile_y::text,
      'revision', new.revision
    ),
    'wall_changed',
    'wall:' || new.tile_x::text || ':' || new.tile_y::text,
    true
  );
  return new;
end;
$$;

create trigger wall_regions_broadcast_revision
after insert or update of revision on public.wall_regions
for each row execute function app_private.broadcast_wall_region_change();

create function public.block_from_note(p_note_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if p_note_id is null then
    return app_private.api_error('INVALID_INPUT');
  end if;
  select n.author_id into target_user from public.notes n
   where n.id = p_note_id and n.status in ('published', 'hidden');
  if not found then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  if target_user = actor_id then
    return app_private.api_error('INVALID_INPUT');
  end if;

  insert into public.blocks (blocker_id, blocked_id, source_note_id)
  values (actor_id, target_user, p_note_id)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.conversations c
     set status = 'blocked', updated_at = now()
   where actor_id in (c.participant_low, c.participant_high)
     and target_user in (c.participant_low, c.participant_high)
     and c.status = 'active';
  perform realtime.send(
    jsonb_build_object(
      'kind', 'conversation_blocked',
      'id', c.id,
      'conversation_id', c.id
    ),
    'signal',
    'conversation:' || c.id::text,
    true
  ) from public.conversations c
   where actor_id in (c.participant_low, c.participant_high)
     and target_user in (c.participant_low, c.participant_high)
     and c.status = 'blocked';
  return jsonb_build_object('data', jsonb_build_object('blocked', true));
end;
$$;

create function public.block_from_conversation(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  select case when c.participant_low = actor_id then c.participant_high else c.participant_low end
    into target_user
    from public.conversations c
   where c.id = p_conversation_id and actor_id in (c.participant_low, c.participant_high);
  if not found then
    return app_private.api_error('NOT_PARTICIPANT');
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (actor_id, target_user)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.conversations c set status = 'blocked', updated_at = now()
   where c.id = p_conversation_id and c.status = 'active';
  perform realtime.send(
    jsonb_build_object('kind', 'conversation_blocked', 'id', p_conversation_id),
    'signal',
    'conversation:' || p_conversation_id::text,
    true
  );
  return jsonb_build_object('data', jsonb_build_object('blocked', true));
end;
$$;

create function public.get_my_blocks()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  items jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'block_ref', b.id,
    'created_at', b.created_at
  ) order by b.created_at desc, b.id desc), '[]'::jsonb)
    into items from public.blocks b where b.blocker_id = actor_id;
  return jsonb_build_object('data', jsonb_build_object('items', items));
end;
$$;

create function public.unblock_from_my_list(p_block_ref uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  delete from public.blocks b
   where b.id = p_block_ref and b.blocker_id = actor_id
   returning b.blocked_id into target_user;
  if not found then
    return jsonb_build_object('data', jsonb_build_object('unblocked', false));
  end if;
  return jsonb_build_object('data', jsonb_build_object('unblocked', true));
end;
$$;

create function app_private.report_content_internal(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  report_row public.reports%rowtype;
  target_exists boolean := false;
  normalized_description text;
  report_count integer;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  normalized_description := nullif(btrim(normalize(coalesce(p_description, ''), NFC)), '');
  if p_target_type is null or p_target_type not in ('note', 'message', 'conversation', 'user')
     or p_target_id is null
     or p_reason is null or p_reason not in ('harassment', 'hate', 'sexual_content', 'self_harm_concern', 'personal_info', 'spam', 'other')
     or char_length(coalesce(normalized_description, '')) > 500
     or octet_length(coalesce(normalized_description, '')) > 3072 then
    return app_private.api_error('INVALID_INPUT');
  end if;

  case p_target_type
    when 'note' then
      select exists(select 1 from public.notes n where n.id = p_target_id
        and (n.status = 'published' or n.author_id = actor_id)) into target_exists;
    when 'message' then
      select exists(
        select 1 from public.messages m join public.conversations c on c.id = m.conversation_id
         where m.id = p_target_id and actor_id in (c.participant_low, c.participant_high)
      ) into target_exists;
    when 'conversation' then
      select exists(select 1 from public.conversations c where c.id = p_target_id
        and actor_id in (c.participant_low, c.participant_high)) into target_exists;
    when 'user' then
      select exists(select 1 from auth.users u where u.id = p_target_id and u.id <> actor_id) into target_exists;
  end case;
  if not target_exists then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;

  select * into report_row from public.reports r
   where r.reporter_id = actor_id
     and r.target_type = p_target_type
     and r.target_id = p_target_id;
  if found then
    return jsonb_build_object('data', jsonb_build_object(
      'report_id', report_row.id,
      'status', report_row.status
    ));
  end if;

  select count(*)::integer into report_count from public.reports r
   where r.reporter_id = actor_id and r.created_at > now() - interval '1 hour';
  if report_count >= 10 then
    return app_private.api_error('RATE_LIMITED', null, true);
  end if;

  insert into public.reports (reporter_id, target_type, target_id, reason, description)
  values (actor_id, p_target_type, p_target_id, p_reason, normalized_description)
  on conflict (reporter_id, target_type, target_id) do nothing
  returning * into report_row;
  if not found then
    select * into report_row from public.reports r
     where r.reporter_id = actor_id and r.target_type = p_target_type and r.target_id = p_target_id;
  end if;

  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_row.id,
    'status', report_row.status
  ));
end;
$$;

create function public.report_content(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
begin
  if p_target_type = 'user' then
    return app_private.api_error('INVALID_INPUT');
  end if;
  return app_private.report_content_internal(p_target_type, p_target_id, p_reason, p_description);
end;
$$;

create function public.report_user_from_note(
  p_note_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
begin
  if actor_id is null then return app_private.api_error('UNAUTHENTICATED'); end if;
  if p_note_id is null then return app_private.api_error('INVALID_INPUT'); end if;
  select n.author_id into target_user
    from public.notes n
   where n.id = p_note_id and n.status = 'published'
   for share;
  if not found or target_user = actor_id then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  return app_private.report_content_internal('user', target_user, p_reason, p_description);
end;
$$;

create function public.report_user_from_conversation(
  p_conversation_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
begin
  if actor_id is null then return app_private.api_error('UNAUTHENTICATED'); end if;
  select case when c.participant_low = actor_id then c.participant_high else c.participant_low end
    into target_user
    from public.conversations c
   where c.id = p_conversation_id
     and actor_id in (c.participant_low, c.participant_high)
   for update;
  if not found then return app_private.api_error('NOT_PARTICIPANT'); end if;
  return app_private.report_content_internal('user', target_user, p_reason, p_description);
end;
$$;

create function public.report_and_block_user_from_note(
  p_note_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
  report_result jsonb;
  block_result jsonb;
begin
  if actor_id is null then return app_private.api_error('UNAUTHENTICATED'); end if;
  select n.author_id into target_user
    from public.notes n
   where n.id = p_note_id and n.status in ('published', 'hidden')
   for update;
  if not found or target_user = actor_id then return app_private.api_error('NOTE_NOT_FOUND'); end if;
  report_result := app_private.report_content_internal('user', target_user, p_reason, p_description);
  if report_result ? 'error' then return report_result; end if;
  block_result := public.block_from_note(p_note_id);
  if block_result ? 'error' then return block_result; end if;
  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_result #>> '{data,report_id}',
    'blocked', true
  ));
end;
$$;

create function public.report_and_block_user_from_conversation(
  p_conversation_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  target_user uuid;
  report_result jsonb;
  block_result jsonb;
begin
  if actor_id is null then return app_private.api_error('UNAUTHENTICATED'); end if;
  select case when c.participant_low = actor_id then c.participant_high else c.participant_low end
    into target_user
    from public.conversations c
   where c.id = p_conversation_id
     and actor_id in (c.participant_low, c.participant_high)
   for update;
  if not found then return app_private.api_error('NOT_PARTICIPANT'); end if;
  report_result := app_private.report_content_internal('user', target_user, p_reason, p_description);
  if report_result ? 'error' then return report_result; end if;
  block_result := public.block_from_conversation(p_conversation_id);
  if block_result ? 'error' then return block_result; end if;
  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_result #>> '{data,report_id}',
    'blocked', true
  ));
end;
$$;

create function public.mark_notification_read(p_notification_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  update public.notifications n set read_at = coalesce(read_at, now())
   where n.id = p_notification_id and n.recipient_id = actor_id;
  return jsonb_build_object('data', jsonb_build_object('read', true));
end;
$$;

create function public.report_and_block_note(
  p_note_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  note_owner uuid;
  report_result jsonb;
  block_result jsonb;
begin
  select n.author_id into note_owner from public.notes n
   where n.id = p_note_id and n.status in ('published', 'hidden')
   for update;
  if not found or actor_id is null or note_owner = actor_id then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  report_result := public.report_content('note', p_note_id, p_reason, p_description);
  if report_result ? 'error' then
    return report_result;
  end if;
  block_result := public.block_from_note(p_note_id);
  if block_result ? 'error' then
    return block_result;
  end if;
  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_result #>> '{data,report_id}',
    'blocked', true
  ));
end;
$$;

create function public.report_and_block_conversation(
  p_conversation_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  is_participant boolean;
  report_result jsonb;
  block_result jsonb;
begin
  select actor_id in (c.participant_low, c.participant_high) into is_participant
    from public.conversations c where c.id = p_conversation_id for update;
  if not found or actor_id is null or not coalesce(is_participant, false) then
    return app_private.api_error('NOT_PARTICIPANT');
  end if;
  report_result := public.report_content('conversation', p_conversation_id, p_reason, p_description);
  if report_result ? 'error' then
    return report_result;
  end if;
  block_result := public.block_from_conversation(p_conversation_id);
  if block_result ? 'error' then
    return block_result;
  end if;
  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_result #>> '{data,report_id}',
    'blocked', true
  ));
end;
$$;

create function public.report_and_block_message(
  p_message_id uuid,
  p_reason text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  conversation_id uuid;
  message_sender uuid;
  report_result jsonb;
  block_result jsonb;
begin
  select m.conversation_id, m.sender_id
    into conversation_id, message_sender
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where m.id = p_message_id
     and actor_id in (c.participant_low, c.participant_high)
   for update of m;
  if not found or actor_id is null or message_sender = actor_id then
    return app_private.api_error('MESSAGE_NOT_FOUND');
  end if;

  report_result := public.report_content('message', p_message_id, p_reason, p_description);
  if report_result ? 'error' then
    return report_result;
  end if;
  block_result := public.block_from_conversation(conversation_id);
  if block_result ? 'error' then
    return block_result;
  end if;
  return jsonb_build_object('data', jsonb_build_object(
    'report_id', report_result #>> '{data,report_id}',
    'blocked', true
  ));
end;
$$;

create function public.request_account_deletion(p_confirm boolean, p_client_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  result jsonb;
  request_row public.account_deletion_requests%rowtype;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if p_confirm is distinct from true or p_client_request_id is null then
    return app_private.api_error('INVALID_INPUT');
  end if;

  payload_hash := md5('request_account_deletion');
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':request_account_deletion:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency r
   where r.actor_id = auth.uid() and r.operation = 'request_account_deletion'
     and r.request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  update public.profiles set account_status = 'deletion_requested'
   where user_id = actor_id and account_status <> 'deleted';
  if not found then
    return app_private.api_error('ACCOUNT_NOT_FOUND');
  end if;

  update public.notes
     set status = 'deleted', deleted_at = coalesce(deleted_at, now()), content = '', allow_chat = false
   where author_id = actor_id and status in ('pending_review', 'published', 'hidden');
  update public.conversations c
     set status = case when c.status = 'blocked' then 'blocked'::app_private.conversation_status
                       else 'closed_by_user'::app_private.conversation_status end,
         updated_at = now()
   where actor_id in (c.participant_low, c.participant_high)
     and c.status <> 'suspended';
  perform realtime.send(
    jsonb_build_object('kind', 'conversation_closed', 'id', c.id, 'conversation_id', c.id),
    'signal',
    'conversation:' || c.id::text,
    true
  ) from public.conversations c
   where actor_id in (c.participant_low, c.participant_high)
     and c.status = 'closed_by_user';
  delete from public.notifications where recipient_id = actor_id;
  delete from public.user_devices where user_id = actor_id;

  insert into public.account_deletion_requests (user_id)
  values (actor_id)
  on conflict (user_id) do update set updated_at = now()
  returning * into request_row;

  result := jsonb_build_object('data', jsonb_build_object(
    'request_id', request_row.id,
    'status', request_row.status,
    'requested_at', request_row.requested_at
  ));
  insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
  values (actor_id, 'request_account_deletion', p_client_request_id, payload_hash, result);
  return result;
end;
$$;

create function public.register_device(
  p_device_key_hash text,
  p_push_token text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_device_key_hash is null or length(p_device_key_hash) <> 64
     or p_device_key_hash !~ '^[0-9a-f]{64}$'
     or p_push_token is null or length(p_push_token) < 20 or length(p_push_token) > 4096
     or p_platform is null or p_platform not in ('android', 'ios') then
    return app_private.api_error('INVALID_INPUT');
  end if;

  insert into public.user_devices (user_id, device_key_hash, push_token, platform)
  values (actor_id, p_device_key_hash, p_push_token, p_platform)
  on conflict (user_id, device_key_hash) do update
    set push_token = excluded.push_token, platform = excluded.platform, updated_at = now();
  return jsonb_build_object('data', jsonb_build_object('registered', true));
end;
$$;

create function public.unregister_device(p_device_key_hash text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  delete from public.user_devices d
   where d.user_id = actor_id and d.device_key_hash = p_device_key_hash;
  return jsonb_build_object('data', jsonb_build_object('unregistered', true));
end;
$$;

create function public.get_moderation_queue(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  items jsonb;
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  select coalesce(jsonb_agg(row_data order by created_at, id), '[]'::jsonb)
    into items
    from (
      select q.id, q.target_type, q.target_id, q.reason_code, q.queue_status, q.created_at,
             case when q.target_type = 'note' then n.content else m.body end as content,
             case when q.target_type = 'note' then n.paper_color else null end as paper_color,
             case when q.target_type = 'note' then n.status::text else m.status::text end as content_status
        from app_private.moderation_queue q
        left join public.notes n on q.target_type = 'note' and n.id = q.target_id
        left join public.messages m on q.target_type = 'message' and m.id = q.target_id
       where q.queue_status in ('pending', 'reviewing')
       order by q.created_at, q.id
       limit safe_limit
    ) queued
    cross join lateral (select jsonb_build_object(
      'id', queued.id,
      'target_type', queued.target_type,
      'target_id', queued.target_id,
      'reason_code', queued.reason_code,
      'status', queued.queue_status,
      'content', queued.content,
      'paper_color', queued.paper_color,
      'content_status', queued.content_status,
      'created_at', queued.created_at
    ) as row_data) encoded;
  return jsonb_build_object('data', jsonb_build_object('items', items));
end;
$$;

create function public.get_reports_queue(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  items jsonb;
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'report_id', page.id,
    'target_type', page.target_type,
    'target_id', page.safe_target_id,
    'reason', page.reason,
    'description', page.description,
    'status', page.status,
    'created_at', page.created_at,
    'content', page.content
  ) order by page.created_at, page.id), '[]'::jsonb)
    into items
    from (
      select r.id, r.target_type, r.target_id, r.reason, r.description, r.status, r.created_at,
             case r.target_type
               when 'note' then (select n.content from public.notes n where n.id = r.target_id)
               when 'message' then (select m.body from public.messages m where m.id = r.target_id)
               else null
             end as content,
             case when r.target_type = 'user' then null::uuid else r.target_id end as safe_target_id
        from public.reports r
       where r.status in ('pending', 'reviewing')
       order by r.created_at, r.id
       limit safe_limit
    ) page;
  return jsonb_build_object('data', jsonb_build_object('items', items));
end;
$$;

create function public.get_deletion_queue(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  items jsonb;
  safe_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'request_id', page.id,
    'status', page.status,
    'requested_at', page.requested_at,
    'resolution_code', page.resolution_code
  ) order by page.requested_at, page.id), '[]'::jsonb)
    into items
    from (
      select r.id, r.status, r.requested_at, r.resolution_code
        from public.account_deletion_requests r
       where r.status in ('pending', 'processing', 'held')
       order by r.requested_at, r.id
       limit safe_limit
    ) page;
  return jsonb_build_object('data', jsonb_build_object('items', items));
end;
$$;

create function public.moderate_note(p_note_id uuid, p_action text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  note_row public.notes%rowtype;
  next_status app_private.note_status;
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  if p_note_id is null or p_action not in ('publish', 'hide', 'reject', 'delete', 'restore')
     or nullif(btrim(p_reason), '') is null or char_length(p_reason) > 500 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  select * into note_row from public.notes where id = p_note_id for update;
  if not found then return app_private.api_error('NOTE_NOT_FOUND'); end if;

  next_status := case p_action
    when 'publish' then 'published'::app_private.note_status
    when 'hide' then 'hidden'::app_private.note_status
    when 'reject' then 'rejected'::app_private.note_status
    when 'delete' then 'deleted'::app_private.note_status
    when 'restore' then 'published'::app_private.note_status
  end;
  if note_row.status = 'deleted'
     or (p_action = 'publish' and note_row.status <> 'pending_review')
     or (p_action = 'reject' and note_row.status <> 'pending_review')
     or (p_action = 'hide' and note_row.status <> 'published')
     or (p_action = 'restore' and note_row.status <> 'hidden') then
    return app_private.api_error('INVALID_STATE');
  end if;

  update public.notes
     set status = next_status,
         published_at = case when next_status = 'published' then coalesce(published_at, now()) else published_at end,
         deleted_at = case when next_status = 'deleted' then coalesce(deleted_at, now()) else deleted_at end,
         content = case when next_status = 'deleted' then '' else content end,
         allow_chat = case when next_status in ('deleted', 'rejected') then false else allow_chat end
   where id = note_row.id;
  insert into app_private.moderation_events (note_id, actor_id, from_status, to_status, reason_code)
  values (note_row.id, actor_id, note_row.status, next_status, left(btrim(p_reason), 100));
  insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
  values (actor_id, 'moderate_note:' || p_action, 'note', note_row.id, left(btrim(p_reason), 500));
  return jsonb_build_object('data', jsonb_build_object('status', next_status));
end;
$$;

create function public.moderate_message(p_message_id uuid, p_action text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  message_row public.messages%rowtype;
  conversation_row public.conversations%rowtype;
  target_user uuid;
  next_status app_private.message_status;
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  if p_message_id is null or p_action not in ('approve', 'reject', 'hide')
     or nullif(btrim(p_reason), '') is null or char_length(p_reason) > 500 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  select * into message_row from public.messages where id = p_message_id for update;
  if not found then return app_private.api_error('NOTE_NOT_FOUND'); end if;
  select * into conversation_row from public.conversations where id = message_row.conversation_id for update;

  if p_action = 'approve' then
    if message_row.status <> 'pending_review' or conversation_row.status <> 'active' then
      return app_private.api_error('INVALID_STATE');
    end if;
    target_user := case when message_row.sender_id = conversation_row.participant_low
      then conversation_row.participant_high else conversation_row.participant_low end;
    if app_private.is_blocked_between(message_row.sender_id, target_user) then
      return app_private.api_error('BLOCKED');
    end if;
    next_status := 'delivered';
    insert into public.notifications (recipient_id, notification_type, source_id, conversation_id)
    values (target_user, 'message', message_row.id, message_row.conversation_id)
    on conflict (recipient_id, notification_type, source_id) do nothing;
    perform realtime.send(
      jsonb_build_object(
        'kind', 'message',
        'id', message_row.id,
        'conversation_id', message_row.conversation_id
      ),
      'signal',
      'conversation:' || message_row.conversation_id::text,
      true
    );
  elsif p_action = 'reject' then
    if message_row.status <> 'pending_review' then return app_private.api_error('INVALID_STATE'); end if;
    next_status := 'rejected';
  else
    if message_row.status <> 'delivered' then return app_private.api_error('INVALID_STATE'); end if;
    next_status := 'hidden';
  end if;

  update public.messages set status = next_status where id = message_row.id;
  insert into app_private.message_moderation_events (message_id, actor_id, reason_code)
  values (message_row.id, actor_id, left(btrim(p_reason), 100));
  insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
  values (actor_id, 'moderate_message:' || p_action, 'message', message_row.id, left(btrim(p_reason), 500));
  return jsonb_build_object('data', jsonb_build_object('status', next_status));
end;
$$;

create function public.review_report(p_report_id uuid, p_action text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  next_status app_private.report_status;
  report_row public.reports%rowtype;
  note_row public.notes%rowtype;
  message_row public.messages%rowtype;
  conversation_row public.conversations%rowtype;
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  if p_report_id is null
     or p_action is null
     or p_action not in ('start_review', 'resolve', 'dismiss', 'hide_content', 'suspend_user')
     or p_reason is null
     or nullif(btrim(p_reason), '') is null
     or char_length(p_reason) > 500 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  select * into report_row from public.reports where id = p_report_id for update;
  if not found then return app_private.api_error('REPORT_NOT_FOUND'); end if;
  if report_row.status in ('resolved', 'dismissed') then
    return app_private.api_error('INVALID_STATE');
  end if;

  if p_action = 'suspend_user' and report_row.target_type <> 'user' then
    return app_private.api_error('INVALID_INPUT');
  end if;
  if report_row.target_type = 'user'
     and p_action in ('hide_content', 'suspend_user')
     and report_row.target_id = actor_id then
    return app_private.api_error('INVALID_INPUT');
  end if;

  if p_action in ('hide_content', 'suspend_user') then
    case report_row.target_type
      when 'note' then
        select * into note_row from public.notes n where n.id = report_row.target_id for update;
        if not found then return app_private.api_error('REPORT_TARGET_NOT_FOUND'); end if;
        if note_row.status = 'published' then
          update public.notes set status = 'hidden' where id = note_row.id;
          insert into app_private.moderation_events (note_id, actor_id, from_status, to_status, reason_code)
          values (note_row.id, actor_id, note_row.status, 'hidden', left(btrim(p_reason), 100));
        elsif note_row.status not in ('hidden', 'rejected', 'deleted') then
          return app_private.api_error('INVALID_STATE');
        end if;
      when 'message' then
        select * into message_row from public.messages m where m.id = report_row.target_id for update;
        if not found then return app_private.api_error('REPORT_TARGET_NOT_FOUND'); end if;
        if message_row.status in ('delivered', 'pending_review') then
          update public.messages set status = 'hidden' where id = message_row.id;
          insert into app_private.message_moderation_events (message_id, actor_id, reason_code)
          values (message_row.id, actor_id, left(btrim(p_reason), 100));
          delete from public.notifications where source_id = message_row.id;
          perform realtime.send(
            jsonb_build_object('kind', 'message_hidden', 'id', message_row.id),
            'signal', 'conversation:' || message_row.conversation_id::text, true
          );
        elsif message_row.status <> 'hidden' then
          return app_private.api_error('INVALID_STATE');
        end if;
      when 'conversation' then
        select * into conversation_row from public.conversations c
         where c.id = report_row.target_id for update;
        if not found then return app_private.api_error('REPORT_TARGET_NOT_FOUND'); end if;
        update public.conversations set status = 'suspended', updated_at = now()
         where id = conversation_row.id and status = 'active';
        update public.messages set status = 'hidden'
         where conversation_id = conversation_row.id and status in ('delivered', 'pending_review');
        delete from public.notifications where conversation_id = conversation_row.id;
        perform realtime.send(
          jsonb_build_object('kind', 'conversation_closed', 'id', conversation_row.id),
          'signal', 'conversation:' || conversation_row.id::text, true
        );
      when 'user' then
        update public.profiles set account_status = 'suspended'
         where user_id = report_row.target_id and account_status = 'active';
        if not found and not exists (
          select 1 from public.profiles p where p.user_id = report_row.target_id
            and p.account_status = 'suspended'
        ) then
          return app_private.api_error('REPORT_TARGET_NOT_FOUND');
        end if;
        update public.notes set status = 'hidden'
         where author_id = report_row.target_id and status = 'published';
        update public.conversations c set status = 'suspended', updated_at = now()
         where report_row.target_id in (c.participant_low, c.participant_high) and c.status = 'active';
        delete from public.notifications
         where recipient_id = report_row.target_id
            or conversation_id in (
              select c.id from public.conversations c
               where report_row.target_id in (c.participant_low, c.participant_high)
            );
        delete from public.user_devices where user_id = report_row.target_id;
        insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
        values (actor_id, 'suspend_account_from_report', 'user', report_row.target_id, left(btrim(p_reason), 500));
    end case;
    next_status := 'resolved';
  else
    next_status := case p_action
      when 'start_review' then 'reviewing'::app_private.report_status
      when 'resolve' then 'resolved'::app_private.report_status
      when 'dismiss' then 'dismissed'::app_private.report_status
    end;
  end if;

  update public.reports
     set status = next_status,
         moderator_id = actor_id,
         resolved_at = case when next_status in ('resolved', 'dismissed') then now() else null end,
         updated_at = now()
   where id = report_row.id;
  insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
  values (actor_id, 'review_report:' || p_action, 'report', report_row.id, left(btrim(p_reason), 500));
  return jsonb_build_object('data', jsonb_build_object('status', next_status));
end;
$$;

create function public.process_deletion_request(
  p_request_id uuid,
  p_action text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  request_row public.account_deletion_requests%rowtype;
  next_status text;
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  if p_request_id is null or p_action not in ('start_processing', 'hold')
     or nullif(btrim(p_reason), '') is null or char_length(p_reason) > 500 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  select * into request_row from public.account_deletion_requests r
   where r.id = p_request_id for update;
  if not found then return app_private.api_error('DELETION_REQUEST_NOT_FOUND'); end if;
  if request_row.status = 'completed'
     or (request_row.status = 'held' and p_action = 'start_processing') then
    return app_private.api_error('INVALID_STATE');
  end if;
  next_status := case p_action when 'start_processing' then 'processing' else 'held' end;
  update public.account_deletion_requests
     set status = next_status, resolution_code = left(btrim(p_reason), 100), updated_at = now()
   where id = request_row.id;
  insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
  values (actor_id, 'process_deletion_request:' || p_action, 'deletion_request', request_row.id, left(btrim(p_reason), 500));
  return jsonb_build_object('data', jsonb_build_object('status', next_status));
end;
$$;

create function public.moderate_account(p_target_user_id uuid, p_action text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  next_status text;
begin
  if actor_id is null or not app_private.is_moderator(actor_id) then
    return app_private.api_error('NOT_AUTHORIZED');
  end if;
  if p_target_user_id is null or p_target_user_id = actor_id
     or p_action not in ('suspend', 'restore')
     or nullif(btrim(p_reason), '') is null or char_length(p_reason) > 500 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  next_status := case p_action when 'suspend' then 'suspended' else 'active' end;
  update public.profiles set account_status = next_status where user_id = p_target_user_id;
  if not found then return app_private.api_error('ACCOUNT_NOT_FOUND'); end if;

  if p_action = 'suspend' then
    update public.notes set status = 'hidden' where author_id = p_target_user_id and status = 'published';
    update public.conversations c set status = 'suspended', updated_at = now()
     where p_target_user_id in (c.participant_low, c.participant_high) and c.status = 'active';
    delete from public.notifications
     where recipient_id = p_target_user_id
        or conversation_id in (
          select c.id from public.conversations c
           where p_target_user_id in (c.participant_low, c.participant_high)
        );
    delete from public.user_devices where user_id = p_target_user_id;
  end if;
  insert into app_private.admin_audit_logs (actor_id, action, target_type, target_id, reason)
  values (actor_id, 'moderate_account:' || p_action, 'user', p_target_user_id, left(btrim(p_reason), 500));
  return jsonb_build_object('data', jsonb_build_object('account_status', next_status));
end;
$$;

revoke all on all tables in schema app_private from public, anon, authenticated;
revoke all on all functions in schema app_private from public, anon, authenticated;
revoke all on all sequences in schema app_private from public, anon, authenticated;

revoke all on function public.block_from_note(uuid) from public, anon;
revoke all on function public.block_from_conversation(uuid) from public, anon;
revoke all on function public.get_my_blocks() from public, anon;
revoke all on function public.unblock_from_my_list(uuid) from public, anon;
revoke all on function public.report_content(text, uuid, text, text) from public, anon;
revoke all on function public.report_user_from_note(uuid, text, text) from public, anon;
revoke all on function public.report_user_from_conversation(uuid, text, text) from public, anon;
revoke all on function public.report_and_block_user_from_note(uuid, text, text) from public, anon;
revoke all on function public.report_and_block_user_from_conversation(uuid, text, text) from public, anon;
revoke all on function public.report_and_block_note(uuid, text, text) from public, anon;
revoke all on function public.report_and_block_conversation(uuid, text, text) from public, anon;
revoke all on function public.report_and_block_message(uuid, text, text) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.request_account_deletion(boolean, uuid) from public, anon;
revoke all on function public.register_device(text, text, text) from public, anon;
revoke all on function public.unregister_device(text) from public, anon;
revoke all on function public.get_moderation_queue(integer) from public, anon;
revoke all on function public.get_reports_queue(integer) from public, anon;
revoke all on function public.get_deletion_queue(integer) from public, anon;
revoke all on function public.moderate_note(uuid, text, text) from public, anon;
revoke all on function public.moderate_message(uuid, text, text) from public, anon;
revoke all on function public.review_report(uuid, text, text) from public, anon;
revoke all on function public.process_deletion_request(uuid, text, text) from public, anon;
revoke all on function public.moderate_account(uuid, text, text) from public, anon;
revoke all on function public.can_access_private_wall_signals() from public, anon;

grant execute on function public.block_from_note(uuid) to authenticated;
grant execute on function public.block_from_conversation(uuid) to authenticated;
grant execute on function public.get_my_blocks() to authenticated;
grant execute on function public.unblock_from_my_list(uuid) to authenticated;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;
grant execute on function public.report_user_from_note(uuid, text, text) to authenticated;
grant execute on function public.report_user_from_conversation(uuid, text, text) to authenticated;
grant execute on function public.report_and_block_user_from_note(uuid, text, text) to authenticated;
grant execute on function public.report_and_block_user_from_conversation(uuid, text, text) to authenticated;
grant execute on function public.report_and_block_note(uuid, text, text) to authenticated;
grant execute on function public.report_and_block_conversation(uuid, text, text) to authenticated;
grant execute on function public.report_and_block_message(uuid, text, text) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.request_account_deletion(boolean, uuid) to authenticated;
grant execute on function public.register_device(text, text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;
grant execute on function public.get_moderation_queue(integer) to authenticated;
grant execute on function public.get_reports_queue(integer) to authenticated;
grant execute on function public.get_deletion_queue(integer) to authenticated;
grant execute on function public.moderate_note(uuid, text, text) to authenticated;
grant execute on function public.moderate_message(uuid, text, text) to authenticated;
grant execute on function public.review_report(uuid, text, text) to authenticated;
grant execute on function public.process_deletion_request(uuid, text, text) to authenticated;
grant execute on function public.moderate_account(uuid, text, text) to authenticated;
grant execute on function public.can_access_private_wall_signals() to authenticated;

create policy "eligible users receive conversation signals"
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and exists (
    select 1
      from public.conversations c
     where realtime.topic() = 'conversation:' || c.id::text
       and auth.uid() in (c.participant_low, c.participant_high)
       and c.status = 'active'
  )
);

create policy "users receive their own inbox signals"
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() = 'user:' || auth.uid()::text
);

create policy "eligible users receive wall revision signals"
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and realtime.topic() ~ '^wall:-?[0-9]+:-?[0-9]+$'
  and public.can_access_private_wall_signals()
);

commit;
