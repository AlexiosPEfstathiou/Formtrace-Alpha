-- =====================================================================
-- FormTrace — Item CI: protect discipline streaks between goals - finitely.
-- Run in the Supabase SQL editor (needs migrations_platform_rates.sql).
--
-- Finding: between goals no engagement is active, so close_week never runs
-- and those weeks have NO closure rows; compute_week_streak skips them, and
-- the streak is preserved for ever - silently. This makes the protection
-- explicit and finite:
--   * profiles.streak_grace_until (a Monday). Set when a trainee's LAST
--     active goal completes or ends: this week's Monday + grace_weeks*7.
--   * While the trainee has a pending offer (any kind, incl. a counter in
--     flight) and no active goal, the window is pushed forward a week at a
--     time - nobody is punished for a coach's response time.
--   * compute_week_streak: a gap week (no closure rows) at or after
--     streak_grace_until BREAKS the run; before it, the week is skipped as
--     today. A new active goal clears the window.
-- Numbers live in platform_rates (editable without a deploy):
--   streak_grace_weeks = 3, streak_amber_weeks = 1.
-- =====================================================================
insert into public.platform_rates (key, value, note) values
  ('streak_grace_weeks', 3, 'weeks a streak is protected after a goal completes while no new goal is active'),
  ('streak_amber_weeks', 1, 'weeks before the grace ends that the app turns the message amber')
on conflict (key) do nothing;

alter table public.profiles add column if not exists streak_grace_until date;

-- helper: this week's Monday
create or replace function public.week_monday(p date default current_date)
returns date language sql immutable as $$ select date_trunc('week', p::timestamp)::date; $$;

-- set / extend / clear the window for one trainee (idempotent)
create or replace function public.ensure_streak_grace(p_uid uuid)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active boolean;
  v_pending boolean;
  v_until date;
  v_weeks int := coalesce((select value::int from public.platform_rates where key='streak_grace_weeks'), 3);
  v_mon date := public.week_monday(current_date);
begin
  select exists (select 1 from public.engagements e where e.trainee_id = p_uid and e.status = 'active') into v_active;
  if v_active then
    update public.profiles set streak_grace_until = null where id = p_uid and streak_grace_until is not null;
    return null;
  end if;
  select streak_grace_until into v_until from public.profiles where id = p_uid;
  if v_until is null then
    -- first time we see this trainee between goals: open a window from now
    if exists (select 1 from public.engagements e where e.trainee_id = p_uid and e.status in ('completed','ended')) then
      v_until := v_mon + 7 * v_weeks;
      update public.profiles set streak_grace_until = v_until where id = p_uid;
    end if;
    return v_until;
  end if;
  -- an offer in flight pauses the clock: keep the window at least one week ahead
  select exists (select 1 from public.offers o where o.trainee_id = p_uid and o.status in ('pending','countered')) into v_pending;
  if v_pending and v_until <= v_mon then
    v_until := v_mon + 7;
    update public.profiles set streak_grace_until = v_until where id = p_uid;
  end if;
  return v_until;
end;
$$;
revoke execute on function public.ensure_streak_grace(uuid) from public;
grant  execute on function public.ensure_streak_grace(uuid) to authenticated;

-- when a goal completes/ends, open the window if nothing else is active
create or replace function public.engagements_streak_grace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('completed','ended') and old.status = 'active' then perform public.ensure_streak_grace(new.trainee_id); end if;
  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active') then
    update public.profiles set streak_grace_until = null where id = new.trainee_id;
  end if;
  return new;
end;
$$;
drop trigger if exists engagements_streak_grace on public.engagements;
create trigger engagements_streak_grace after insert or update of status on public.engagements
  for each row execute function public.engagements_streak_grace();

-- streak: a gap week at/after the window breaks the run
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
  any_row    boolean;
  v_grace    date;
begin
  select min(date_trunc('week', (started_at at time zone 'UTC')::date::timestamp)::date)
    into floor_week from public.engagements where trainee_id = p_uid;
  if floor_week is null then return 0; end if;
  select streak_grace_until into v_grace from public.profiles where id = p_uid;

  while w >= floor_week loop
    select
      bool_or(not c.neutral and c.completed_count < c.assigned_count),
      bool_or(not c.neutral and c.completed_count >= c.assigned_count),
      count(*) > 0
    into any_bad, any_good, any_row
    from public.week_closures c
    join public.engagements e on e.id = c.engagement_id
    where e.trainee_id = p_uid and c.week_start = w;

    if coalesce(any_bad,false) then
      exit;                                             -- an unfinished session ends the run
    elsif coalesce(any_good,false) then
      streak := streak + 1;                             -- a fully-completed week extends it
    elsif not coalesce(any_row,false) and v_grace is not null and w >= v_grace then
      exit;                                             -- CI: a gap week past the protection window ends the run
    end if;                                             -- otherwise neutral / protected gap: skip
    w := w - 7;
  end loop;
  return streak;
end;
$$;

-- refresh keeps the window honest before recomputing
create or replace function public.refresh_my_week_streak(p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  perform public.ensure_streak_grace(auth.uid());
  n := public.compute_week_streak(auth.uid(), p_today);
  update public.profiles set week_streak_count = n where id = auth.uid();
  return n;
end;
$$;

-- backfill: every trainee currently between goals gets a fresh window from this week
do $$ declare r record; begin
  for r in select p.id from public.profiles p where p.role='trainee' loop perform public.ensure_streak_grace(r.id); end loop;
end $$;

select 'trainees with a grace window' as check, count(*) from public.profiles where streak_grace_until is not null;
