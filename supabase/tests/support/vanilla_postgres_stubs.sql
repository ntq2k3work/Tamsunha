-- Supabase surface stubs for running the migration workflow tests on a fresh,
-- disposable vanilla PostgreSQL database. This is not a replacement for a
-- Supabase CLI reset or Realtime/Auth integration test.
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object or unique_violation then null; end $$;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  created_at timestamptz not null default now()
);
create function auth.uid()
returns uuid
language sql
stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create schema realtime;
create table realtime.messages (
  id bigint generated always as identity primary key,
  extension text not null,
  topic text not null
);
alter table realtime.messages enable row level security;
create function realtime.topic()
returns text
language sql
stable
as $$ select current_setting('realtime.topic', true) $$;
create function realtime.send(jsonb, text, text, boolean)
returns void
language plpgsql
as $$ begin return; end; $$;
