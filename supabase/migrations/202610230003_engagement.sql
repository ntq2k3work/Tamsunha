begin;

create type app_private.conversation_status as enum (
  'active',
  'closed_by_user',
  'blocked',
  'suspended'
);

create type app_private.message_status as enum (
  'pending_review',
  'delivered',
  'rejected',
  'hidden'
);

create table public.encouragements (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes (id) on delete restrict,
  sender_id uuid not null references auth.users (id) on delete restrict,
  template_key text not null check (template_key in ('LISTEN', 'TOMORROW', 'TRIED', 'THANKS', 'HUG')),
  created_at timestamptz not null default now(),
  unique (note_id, sender_id)
);

create index encouragements_note_time_idx
  on public.encouragements (note_id, created_at desc, id desc);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  participant_low uuid not null references auth.users (id) on delete restrict,
  participant_high uuid not null references auth.users (id) on delete restrict,
  source_note_id uuid not null references public.notes (id) on delete restrict,
  created_by uuid not null references auth.users (id) on delete restrict,
  status app_private.conversation_status not null default 'active',
  last_sender_id uuid references auth.users (id) on delete set null,
  streak_count integer not null default 0 check (streak_count between 0 and 3),
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_ordered_pair check (participant_low < participant_high),
  unique (participant_low, participant_high)
);

create index conversations_low_updated_idx
  on public.conversations (participant_low, updated_at desc, id desc);
create index conversations_high_updated_idx
  on public.conversations (participant_high, updated_at desc, id desc);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete restrict,
  sender_id uuid not null references auth.users (id) on delete restrict,
  client_request_id uuid not null,
  body text not null,
  status app_private.message_status not null default 'pending_review',
  created_at timestamptz not null default now(),
  constraint messages_content_byte_limit check (octet_length(body) <= 3072),
  unique (sender_id, client_request_id)
);

create table app_private.message_moderation_events (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.messages (id) on delete set null,
  actor_id uuid references auth.users (id) on delete set null,
  reason_code text not null,
  created_at timestamptz not null default now()
);

create index messages_conversation_created_idx
  on public.messages (conversation_id, created_at desc, id desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users (id) on delete cascade,
  notification_type text not null check (notification_type in ('encouragement', 'message')),
  source_id uuid not null,
  conversation_id uuid references public.conversations (id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (recipient_id, notification_type, source_id)
);

create index notifications_recipient_unread_idx
  on public.notifications (recipient_id, created_at desc, id desc)
  where read_at is null;

create table app_private.rate_limit_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users (id) on delete cascade,
  operation text not null,
  occurred_at timestamptz not null default now()
);

create index rate_limit_events_actor_operation_time_idx
  on app_private.rate_limit_events (actor_id, operation, occurred_at desc);

alter table public.encouragements enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;

revoke all on table public.encouragements from public, anon, authenticated;
revoke all on table public.conversations from public, anon, authenticated;
revoke all on table public.messages from public, anon, authenticated;
revoke all on table public.notifications from public, anon, authenticated;
revoke all on table app_private.rate_limit_events from public, anon, authenticated;
revoke all on table app_private.message_moderation_events from public, anon, authenticated;

