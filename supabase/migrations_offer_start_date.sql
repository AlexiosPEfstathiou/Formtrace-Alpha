-- =====================================================================
-- FormTrace — Item BH (offer card): a real start date on offers.
-- Run in the Supabase SQL editor.
-- Offers stored only a formatted start string (start_text, e.g. "14 Sep
-- 2026"), so the card could not compute the last day. Adds start_date and
-- backfills where the text parses in the "D Mon YYYY" form the app writes.
-- =====================================================================
alter table public.offers add column if not exists start_date date;

update public.offers
   set start_date = to_date(start_text, 'DD Mon YYYY')
 where start_date is null
   and start_text ~ '^\d{1,2} [A-Za-z]{3} \d{4}$';

select 'offers with start_date' as check, count(*) from public.offers where start_date is not null
union all
select 'offers still without (unparsed text)', count(*) from public.offers where start_date is null;
