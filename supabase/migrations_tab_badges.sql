-- =====================================================================
-- FormTrace — Item EQ: tab badges.
-- Coach: "Open goals" shows how many open goals this coach has neither pitched nor hidden.
-- Trainee: "Goal" shows how many pitches they have not seen yet (marked seen when they
-- open the Goal tab). Updating seen_at is safe: the offers triggers (push_on_offer,
-- offers_guard_accept) act only on a change of status.
-- =====================================================================
alter table public.offers add column if not exists seen_at timestamptz;

create or replace function public.my_tab_badges() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'unpitched', (select count(*) from public.listings l
                   where l.status = 'open' and l.trainee_id <> auth.uid()
                     and not exists (select 1 from public.listing_hides h where h.listing_id = l.id and h.coach_id = auth.uid())
                     and not exists (select 1 from public.offers o where o.listing_id = l.id and o.coach_id = auth.uid())),
    'unseen',    (select count(*) from public.offers o
                   where o.trainee_id = auth.uid() and o.status = 'pending' and o.seen_at is null)
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

create or replace function public.mark_my_offers_seen() returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.offers set seen_at = now()
   where trainee_id = auth.uid() and seen_at is null and status in ('pending','countered');
  get diagnostics n = row_count;
  return n;
end; $$;
revoke execute on function public.mark_my_offers_seen() from public;
grant  execute on function public.mark_my_offers_seen() to authenticated;

-- pitches made before today count as seen (no sudden badge for old offers)
update public.offers set seen_at = coalesce(seen_at, now()) where status in ('pending','countered');

select (select count(*) from information_schema.columns where table_schema='public' and table_name='offers' and column_name='seen_at') as seen_column,
       (select count(*) from pg_proc where proname in ('my_tab_badges','mark_my_offers_seen')) as functions;
