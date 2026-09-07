-- =====================================================================
-- FormTrace — Item BA: Open goals hygiene (coach side).
-- Run in the Supabase SQL editor.
--
-- 1. listing_hides: a coach can hide an open goal so it stops reappearing.
--    Per coach, per listing; visible to nobody else; the trainee's goal is
--    untouched.
-- 2. expire_listings(): a goal posting expires 7 days after it was posted.
--    It is closed with closed_reason='expired', and every still-pending
--    offer on it becomes 'expired' - which is what moves a coach's stale
--    "Pitched" into their Not selected outcomes. Called by the client when
--    the Open goals tab or the trainee's goals screen loads (same
--    no-scheduler pattern as close_weeks_due). Idempotent.
-- =====================================================================

-- ---------- 1. hides ----------
create table if not exists public.listing_hides (
  coach_id   uuid not null references public.profiles(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (coach_id, listing_id)
);
alter table public.listing_hides enable row level security;
drop policy if exists "coach manages own hides" on public.listing_hides;
create policy "coach manages own hides" on public.listing_hides
  for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());

-- ---------- 2. expiry ----------
alter table public.listings drop constraint if exists listings_closed_reason_chk;
alter table public.listings add constraint listings_closed_reason_chk
  check (closed_reason is null or closed_reason in ('matched','cancelled','expired'));

create or replace function public.expire_listings()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n_listings integer; n_offers integer;
begin
  with x as (
    update public.listings
       set status = 'closed', closed_reason = 'expired'
     where status = 'open'
       and created_at < now() - interval '7 days'
    returning id
  ), y as (
    update public.offers o
       set status = 'expired'
      from x
     where o.listing_id = x.id and o.status = 'pending'
    returning o.id
  )
  select (select count(*) from x), (select count(*) from y) into n_listings, n_offers;
  return jsonb_build_object('listings_expired', n_listings, 'offers_expired', n_offers);
end;
$$;
revoke execute on function public.expire_listings() from public;
grant execute on function public.expire_listings() to authenticated;

-- run once now, and report
select public.expire_listings() as expired_now;
