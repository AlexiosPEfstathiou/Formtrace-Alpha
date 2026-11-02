-- =====================================================================
-- FormTrace — FH refinement (owner, 2026-11-02): weekly calls, and "take me to the next one".
-- (1) first_calls becomes weekly_calls: active goals with no call proposed or booked THIS
--     week (any trainee, not only new ones); the Home badge counts one per trainee.
-- (2) coach_todo_targets(): for review / assign / calls / macros, the goals that still need it,
--     in the order the coach should be taken to them (reviews: oldest submission first;
--     the rest: by start date). The checklist opens the first; the item is crossed off only
--     when the list is empty.
-- =====================================================================
create or replace function public.coach_todo_targets() returns jsonb
language sql stable security definer set search_path = public as $$
  with wk as (
    select date_trunc('week', now() at time zone coalesce((select tz from public.profiles where id = auth.uid()), 'Europe/Dublin'))::date as mon
  ), mine as (
    select e.id, e.offer_id, e.started_at from public.engagements e where e.coach_id = auth.uid() and e.status = 'active'
  )
  select jsonb_build_object(
    'review', coalesce((select jsonb_agg(id order by first_sub) from (
                 select e.id, min(s.created_at) as first_sub from mine e
                   join public.assigned_workouts aw on aw.engagement_id = e.id and aw.status = 'submitted'
                   left join public.submissions s on s.assigned_id = aw.id
                  group by e.id) x), '[]'::jsonb),
    'assign', coalesce((select jsonb_agg(e.id order by e.started_at) from mine e join public.offers o on o.id = e.offer_id
                  where coalesce(o.workouts_per_week_cap, 0) > (select count(*) from public.assigned_workouts aw where aw.engagement_id = e.id and aw.week_start = (select mon from wk))), '[]'::jsonb),
    'calls',  coalesce((select jsonb_agg(e.id order by e.started_at) from mine e
                  where not exists (select 1 from public.call_proposals cp where cp.engagement_id = e.id and cp.status in ('pending','accepted','countered')
                                      and cp.proposed_date between (select mon from wk) and (select mon from wk) + 6)), '[]'::jsonb),
    'macros', coalesce((select jsonb_agg(e.id order by e.started_at) from mine e
                  where not exists (select 1 from public.macro_goals mg where mg.engagement_id = e.id and mg.week_start = (select mon from wk))), '[]'::jsonb)
  );
$$;
revoke execute on function public.coach_todo_targets() from public;
grant  execute on function public.coach_todo_targets() to authenticated;
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
    'weekly_calls', (select count(*) from mine e
                      where not exists (select 1 from public.call_proposals cp where cp.engagement_id = e.id and cp.status in ('pending','accepted','countered')
                                          and cp.proposed_date between (select mon from wk) and (select mon from wk) + 6)),
    'macros_missing', (select count(*) from mine e
                        where not exists (select 1 from public.macro_goals mg where mg.engagement_id = e.id and mg.week_start = (select mon from wk))),
    'payouts_ready', coalesce((select details_submitted and transfers_active from public.coach_stripe_accounts where coach_id = auth.uid()), false)
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

select (public.my_tab_badges() ? 'weekly_calls') as has_weekly_calls, (public.coach_todo_targets() ?& array['review','assign','calls','macros']) as has_targets;
