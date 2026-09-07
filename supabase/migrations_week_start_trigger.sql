-- =====================================================================
-- FormTrace — Item AT, step 3 (part 1): week_start safety net.
-- Run in the Supabase SQL editor. Requires migrations_week_model.sql.
--
-- Found while building the coach side: the step-1 migration backfilled
-- week_start once, but the app's own assignment insert had never set it,
-- so any workout assigned AFTER that run had week_start = NULL — invisible
-- to close_week() (which counts `where week_start = w`), so never carried,
-- never counted toward a week. The client now sets week_start explicitly;
-- this trigger guarantees it regardless of which code path inserts, and
-- repairs the rows created in the gap.
-- =====================================================================

create or replace function public.assigned_workouts_default_week_start()
returns trigger
language plpgsql
as $$
begin
  if new.week_start is null then
    new.week_start := date_trunc('week',
      coalesce(new.due_date, (coalesce(new.created_at, now()) at time zone 'UTC')::date)::timestamp)::date;
  end if;
  return new;
end;
$$;

drop trigger if exists assigned_workouts_week_start_trg on public.assigned_workouts;
create trigger assigned_workouts_week_start_trg
  before insert or update of due_date, week_start on public.assigned_workouts
  for each row execute function public.assigned_workouts_default_week_start();

-- Repair anything inserted between the step-1 run and this one.
update public.assigned_workouts
   set week_start = date_trunc('week', coalesce(due_date, (created_at at time zone 'UTC')::date)::timestamp)::date
 where week_start is null;

select 'assigned_workouts.week_start nulls (should be 0)' as check, count(*) from public.assigned_workouts where week_start is null;
