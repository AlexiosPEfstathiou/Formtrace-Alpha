-- =====================================================================
-- FormTrace — Item AT, step 1 of 5: week-based calendar data model.
-- Run in the Supabase SQL editor. Safe to run while the app is still on
-- the day model: nothing client-side reads any of this until step 2, and
-- nothing here changes what existing code reads. Idempotent — re-running
-- is harmless.
--
-- DESIGN (decided 2026-09-07, see PRODUCT_LOG.md item AT):
--   * A session belongs to a WEEK (week_start = its Monday). due_date now
--     means "the day it was actually done" and is null until picked.
--   * Streak = consecutive closed weeks with every session done. Weeks
--     with no sessions, or overlapping a pause, are neutral (skipped).
--   * Leftovers carry into the next week and occupy a slot: the weekly
--     pool is capped at the offer's workouts_per_week_cap; newly assigned
--     sessions that no longer fit are bumped a further week.
--   * Weeks are Monday..Sunday (Postgres date_trunc('week') is ISO).
--
-- WHAT THIS DOES NOT DO: it does not touch profiles.streak_count or any
-- existing streak function. The new streak lives in a NEW column
-- (week_streak_count) so both measures coexist until step 5 cuts over.
-- =====================================================================

-- ---------- 1. week_start on assigned_workouts, backfilled ----------
alter table public.assigned_workouts
  add column if not exists week_start date;

-- Backfill: every existing row belongs to the week of its due_date (or
-- created_at when due_date was never set). Only rows still null, so
-- re-running never moves anything already placed.
update public.assigned_workouts
   set week_start = date_trunc('week', coalesce(due_date, (created_at at time zone 'UTC')::date)::timestamp)::date
 where week_start is null;

create index if not exists assigned_workouts_eng_week_idx
  on public.assigned_workouts (engagement_id, week_start);

-- ---------- 2. week_closures: one row per engagement per closed week ----------
-- This is the streak's source of truth AND the audit trail — it can answer
-- "why did my streak break" exactly, which the day model never could.
create table if not exists public.week_closures (
  id              uuid primary key default gen_random_uuid(),
  engagement_id   uuid not null references public.engagements(id) on delete cascade,
  week_start      date not null,
  assigned_count  integer not null,
  completed_count integer not null,
  carried_count   integer not null default 0,   -- how many leftovers rolled into the next week
  bumped_count    integer not null default 0,   -- how many new sessions got pushed a further week to respect the cap
  neutral         boolean not null,             -- true = doesn't count toward or against the streak
  neutral_reason  text,                         -- 'no_sessions' | 'paused' | null
  closed_at       timestamptz not null default now(),
  unique (engagement_id, week_start)
);

alter table public.week_closures enable row level security;

drop policy if exists "party reads own week closures" on public.week_closures;
create policy "party reads own week closures" on public.week_closures
  for select using (
    exists (select 1 from public.engagements e
             where e.id = week_closures.engagement_id
               and (e.coach_id = auth.uid() or e.trainee_id = auth.uid()))
  );
-- No insert/update/delete policies on purpose: rows are only ever written
-- by close_week() below, which is SECURITY DEFINER.

