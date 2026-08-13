-- =====================================================================
-- FormTrace — items M & N: vacation mode, one shared pause primitive
-- Run in the Supabase SQL editor. Requires migrations_streak_redefine.sql
-- and migrations_journey.sql to already be applied (this replaces two of
-- their functions).
--
-- DECIDED (proceeding on this default since the log's open question was
-- never answered): a paused week bills nothing, full stop — not a
-- pro-rated partial charge. This is the simplest reading consistent with
-- "no workouts are due" during a pause, and avoids inventing a day-by-day
-- proration mechanism the request never asked for.
--
-- M and N share ONE table and ONE set of functions, per the log's own
-- note that they're the same mechanism with different triggers. N (coach
-- pausing everyone at once) is just "insert one pause row per active
-- engagement", not a separate feature.
--
-- SCOPE, stated plainly rather than silently assumed complete:
--   - Built: the pause table, day-state/streak awareness (a paused day
--     is neither 'done' nor 'missed' nor ordinary 'rest' - it's skipped
--     entirely, so it can never break a streak and never inflates one),
--     start/end/bulk-start functions, and a read function for display.
--   - NOT built here: payment-ledger integration (recompute_cycle doesn't
--     yet know about pauses - a paused week still bills normally until
--     that function gets its own pass) and server-side blocking of
--     assigning a workout INTO a paused window (a coach can still do it
--     today; the day-state fix means it just won't count as missed if
--     they do). Both are real gaps, named so nobody assumes otherwise.
-- =====================================================================

create table public.engagement_pauses (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  triggered_by  uuid not null references public.profiles(id),
  message       text,
  starts_on     date not null default current_date,
  ends_on       date,                    -- null = open-ended until resumed
  created_at    timestamptz not null default now()
);

alter table public.engagement_pauses enable row level security;

drop policy if exists "party reads own pauses" on public.engagement_pauses;
create policy "party reads own pauses"
  on public.engagement_pauses for select to authenticated
  using (
    exists (select 1 from public.engagements e
            where e.id = engagement_pauses.engagement_id
              and (e.trainee_id = auth.uid() or e.coach_id = auth.uid()))
  );
-- no client insert/update/delete policy — written only by the functions below

create index if not exists engagement_pauses_eng_idx on public.engagement_pauses (engagement_id);

-- ---------------------------------------------------------------------
-- _day_state, extended with a 'paused' state. A day only reads as
-- 'paused' when EVERY one of the trainee's active engagements has a
-- covering pause for that date — if a trainee has two goals and only one
-- is paused, the other's workouts still count normally, since the
-- trainee's calendar is genuinely still live for that goal.
-- ---------------------------------------------------------------------
create or replace function public._day_state(p_trainee uuid, p_date date)
returns text
language sql
security definer
set search_path = public
as $$
  with active_engs as (
    select e.id from public.engagements e
    where e.trainee_id = p_trainee and e.status = 'active'
  ),
  due as (
    select aw.status
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where e.trainee_id = p_trainee
      and e.status = 'active'
      and coalesce(aw.due_date, (aw.created_at at time zone 'UTC')::date) = p_date
  )
  select case
    when exists (select 1 from active_engs)
         and not exists (
           select 1 from active_engs ae
           where not exists (
             select 1 from public.engagement_pauses ep
             where ep.engagement_id = ae.id
               and ep.starts_on <= p_date
               and (ep.ends_on is null or ep.ends_on >= p_date)
           )
         )
      then 'paused'
    when not exists (select 1 from due)                       then 'rest'
    when exists (select 1 from due where status = 'assigned') then 'missed'
    else 'done'
  end;
$$;

-- kept so the old predicate name still resolves; now derived from _day_state
create or replace function public._day_complete(p_trainee uuid, p_date date)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public._day_state(p_trainee, p_date) <> 'missed';
$$;

