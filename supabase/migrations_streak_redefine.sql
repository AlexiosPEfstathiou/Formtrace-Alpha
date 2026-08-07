-- =====================================================================
-- FormTrace — redefine the streak around training, not food logging
-- Run in the Supabase SQL editor.
--
-- OLD RULE (surprising in practice)
--   A day counted only if macros were logged AND no workout was still
--   outstanding. Completing a workout contributed nothing on its own, so a
--   trainee who trained five days out of six and never logged food had a
--   streak of zero. The badge is a flame labelled discipline; users read
--   that as training.
--
-- NEW RULE
--   * workout due and every one submitted/reviewed  -> counts
--   * no workout due at all (rest day)              -> counts
--   * workout due and still 'assigned' (missed)     -> breaks the streak
--   * 7 consecutive rest days                       -> breaks the streak
--
--   The last clause is the guard against inactivity: rest days extend a
--   real streak, but a trainee with nothing assigned cannot accrue one
--   indefinitely. Macros no longer affect the streak at all; the homepage
--   nudges cover logging separately.
--
--   Only ACTIVE engagements are considered. Previously a forgotten
--   unsubmitted workout on a completed goal poisoned that date forever,
--   with no way for the trainee to clear it.
-- =====================================================================

set local search_path = public;

-- ---------------------------------------------------------------------
-- one day, three possible states
-- ---------------------------------------------------------------------
create or replace function public._day_state(p_trainee uuid, p_date date)
returns text
language sql
security definer
set search_path = public
as $$
  with due as (
    select aw.status
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where e.trainee_id = p_trainee
      and e.status = 'active'
      and coalesce(aw.due_date, (aw.created_at at time zone 'UTC')::date) = p_date
  )
  select case
    when not exists (select 1 from due)                     then 'rest'
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
-- walk out from an anchor, breaking on a missed day or a 7th rest day
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
  -- never count days before anything was ever assigned, or every rest day
  -- before the trainee started would extend the streak
  select min(coalesce(aw.due_date, (aw.created_at at time zone 'UTC')::date))
    into v_floor
  from public.assigned_workouts aw
  join public.engagements e on e.id = aw.engagement_id
  where e.trainee_id = p_trainee and e.status = 'active';
  if v_floor is null then return 0; end if;   -- nothing ever assigned

  -- anchor on the most recent day that isn't a missed workout
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
    if v_state = 'missed' then exit; end if;
    if v_state = 'rest' then
      v_rest := v_rest + 1;
      if v_rest >= 7 then exit; end if;   -- a whole week off ends it
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
    if v_state = 'missed' then exit; end if;
    if v_state = 'rest' then
      -- don't let empty future dates inflate the streak
      exit;
    end if;
    v_count := v_count + 1;
    v_cur := v_cur + 1; v_guard := v_guard + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public._day_state(uuid, date) from public;
revoke execute on function public.compute_streak(uuid, date) from public;

-- recompute everyone under the new rule
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    update public.profiles set streak_count = public.compute_streak(r.id) where id = r.id;
  end loop;
end $$;

select display_name, streak_count from public.profiles
where streak_count > 0 order by streak_count desc;
