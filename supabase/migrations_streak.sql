-- =====================================================================
-- FormTrace — server-side discipline streak
-- Run this whole file once in the Supabase SQL editor.
--
-- WHY: a trainee's streak spans ALL their goals. A coach can't recompute
-- it because RLS hides other coaches' engagements. So we compute it in a
-- SECURITY DEFINER function (runs with elevated rights, sees every row),
-- store the result on profiles.streak_count, and keep it fresh with
-- triggers on logs + assigned_workouts. Everyone just READS the column.
--
-- DEFINITION (mirrors the client exactly):
--   * A day is COMPLETE when macros are logged that day
--     (protein_g, carbs_g, or fat_g is not null) AND no workout that day
--     is still in status 'assigned'.
--   * Anchor = first COMPLETE day among [today, yesterday, tomorrow].
--   * Streak = consecutive COMPLETE days backward from the anchor plus
--     consecutive COMPLETE days forward from anchor+1 (so days logged
--     ahead still count), matching the client's two-direction walk.
--   * No anchor  => 0.
-- =====================================================================

-- 1) Column (idempotent) --------------------------------------------------
alter table public.profiles
  add column if not exists streak_count integer not null default 0;

-- 2) day-complete predicate (security definer so it sees all rows) --------
create or replace function public._day_complete(p_trainee uuid, p_date date)
returns boolean
language sql
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from public.logs l
      where l.trainee_id = p_trainee
        and l.log_date = p_date
        and (l.protein_g is not null or l.carbs_g is not null or l.fat_g is not null)
    )
    and not exists (
      select 1
      from public.assigned_workouts aw
      join public.engagements e on e.id = aw.engagement_id
      where e.trainee_id = p_trainee
        and aw.status = 'assigned'
        and coalesce(aw.due_date, (aw.created_at at time zone 'UTC')::date) = p_date
    );
$$;

-- 3) Core computation -----------------------------------------------------
create or replace function public.compute_streak(p_trainee uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := current_date;
  v_anchor  date;
  v_count   integer := 0;
  v_cur     date;
  v_guard   integer := 0;
begin
  -- anchor = first complete day among today / yesterday / tomorrow
  foreach v_cur in array array[v_today, v_today - 1, v_today + 1]
  loop
    if public._day_complete(p_trainee, v_cur) then
      v_anchor := v_cur;
      exit;
    end if;
  end loop;

  if v_anchor is null then
    return 0;
  end if;

  -- backward from anchor
  v_cur := v_anchor; v_guard := 0;
  while v_guard < 400 and public._day_complete(p_trainee, v_cur) loop
    v_count := v_count + 1;
    v_cur := v_cur - 1;
    v_guard := v_guard + 1;
  end loop;

  -- forward from anchor + 1
  v_cur := v_anchor + 1; v_guard := 0;
  while v_guard < 400 and public._day_complete(p_trainee, v_cur) loop
    v_count := v_count + 1;
    v_cur := v_cur + 1;
    v_guard := v_guard + 1;
  end loop;

  return v_count;
end;
$$;

-- 4) Refresh writers ------------------------------------------------------
-- Internal writer used by triggers (can refresh any trainee).
create or replace function public.refresh_streak(p_trainee uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
    set streak_count = public.compute_streak(p_trainee)
  where id = p_trainee;
end;
$$;

-- Public RPC the app calls (e.g. on login) to recompute the CALLER'S own
-- streak — catches the daily rollover where "today" advances with no data
-- change. Restricted to auth.uid() so nobody can poke other rows.
create or replace function public.refresh_my_streak()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v integer;
begin
  if auth.uid() is null then
    return 0;
  end if;
  v := public.compute_streak(auth.uid());
  update public.profiles set streak_count = v where id = auth.uid();
  return v;
end;
$$;

-- 5) Triggers keep it current --------------------------------------------
-- logs: trainee_id is on the row directly
create or replace function public.trg_refresh_streak_logs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_streak(coalesce(new.trainee_id, old.trainee_id));
  return null;
end;
$$;

drop trigger if exists refresh_streak_on_logs on public.logs;
create trigger refresh_streak_on_logs
  after insert or update or delete on public.logs
  for each row execute function public.trg_refresh_streak_logs();

-- assigned_workouts: trainee_id via engagement
create or replace function public.trg_refresh_streak_aw()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trainee uuid;
begin
  select e.trainee_id into v_trainee
  from public.engagements e
  where e.id = coalesce(new.engagement_id, old.engagement_id);
  if v_trainee is not null then
    perform public.refresh_streak(v_trainee);
  end if;
  return null;
end;
$$;

drop trigger if exists refresh_streak_on_aw on public.assigned_workouts;
create trigger refresh_streak_on_aw
  after insert or update or delete on public.assigned_workouts
  for each row execute function public.trg_refresh_streak_aw();

-- 6) Expose ONLY the safe self-refresh RPC to clients. -------------------
grant execute on function public.refresh_my_streak() to authenticated;
revoke execute on function public.refresh_streak(uuid) from public;
revoke execute on function public.compute_streak(uuid) from public;

-- 7) One-time backfill for existing trainees ------------------------------
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    update public.profiles set streak_count = public.compute_streak(r.id) where id = r.id;
  end loop;
end $$;