-- ---------------------------------------------------------------------
-- compute_streak, with a paused day skipped entirely in both directions —
-- neither counted as streak progress nor allowed to touch the rest
-- counter, so walking through a whole vacation leaves the streak exactly
-- as it was on either side of it.
-- ---------------------------------------------------------------------
create or replace function public.compute_streak(p_trainee uuid, p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today  date := coalesce(p_today, current_date);
  v_anchor date;
  v_count  integer := 0;
  v_cur    date;
  v_state  text;
  v_rest   integer;
  v_guard  integer;
  v_floor  date;
begin
  select min(coalesce(aw.due_date, (aw.created_at at time zone 'UTC')::date))
    into v_floor
  from public.assigned_workouts aw
  join public.engagements e on e.id = aw.engagement_id
  where e.trainee_id = p_trainee and e.status = 'active';
  if v_floor is null then return 0; end if;

  foreach v_cur in array array[v_today, v_today - 1] loop
    if public._day_state(p_trainee, v_cur) <> 'missed' then
      v_anchor := v_cur; exit;
    end if;
  end loop;
  if v_anchor is null then return 0; end if;

  -- backward
  v_cur := v_anchor; v_rest := 0; v_guard := 0;
  while v_guard < 400 loop
    exit when v_cur < v_floor;
    v_state := public._day_state(p_trainee, v_cur);
    if v_state = 'paused' then
      v_cur := v_cur - 1; v_guard := v_guard + 1; continue;
    end if;
    if v_state = 'missed' then exit; end if;
    if v_state = 'rest' then
      v_rest := v_rest + 1;
      if v_rest >= 7 then exit; end if;
    else
      v_rest := 0;
    end if;
    v_count := v_count + 1;
    v_cur := v_cur - 1; v_guard := v_guard + 1;
  end loop;

  -- forward, for days already logged ahead
  v_cur := v_anchor + 1; v_rest := 0; v_guard := 0;
  while v_guard < 400 loop
    v_state := public._day_state(p_trainee, v_cur);
    if v_state = 'paused' then
      v_cur := v_cur + 1; v_guard := v_guard + 1; continue;
    end if;
    if v_state = 'missed' then exit; end if;
    if v_state = 'rest' then exit; end if;
    v_count := v_count + 1;
    v_cur := v_cur + 1; v_guard := v_guard + 1;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- peak_streak_in_range, same paused-skip treatment.
-- ---------------------------------------------------------------------
create or replace function public.peak_streak_in_range(p_trainee uuid, p_from date, p_to date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cur date := p_from;
  run integer := 0;
  rest integer := 0;
  best integer := 0;
  guard integer := 0;
  st text;
begin
  if p_from is null or p_to is null or p_to < p_from then return 0; end if;
  while cur <= p_to and guard < 1000 loop
    st := public._day_state(p_trainee, cur);
    if st = 'paused' then
      null;   -- skip: no run change, no rest change, no break
    elsif st = 'missed' then
      run := 0; rest := 0;
    elsif st = 'rest' then
      rest := rest + 1;
      if rest >= 7 then run := 0; rest := 0;
      else run := run + 1; end if;
    else
      run := run + 1; rest := 0;
    end if;
    if run > best then best := run; end if;
    cur := cur + 1; guard := guard + 1;
  end loop;
  return best;
end;
$$;

revoke execute on function public._day_state(uuid, date) from public;
revoke execute on function public.compute_streak(uuid, date) from public;
revoke execute on function public.peak_streak_in_range(uuid,date,date) from public;
grant  execute on function public.peak_streak_in_range(uuid,date,date) to authenticated;

-- ---------------------------------------------------------------------
-- Start a pause. Either party on the engagement may call this — a
-- trainee pausing their own goal (item M) and a coach pausing one goal
-- use the exact same function; item N (coach pausing everyone) is
-- start_pause_all below, which just calls this once per engagement.
-- ---------------------------------------------------------------------
create or replace function public.start_pause(p_engagement uuid, p_message text, p_ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  eng record;
  out jsonb;
begin
  select id, trainee_id, coach_id, status into eng from public.engagements where id = p_engagement;
  if eng.id is null then raise exception 'goal not found'; end if;
  if uid <> eng.trainee_id and uid <> eng.coach_id then raise exception 'not authorised'; end if;
  if eng.status <> 'active' then raise exception 'goal is not active'; end if;
  if p_ends_on is not null and p_ends_on < current_date then raise exception 'end date must be today or later'; end if;

  insert into public.engagement_pauses (engagement_id, triggered_by, message, starts_on, ends_on)
  values (p_engagement, uid, p_message, current_date, p_ends_on)
  returning to_jsonb(engagement_pauses.*) into out;
  return out;
end;
$$;

revoke execute on function public.start_pause(uuid,text,date) from public;
grant  execute on function public.start_pause(uuid,text,date) to authenticated;

-- ---------------------------------------------------------------------
-- Item N: coach pauses every one of their own active engagements at once,
-- with one shared message. Returns how many were paused.
-- ---------------------------------------------------------------------
create or replace function public.start_pause_all(p_message text, p_ends_on date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n integer := 0;
  eng record;
begin
  if p_ends_on is not null and p_ends_on < current_date then raise exception 'end date must be today or later'; end if;
  for eng in select id from public.engagements where coach_id = uid and status = 'active' loop
    insert into public.engagement_pauses (engagement_id, triggered_by, message, starts_on, ends_on)
    values (eng.id, uid, p_message, current_date, p_ends_on);
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.start_pause_all(text,date) from public;
grant  execute on function public.start_pause_all(text,date) to authenticated;

-- ---------------------------------------------------------------------
-- Resume early: today becomes a normal day again (not the day the button
-- was tapped becoming retroactively un-paused — "resume" reads as "from
-- now on", so yesterday and earlier stay paused, today onward doesn't).
-- ---------------------------------------------------------------------
create or replace function public.end_pause(p_engagement uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if not exists (
    select 1 from public.engagements e where e.id = p_engagement
      and (e.trainee_id = uid or e.coach_id = uid)
  ) then raise exception 'not authorised'; end if;

  update public.engagement_pauses
     set ends_on = current_date - 1
   where engagement_id = p_engagement
     and (ends_on is null or ends_on >= current_date);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.end_pause(uuid) from public;
grant  execute on function public.end_pause(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Currently-active-or-future pauses visible to the caller, for both
-- homepages to render a vacation banner from.
-- ---------------------------------------------------------------------
create or replace function public.my_active_pauses()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(row order by starts_on), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'engagement_id', ep.engagement_id,
      'goal_title', e.goal_title,
      'message', ep.message,
      'starts_on', ep.starts_on,
      'ends_on', ep.ends_on,
      'triggered_by', ep.triggered_by,
      'i_triggered_it', ep.triggered_by = auth.uid()
    ) as row, ep.starts_on
    from public.engagement_pauses ep
    join public.engagements e on e.id = ep.engagement_id
    where (e.trainee_id = auth.uid() or e.coach_id = auth.uid())
      and (ep.ends_on is null or ep.ends_on >= current_date)
  ) s;
$$;

revoke execute on function public.my_active_pauses() from public;
grant  execute on function public.my_active_pauses() to authenticated;

select proname from pg_proc
where proname in ('start_pause','start_pause_all','end_pause','my_active_pauses',
                   '_day_state','compute_streak','peak_streak_in_range')
order by proname;
