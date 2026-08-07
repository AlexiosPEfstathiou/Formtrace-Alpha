-- =====================================================================
-- FormTrace — enforce postpone approval in the database
-- Run in the Supabase SQL editor.
--
-- WHY
--   Trainees need UPDATE on their own assigned_workouts (that is how
--   submitting and draft-saving work), and RLS is row-level, so nothing
--   stopped a trainee writing postpone_status='approved' — or simply
--   setting due_date themselves and skipping the request entirely. The
--   approval flow was enforced only by the UI.
--
-- HOW
--   Column-level privileges: revoke blanket UPDATE and grant it back for
--   only the columns a client may legitimately write. Scheduling columns
--   then move exclusively through SECURITY DEFINER functions that check
--   who is asking.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1 — who may write what, column by column
--   Granted: status, draft, opened  (submitting, progress, read receipts)
--   Withheld: due_date and all postpone_* — scheduling is a negotiation
-- ---------------------------------------------------------------------
revoke update on public.assigned_workouts from authenticated;
grant  update (status, draft, opened) on public.assigned_workouts to authenticated;

-- ---------------------------------------------------------------------
-- PART 2 — trainee asks
-- ---------------------------------------------------------------------
create or replace function public.request_postpone(p_assigned uuid, p_date date, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare e record;
begin
  select aw.id, aw.status, aw.due_date, en.trainee_id
    into e
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if e.id is null then raise exception 'workout not found'; end if;
  if e.trainee_id <> auth.uid() then raise exception 'not your workout'; end if;
  if e.status <> 'assigned' then raise exception 'only a pending workout can be moved'; end if;
  if p_date is null or p_date < current_date then raise exception 'pick a future date'; end if;
  if p_date = e.due_date then raise exception 'that is already the scheduled day'; end if;

  update public.assigned_workouts
     set postpone_to = p_date, postpone_status = 'pending',
         postpone_note = nullif(btrim(coalesce(p_note,'')),''), postpone_at = now()
   where id = p_assigned;
end; $$;

-- ---------------------------------------------------------------------
-- PART 3 — trainee withdraws their own request
-- ---------------------------------------------------------------------
create or replace function public.cancel_postpone(p_assigned uuid)
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
     set postpone_to = null, postpone_status = null, postpone_note = null, postpone_at = null
   where id = p_assigned and postpone_status = 'pending';
end; $$;

-- ---------------------------------------------------------------------
-- PART 4 — coach decides. Approving is the ONLY path that moves due_date
--          off the back of a request.
-- ---------------------------------------------------------------------
create or replace function public.decide_postpone(p_assigned uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare e record;
begin
  select aw.id, aw.postpone_status, aw.postpone_to, en.coach_id
    into e
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if e.id is null then raise exception 'workout not found'; end if;
  if e.coach_id <> auth.uid() then raise exception 'not your trainee'; end if;
  if e.postpone_status <> 'pending' then raise exception 'no pending request'; end if;

  if p_approve then
    update public.assigned_workouts
       set due_date = e.postpone_to, postpone_status = 'approved'
     where id = p_assigned;
  else
    update public.assigned_workouts
       set postpone_status = 'rejected'
     where id = p_assigned;
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- PART 5 — coach reschedules directly (the modify sheet)
-- ---------------------------------------------------------------------
create or replace function public.set_due_date(p_assigned uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare c uuid; s text;
begin
  select en.coach_id, aw.status into c, s
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if c is null then raise exception 'workout not found'; end if;
  if c <> auth.uid() then raise exception 'not your trainee'; end if;
  if s <> 'assigned' then raise exception 'that workout has already been submitted'; end if;
  if p_date is null then raise exception 'pick a date'; end if;

  update public.assigned_workouts set due_date = p_date where id = p_assigned;
end; $$;

-- ---------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['request_postpone(uuid,date,text)','cancel_postpone(uuid)',
                           'decide_postpone(uuid,boolean)','set_due_date(uuid,date)']
  loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- verify
select proname from pg_proc
where proname in ('request_postpone','cancel_postpone','decide_postpone','set_due_date')
order by proname;
