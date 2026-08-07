-- =====================================================================
-- FormTrace — notify the trainee of a postpone decision
-- Run in the Supabase SQL editor.
--
-- The coach's approve/decline currently changes postpone_status and
-- nothing tells the trainee. This adds a seen-marker so the homepage can
-- show the decision once and then stop.
--
-- The marker cannot be a plain client write: postpone_* columns are
-- deliberately excluded from the UPDATE grant (see
-- migrations_status_enforce.sql), so acknowledging goes through a
-- function that verifies the caller is that trainee.
-- =====================================================================

alter table public.assigned_workouts
  add column if not exists postpone_seen_at timestamptz;

-- surfaces "decisions this trainee has not seen yet" cheaply
create index if not exists assigned_postpone_unseen_idx
  on public.assigned_workouts (postpone_status)
  where postpone_status in ('approved','rejected') and postpone_seen_at is null;

create or replace function public.ack_postpone(p_assigned uuid)
returns void language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select en.trainee_id into t
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if t is null then raise exception 'workout not found'; end if;
  if t <> auth.uid() then raise exception 'not your workout'; end if;

  update public.assigned_workouts
     set postpone_seen_at = now()
   where id = p_assigned
     and postpone_status in ('approved','rejected')
     and postpone_seen_at is null;
end; $$;

revoke execute on function public.ack_postpone(uuid) from public;
grant  execute on function public.ack_postpone(uuid) to authenticated;

select proname from pg_proc where proname = 'ack_postpone';
