-- =====================================================================
-- FormTrace — trainee requests to postpone a workout
-- Run this in the Supabase SQL editor.
--
-- A workout has at most one open request at a time, so this lives on
-- assigned_workouts rather than in a separate table. The trainee already
-- has UPDATE on their own assigned workouts (that is how submitting
-- works), and the coach has UPDATE on theirs, so no new policies.
-- =====================================================================

alter table public.assigned_workouts
  add column if not exists postpone_to     date,
  add column if not exists postpone_status text,
  add column if not exists postpone_note   text,
  add column if not exists postpone_at     timestamptz;

-- keep the status values honest
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'assigned_workouts_postpone_status_chk'
  ) then
    alter table public.assigned_workouts
      add constraint assigned_workouts_postpone_status_chk
      check (postpone_status is null or postpone_status in ('pending','approved','rejected'));
  end if;
end $$;

-- coaches list pending requests across their engagements
create index if not exists assigned_postpone_idx
  on public.assigned_workouts (postpone_status)
  where postpone_status = 'pending';

-- NOTE (alpha): approval is enforced in the client, not the database. A
-- trainee could technically write postpone_status='approved' themselves via
-- the API. Locking that down needs a SECURITY DEFINER function or
-- column-level grants — worth doing before real users.
