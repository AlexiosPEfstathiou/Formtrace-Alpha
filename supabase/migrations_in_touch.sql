-- =====================================================================
-- FormTrace — Item CM "In Touch": knock to connect + congratulate.
-- Run in the Supabase SQL editor.
-- =====================================================================
create table if not exists public.connections (
  id           uuid primary key default gen_random_uuid(),
  a            uuid not null references public.profiles(id) on delete cascade,
  b            uuid not null references public.profiles(id) on delete cascade,
  a_ok         boolean not null default false,
  b_ok         boolean not null default false,
  status       text not null default 'pending' check (status in ('pending','confirmed','ended')),
  via          text not null default 'knock' check (via in ('knock','qr')),
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,
  constraint connections_pair check (a < b),
  unique (a, b)
);
alter table public.connections enable row level security;
drop policy if exists "parties read connections" on public.connections;
create policy "parties read connections" on public.connections for select to authenticated using (a = auth.uid() or b = auth.uid());

create table if not exists public.knocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  received_at timestamptz not null default now(),
  lat         double precision, lng double precision,
  magnitude   double precision,
  matched     uuid references public.connections(id) on delete set null
);
alter table public.knocks enable row level security;
drop policy if exists "own knocks" on public.knocks;
create policy "own knocks" on public.knocks for select to authenticated using (user_id = auth.uid());
create index if not exists knocks_recent on public.knocks (received_at desc);

create table if not exists public.connect_tokens (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  token      text not null,
  expires_at timestamptz not null
);
alter table public.connect_tokens enable row level security;

create table if not exists public.celebrations (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null references public.profiles(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  event_kind text not null,          -- 'pb' | 'goal' | 'streak' | 'badge'
  event_ref  text not null,          -- id or key of the celebrated thing (dedupes: one clap per person per event)
  event_text text not null,          -- "Squat 80 kg × 5"
  created_at timestamptz not null default now(),
  seen_at    timestamptz,
  unique (from_user, to_user, event_kind, event_ref)
);
alter table public.celebrations enable row level security;
drop policy if exists "parties read celebrations" on public.celebrations;
create policy "parties read celebrations" on public.celebrations for select to authenticated using (from_user = auth.uid() or to_user = auth.uid());
drop policy if exists "recipient marks seen" on public.celebrations;
create policy "recipient marks seen" on public.celebrations for update to authenticated using (to_user = auth.uid()) with check (to_user = auth.uid());

-- helper: are two users confirmed connections?
create or replace function public.are_connected(p_x uuid, p_y uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.connections c where c.status='confirmed' and c.a = least(p_x,p_y) and c.b = greatest(p_x,p_y));
$$;

-- pending/confirmed connection row for a pair, creating it if needed (pending)
create or replace function public._connection_for(p_x uuid, p_y uuid, p_via text)
returns public.connections language plpgsql security definer set search_path = public as $$
declare c public.connections;
begin
  insert into public.connections (a, b, via) values (least(p_x,p_y), greatest(p_x,p_y), p_via)
  on conflict (a, b) do update set status = case when public.connections.status='ended' then 'pending' else public.connections.status end
  returning * into c;
  return c;
end; $$;

-- ---------- the knock ----------
-- Registers this phone's jolt and looks for another user's jolt within
-- 600 ms and ~60 m that is not yet matched. Returns the connection and the
-- other person, or {matched:false}. The client polls this a few times
-- (with p_poll_only=true) because the other phone's report may arrive
-- a moment later.
create or replace function public.register_knock(p_lat double precision, p_lng double precision, p_magnitude double precision, p_poll_only boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  me public.knocks; other public.knocks; c public.connections; o record;
begin
  if uid is null then raise exception 'not signed in'; end if;
  if not p_poll_only then
    insert into public.knocks (user_id, lat, lng, magnitude) values (uid, p_lat, p_lng, p_magnitude) returning * into me;
  else
    select * into me from public.knocks where user_id = uid and matched is null order by received_at desc limit 1;
    if me.id is null then return jsonb_build_object('matched', false); end if;
    if me.received_at < now() - interval '6 seconds' then return jsonb_build_object('matched', false, 'expired', true); end if;
  end if;
  -- already matched by the other side's call?
  if me.matched is not null then
    select * into c from public.connections where id = me.matched;
  else
    select k.* into other from public.knocks k
     where k.user_id <> uid and k.matched is null
       and abs(extract(epoch from (k.received_at - me.received_at))) <= 0.6
       and (me.lat is null or k.lat is null or
            (abs(k.lat - me.lat) < 0.0006 and abs(k.lng - me.lng) < 0.0009))   -- ~60 m
     order by abs(extract(epoch from (k.received_at - me.received_at))) limit 1;
    if other.id is null then return jsonb_build_object('matched', false); end if;
    c := public._connection_for(uid, other.user_id, 'knock');
    update public.knocks set matched = c.id where id in (me.id, other.id);
  end if;
  select p.id, p.display_name, p.avatar_path, p.avatar_initials into o from public.profiles p
   where p.id = case when c.a = uid then c.b else c.a end;
  return jsonb_build_object('matched', true, 'connection_id', c.id, 'status', c.status,
    'other', jsonb_build_object('id', o.id, 'display_name', o.display_name, 'avatar_path', o.avatar_path, 'avatar_initials', o.avatar_initials));
end; $$;
revoke execute on function public.register_knock(double precision,double precision,double precision,boolean) from public;
grant  execute on function public.register_knock(double precision,double precision,double precision,boolean) to authenticated;

-- both sides confirm; the second confirmation completes it
create or replace function public.confirm_connection(p_id uuid, p_accept boolean)
returns public.connections language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c public.connections;
begin
  select * into c from public.connections where id = p_id;
  if not found or (c.a <> uid and c.b <> uid) then raise exception 'not your connection'; end if;
  if not p_accept then update public.connections set status='ended' where id = p_id returning * into c; return c; end if;
  update public.connections
     set a_ok = case when a = uid then true else a_ok end,
         b_ok = case when b = uid then true else b_ok end
   where id = p_id returning * into c;
  if c.a_ok and c.b_ok and c.status <> 'confirmed' then
    update public.connections set status='confirmed', confirmed_at=now() where id = p_id returning * into c;
  end if;
  return c;
end; $$;
revoke execute on function public.confirm_connection(uuid,boolean) from public;
grant  execute on function public.confirm_connection(uuid,boolean) to authenticated;

-- ---------- QR fallback: 60-second token ----------
create or replace function public.issue_connect_token()
returns text language plpgsql security definer set search_path = public as $$
declare t text := upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 10));
begin
  insert into public.connect_tokens (user_id, token, expires_at) values (auth.uid(), t, now() + interval '60 seconds')
  on conflict (user_id) do update set token = excluded.token, expires_at = excluded.expires_at;
  return t;
