-- =====================================================================
-- FormTrace — FH: the coach's daily checklist (Home) and its Home tab badge.
-- my_tab_badges() gains: counters (counter-offers waiting for this coach), first_calls (active
-- goals started in the last 14 days with no call proposed or booked), macros_missing (active
-- goals without this week's calorie goal) and payouts_ready (Stripe payouts set up). The other
-- counts are unchanged. Run AFTER migrations_social_badge.sql.
-- =====================================================================
create or replace function public.my_tab_badges() returns jsonb
language sql stable security definer set search_path = public as $$
  with wk as (
    select date_trunc('week', now() at time zone coalesce((select tz from public.profiles where id = auth.uid()), 'Europe/Dublin'))::date as mon
  ), seen as (
    select coalesce((select social_seen_at from public.profiles where id = auth.uid()), now()) as at
  ), friends as (
    select case when c.a = auth.uid() then c.b else c.a end as id
      from public.connections c where c.status = 'confirmed' and (c.a = auth.uid() or c.b = auth.uid())
  ), mine as (
    select e.* from public.engagements e where e.coach_id = auth.uid() and e.status = 'active'
  )
  select jsonb_build_object(
    'unpitched', (select count(*) from public.listings l
                   where l.status = 'open' and l.trainee_id <> auth.uid()
                     and not exists (select 1 from public.listing_hides h where h.listing_id = l.id and h.coach_id = auth.uid())
                     and not exists (select 1 from public.offers o where o.listing_id = l.id and o.coach_id = auth.uid())),
    'unseen',    (select count(*) from public.offers o
                   where o.trainee_id = auth.uid() and o.status = 'pending' and o.seen_at is null),
    'to_answer', (select count(*) from public.offers o
                   where o.trainee_id = auth.uid() and o.status = 'pending'),
    'to_assign', (select coalesce(sum(greatest(0, coalesce(o.workouts_per_week_cap, 0)
                                   - (select count(*) from public.assigned_workouts aw where aw.engagement_id = e.id and aw.week_start = (select mon from wk)))), 0)
                    from mine e join public.offers o on o.id = e.offer_id),
    'to_review', (select count(*) from public.assigned_workouts aw join mine e on e.id = aw.engagement_id where aw.status = 'submitted'),
    'social',    (select count(*) from public.connections c
                   where c.status = 'pending'
                     and ((c.a = auth.uid() and not c.a_ok and c.b_ok) or (c.b = auth.uid() and not c.b_ok and c.a_ok)))
               + (select count(*) from public.user_achievements ua
                   where ua.user_id in (select id from friends) and ua.earned_at > (select at from seen))
               + (select count(*) from public.celebrations ce
                   where ce.to_user = auth.uid() and ce.created_at > (select at from seen)),
    'counters',  (select count(*) from public.offers o where o.coach_id = auth.uid() and o.status = 'countered'),
    'first_calls', (select count(*) from mine e
                     where e.started_at >= now() - interval '14 days'
                       and not exists (select 1 from public.call_proposals cp where cp.engagement_id = e.id and cp.status in ('pending','accepted','countered'))),
    'macros_missing', (select count(*) from mine e
                        where not exists (select 1 from public.macro_goals mg where mg.engagement_id = e.id and mg.week_start = (select mon from wk))),
    'payouts_ready', coalesce((select details_submitted and transfers_active from public.coach_stripe_accounts where coach_id = auth.uid()), false)
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

select (public.my_tab_badges() ?& array['counters','first_calls','macros_missing','payouts_ready']) as has_coach_counts;