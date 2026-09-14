-- =====================================================================
-- FormTrace — Item BK: pitches commit to ONE length, so the total commits.
-- Run in the Supabase SQL editor.
--
-- Offers carried their length only as a text RANGE ("4-6 weeks"), which is
-- exactly why no total could be committed at acceptance. Adds a single
-- integer length, backfilled from the range's upper bound, and stamps each
-- engagement with the weeks and end date it was accepted for.
-- Total (a ceiling - only reviewed sessions are ever charged, per item B)
--   = length_weeks x rate_per_workout_cents   (that column holds the WEEKLY
--     price, per migrations_payment_ledger_v2).
-- =====================================================================
alter table public.offers
  add column if not exists length_weeks integer
    check (length_weeks is null or (length_weeks between 1 and 104));

-- backfill: the range's largest number ("4-6 weeks" -> 6, "8 weeks" -> 8)
update public.offers
   set length_weeks = (select max(m[1]::int) from regexp_matches(length_text, '(\d+)', 'g') m)
 where length_weeks is null and length_text ~ '\d';

alter table public.engagements
  add column if not exists committed_weeks    integer,
  add column if not exists committed_end_date date;

-- backfill engagements from their accepted offer
update public.engagements e
   set committed_weeks    = o.length_weeks,
       committed_end_date = (e.started_at at time zone 'UTC')::date + 7 * o.length_weeks
  from public.offers o
 where o.id = e.offer_id and e.committed_weeks is null and o.length_weeks is not null;

select 'offers with length_weeks' as check, count(*) from public.offers where length_weeks is not null
union all
select 'engagements with committed end', count(*) from public.engagements where committed_end_date is not null;
