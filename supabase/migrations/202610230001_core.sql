begin;

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create type app_private.note_status as enum (
  'pending_review',
  'published',
  'rejected',
  'hidden',
  'deleted'
);

create type app_private.consent_kind as enum (
  'terms',
  'privacy',
  'community_rules',
  'adult_18_plus',
  'onboarding'
);

create table app_private.app_settings (
  setting_key text primary key,
  setting_value text not null,
  updated_at timestamptz not null default now()
);

insert into app_private.app_settings (setting_key, setting_value)
values
  ('terms_version', 'terms-v1'),
  ('privacy_version', 'privacy-v1'),
  ('community_rules_version', 'community-v1'),
  ('onboarding_version', 'onboarding-v1'),
  ('moderation_mode', 'hold_all')
on conflict (setting_key) do nothing;

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  account_status text not null default 'active'
    check (account_status in ('active', 'suspended', 'deletion_requested', 'deleted')),
  adult_confirmed_at timestamptz,
  terms_version text,
  privacy_version text,
  community_rules_version text,
  onboarding_version text,
  reduced_motion boolean not null default false,
  notifications_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  consent_kind app_private.consent_kind not null,
  policy_version text not null,
  accepted_at timestamptz not null default now(),
  accepted boolean not null check (accepted),
  unique (user_id, consent_kind, policy_version)
);

create index user_consents_user_time_idx
  on public.user_consents (user_id, accepted_at desc);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete restrict,
  content text not null,
  paper_color text not null check (paper_color in ('pink', 'butter', 'sage', 'blue', 'lilac')),
  style_seed integer not null,
  cell_x bigint not null,
  cell_y bigint not null,
  allow_chat boolean not null default true,
  status app_private.note_status not null default 'pending_review',
  created_at timestamptz not null default now(),
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  content_version integer not null default 1 check (content_version > 0),
  constraint notes_content_byte_limit check (octet_length(content) <= 6144),
  constraint notes_status_timestamps check (
    (status <> 'published' or published_at is not null)
    and (status <> 'deleted' or deleted_at is not null)
  )
);

create unique index notes_active_cell_uidx
  on public.notes (cell_x, cell_y)
  where status in ('pending_review', 'published', 'hidden');

create index notes_published_cell_idx
  on public.notes (cell_y, cell_x, id)
  where status = 'published';

create index notes_owner_created_idx
  on public.notes (author_id, created_at desc, id desc);

create index notes_owner_active_idx
  on public.notes (author_id, status, created_at desc);

create table public.daily_note_creations (
  user_id uuid not null references auth.users (id) on delete restrict,
  creation_day_vn date not null,
  note_id uuid references public.notes (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, creation_day_vn)
);

create table public.wall_regions (
  tile_x bigint not null,
  tile_y bigint not null,
  published_count integer not null default 0 check (published_count >= 0),
  revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (tile_x, tile_y)
);

create sequence app_private.wall_revision_seq;

create function app_private.floor_div(p_value bigint, p_divisor bigint)
returns bigint
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
  select floor(p_value::numeric / p_divisor::numeric)::bigint
$$;

