-- =====================================================================
-- FormTrace — backfill offers.workouts_per_week_cap from sessions_text.
-- Run in the Supabase SQL editor.
--
-- Found via the week model (AT step 3): future weeks showed a single
-- "Session 1 + Assign" slot and no "planned" count for an engagement whose
-- offer was agreed at 3/week. The original offers table stored the weekly
-- number only as free text (sessions_text, written as "3 / week"); when
-- migrations_payment_ledger_v2 added the integer workouts_per_week_cap it
-- never backfilled it, so every offer accepted before that migration has a
-- null cap. That also means the payment ledger's "agreed" denominator was
-- null for those same engagements. Parses the leading integer; leaves
-- anything unparseable (or zero, which the check constraint forbids) alone.
-- =====================================================================
update public.offers
   set workouts_per_week_cap = (regexp_match(sessions_text, '^\s*(\d+)'))[1]::int
 where workouts_per_week_cap is null
   and sessions_text ~ '^\s*\d+'
   and (regexp_match(sessions_text, '^\s*(\d+)'))[1]::int > 0;

select 'offers with a cap'      as check, count(*) from public.offers where workouts_per_week_cap is not null
union all
select 'offers still without',  count(*) from public.offers where workouts_per_week_cap is null;
