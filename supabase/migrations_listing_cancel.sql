-- =====================================================================
-- FormTrace — let a trainee cancel a posted goal (before it's accepted)
-- Run in the Supabase SQL editor.
--
-- listings.status only allows 'open' | 'matched' | 'closed'. A trainee
-- cancelling their own goal uses 'closed', same as when a goal is
-- accepted — 'closed' means "no longer accepting offers" either way. A
-- separate reason column distinguishes them so the trainee's own listing
-- screen isn't stuck saying "closed" for a goal they walked away from
-- versus one that actually matched with a coach.
-- =====================================================================

alter table public.listings
  add column if not exists closed_reason text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='listings_closed_reason_chk') then
    alter table public.listings add constraint listings_closed_reason_chk
      check (closed_reason is null or closed_reason in ('matched','cancelled'));
  end if;
end $$;

select status, closed_reason, count(*) from public.listings group by 1,2 order by 1,2;