create function app_private.profile_is_eligible(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private
as $$
  select exists (
    select 1
    from public.profiles p
    join app_private.app_settings terms
      on terms.setting_key = 'terms_version'
     and terms.setting_value = p.terms_version
    join app_private.app_settings privacy
      on privacy.setting_key = 'privacy_version'
     and privacy.setting_value = p.privacy_version
    join app_private.app_settings community
      on community.setting_key = 'community_rules_version'
     and community.setting_value = p.community_rules_version
    join app_private.app_settings onboarding
      on onboarding.setting_key = 'onboarding_version'
     and onboarding.setting_value = p.onboarding_version
    where p.user_id = p_user_id
      and p.account_status = 'active'
      and p.adult_confirmed_at is not null
  )
$$;

create function app_private.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function app_private.sync_wall_region_counts()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  old_is_published boolean := false;
  new_is_published boolean := false;
  old_tile_x bigint;
  old_tile_y bigint;
  new_tile_x bigint;
  new_tile_y bigint;
  next_revision bigint;
begin
  if tg_op <> 'INSERT' then
    old_is_published := old.status = 'published';
    old_tile_x := app_private.floor_div(old.cell_x, 8);
    old_tile_y := app_private.floor_div(old.cell_y, 8);
  end if;
  if tg_op <> 'DELETE' then
    new_is_published := new.status = 'published';
    new_tile_x := app_private.floor_div(new.cell_x, 8);
    new_tile_y := app_private.floor_div(new.cell_y, 8);
  end if;

  if old_is_published and (
    not new_is_published
    or old_tile_x is distinct from new_tile_x
    or old_tile_y is distinct from new_tile_y
  ) then
    next_revision := nextval('app_private.wall_revision_seq');
    update public.wall_regions
       set published_count = greatest(0, published_count - 1),
           revision = next_revision,
           updated_at = now()
     where tile_x = old_tile_x and tile_y = old_tile_y;
  end if;

  if new_is_published and (
    not old_is_published
    or old_tile_x is distinct from new_tile_x
    or old_tile_y is distinct from new_tile_y
  ) then
    next_revision := nextval('app_private.wall_revision_seq');
    insert into public.wall_regions (tile_x, tile_y, published_count, revision, updated_at)
    values (new_tile_x, new_tile_y, 1, next_revision, now())
    on conflict (tile_x, tile_y) do update
      set published_count = public.wall_regions.published_count + 1,
          revision = excluded.revision,
          updated_at = excluded.updated_at;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function app_private.touch_updated_at();

create trigger notes_touch_updated_at
before update on public.notes
for each row execute function app_private.touch_updated_at();

create trigger notes_sync_wall_region_counts
after insert or update of status, cell_x, cell_y or delete on public.notes
for each row execute function app_private.sync_wall_region_counts();

create function app_private.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function app_private.create_profile_for_auth_user();

alter table public.profiles enable row level security;
alter table public.user_consents enable row level security;
alter table public.notes enable row level security;
alter table public.daily_note_creations enable row level security;
alter table public.wall_regions enable row level security;

revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.user_consents from public, anon, authenticated;
revoke all on table public.notes from public, anon, authenticated;
revoke all on table public.daily_note_creations from public, anon, authenticated;
revoke all on table public.wall_regions from public, anon, authenticated;

create table app_private.request_idempotency (
  actor_id uuid not null references auth.users (id) on delete cascade,
  operation text not null,
  request_id uuid not null,
  payload_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  primary key (actor_id, operation, request_id)
);

create table app_private.moderation_events (
  id uuid primary key default gen_random_uuid(),
  note_id uuid references public.notes (id) on delete set null,
  actor_id uuid references auth.users (id) on delete set null,
  from_status app_private.note_status,
  to_status app_private.note_status not null,
  reason_code text not null,
  created_at timestamptz not null default now()
);

create table app_private.admin_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('moderator', 'admin')),
  granted_by uuid references auth.users (id) on delete set null,
  granted_at timestamptz not null default now()
);

create table app_private.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  reason text not null,
  created_at timestamptz not null default now()
);

revoke all on all tables in schema app_private from public, anon, authenticated;
revoke all on all sequences in schema app_private from public, anon, authenticated;
revoke all on all functions in schema app_private from public, anon, authenticated;