create function app_private.content_risk_code(p_content text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case
    when p_content ~* '(https?://|www\.|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|\+?[0-9][0-9 .()-]{7,}[0-9])'
      then 'CONTACT_OR_LINK'
    else null
  end
$$;

create function public.send_encouragement(
  p_note_id uuid,
  p_template_key text,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  note_owner uuid;
  note_status app_private.note_status;
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  existing public.encouragements%rowtype;
  created_encouragement public.encouragements%rowtype;
  result jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_note_id is null or p_client_request_id is null
     or p_template_key not in ('LISTEN', 'TOMORROW', 'TRIED', 'THANKS', 'HUG') then
    return app_private.api_error('INVALID_INPUT');
  end if;

  payload_hash := md5(jsonb_build_object('note_id', p_note_id, 'template_key', p_template_key)::text);
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':send_encouragement:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency r
   where r.actor_id = auth.uid() and r.operation = 'send_encouragement'
     and r.request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  select n.author_id, n.status into note_owner, note_status
    from public.notes n where n.id = p_note_id
   for update of n;
  if not found or note_status <> 'published' then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  if note_owner = actor_id then
    return app_private.api_error('INVALID_INPUT', 'Bạn không thể tự gửi lời động viên cho giấy của mình.');
  end if;
  if app_private.is_blocked_between(actor_id, note_owner) then
    return app_private.api_error('BLOCKED');
  end if;

  select * into existing from public.encouragements e
   where e.note_id = p_note_id and e.sender_id = actor_id;
  if found then
    return app_private.api_error('ALREADY_ENCOURAGED');
  end if;

  begin
    insert into public.encouragements (note_id, sender_id, template_key)
    values (p_note_id, actor_id, p_template_key)
    returning * into created_encouragement;

    insert into public.notifications (recipient_id, notification_type, source_id)
    values (note_owner, 'encouragement', created_encouragement.id)
    on conflict (recipient_id, notification_type, source_id) do nothing;

    perform realtime.send(
      jsonb_build_object('kind', 'encouragement', 'id', created_encouragement.id),
      'signal',
      'user:' || note_owner::text,
      true
    );

    result := jsonb_build_object('data', jsonb_build_object(
      'id', created_encouragement.id,
      'created_at', created_encouragement.created_at
    ));
    insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
    values (actor_id, 'send_encouragement', p_client_request_id, payload_hash, result);
  exception when unique_violation then
    return app_private.api_error('ALREADY_ENCOURAGED');
  end;
  return result;
end;
$$;

create function public.start_conversation_from_note(
  p_note_id uuid,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  note_owner uuid;
  note_status app_private.note_status;
  note_allows_chat boolean;
  low_user uuid;
  high_user uuid;
  conversation_row public.conversations%rowtype;
  created_new boolean := false;
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  result jsonb;
  outbound_remaining integer;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_note_id is null or p_client_request_id is null then
    return app_private.api_error('INVALID_INPUT');
  end if;

  payload_hash := md5(jsonb_build_object('note_id', p_note_id)::text);
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':start_conversation:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency r
   where r.actor_id = auth.uid() and r.operation = 'start_conversation_from_note'
     and r.request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  select n.author_id, n.status, n.allow_chat
    into note_owner, note_status, note_allows_chat
    from public.notes n where n.id = p_note_id
   for update of n;
  if not found or note_status <> 'published' then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  if note_owner = actor_id then
    return app_private.api_error('INVALID_INPUT');
  end if;
  if not note_allows_chat then
    return app_private.api_error('CHAT_DISABLED');
  end if;
  if app_private.is_blocked_between(actor_id, note_owner) then
    return app_private.api_error('BLOCKED');
  end if;

  low_user := least(actor_id, note_owner);
  high_user := greatest(actor_id, note_owner);
  perform pg_advisory_xact_lock(hashtextextended(low_user::text || ':' || high_user::text, 0));

  insert into public.conversations (
    participant_low, participant_high, source_note_id, created_by
  ) values (
    low_user, high_user, p_note_id, actor_id
  ) on conflict (participant_low, participant_high) do nothing;
  created_new := found;

  select * into conversation_row
    from public.conversations c
   where c.participant_low = low_user and c.participant_high = high_user
   for update;
  if conversation_row.status <> 'active' then
    return app_private.api_error('CLOSED');
  end if;
  outbound_remaining := case
    when conversation_row.last_sender_id = actor_id then 3 - conversation_row.streak_count
    else 3
  end;
  result := jsonb_build_object('data', jsonb_build_object(
    'conversation_id', conversation_row.id,
    'created', created_new,
    'can_send', outbound_remaining > 0,
    'remaining_outbound', outbound_remaining
  ));
  insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
  values (actor_id, 'start_conversation_from_note', p_client_request_id, payload_hash, result);
  return result;
end;
$$;

create function public.send_message(
  p_conversation_id uuid,
  p_body text,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  normalized_body text;
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  existing public.messages%rowtype;
  conversation_row public.conversations%rowtype;
  created_message public.messages%rowtype;
  target_user uuid;
  new_streak integer;
  remaining integer;
  moderation_mode text;
  risk_code text;
  message_status app_private.message_status;
  result jsonb;
  recent_count integer;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;

  normalized_body := btrim(normalize(replace(replace(coalesce(p_body, ''), E'\r\n', E'\n'), E'\r', E'\n'), NFC));
  if normalized_body = '' or char_length(normalized_body) > 500
     or octet_length(normalized_body) > 3072
     or p_conversation_id is null or p_client_request_id is null then
    return app_private.api_error('INVALID_INPUT', 'Tin nhắn cần có nội dung và không quá 500 ký tự.');
  end if;

  payload_hash := md5(jsonb_build_object(
    'conversation_id', p_conversation_id,
    'body', normalized_body
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':send_message:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency r
   where r.actor_id = auth.uid() and r.operation = 'send_message'
     and r.request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  select * into existing from public.messages m
   where m.sender_id = actor_id and m.client_request_id = p_client_request_id;
  if found then
    if existing.conversation_id <> p_conversation_id or existing.body <> normalized_body then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    select * into conversation_row from public.conversations c where c.id = p_conversation_id;
    remaining := case when conversation_row.last_sender_id = actor_id
      then greatest(0, 3 - conversation_row.streak_count) else 3 end;
    return jsonb_build_object('data', jsonb_build_object(
      'message_id', existing.id,
      'created_at', existing.created_at,
      'remaining_outbound', remaining,
      'status', existing.status
    ));
  end if;

  select * into conversation_row
    from public.conversations c where c.id = p_conversation_id for update;
  if not found or actor_id not in (conversation_row.participant_low, conversation_row.participant_high) then
    return app_private.api_error('NOT_PARTICIPANT');
  end if;
  if conversation_row.status <> 'active' then
    return app_private.api_error('CLOSED');
  end if;
  target_user := case when conversation_row.participant_low = actor_id
    then conversation_row.participant_high else conversation_row.participant_low end;
  if app_private.is_blocked_between(actor_id, target_user) then
    return app_private.api_error('BLOCKED');
  end if;

  select count(*)::integer into recent_count
    from app_private.rate_limit_events e
   where e.actor_id = auth.uid() and e.operation = 'send_message'
     and e.occurred_at > now() - interval '1 minute';
  if recent_count >= 30 then
    return app_private.api_error('RATE_LIMITED', null, true);
  end if;
  insert into app_private.rate_limit_events (actor_id, operation) values (actor_id, 'send_message');

  new_streak := case when conversation_row.last_sender_id = actor_id
    then conversation_row.streak_count + 1 else 1 end;
  if new_streak > 3 then
    return app_private.api_error('MESSAGE_LIMIT_REACHED');
  end if;

  select setting_value into moderation_mode from app_private.app_settings
   where setting_key = 'moderation_mode';
  risk_code := app_private.content_risk_code(normalized_body);
  if moderation_mode = 'hold_all' or risk_code is not null then
    message_status := 'pending_review';
  else
    message_status := 'delivered';
  end if;

  begin
    insert into public.messages (
      conversation_id, sender_id, client_request_id, body, status
    ) values (
      conversation_row.id, actor_id, p_client_request_id, normalized_body, message_status
    ) returning * into created_message;

    update public.conversations
       set last_sender_id = actor_id,
           streak_count = new_streak,
           last_message_at = created_message.created_at,
           updated_at = now()
     where id = conversation_row.id;

    if message_status = 'delivered' then
      insert into public.notifications (recipient_id, notification_type, source_id, conversation_id)
      values (target_user, 'message', created_message.id, conversation_row.id)
      on conflict (recipient_id, notification_type, source_id) do nothing;
      perform realtime.send(
        jsonb_build_object(
          'kind', 'message',
          'id', created_message.id,
          'conversation_id', conversation_row.id
        ),
        'signal',
        'conversation:' || conversation_row.id::text,
        true
      );
      perform realtime.send(
        jsonb_build_object(
          'kind', 'message',
          'id', created_message.id,
          'conversation_id', conversation_row.id
        ),
        'signal',
        'user:' || target_user::text,
        true
      );
    else
      insert into app_private.message_moderation_events (
        message_id, actor_id, reason_code
      ) values (created_message.id, actor_id, coalesce(risk_code, 'HOLD_ALL_MESSAGE'));
    end if;

    remaining := 3 - new_streak;
    result := jsonb_build_object('data', jsonb_build_object(
      'message_id', created_message.id,
      'created_at', created_message.created_at,
      'remaining_outbound', remaining,
      'status', created_message.status
    ));
    insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
    values (actor_id, 'send_message', p_client_request_id, payload_hash, result);
  exception when unique_violation then
    return app_private.api_error('IDEMPOTENCY_CONFLICT');
  end;
  return result;
end;
$$;

create function public.get_messages(
  p_conversation_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  conversation_row public.conversations%rowtype;
  items jsonb;
  has_more boolean;
  next_cursor jsonb;
  remaining integer;
  source_note_content text;
  safe_limit integer := least(greatest(coalesce(p_limit, 30), 1), 50);
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_conversation_id is null or ((p_before_created_at is null) <> (p_before_id is null)) then
    return app_private.api_error('INVALID_INPUT');
  end if;

  select * into conversation_row from public.conversations c where c.id = p_conversation_id;
  if not found or actor_id not in (conversation_row.participant_low, conversation_row.participant_high) then
    return app_private.api_error('NOT_PARTICIPANT');
  end if;
  select n.content into source_note_content
    from public.notes n
   where n.id = conversation_row.source_note_id
     and n.status = 'published';
  update public.notifications
     set read_at = coalesce(read_at, now())
   where recipient_id = actor_id
     and conversation_id = p_conversation_id
     and notification_type = 'message'
     and read_at is null;
  remaining := case when conversation_row.last_sender_id = actor_id
    then greatest(0, 3 - conversation_row.streak_count) else 3 end;

  with limited as (
    select m.* from public.messages m
     where m.conversation_id = p_conversation_id
       and (m.status = 'delivered' or (m.sender_id = actor_id and m.status in ('pending_review', 'rejected', 'hidden')))
       and (p_before_id is null or (m.created_at, m.id) < (p_before_created_at, p_before_id))
     order by m.created_at desc, m.id desc
     limit safe_limit + 1
  ), page as (
    select * from limited order by created_at desc, id desc limit safe_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id,
      'conversation_id', page.conversation_id,
      'body', page.body,
      'is_mine', page.sender_id = actor_id,
      'created_at', page.created_at,
      'status', page.status
    ) order by page.created_at desc, page.id desc), '[]'::jsonb),
    (select count(*) > safe_limit from limited),
    (select jsonb_build_object('created_at', old_page.created_at, 'id', old_page.id)
       from page old_page order by old_page.created_at asc, old_page.id asc limit 1)
    into items, has_more, next_cursor
    from page;

  return jsonb_build_object('data', jsonb_build_object(
    'items', items,
    'remaining_outbound', remaining,
    'can_send', conversation_row.status = 'active' and remaining > 0,
    'status', conversation_row.status,
    'source_note_content', source_note_content,
    'next_cursor', case when has_more then next_cursor else null end
  ));
end;
$$;

create function public.get_inbox(
  p_kind text,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  items jsonb;
  has_more boolean;
  next_cursor jsonb;
  safe_limit integer := least(greatest(coalesce(p_limit, 20), 1), 30);
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_kind is null or p_kind not in ('encouragements', 'chats')
     or ((p_cursor_created_at is null) <> (p_cursor_id is null)) then
    return app_private.api_error('INVALID_INPUT');
  end if;

  if p_kind = 'encouragements' then
    with limited as (
      select e.id, e.note_id, e.template_key, e.created_at, n.cell_x, n.cell_y,
             notification.id as notification_id, notification.read_at
        from public.encouragements e
        join public.notes n on n.id = e.note_id and n.author_id = actor_id
        left join public.notifications notification
          on notification.recipient_id = actor_id
         and notification.notification_type = 'encouragement'
         and notification.source_id = e.id
       where (p_cursor_id is null or (e.created_at, e.id) < (p_cursor_created_at, p_cursor_id))
       order by e.created_at desc, e.id desc
       limit safe_limit + 1
    ), page as (
      select * from limited order by created_at desc, id desc limit safe_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', page.id,
        'note_id', page.note_id,
        'template_key', page.template_key,
        'created_at', page.created_at,
        'cell_x', page.cell_x,
        'cell_y', page.cell_y,
        'notification_id', page.notification_id,
        'is_read', page.read_at is not null
      ) order by page.created_at desc, page.id desc), '[]'::jsonb),
      (select count(*) > safe_limit from limited),
      (select jsonb_build_object('created_at', old_page.created_at, 'id', old_page.id)
         from page old_page order by old_page.created_at asc, old_page.id asc limit 1)
      into items, has_more, next_cursor
      from page;
  else
    with limited as (
      select c.id, last_message.created_at as last_message_at,
             last_message.sender_id = actor_id as last_message_is_mine,
             case when c.last_sender_id = actor_id then greatest(0, 3 - c.streak_count) else 3 end as remaining_outbound,
             last_message.body as last_message_body,
             (select count(*)::integer from public.notifications n
               where n.recipient_id = actor_id and n.conversation_id = c.id and n.read_at is null) as unread_count
        from public.conversations c
        join lateral (
          select m.body, m.created_at, m.sender_id
            from public.messages m
           where m.conversation_id = c.id and m.status = 'delivered'
           order by m.created_at desc, m.id desc limit 1
        ) last_message on true
       where actor_id in (c.participant_low, c.participant_high)
         and c.status = 'active'
         and (p_cursor_id is null or (last_message.created_at, c.id) < (p_cursor_created_at, p_cursor_id))
       order by last_message.created_at desc, c.id desc
       limit safe_limit + 1
    ), page as (
      select * from limited order by last_message_at desc, id desc limit safe_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'conversation_id', page.id,
        'last_message_at', page.last_message_at,
        'last_message_is_mine', page.last_message_is_mine,
        'remaining_outbound', page.remaining_outbound,
        'last_message_preview', page.last_message_body,
        'unread_count', page.unread_count
      ) order by page.last_message_at desc, page.id desc), '[]'::jsonb),
      (select count(*) > safe_limit from limited),
      (select jsonb_build_object('created_at', old_page.last_message_at, 'id', old_page.id)
         from page old_page order by old_page.last_message_at asc, old_page.id asc limit 1)
      into items, has_more, next_cursor
      from page;
  end if;

  return jsonb_build_object('data', jsonb_build_object(
    'items', items,
    'next_cursor', case when has_more then next_cursor else null end
  ));
end;
$$;

create function public.close_conversation(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  updated_status app_private.conversation_status;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if p_conversation_id is null then
    return app_private.api_error('INVALID_INPUT');
  end if;

  update public.conversations c
     set status = 'closed_by_user', updated_at = now()
   where c.id = p_conversation_id
     and actor_id in (c.participant_low, c.participant_high)
     and c.status = 'active'
   returning status into updated_status;
  if not found then
    select c.status into updated_status from public.conversations c
     where c.id = p_conversation_id and actor_id in (c.participant_low, c.participant_high);
    if not found then return app_private.api_error('NOT_PARTICIPANT'); end if;
  end if;
  return jsonb_build_object('data', jsonb_build_object('status', updated_status));
end;
$$;

revoke all on all functions in schema app_private from public, anon, authenticated;
revoke all on function public.send_encouragement(uuid, text, uuid) from public, anon;
revoke all on function public.start_conversation_from_note(uuid, uuid) from public, anon;
revoke all on function public.send_message(uuid, text, uuid) from public, anon;
revoke all on function public.get_messages(uuid, timestamptz, uuid, integer) from public, anon;
revoke all on function public.get_inbox(text, timestamptz, uuid, integer) from public, anon;
revoke all on function public.close_conversation(uuid) from public, anon;
grant execute on function public.send_encouragement(uuid, text, uuid) to authenticated;
grant execute on function public.start_conversation_from_note(uuid, uuid) to authenticated;
grant execute on function public.send_message(uuid, text, uuid) to authenticated;
grant execute on function public.get_messages(uuid, timestamptz, uuid, integer) to authenticated;
grant execute on function public.get_inbox(text, timestamptz, uuid, integer) to authenticated;
grant execute on function public.close_conversation(uuid) to authenticated;

commit;
