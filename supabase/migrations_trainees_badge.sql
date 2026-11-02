-- =====================================================================
-- FormTrace — FD: the coach's Trainees tab badge = sessions still to assign this week
-- (agreed sessions per week on the offer, minus sessions assigned this week, per active goal)
-- + sessions submitted and waiting for review. Adds to_assign / to_review to my_tab_badges();
-- the rest unchanged. The week is the coach's own (profiles.tz, Ireland by default).
-- =====================================================================
create or replace function public.my_tab_badges() returns jsonb
language sql stable security definer set search_path = public as $$
  with wk as (
    select date_trunc('week', now() at time zone coalesce((select tz from public.profiles where id = auth.uid()), 'Europe/Dublin'))::date as mon
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
                    from public.engagements e join public.offers o on o.id = e.offer_id
                   where e.coach_id = auth.uid() and e.status = 'active'),
    'to_review', (select count(*) from public.assigned_workouts aw join public.engagements e on e.id = aw.engagement_id
                   where e.coach_id = auth.uid() and e.status = 'active' and aw.status = 'submitted')
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

select (public.my_tab_badges() ? 'to_assign') and (public.my_tab_badges() ? 'to_review') as has_new_counts;