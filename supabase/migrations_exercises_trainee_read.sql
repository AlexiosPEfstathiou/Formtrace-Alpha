-- =====================================================================
-- FormTrace — trainee read access to a coach's exercise library
--
-- REAL, PRE-EXISTING GAP, not introduced today: found while diagnosing a
-- wildcard-slot bug reported live. The original schema's only policy on
-- exercises is "coach manages own exercises" (for all, using coach_id =
-- auth.uid()) — meaning a TRAINEE has never been able to read a coach's
-- exercises table at all, under any circumstance.
--
-- This never surfaced before because every other place a trainee sees
-- exercise data (ordinary workout items) comes from the assigned
-- workout's SNAPSHOT — a frozen copy taken at assign time, requiring no
-- live read of the exercises table itself. The wildcard-slot feature is
-- the one place that genuinely needs a live read: "show me the coach's
-- CURRENT library for this muscle group," which by design can't be
-- pre-baked into a snapshot. That live read was never granted.
--
-- Confirmed directly before writing this: as the coach,
-- store.exercises.list({coach_id: self}) returns rows. As the trainee,
-- the EXACT same call with the EXACT same (correct) coach_id returns
-- nothing. Same query, same data, different caller — a permissions gap,
-- not a data or key mismatch.
--
-- Additive only: this does not touch "coach manages own exercises" at all
-- (Postgres RLS policies for the same command OR together — a row is
-- visible if EITHER policy allows it). Scoped narrowly: a trainee may
-- read a coach's exercises only while they have an ACTIVE engagement
-- with that specific coach — the same scoping already used for
-- set_labels' "coach reads set labels on their engagements" policy.
-- =====================================================================

drop policy if exists "trainee reads exercises of an active coach" on public.exercises;
create policy "trainee reads exercises of an active coach"
  on public.exercises for select to authenticated
  using (
    exists (
      select 1 from public.engagements e
      where e.coach_id = exercises.coach_id
        and e.trainee_id = auth.uid()
        and e.status = 'active'
    )
  );

select policyname, cmd from pg_policies
where schemaname='public' and tablename='exercises'
order by policyname;
