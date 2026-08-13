-- =====================================================================
-- FormTrace — item C: reschedule a missed workout to protect a streak
-- Run in the Supabase SQL editor.
--
-- DECIDED 2026-08-07: no coach approval needed, but the new date must fall
-- within the next 6 days, and it must be a genuine reschedule of a workout
-- that would otherwise break the streak TODAY — not a general-purpose way
-- to move any workout whenever. request_postpone (coach-approved, no day
-- ceiling) already exists for ordinary rescheduling; this is deliberately
-- separate and narrower, per the log's own implementation note.
-- =====================================================================

create or replace function public.reschedule_for_streak(p_assigned uuid, p_new_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t uuid;
  d date;
  s text;
  today date := current_date;
begin
  select en.trainee_id, aw.due_date, aw.status
    into t, d, s
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if t is null then raise exception 'workout not found'; end if;
  if t <> auth.uid() then raise exception 'not your workout'; end if;
  if s <> 'assigned' then raise exception 'only a pending workout can be rescheduled'; end if;
  -- must genuinely be at risk today, not any future workout moved early
  if d is null or d >= today then raise exception 'this workout is not overdue yet'; end if;
  if p_new_date is null or p_new_date <= today or p_new_date > today + 6 then
    raise exception 'pick a day within the next 6 days';
  end if;

  update public.assigned_workouts set due_date = p_new_date where id = p_assigned;
end;
$$;

revoke execute on function public.reschedule_for_streak(uuid,date) from public;
grant  execute on function public.reschedule_for_streak(uuid,date) to authenticated;

select proname from pg_proc where proname = 'reschedule_for_streak';
