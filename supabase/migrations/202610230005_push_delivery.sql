begin;

-- Push is an explicit user opt-in; earlier builds had no working delivery control.
alter table public.profiles alter column notifications_enabled set default false;
delete from public.user_devices
 where user_id in (select user_id from public.profiles where notifications_enabled);
update public.profiles
   set notifications_enabled = false
 where notifications_enabled;

create table app_private.push_delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications (id) on delete cascade,
  device_id uuid not null references public.user_devices (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed')),
  attempt_count smallint not null default 0 check (attempt_count between 0 and 8),
  available_at timestamptz not null default now(),
  locked_until timestamptz,
  sent_at timestamptz,
  last_error_code text check (last_error_code is null or last_error_code in (
    'UNREGISTERED', 'INVALID_ARGUMENT', 'UNAVAILABLE', 'INTERNAL', 'UNKNOWN'
  )),
  created_at timestamptz not null default now(),
  unique (notification_id, device_id)
);

create index push_delivery_outbox_claim_idx
  on app_private.push_delivery_outbox (available_at, created_at, id)
  where status in ('pending', 'sending');

revoke all on table app_private.push_delivery_outbox from public, anon, authenticated;

create function app_private.enqueue_notification_push()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  insert into app_private.push_delivery_outbox (notification_id, device_id)
  select new.id, device.id
    from public.profiles profile
    join public.user_devices device on device.user_id = profile.user_id
   where profile.user_id = new.recipient_id
     and profile.notifications_enabled
  on conflict (notification_id, device_id) do nothing;
  return new;
end;
$$;

revoke all on function app_private.enqueue_notification_push() from public, anon, authenticated;

create trigger notifications_enqueue_push
after insert on public.notifications
for each row execute function app_private.enqueue_notification_push();

create function app_private.remove_devices_when_push_disabled()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  if old.notifications_enabled and not new.notifications_enabled then
    delete from public.user_devices where user_id = new.user_id;
  end if;
  return new;
end;
$$;

revoke all on function app_private.remove_devices_when_push_disabled() from public, anon, authenticated;

create trigger profiles_remove_devices_when_push_disabled
after update of notifications_enabled on public.profiles
for each row execute function app_private.remove_devices_when_push_disabled();

create or replace function public.register_device(
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
  if not exists (
    select 1 from public.profiles profile
     where profile.user_id = actor_id and profile.notifications_enabled
  ) then
    return app_private.api_error('PUSH_DISABLED');
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

create function public.claim_push_deliveries(p_limit integer default 100)
returns table (
  delivery_id uuid,
  notification_type text,
  push_token text,
  platform text,
  attempt_count integer
)
language sql
security definer
set search_path = pg_catalog, public, app_private
as $$
  with candidates as (
    select outbox.id
      from app_private.push_delivery_outbox outbox
      join public.notifications notification on notification.id = outbox.notification_id
      join public.user_devices device on device.id = outbox.device_id
      join public.profiles profile on profile.user_id = notification.recipient_id
     where outbox.status in ('pending', 'sending')
       and outbox.attempt_count < 8
       and outbox.available_at <= now()
       and (outbox.locked_until is null or outbox.locked_until < now())
       and profile.notifications_enabled
       and profile.account_status = 'active'
     order by outbox.available_at, outbox.created_at, outbox.id
     for update of outbox skip locked
     limit greatest(1, least(coalesce(p_limit, 100), 100))
  ), claimed as (
    update app_private.push_delivery_outbox outbox
       set status = 'sending',
           attempt_count = outbox.attempt_count + 1,
           locked_until = now() + interval '2 minutes'
      from candidates
     where outbox.id = candidates.id
    returning outbox.id, outbox.notification_id, outbox.device_id, outbox.attempt_count
  )
  select claimed.id,
         notification.notification_type,
         device.push_token,
         device.platform,
         claimed.attempt_count::integer
    from claimed
    join public.notifications notification on notification.id = claimed.notification_id
    join public.user_devices device on device.id = claimed.device_id;
$$;

create function public.complete_push_delivery(
  p_delivery_id uuid,
  p_outcome text,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  delivery_row app_private.push_delivery_outbox%rowtype;
  safe_error_code text;
begin
  if p_outcome is null or p_outcome not in ('sent', 'invalid_token', 'retry') then
    return app_private.api_error('INVALID_INPUT');
  end if;

  safe_error_code := case
    when p_error_code in ('UNREGISTERED', 'INVALID_ARGUMENT', 'UNAVAILABLE', 'INTERNAL')
      then p_error_code
    else 'UNKNOWN'
  end;

  select * into delivery_row
    from app_private.push_delivery_outbox
   where id = p_delivery_id
   for update;
  if not found then
    return jsonb_build_object('data', jsonb_build_object('updated', false));
  end if;

  if p_outcome = 'invalid_token' then
    delete from public.user_devices where id = delivery_row.device_id;
    return jsonb_build_object('data', jsonb_build_object('updated', true));
  elsif p_outcome = 'sent' then
    update app_private.push_delivery_outbox
       set status = 'sent', sent_at = now(), locked_until = null, last_error_code = null
     where id = p_delivery_id;
  elsif delivery_row.attempt_count >= 8 then
    update app_private.push_delivery_outbox
       set status = 'failed', locked_until = null, last_error_code = safe_error_code
     where id = p_delivery_id;
  else
    update app_private.push_delivery_outbox
       set status = 'pending',
           available_at = now() + make_interval(secs => least(3600, 15 * (2 ^ delivery_row.attempt_count)::integer)),
           locked_until = null,
           last_error_code = safe_error_code
     where id = p_delivery_id;
  end if;

  return jsonb_build_object('data', jsonb_build_object('updated', true));
end;
$$;

revoke all on function public.claim_push_deliveries(integer) from public, anon, authenticated;
revoke all on function public.complete_push_delivery(uuid, text, text) from public, anon, authenticated;
grant execute on function public.claim_push_deliveries(integer) to service_role;
grant execute on function public.complete_push_delivery(uuid, text, text) to service_role;

commit;
