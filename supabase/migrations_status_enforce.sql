-- =====================================================================
-- FormTrace — stop clients writing workout status directly
-- Run in the Supabase SQL editor.
--
-- WHY
--   After migrations_postpone_enforce.sql, clients hold column-level
--   UPDATE on (status, draft, opened). status was left grantable, so a
--   trainee could set their own workout to 'reviewed' — no review exists
--   behind it, so it is mischief rather than damage, but it is the same
--   hole the postpone work closed and it corrupts the coach's queue.
--
-- AFTER THIS
--   Clients may write only draft and opened. Status transitions go through
--   functions that check who is asking and that the transition is real.
-- =====================================================================

revoke update on public.assigned_workouts from authenticated;
grant  update (draft, opened) on public.assigned_workouts to authenticated;

-- ---------------------------------------------------------------------
-- trainee submits: only their own, only from 'assigned', and only once a
-- submission row actually exists
-- ---------------------------------------------------------------------
create or replace function public.mark_submitted(p_assigned uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t uuid; s text; n int;
begin
  select en.trainee_id, aw.status into t, s
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if t is null then raise exception 'workout not found'; end if;
  if t <> auth.uid() then raise exception 'not your workout'; end if;
  if s <> 'assigned' then raise exception 'already submitted'; end if;

  select count(*) into n from public.submissions where assigned_id = p_assigned;
  if n = 0 then raise exception 'no submission recorded for this workout'; end if;

  update public.assigned_workouts set status = 'submitted' where id = p_assigned;
end; $$;

-- ---------------------------------------------------------------------
-- coach marks reviewed: only their trainee, only from 'submitted', and
-- only once a review row exists. Also flags it unseen for the trainee.
-- ---------------------------------------------------------------------
create or replace function public.mark_reviewed(p_assigned uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c uuid; s text; n int;
begin
  select en.coach_id, aw.status into c, s
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if c is null then raise exception 'workout not found'; end if;
  if c <> auth.uid() then raise exception 'not your trainee'; end if;
  if s <> 'submitted' then raise exception 'nothing to review'; end if;

  select count(*) into n
  from public.reviews r
  join public.submissions sub on sub.id = r.submission_id
  where sub.assigned_id = p_assigned;
  if n = 0 then raise exception 'no review recorded'; end if;

  update public.assigned_workouts
     set status = 'reviewed', opened = false
   where id = p_assigned;
end; $$;

do $$
declare f text;
begin
  foreach f in array array['mark_submitted(uuid)','mark_reviewed(uuid)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

select proname from pg_proc
where proname in ('mark_submitted','mark_reviewed') order by proname;
