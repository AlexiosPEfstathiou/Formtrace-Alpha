-- =====================================================================
-- FormTrace — move private fields off the widely-readable profiles table,
--             then narrow who can read a profile at all
-- Run in the Supabase SQL editor.
--
-- WHY
--   RLS controls which ROWS you can read, never which COLUMNS. Coach
--   profiles must stay broadly readable — browsing coaches is the
--   marketplace — so date_of_birth and consent, which were added to
--   profiles, are readable by any signed-in user for any coach and no
--   policy can stop that. They have to live somewhere only the owner
--   can reach.
--
-- REVERSIBILITY
--   This COPIES the columns to profile_private and does NOT drop them
--   from profiles. Once the app is confirmed working against the new
--   table, a later migration can drop the originals.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1 — owner-only table for private fields
-- ---------------------------------------------------------------------
create table if not exists public.profile_private (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  date_of_birth   date,
  consent_version text,
  consented_at    timestamptz,
  updated_at      timestamptz not null default now()
);

alter table public.profile_private enable row level security;

drop policy if exists "own private profile" on public.profile_private;
create policy "own private profile"
  on public.profile_private for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- same 18+ guarantee as before
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profile_private_min_age_chk') then
    alter table public.profile_private
      add constraint profile_private_min_age_chk
      check (date_of_birth is null or date_of_birth <= (current_date - interval '18 years'));
  end if;
end $$;

-- carry across anything already recorded (safe to re-run)
insert into public.profile_private (user_id, date_of_birth, consent_version, consented_at)
select p.id, p.date_of_birth, p.consent_version, p.consented_at
from public.profiles p
where (p.date_of_birth is not null or p.consented_at is not null)
on conflict (user_id) do update
  set date_of_birth   = coalesce(excluded.date_of_birth,   public.profile_private.date_of_birth),
      consent_version = coalesce(excluded.consent_version, public.profile_private.consent_version),
      consented_at    = coalesce(excluded.consented_at,    public.profile_private.consented_at);

-- ---------------------------------------------------------------------
-- PART 2 — admin check that does not recurse
--   A policy ON profiles cannot sub-select FROM profiles: Postgres would
--   re-evaluate the policy and error with infinite recursion. A
--   SECURITY DEFINER function bypasses RLS and breaks the loop.
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

revoke execute on function public.is_admin() from public;
grant  execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- PART 3 — narrow profile reads
--   Coaches stay public because a coach profile IS a service listing.
--   Trainees become visible only to themselves, their coaches, admins,
--   and anyone at all if they opted into the community feed.
-- ---------------------------------------------------------------------
drop policy if exists "profiles readable by authenticated" on public.profiles;
drop policy if exists "ft profiles scoped read" on public.profiles;
create policy "ft profiles scoped read"
  on public.profiles for select to authenticated
  using (
    id = auth.uid()                       -- yourself
    or role = 'coach'                     -- coaches are browsable by design
    or coalesce(social_enabled, false)    -- opted into the community
    or public.is_admin()                  -- admin review screens
    or exists (                           -- the other party in a goal
      select 1 from public.engagements e
      where (e.coach_id = auth.uid() and e.trainee_id = profiles.id)
         or (e.trainee_id = auth.uid() and e.coach_id = profiles.id)
    )
  );

-- ---------------------------------------------------------------------
-- VERIFY
-- ---------------------------------------------------------------------
select policyname, cmd from pg_policies
where schemaname='public' and tablename='profiles' order by cmd, policyname;

select count(*) as private_rows_migrated from public.profile_private;