-- ---------- 3. close_week(): the week transition, idempotent ----------
create or replace function public.close_week(p_engagement uuid, p_week_start date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  w            date := date_trunc('week', p_week_start::timestamp)::date;
  cur_week     date := date_trunc('week', current_date::timestamp)::date;
  e            public.engagements%rowtype;
  cap          integer;
  n_assigned   integer;
  n_completed  integer;
  n_carried    integer := 0;
  n_bumped     integer := 0;
  is_neutral   boolean;
  why_neutral  text;
  existing     public.week_closures%rowtype;
  next_total   integer;
  carried_ids  uuid[];
begin
  select * into e from public.engagements where id = p_engagement;
  if e.id is null then raise exception 'engagement not found'; end if;
  if auth.uid() is null or (auth.uid() <> e.coach_id and auth.uid() <> e.trainee_id) then
    raise exception 'not a party to this engagement';
  end if;
  if w >= cur_week then
    raise exception 'cannot close the current or a future week (%)', w;
  end if;

  -- Idempotent: already closed → return the existing row untouched.
  select * into existing from public.week_closures
   where engagement_id = p_engagement and week_start = w;
  if existing.id is not null then
    return jsonb_build_object('already_closed', true, 'week_start', w,
      'assigned', existing.assigned_count, 'completed', existing.completed_count,
      'neutral', existing.neutral, 'carried', existing.carried_count, 'bumped', existing.bumped_count);
  end if;

  select count(*), count(*) filter (where status in ('submitted','reviewed'))
    into n_assigned, n_completed
    from public.assigned_workouts
   where engagement_id = p_engagement and week_start = w;

  -- Neutral: nothing was assigned, or any pause overlaps the week.
  if n_assigned = 0 then
    is_neutral := true; why_neutral := 'no_sessions';
  elsif exists (select 1 from public.engagement_pauses p
                 where p.engagement_id = p_engagement
                   and p.starts_on <= w + 6
                   and coalesce(p.ends_on, w + 6) >= w) then
    is_neutral := true; why_neutral := 'paused';
  else
    is_neutral := false; why_neutral := null;
  end if;

  -- Carry: every still-unfinished session of this week moves to next week.
  -- Remember exactly which rows these were, so the cap step below can never
  -- bump a carried session by mistake (they are owed first, by design).
  select coalesce(array_agg(id), '{}') into carried_ids
    from public.assigned_workouts
   where engagement_id = p_engagement and week_start = w and status = 'assigned';
  update public.assigned_workouts
     set week_start = w + 7
   where id = any(carried_ids);
  n_carried := coalesce(array_length(carried_ids, 1), 0);

  -- Cap: next week's pool must not exceed the agreed weekly number. Carried
  -- sessions keep their slots (they were owed first); the NEWEST of the
  -- coach's own new assignments for next week are bumped a further week.
  -- (If that in turn overflows the week after, it is resolved when THAT
  -- week closes — the cascade is handled one close at a time, on purpose.)
  select o.workouts_per_week_cap into cap
    from public.offers o where o.id = e.offer_id;
  if cap is not null and n_carried > 0 then
    select count(*) into next_total from public.assigned_workouts
     where engagement_id = p_engagement and week_start = w + 7;
    if next_total > cap then
      with to_bump as (
        select id from public.assigned_workouts
         where engagement_id = p_engagement and week_start = w + 7 and status = 'assigned'
           and not (id = any(carried_ids))        -- never bump a carried session
         order by created_at desc                 -- newest of the coach's own new ones go first
         limit (next_total - cap)
      )
      update public.assigned_workouts a set week_start = w + 14
        from to_bump where a.id = to_bump.id;
      get diagnostics n_bumped = row_count;
    end if;
  end if;

  insert into public.week_closures
    (engagement_id, week_start, assigned_count, completed_count, carried_count, bumped_count, neutral, neutral_reason)
  values (p_engagement, w, n_assigned, n_completed, n_carried, n_bumped, is_neutral, why_neutral);

  return jsonb_build_object('already_closed', false, 'week_start', w,
    'assigned', n_assigned, 'completed', n_completed,
    'neutral', is_neutral, 'neutral_reason', why_neutral,
    'carried', n_carried, 'bumped', n_bumped);
end;
$$;
grant execute on function public.close_week(uuid, date) to authenticated;

-- ---------- 4. close_weeks_due(): catch up every unclosed past week ----------
-- What the client actually calls, once, on first load. Walks from the first
-- unclosed week up to last week. Cheap when nothing is due (one lookup).
create or replace function public.close_weeks_due(p_engagement uuid, p_today date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cur_week  date := date_trunc('week', coalesce(p_today, current_date)::timestamp)::date;
  e         public.engagements%rowtype;
  w         date;
  n         integer := 0;
begin
  select * into e from public.engagements where id = p_engagement;
  if e.id is null then raise exception 'engagement not found'; end if;
  if auth.uid() is null or (auth.uid() <> e.coach_id and auth.uid() <> e.trainee_id) then
    raise exception 'not a party to this engagement';
  end if;

  -- start at the week after the last closure, or the engagement's first week
  select coalesce(max(week_start) + 7, date_trunc('week', (e.started_at at time zone 'UTC')::date::timestamp)::date)
    into w from public.week_closures where engagement_id = p_engagement;

  while w < cur_week loop
    perform public.close_week(p_engagement, w);
    n := n + 1;
    w := w + 7;
  end loop;
  return jsonb_build_object('closed', n, 'current_week', cur_week);
end;
$$;
grant execute on function public.close_weeks_due(uuid, date) to authenticated;

-- ---------- 5. Week-based streak, alongside (not replacing) the day one ----------
alter table public.profiles
  add column if not exists week_streak_count integer not null default 0;

-- Private calculator. Walks back from last week; per trainee across ALL their
-- engagements: any non-neutral incomplete closure in a week breaks; a week
-- with only neutral rows (or no rows at all) is skipped; stops at the
-- trainee's earliest engagement so it can't walk back forever.
create or replace function public.compute_week_streak(p_uid uuid, p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cur_week   date := date_trunc('week', coalesce(p_today, current_date)::timestamp)::date;
  w          date := cur_week - 7;
  floor_week date;
  streak     integer := 0;
  any_bad    boolean;
  any_good   boolean;
begin
  select min(date_trunc('week', (started_at at time zone 'UTC')::date::timestamp)::date)
    into floor_week from public.engagements where trainee_id = p_uid;
  if floor_week is null then return 0; end if;

  while w >= floor_week loop
    select
      bool_or(not c.neutral and c.completed_count < c.assigned_count),
      bool_or(not c.neutral and c.completed_count >= c.assigned_count)
      into any_bad, any_good
      from public.week_closures c
      join public.engagements e on e.id = c.engagement_id
     where e.trainee_id = p_uid and c.week_start = w;

    if coalesce(any_bad,false) then
      exit;                      -- a week with an unfinished session ends the run
    elsif coalesce(any_good,false) then
      streak := streak + 1;      -- a fully-completed week extends it
    end if;                      -- otherwise neutral / nothing recorded: skip
    w := w - 7;
  end loop;
  return streak;
end;
$$;
revoke execute on function public.compute_week_streak(uuid, date) from public;

create or replace function public.refresh_my_week_streak(p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v integer;
begin
  if auth.uid() is null then return 0; end if;
  v := public.compute_week_streak(auth.uid(), coalesce(p_today, current_date));
  update public.profiles set week_streak_count = v where id = auth.uid();
  return v;
end;
$$;
grant execute on function public.refresh_my_week_streak(date) to authenticated;

-- ---------- 6. Backfill closures from history, so streaks are continuous ----------
-- Records what already happened, week by week, per engagement, from its
-- first week up to last week. Deliberately does NOT carry or bump anything:
-- historically-missed day-model sessions stay where they were and are NOT
-- resurrected into anyone's current pool (the pool is strictly
-- week_start = this Monday, and only close_week ever moves a row forward).
-- Only inserts weeks that have no closure yet, so it is safe to re-run.
insert into public.week_closures
  (engagement_id, week_start, assigned_count, completed_count, carried_count, bumped_count, neutral, neutral_reason)
select
  e.id,
  wk.w,
  coalesce(a.n_assigned, 0),
  coalesce(a.n_completed, 0),
  0, 0,
  case when coalesce(a.n_assigned,0) = 0 then true
       when exists (select 1 from public.engagement_pauses p
                     where p.engagement_id = e.id
                       and p.starts_on <= wk.w + 6
                       and coalesce(p.ends_on, wk.w + 6) >= wk.w) then true
       else false end,
  case when coalesce(a.n_assigned,0) = 0 then 'no_sessions'
       when exists (select 1 from public.engagement_pauses p
                     where p.engagement_id = e.id
                       and p.starts_on <= wk.w + 6
                       and coalesce(p.ends_on, wk.w + 6) >= wk.w) then 'paused'
       else null end
from public.engagements e
cross join lateral (
  select generate_series(
           date_trunc('week', (e.started_at at time zone 'UTC')::date::timestamp)::date,
           date_trunc('week', current_date::timestamp)::date - 7,
           interval '7 days')::date as w
) wk
left join lateral (
  select count(*) as n_assigned,
         count(*) filter (where status in ('submitted','reviewed')) as n_completed
    from public.assigned_workouts x
   where x.engagement_id = e.id and x.week_start = wk.w
) a on true
where not exists (select 1 from public.week_closures c
                   where c.engagement_id = e.id and c.week_start = wk.w);

-- ---------- 7. Seed the new streak column for everyone ----------
update public.profiles p
   set week_streak_count = public.compute_week_streak(p.id, current_date)
 where exists (select 1 from public.engagements e where e.trainee_id = p.id);

-- ---------- sanity: what exists now ----------
select 'assigned_workouts.week_start nulls' as check, count(*) from public.assigned_workouts where week_start is null
union all
select 'week_closures rows', count(*) from public.week_closures
union all
select 'trainees with week_streak > 0', count(*) from public.profiles where week_streak_count > 0;