create function public.complete_onboarding(
  p_age_confirmed boolean,
  p_terms_accepted boolean,
  p_privacy_accepted boolean,
  p_community_rules_accepted boolean,
  p_onboarding_acknowledged boolean,
  p_terms_version text,
  p_privacy_version text,
  p_community_rules_version text,
  p_onboarding_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  expected_terms text;
  expected_privacy text;
  expected_community text;
  expected_onboarding text;
begin
  if actor_id is null then
    return jsonb_build_object('error', jsonb_build_object('code', 'UNAUTHENTICATED'));
  end if;
  if p_age_confirmed is distinct from true then
    return jsonb_build_object('error', jsonb_build_object('code', 'AGE_RESTRICTED'));
  end if;
  if p_terms_accepted is distinct from true
     or p_privacy_accepted is distinct from true
     or p_community_rules_accepted is distinct from true
     or p_onboarding_acknowledged is distinct from true then
    return jsonb_build_object('error', jsonb_build_object('code', 'CONSENT_REQUIRED'));
  end if;

  select setting_value into expected_terms from app_private.app_settings where setting_key = 'terms_version';
  select setting_value into expected_privacy from app_private.app_settings where setting_key = 'privacy_version';
  select setting_value into expected_community from app_private.app_settings where setting_key = 'community_rules_version';
  select setting_value into expected_onboarding from app_private.app_settings where setting_key = 'onboarding_version';

  if p_terms_version is distinct from expected_terms
     or p_privacy_version is distinct from expected_privacy
     or p_community_rules_version is distinct from expected_community
     or p_onboarding_version is distinct from expected_onboarding then
    return jsonb_build_object('error', jsonb_build_object('code', 'POLICY_VERSION_MISMATCH'));
  end if;

  update public.profiles
     set adult_confirmed_at = coalesce(adult_confirmed_at, now()),
         terms_version = p_terms_version,
         privacy_version = p_privacy_version,
         community_rules_version = p_community_rules_version,
         onboarding_version = p_onboarding_version
   where user_id = actor_id and account_status = 'active';

  if not found then
    return jsonb_build_object('error', jsonb_build_object('code', 'SUSPENDED'));
  end if;

  insert into public.user_consents (user_id, consent_kind, policy_version, accepted_at, accepted)
  values
    (actor_id, 'adult_18_plus', 'self-declared-v1', now(), true),
    (actor_id, 'terms', p_terms_version, now(), true),
    (actor_id, 'privacy', p_privacy_version, now(), true),
    (actor_id, 'community_rules', p_community_rules_version, now(), true),
    (actor_id, 'onboarding', p_onboarding_version, now(), true)
  on conflict (user_id, consent_kind, policy_version) do nothing;

  return jsonb_build_object('data', jsonb_build_object('eligible', true));
end;
$$;

create function public.get_account_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
begin
  if actor_id is null then
    return jsonb_build_object('error', jsonb_build_object('code', 'UNAUTHENTICATED'));
  end if;

  select * into profile_row from public.profiles where user_id = actor_id;
  if not found then
    return jsonb_build_object('error', jsonb_build_object('code', 'NOT_ELIGIBLE'));
  end if;

  return jsonb_build_object('data', jsonb_build_object(
    'eligible', app_private.profile_is_eligible(actor_id),
    'account_status', profile_row.account_status,
    'adult_confirmed', profile_row.adult_confirmed_at is not null,
    'terms_version', profile_row.terms_version,
    'privacy_version', profile_row.privacy_version,
    'community_rules_version', profile_row.community_rules_version,
    'onboarding_version', profile_row.onboarding_version,
    'is_moderator', exists (
      select 1 from app_private.admin_roles r where r.user_id = actor_id
    ),
    'reduced_motion', profile_row.reduced_motion,
    'notifications_enabled', profile_row.notifications_enabled
  ));
end;
$$;

create function public.update_settings(
  p_reduced_motion boolean default null,
  p_notifications_enabled boolean default null
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
    return jsonb_build_object('error', jsonb_build_object('code', 'UNAUTHENTICATED'));
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return jsonb_build_object('error', jsonb_build_object('code', 'NOT_ELIGIBLE'));
  end if;
  if p_reduced_motion is null and p_notifications_enabled is null then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT'));
  end if;

  update public.profiles
     set reduced_motion = coalesce(p_reduced_motion, reduced_motion),
         notifications_enabled = coalesce(p_notifications_enabled, notifications_enabled)
   where user_id = actor_id;

  return jsonb_build_object('data', jsonb_build_object(
    'reduced_motion', (select reduced_motion from public.profiles where user_id = actor_id),
    'notifications_enabled', (select notifications_enabled from public.profiles where user_id = actor_id)
  ));
end;
$$;

revoke all on function public.complete_onboarding(boolean, boolean, boolean, boolean, boolean, text, text, text, text) from public, anon;
revoke all on function public.get_account_settings() from public, anon;
revoke all on function public.update_settings(boolean, boolean) from public, anon;
grant execute on function public.complete_onboarding(boolean, boolean, boolean, boolean, boolean, text, text, text, text) to authenticated;
grant execute on function public.get_account_settings() to authenticated;
grant execute on function public.update_settings(boolean, boolean) to authenticated;

commit;
