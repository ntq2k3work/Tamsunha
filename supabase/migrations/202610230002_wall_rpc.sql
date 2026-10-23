begin;

create function app_private.api_error(
  p_code text,
  p_message text default null,
  p_retryable boolean default false,
  p_details jsonb default null
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'error', jsonb_strip_nulls(jsonb_build_object(
      'code', p_code,
      'message', p_message,
      'retryable', p_retryable,
      'details', p_details
    ))
  )
$$;

create function public.get_wall_tiles(
  p_min_cell_x bigint,
  p_max_cell_x bigint,
  p_min_cell_y bigint,
  p_max_cell_y bigint,
  p_cursor_cell_y bigint default null,
  p_cursor_cell_x bigint default null,
  p_cursor_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  page_items jsonb;
  next_cursor jsonb;
  result_revision bigint;
  has_more boolean;
  safe_limit integer := least(greatest(coalesce(p_limit, 200), 1), 200);
begin
  if v_actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(v_actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_min_cell_x is null or p_max_cell_x is null or p_min_cell_y is null or p_max_cell_y is null
     or p_min_cell_x > p_max_cell_x or p_min_cell_y > p_max_cell_y
     or p_max_cell_x::numeric - p_min_cell_x::numeric + 1 > 32
     or p_max_cell_y::numeric - p_min_cell_y::numeric + 1 > 32
     or not (
       (p_cursor_cell_y is null and p_cursor_cell_x is null and p_cursor_id is null)
       or (p_cursor_cell_y is not null and p_cursor_cell_x is not null and p_cursor_id is not null)
     ) then
    return app_private.api_error('INVALID_VIEWPORT');
  end if;

  with limited as (
    select n.id, n.cell_x, n.cell_y, n.paper_color, n.style_seed, n.published_at
      from public.notes n
     where n.status = 'published'
       and n.cell_x between p_min_cell_x and p_max_cell_x
       and n.cell_y between p_min_cell_y and p_max_cell_y
       and (
         p_cursor_id is null
         or (n.cell_y, n.cell_x, n.id) > (p_cursor_cell_y, p_cursor_cell_x, p_cursor_id)
       )
     order by n.cell_y, n.cell_x, n.id
     limit safe_limit + 1
  ), page as (
    select * from limited order by cell_y, cell_x, id limit safe_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id,
      'cell_x', page.cell_x,
      'cell_y', page.cell_y,
      'paper_color', page.paper_color,
      'style_seed', page.style_seed,
      'published_at', page.published_at
    ) order by page.cell_y, page.cell_x, page.id), '[]'::jsonb),
    (select count(*) > safe_limit from limited),
    (select jsonb_build_object(
       'cell_y', last_page.cell_y,
       'cell_x', last_page.cell_x,
       'id', last_page.id
     ) from page last_page order by last_page.cell_y desc, last_page.cell_x desc, last_page.id desc limit 1),
    coalesce((
      select max(w.revision)
        from public.wall_regions w
       where w.tile_x between app_private.floor_div(p_min_cell_x, 8) and app_private.floor_div(p_max_cell_x, 8)
         and w.tile_y between app_private.floor_div(p_min_cell_y, 8) and app_private.floor_div(p_max_cell_y, 8)
    ), 0)
  into page_items, has_more, next_cursor, result_revision
  from page;

  return jsonb_build_object('data', jsonb_build_object(
    'items', page_items,
    'next_cursor', case when has_more then next_cursor else null end,
    'revision', result_revision
  ));
end;
$$;

