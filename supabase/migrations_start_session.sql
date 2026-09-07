-- =====================================================================
-- FormTrace — Item AT: start_session(): the trainee stamps the day they did it.
-- Run in the Supabase SQL editor. Requires migrations_week_model.sql.
--
-- Under the week model the TRAINEE picks the day a session is done. Found
-- while testing: they had no permitted way to record it. Direct updates on
-- assigned_workouts are column-restricted to (status, draft, opened) since
-- migrations_status_enforce / postpone_enforce, and the existing
-- set_due_date() is deliberately coach-only. This is the trainee-side
-- counterpart, tightly scoped: own engagement, still 'assigned', and only
-- to TODAY - it records what happened, it does not schedule.
-- =====================================================================
create or replace function public.start_session(p_assigned uuid)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare t uuid; s text;
begin
  select en.trainee_id, aw.status into t, s
    from public.assigned_workouts aw
    join public.engagements en on en.id = aw.engagement_id
   where aw.id = p_assigned;
  if t is null then raise exception 'session not found'; end if;
  if t <> auth.uid() then raise exception 'not your session'; end if;
  if s <> 'assigned' then raise exception 'that session has already been submitted'; end if;
  update public.assigned_workouts set due_date = current_date where id = p_assigned;
  return current_date;
end;
$$;
revoke execute on function public.start_session(uuid) from public;
grant execute on function public.start_session(uuid) to authenticated;
