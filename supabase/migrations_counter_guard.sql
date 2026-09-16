-- =====================================================================
-- FormTrace — Item CK: counter-offer safeguards and timers.
-- Run in the Supabase SQL editor (after migrations_counter_offers.sql).
--
-- Rules (decided 2026-09-16):
--  * A goal can have ONE accepted offer, enforced in the database.
--  * While an offer on a goal is COUNTERED (waiting for the coach), or is a
--    FOLLOW-UP (coach has answered, trainee has not yet decided, within the
--    decision window), NO offer on that goal can be accepted - the trainee
--    must address the follow-up first. Enforced in the database; the app
--    shows the hold and the timers.
--  * Timers: the coach has 48 h to answer a counter; unanswered, the
--    original terms stand ('kept', timed out). The trainee then has 48 h to
--    decide on the follow-up; after that the hold lifts on its own.
-- =====================================================================
create or replace function public.offer_hold_reason(p_listing uuid, p_except uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from public.offers o where o.listing_id = p_listing and o.id <> p_except and o.status = 'accepted')
      then 'this goal already has an accepted offer'
    when exists (select 1 from public.offers o where o.listing_id = p_listing and o.id <> p_except and o.status = 'countered')
      then 'a proposed change on another offer is waiting for the coach'
    when exists (select 1 from public.offers o where o.listing_id = p_listing and o.id <> p_except and o.status = 'pending'
                   and o.counter_outcome is not null and o.counter_resolved_at > now() - interval '48 hours')
      then 'decide on the offer your coach answered first'
    else null end
  where p_listing is not null;
$$;

create or replace function public.offers_guard_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_reason text;
begin
  if new.status = 'accepted' and (old.status is distinct from 'accepted') then
    if new.listing_id is not null then
      v_reason := public.offer_hold_reason(new.listing_id, new.id);
      if v_reason is not null then raise exception 'cannot accept: %', v_reason; end if;
    end if;
    -- a countered offer itself can never be accepted until the coach answers
    if old.status = 'countered' then raise exception 'cannot accept: your proposed change is still waiting for the coach'; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists offers_guard_accept on public.offers;
create trigger offers_guard_accept before update on public.offers
  for each row execute function public.offers_guard_accept();

-- coach's 48 h to answer: unanswered counters resolve as 'kept' (timed out)
create or replace function public.expire_counters()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  update public.offers
     set status = 'pending', counter_outcome = 'kept',
         counter_reply = coalesce(counter_reply, 'No reply within 48 hours - the original terms stand'),
         counter_resolved_at = now()
   where status = 'countered' and counter_at < now() - interval '48 hours';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.expire_counters() from public;
grant  execute on function public.expire_counters() to authenticated;
grant  execute on function public.offer_hold_reason(uuid, uuid) to authenticated;

select 'guard trigger' as check, count(*) from pg_trigger where tgname = 'offers_guard_accept';