create function public.get_wall_density(
  p_min_tile_x bigint,
  p_max_tile_x bigint,
  p_min_tile_y bigint,
  p_max_tile_y bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  density jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_min_tile_x is null or p_max_tile_x is null or p_min_tile_y is null or p_max_tile_y is null
     or p_min_tile_x > p_max_tile_x or p_min_tile_y > p_max_tile_y
     or p_max_tile_x::numeric - p_min_tile_x::numeric + 1 > 32
     or p_max_tile_y::numeric - p_min_tile_y::numeric + 1 > 32 then
    return app_private.api_error('INVALID_VIEWPORT');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tile_x', tile_x,
    'tile_y', tile_y,
    'published_count', published_count
  ) order by tile_y, tile_x), '[]'::jsonb)
    into density
    from public.wall_regions
   where tile_x between p_min_tile_x and p_max_tile_x
     and tile_y between p_min_tile_y and p_max_tile_y
     and published_count > 0;

  return jsonb_build_object('data', jsonb_build_object('items', density));
end;
$$;

create function public.get_note_detail(p_note_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  note_row public.notes%rowtype;
  is_owner boolean;
  blocked boolean;
  encouraged boolean := false;
  interacted boolean := false;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;

  select n.* into note_row
    from public.notes n
   where n.id = p_note_id
     and (n.status = 'published' or n.author_id = actor_id)
   limit 1;
  if not found then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;

  is_owner := note_row.author_id = actor_id;
  if not is_owner then
    select app_private.is_blocked_between(actor_id, note_row.author_id) into blocked;
    select exists (
      select 1 from public.encouragements e
       where e.note_id = note_row.id and e.sender_id = actor_id
    ) into encouraged;
  else
    blocked := false;
  end if;

  select exists (
    select 1 from public.encouragements e where e.note_id = note_row.id
    union all
    select 1 from public.conversations c where c.source_note_id = note_row.id
  ) into interacted;

  return jsonb_build_object('data', jsonb_build_object(
    'id', note_row.id,
    'content', note_row.content,
    'paper_color', note_row.paper_color,
    'published_at', note_row.published_at,
    'status', note_row.status,
    'is_owner', is_owner,
    'already_encouraged', encouraged,
    'allow_chat', note_row.allow_chat,
    'can_encourage', not is_owner and not blocked and not encouraged and note_row.status = 'published',
    'can_start_chat', not is_owner and not blocked and note_row.allow_chat and note_row.status = 'published',
    'can_edit', is_owner and note_row.status in ('pending_review', 'published')
      and note_row.created_at + interval '30 minutes' > now() and not interacted,
    'can_delete', is_owner and note_row.status <> 'deleted'
  ));
end;
$$;

create function public.get_discovery_target(p_exclude_regions jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  selected_tile record;
  selected_mode numeric := random();
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if jsonb_typeof(coalesce(p_exclude_regions, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_exclude_regions, '[]'::jsonb)) > 10 then
    return app_private.api_error('INVALID_INPUT');
  end if;
  if exists (
    select 1
      from jsonb_array_elements(coalesce(p_exclude_regions, '[]'::jsonb)) excluded(value)
     where jsonb_typeof(excluded.value) <> 'object'
        or coalesce(excluded.value ->> 'tile_x', '') !~ '^-?[0-9]+$'
        or coalesce(excluded.value ->> 'tile_y', '') !~ '^-?[0-9]+$'
  ) then
    return app_private.api_error('INVALID_INPUT');
  end if;

  with candidates as (
    select w.tile_x, w.tile_y, w.published_count,
           64 - count(n.id)::integer as available_cells,
           bool_or(n.status = 'published' and n.published_at >= now() - interval '7 days') as has_recent,
           bool_or(n.status = 'published' and not exists (
             select 1 from public.encouragements e where e.note_id = n.id
           )) as has_unencouraged
      from public.wall_regions w
      join public.notes n
        on app_private.floor_div(n.cell_x, 8) = w.tile_x
       and app_private.floor_div(n.cell_y, 8) = w.tile_y
       and n.status in ('pending_review', 'published', 'hidden')
     where w.published_count > 0
       and not exists (
         select 1 from jsonb_array_elements(coalesce(p_exclude_regions, '[]'::jsonb)) excluded(value)
          where (excluded.value ->> 'tile_x')::bigint = w.tile_x
            and (excluded.value ->> 'tile_y')::bigint = w.tile_y
       )
     group by w.tile_x, w.tile_y, w.published_count
    having count(n.id) <= 61
  ), weighted as (
    select c.*,
           case
             when selected_mode < 0.40 then c.has_unencouraged
             when selected_mode < 0.75 then c.has_recent
             else true
           end as matches_weight
      from candidates c
  )
  select tile_x, tile_y, available_cells, published_count
    into selected_tile
    from weighted
   where available_cells >= 3 and matches_weight
   order by random()
   limit 1;

  if not found then
    select w.tile_x, w.tile_y, 64 - count(n.id)::integer as available_cells, w.published_count
      into selected_tile
      from public.wall_regions w
      join public.notes n
        on app_private.floor_div(n.cell_x, 8) = w.tile_x
       and app_private.floor_div(n.cell_y, 8) = w.tile_y
       and n.status in ('pending_review', 'published', 'hidden')
     where w.published_count > 0
     group by w.tile_x, w.tile_y, w.published_count
    having 64 - count(n.id) >= 3
     order by random()
     limit 1;
  end if;

  if not found then
    return app_private.api_error('EMPTY_WORLD', 'Chưa có vùng tường phù hợp để khám phá.', true);
  end if;

  return jsonb_build_object('data', jsonb_build_object(
    'tile_x', selected_tile.tile_x,
    'tile_y', selected_tile.tile_y,
    'camera_world_x', selected_tile.tile_x * 1440 + 720,
    'camera_world_y', selected_tile.tile_y * 1440 + 720,
    'available_cells_estimate', selected_tile.available_cells
  ));
end;
$$;

create function public.suggest_placement_regions(p_near_cell_x bigint, p_near_cell_y bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  suggestions jsonb;
begin
  if v_actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(v_actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('cell_x', candidates.cell_x, 'cell_y', candidates.cell_y)
                             order by candidates.distance, candidates.cell_y, candidates.cell_x), '[]'::jsonb)
    into suggestions
    from (
      select x.cell_x, y.cell_y,
             abs((x.cell_x::numeric - p_near_cell_x::numeric))
               + abs((y.cell_y::numeric - p_near_cell_y::numeric)) as distance
        from generate_series(p_near_cell_x - 8, p_near_cell_x + 8) x(cell_x)
        cross join generate_series(p_near_cell_y - 8, p_near_cell_y + 8) y(cell_y)
       where not exists (
         select 1 from public.notes n
          where n.cell_x = x.cell_x and n.cell_y = y.cell_y
            and n.status in ('pending_review', 'published', 'hidden')
       )
       order by distance, y.cell_y, x.cell_x
       limit 3
    ) candidates;

  return jsonb_build_object('data', jsonb_build_object('items', suggestions));
end;
$$;

create function public.place_note(
  p_content text,
  p_paper_color text,
  p_allow_chat boolean,
  p_cell_x bigint,
  p_cell_y bigint,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  normalized_content text;
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  created_note public.notes%rowtype;
  result jsonb;
  moderation_mode text;
  note_status app_private.note_status;
  rejected_constraint text;
  error_code text;
begin
  if v_actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(v_actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  normalized_content := btrim(replace(replace(normalize(coalesce(p_content, ''), NFC), E'\r\n', E'\n'), E'\r', E'\n'));
  if normalized_content = '' or char_length(normalized_content) > 1000
     or octet_length(normalized_content) > 6144
     or p_paper_color not in ('pink', 'butter', 'sage', 'blue', 'lilac')
     or p_allow_chat is null or p_client_request_id is null then
    return app_private.api_error('INVALID_INPUT', 'Hãy kiểm tra nội dung và lựa chọn của bạn.');
  end if;

  payload_hash := md5(jsonb_build_object(
    'content', normalized_content,
    'paper_color', p_paper_color,
    'allow_chat', p_allow_chat,
    'cell_x', p_cell_x,
    'cell_y', p_cell_y
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(v_actor_id::text || ':place_note:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency
   where app_private.request_idempotency.actor_id = v_actor_id
     and operation = 'place_note'
     and request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  begin
    insert into public.daily_note_creations (user_id, creation_day_vn)
    values (v_actor_id, (now() at time zone 'Asia/Ho_Chi_Minh')::date)
    on conflict (user_id, creation_day_vn) do nothing;
    if not found then
      raise exception using errcode = 'P0001', message = 'DAILY_LIMIT';
    end if;

    select setting_value into moderation_mode
      from app_private.app_settings where setting_key = 'moderation_mode';
    if moderation_mode = 'hold_all'
       or normalized_content ~* '(https?://|www\.|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|\+?[0-9][0-9 .()-]{7,}[0-9])' then
      note_status := 'pending_review';
    else
      note_status := 'published';
    end if;

    insert into public.notes (
      author_id, content, paper_color, style_seed, cell_x, cell_y,
      allow_chat, status, published_at
    ) values (
      v_actor_id, normalized_content, p_paper_color,
      floor(random() * 2147483647)::integer,
      p_cell_x, p_cell_y, p_allow_chat, note_status,
      case when note_status = 'published' then now() else null end
    ) returning * into created_note;

    update public.daily_note_creations
       set note_id = created_note.id
     where user_id = v_actor_id
       and creation_day_vn = (now() at time zone 'Asia/Ho_Chi_Minh')::date;

    if note_status = 'pending_review' then
      insert into app_private.moderation_events (
        note_id, actor_id, from_status, to_status, reason_code
      ) values (
        created_note.id, v_actor_id, null, 'pending_review',
        case when moderation_mode = 'hold_all' then 'HOLD_ALL' else 'AUTOMATED_SIGNAL' end
      );
    end if;

    result := jsonb_build_object('data', jsonb_build_object(
      'note_id', created_note.id,
      'status', created_note.status,
      'cell_x', created_note.cell_x,
      'cell_y', created_note.cell_y,
      'published_at', created_note.published_at
    ));

    insert into app_private.request_idempotency (
      actor_id, operation, request_id, payload_hash, result
    ) values (
      v_actor_id, 'place_note', p_client_request_id, payload_hash, result
    );

  exception
    when sqlstate 'P0001' then
      get stacked diagnostics error_code = message_text;
      return app_private.api_error(error_code);
    when unique_violation then
      get stacked diagnostics rejected_constraint = constraint_name;
      if rejected_constraint = 'notes_active_cell_uidx' then
        return app_private.api_error('SLOT_OCCUPIED', 'Vị trí này vừa có một tờ giấy khác.', true);
      elsif rejected_constraint = 'daily_note_creations_pkey' then
        return app_private.api_error('DAILY_LIMIT');
      else
        raise;
      end if;
  end;

  return result;
end;
$$;

create function public.get_my_notes(
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
  safe_limit integer := least(greatest(coalesce(p_limit, 20), 1), 30);
  has_more boolean;
  next_cursor jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    return app_private.api_error('INVALID_INPUT');
  end if;

  with limited as (
      select n.*
        from public.notes n
       where n.author_id = actor_id
         and (p_cursor_id is null or (n.created_at, n.id) < (p_cursor_created_at, p_cursor_id))
       order by n.created_at desc, n.id desc
       limit safe_limit + 1
    ), page as (
      select * from limited order by created_at desc, id desc limit safe_limit
    )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', page.id,
      'content', page.content,
      'paper_color', page.paper_color,
      'status', page.status,
      'cell_x', page.cell_x,
      'cell_y', page.cell_y,
      'created_at', page.created_at,
      'allow_chat', page.allow_chat,
      'can_edit', page.status in ('pending_review', 'published')
        and page.created_at + interval '30 minutes' > now(),
      'can_delete', page.status <> 'deleted'
    ) order by page.created_at desc, page.id desc), '[]'::jsonb),
    (select count(*) > safe_limit from limited),
    (select jsonb_build_object('created_at', last_page.created_at, 'id', last_page.id)
       from page last_page order by last_page.created_at asc, last_page.id asc limit 1)
    into items, has_more, next_cursor
    from page;

  return jsonb_build_object('data', jsonb_build_object(
    'items', items,
    'next_cursor', case when has_more then next_cursor else null end,
    'daily_quota_used', exists (
      select 1 from public.daily_note_creations d
       where d.user_id = actor_id
         and d.creation_day_vn = (now() at time zone 'Asia/Ho_Chi_Minh')::date
    )
  ));
end;
$$;

create function public.edit_note(
  p_note_id uuid,
  p_new_content text,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  normalized_content text;
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  note_row public.notes%rowtype;
  old_status app_private.note_status;
  moderation_mode text;
  new_status app_private.note_status;
  result jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  normalized_content := btrim(replace(replace(normalize(coalesce(p_new_content, ''), NFC), E'\r\n', E'\n'), E'\r', E'\n'));
  if p_note_id is null or p_client_request_id is null
     or normalized_content = '' or char_length(normalized_content) > 1000
     or octet_length(normalized_content) > 6144 then
    return app_private.api_error('INVALID_INPUT');
  end if;

  payload_hash := md5(jsonb_build_object('note_id', p_note_id, 'content', normalized_content)::text);
  perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':edit_note:' || p_client_request_id::text, 0));
  select * into previous from app_private.request_idempotency r
   where r.actor_id = auth.uid() and r.operation = 'edit_note'
     and r.request_id = p_client_request_id;
  if found then
    if previous.payload_hash <> payload_hash then
      return app_private.api_error('IDEMPOTENCY_CONFLICT');
    end if;
    return previous.result;
  end if;

  select * into note_row from public.notes n
   where n.id = p_note_id and n.author_id = actor_id
   for update;
  if not found or note_row.status not in ('pending_review', 'published') then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  if note_row.created_at + interval '30 minutes' <= now() then
    return app_private.api_error('EDIT_WINDOW_EXPIRED');
  end if;
  if exists (select 1 from public.encouragements e where e.note_id = note_row.id)
     or exists (select 1 from public.conversations c where c.source_note_id = note_row.id) then
    return app_private.api_error('NOTE_ALREADY_INTERACTED');
  end if;

  select setting_value into moderation_mode
    from app_private.app_settings where setting_key = 'moderation_mode';
  old_status := note_row.status;
  if moderation_mode = 'hold_all'
     or normalized_content ~* '(https?://|www\.|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|\+?[0-9][0-9 .()-]{7,}[0-9])' then
    new_status := 'pending_review';
  else
    new_status := 'published';
  end if;

  update public.notes
     set content = normalized_content,
         content_version = content_version + 1,
         status = new_status,
         published_at = case when new_status = 'published' then coalesce(published_at, now()) else null end
   where id = note_row.id
   returning * into note_row;

  insert into app_private.moderation_events (note_id, actor_id, from_status, to_status, reason_code)
  values (
    note_row.id, actor_id,
    old_status,
    new_status,
    case when new_status = 'pending_review' and moderation_mode = 'hold_all' then 'HOLD_ALL_EDIT' else 'CONTENT_EDIT' end
  );

  result := jsonb_build_object('data', jsonb_build_object(
    'id', note_row.id,
    'status', note_row.status,
    'content', note_row.content,
    'content_version', note_row.content_version
  ));
  insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
  values (actor_id, 'edit_note', p_client_request_id, payload_hash, result);
  return result;
end;
$$;

create function public.delete_note(p_note_id uuid, p_client_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  payload_hash text;
  previous app_private.request_idempotency%rowtype;
  note_row public.notes%rowtype;
  result jsonb;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;

  if p_note_id is null then
    return app_private.api_error('INVALID_INPUT');
  end if;
  if p_client_request_id is not null then
    payload_hash := md5(jsonb_build_object('note_id', p_note_id)::text);
    perform pg_advisory_xact_lock(hashtextextended(actor_id::text || ':delete_note:' || p_client_request_id::text, 0));
    select * into previous from app_private.request_idempotency r
     where r.actor_id = auth.uid() and r.operation = 'delete_note'
       and r.request_id = p_client_request_id;
    if found then
      if previous.payload_hash <> payload_hash then
        return app_private.api_error('IDEMPOTENCY_CONFLICT');
      end if;
      return previous.result;
    end if;
  end if;

  select * into note_row from public.notes n
   where n.id = p_note_id and n.author_id = actor_id
   for update;
  if not found then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;
  if note_row.status <> 'deleted' then
    update public.notes
       set status = 'deleted',
           deleted_at = now(),
           content = '',
           allow_chat = false
     where id = note_row.id;
    insert into app_private.moderation_events (note_id, actor_id, from_status, to_status, reason_code)
    values (note_row.id, actor_id, note_row.status, 'deleted', 'OWNER_DELETE');
  end if;
  result := jsonb_build_object('data', jsonb_build_object('deleted', true));
  if p_client_request_id is not null then
    insert into app_private.request_idempotency (actor_id, operation, request_id, payload_hash, result)
    values (actor_id, 'delete_note', p_client_request_id, payload_hash, result);
  end if;
  return result;
end;
$$;

create function public.update_note_chat(p_note_id uuid, p_allow_chat boolean)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, auth
as $$
declare
  actor_id uuid := auth.uid();
  updated_allow_chat boolean;
  note_id uuid;
begin
  if actor_id is null then
    return app_private.api_error('UNAUTHENTICATED');
  end if;
  if not app_private.profile_is_eligible(actor_id) then
    return app_private.api_error('NOT_ELIGIBLE');
  end if;
  if p_allow_chat is null then
    return app_private.api_error('INVALID_INPUT');
  end if;

  select n.id into note_id
    from public.notes n
   where n.id = p_note_id and n.author_id = actor_id
     and n.status in ('pending_review', 'published', 'hidden')
   for update;
  if not found then
    return app_private.api_error('NOTE_NOT_FOUND');
  end if;

  update public.notes
     set allow_chat = p_allow_chat
   where id = note_id
   returning allow_chat into updated_allow_chat;
  return jsonb_build_object('data', jsonb_build_object('allow_chat', updated_allow_chat));
end;
$$;

revoke all on function public.get_wall_tiles(bigint, bigint, bigint, bigint, bigint, bigint, uuid, integer) from public, anon;
revoke all on function public.get_wall_density(bigint, bigint, bigint, bigint) from public, anon;
revoke all on function public.get_note_detail(uuid) from public, anon;
revoke all on function public.get_discovery_target(jsonb) from public, anon;
revoke all on function public.suggest_placement_regions(bigint, bigint) from public, anon;
revoke all on function public.place_note(text, text, boolean, bigint, bigint, uuid) from public, anon;
revoke all on function public.get_my_notes(timestamptz, uuid, integer) from public, anon;
revoke all on function public.edit_note(uuid, text, uuid) from public, anon;
revoke all on function public.delete_note(uuid, uuid) from public, anon;
revoke all on function public.update_note_chat(uuid, boolean) from public, anon;

grant execute on function public.get_wall_tiles(bigint, bigint, bigint, bigint, bigint, bigint, uuid, integer) to authenticated;
grant execute on function public.get_wall_density(bigint, bigint, bigint, bigint) to authenticated;
grant execute on function public.get_note_detail(uuid) to authenticated;
grant execute on function public.get_discovery_target(jsonb) to authenticated;
grant execute on function public.suggest_placement_regions(bigint, bigint) to authenticated;
grant execute on function public.place_note(text, text, boolean, bigint, bigint, uuid) to authenticated;
grant execute on function public.get_my_notes(timestamptz, uuid, integer) to authenticated;
grant execute on function public.edit_note(uuid, text, uuid) to authenticated;
grant execute on function public.delete_note(uuid, uuid) to authenticated;
grant execute on function public.update_note_chat(uuid, boolean) to authenticated;

commit;
