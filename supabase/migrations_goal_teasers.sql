-- HX (owner, 2026-11-22): Open goals as a list of teaser bars - photo or initials, "posted x ago", "Total of Y sessions over
-- Z weeks", a category emoji, "New" for the last 12 hours.
-- 1. A goal now says how long and how often: weeks and sessions per week (both optional; the trainee sets them when posting).
-- 2. open_goal_posters(): coaches see who posted an open goal (name and name style, initials, photo path) -
--    profiles stay private otherwise; only trainees with an OPEN goal are returned, only to coaches.
-- 3. The 12 demo goals (HW) get lengths and frequencies. Safe to re-run.
alter table public.listings add column if not exists weeks integer;
alter table public.listings add column if not exists sessions_per_week integer;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'listings_weeks_check') then
    alter table public.listings add constraint listings_weeks_check check (weeks is null or weeks between 1 and 52);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'listings_sessions_check') then
    alter table public.listings add constraint listings_sessions_check check (sessions_per_week is null or sessions_per_week between 1 and 14);
  end if;
end $$;

create or replace function public.open_goal_posters(p_ids uuid[]) returns table (id uuid, display_name text, name_style text, initials text, avatar_path text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name, coalesce(p.name_style, 'first'),   -- the app applies the poster's own name style
         coalesce(nullif(p.avatar_initials, ''), upper(left(coalesce(p.display_name, '?'), 1))),
         p.avatar_path
    from public.profiles p
   where p.id = any(p_ids)
     and exists (select 1 from public.listings l where l.trainee_id = p.id and l.status = 'open')
     and exists (select 1 from public.profiles me where me.id = auth.uid() and me.role = 'coach');
$$;
revoke execute on function public.open_goal_posters(uuid[]) from public, anon, authenticated;
grant  execute on function public.open_goal_posters(uuid[]) to authenticated;

update public.listings l set weeks = v.w, sessions_per_week = v.s
  from (values ('First pull-up by spring', 10, 3), ('Add 5 kg of muscle in 12 weeks', 12, 4), ('Run my first 10K under 60 minutes', 14, 3),
               ('Touch my toes again', 6, 5), ('Lose 8 kg before my wedding', 20, 3), ('Deadlift 1.5x bodyweight', 12, 2),
               ('Pain-free squats after knee rehab', 8, 3), ('Cycle 100 km in one day', 16, 2), ('Build glutes and legs', 10, 3),
               ('Get back under 100 kg', 24, 4), ('First strict handstand push-up', 12, 4), ('Hike Carrauntoohil without stopping', 18, 2)) as v(t, w, s),
       auth.users u
 where l.title = v.t and u.id = l.trainee_id and u.email like 'demo-goal-%@formtrace.invalid' and l.weeks is null;

-- Check: expect  columns 2 | posters_callable true | demo_with_length 12
select
  (select count(*) from information_schema.columns where table_name = 'listings' and column_name in ('weeks', 'sessions_per_week')) as columns,
  has_function_privilege('authenticated', 'public.open_goal_posters(uuid[])', 'execute') as posters_callable,
  (select count(*) from public.listings l join auth.users u on u.id = l.trainee_id where u.email like 'demo-goal-%@formtrace.invalid' and l.weeks is not null) as demo_with_length;