end; $$;
create or replace function public.connect_by_token(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); owner uuid; c public.connections; o record;
begin
  select user_id into owner from public.connect_tokens where token = upper(trim(p_token)) and expires_at > now();
  if owner is null then raise exception 'that code has expired - ask them to show it again'; end if;
  if owner = uid then raise exception 'that is your own code'; end if;
  c := public._connection_for(uid, owner, 'qr');
  update public.connections set a_ok = case when a = uid then true else a_ok end, b_ok = case when b = uid then true else b_ok end where id = c.id returning * into c;
  select p.id, p.display_name, p.avatar_path, p.avatar_initials into o from public.profiles p where p.id = owner;
  return jsonb_build_object('connection_id', c.id, 'status', c.status,
    'other', jsonb_build_object('id', o.id, 'display_name', o.display_name, 'avatar_path', o.avatar_path, 'avatar_initials', o.avatar_initials));
end; $$;
revoke execute on function public.issue_connect_token() from public;
grant  execute on function public.issue_connect_token() to authenticated;
revoke execute on function public.connect_by_token(text) from public;
grant  execute on function public.connect_by_token(text) to authenticated;

-- ---------- the feed: connections' PBs and goal completions, last 30 days ----------
create or replace function public.in_touch_feed()
returns jsonb language sql stable security definer set search_path = public as $$
  with mine as (
    select case when a = auth.uid() then b else a end as other from public.connections where status='confirmed' and (a = auth.uid() or b = auth.uid())
  ),
  ev as (
    select p.trainee_id as user_id, 'pb' as kind, p.id::text as ref, p.achieved_at as at,
           p.exercise_name || ' ' || case when p.weight_kg is not null then p.weight_kg || ' kg × ' || p.reps else p.reps || ' reps' end as text
      from public.personal_bests p join mine m on m.other = p.trainee_id
     where p.achieved_at > now() - interval '30 days'
    union all
    select e.trainee_id, 'goal', e.id::text, e.completed_at, 'Completed "' || coalesce(e.goal_title,'a goal') || '"'
      from public.engagements e join mine m on m.other = e.trainee_id
     where e.status = 'completed' and e.completed_at > now() - interval '30 days'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', ev.user_id, 'display_name', pr.display_name, 'avatar_path', pr.avatar_path, 'avatar_initials', pr.avatar_initials,
           'kind', ev.kind, 'ref', ev.ref, 'at', ev.at, 'text', ev.text,
           'congratulated', exists (select 1 from public.celebrations c where c.from_user = auth.uid() and c.to_user = ev.user_id and c.event_kind = ev.kind and c.event_ref = ev.ref)
         ) order by ev.at desc), '[]'::jsonb)
    from ev join public.profiles pr on pr.id = ev.user_id;
$$;
grant execute on function public.in_touch_feed() to authenticated;

-- congratulate: one clap per person per event; only between connections
create or replace function public.congratulate(p_to uuid, p_kind text, p_ref text, p_text text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.are_connected(auth.uid(), p_to) then raise exception 'you are not connected'; end if;
  insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text) values (auth.uid(), p_to, p_kind, p_ref, left(p_text, 120))
  on conflict do nothing;
end; $$;
revoke execute on function public.congratulate(uuid,text,text,text) from public;
grant  execute on function public.congratulate(uuid,text,text,text) to authenticated;

select 'in touch tables' as check, count(*) from information_schema.tables where table_schema='public' and table_name in ('connections','knocks','connect_tokens','celebrations');
