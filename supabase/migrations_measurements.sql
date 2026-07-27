-- =====================================================================
-- FormTrace — quarterly body measurements
-- Run this WHOLE file in the Supabase SQL editor (SQL Editor > New query).
--
-- If you previously only ran "select count(*) from public.measurements"
-- that was a VERIFICATION query and it fails until this file has run.
--
-- One row per trainee per measurement date, in centimetres. The app
-- prompts at the start of each calendar quarter (Jan/Apr/Jul/Oct) and
-- charts each circumference over time on the dashboard.
-- =====================================================================

create table if not exists public.measurements (
  id          uuid primary key default gen_random_uuid(),
  trainee_id  uuid not null references public.profiles(id) on delete cascade,
  measured_on date not null,
  neck_cm     numeric,
  chest_cm    numeric,
  biceps_cm   numeric,
  waist_cm    numeric,
  hips_cm     numeric,
  thighs_cm   numeric,
  created_at  timestamptz not null default now(),
  unique (trainee_id, measured_on)
);

-- Safe to re-run: if the table was created from an earlier five-column version
-- of this file, this adds the missing neck column instead of failing.
alter table public.measurements add column if not exists neck_cm   numeric;
alter table public.measurements add column if not exists chest_cm  numeric;
alter table public.measurements add column if not exists biceps_cm numeric;
alter table public.measurements add column if not exists waist_cm  numeric;
alter table public.measurements add column if not exists hips_cm   numeric;
alter table public.measurements add column if not exists thighs_cm numeric;

alter table public.measurements enable row level security;

-- trainee owns their own measurements
drop policy if exists "trainee manages own measurements" on public.measurements;
create policy "trainee manages own measurements"
  on public.measurements for all to authenticated
  using (trainee_id = auth.uid())
  with check (trainee_id = auth.uid());

-- their coaches may read them. NOTE: unlike the logs policy this is NOT
-- limited to status='active', because the dashboard (and its charts) stays
-- viewable for completed and cancelled goals too.
drop policy if exists "coach reads trainee measurements" on public.measurements;
create policy "coach reads trainee measurements"
  on public.measurements for select to authenticated
  using (exists (
    select 1 from public.engagements e
    where e.trainee_id = measurements.trainee_id
      and e.coach_id = auth.uid()
  ));

create index if not exists measurements_trainee_idx on public.measurements(trainee_id, measured_on);

-- verify AFTER running the above; should return 0
-- select count(*) from public.measurements;
