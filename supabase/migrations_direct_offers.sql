-- =====================================================================
-- FormTrace — Item CD: direct offers to past trainees.
-- Run in the Supabase SQL editor.
-- An offer with listing_id NULL and kind 'renewal' is a coach proposing
-- the next goal directly to someone they have coached before. The insert
-- policy is tightened so that is the ONLY case a coach may create an offer
-- without an open goal - never a cold offer to a stranger.
-- =====================================================================
drop policy if exists "coach creates offers" on public.offers;
create policy "coach creates offers" on public.offers
  for insert to authenticated
  with check (
    coach_id = auth.uid()
    and (
      listing_id is not null
      or exists (select 1 from public.engagements e where e.coach_id = auth.uid() and e.trainee_id = offers.trainee_id)
    )
  );

select 'offers insert policy' as check, count(*) from pg_policies where tablename='offers' and policyname='coach creates offers';
