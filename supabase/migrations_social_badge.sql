-- =====================================================================
-- FormTrace — FG: the Social tab badge = friend requests waiting for MY yes (until answered)
-- + friends' achievements earned since I last opened Social + congratulations received since
-- then. Opening Social marks it seen (mark_social_seen). Everyone starts "seen now", so no
-- sudden big badge. Adds 'social' to my_tab_badges(); the other counts unchanged.
-- =====================================================================
alter table public.profiles add column if not exists social_seen_at timestamptz;
update public.profiles set social_seen_at = now() where social_seen_at is null;

create or replace function public.mark_social_seen() returns void
language sql security definer set search_path = public as $$
  update public.profiles set social_seen_at = now() where id = auth.uid();
$$;
revoke execute on function public.mark_social_seen() from public;
grant  execute on function public.mark_social_seen() to authenticated;

create or replace function public.my_tab_badges() returns jsonb
language sql stable security definer set search_path = public as $$
  with wk as (
    select date_trunc('week', now() at time zone coalesce((select tz from public.profiles where id = auth.uid()), 'Europe/Dublin'))::date as mon
  ), seen as (
    select coalesce((select social_seen_at from public.profiles where id = auth.uid()), now()) as at
  ), friends as (
    select case when c.a = auth.uid() then c.b else c.a end as id
      from public.connections c where c.status = 'confirmed' and (c.a = auth.uid() or c.b = auth.uid())
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
                   where e.coach_id = auth.uid() and e.status = 'active' and aw.status = 'submitted'),
    'social',    (select count(*) from public.connections c
                   where c.status = 'pending'
                     and ((c.a = auth.uid() and not c.a_ok and c.b_ok) or (c.b = auth.uid() and not c.b_ok and c.a_ok)))
               + (select count(*) from public.user_achievements ua
                   where ua.user_id in (select id from friends) and ua.earned_at > (select at from seen))
               + (select count(*) from public.celebrations ce
                   where ce.to_user = auth.uid() and ce.created_at > (select at from seen))
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

select (public.my_tab_badges() ? 'social') as has_social,
       (select count(*) from public.profiles where social_seen_at is null) as profiles_unset;