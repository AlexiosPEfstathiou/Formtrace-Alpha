-- =====================================================================
-- FormTrace — Item BW: the Consistency badge. One badge per trainee that levels up every
-- 3 months (13 weeks) of complete weeks; the highest level reached is kept. Friends-only.
-- =====================================================================
create table if not exists public.streak_badges (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  level      integer not null default 0,
  best_weeks integer not null default 0,
  reached_at timestamptz,
  seen_level integer not null default 0
);
alter table public.streak_badges enable row level security;
drop policy if exists "own streak badge" on public.streak_badges;
create policy "own streak badge" on public.streak_badges for select to authenticated using (user_id = auth.uid());
drop policy if exists "friends read streak badge" on public.streak_badges;
create policy "friends read streak badge" on public.streak_badges for select to authenticated using (public.are_connected(auth.uid(), user_id));

-- the owner marks a level as seen (the unlock animation played)
create or replace function public.mark_streak_badge_seen()
returns void language sql security definer set search_path = public as $$
  update public.streak_badges set seen_level = level where user_id = auth.uid();
$$;
revoke execute on function public.mark_streak_badge_seen() from public;
grant  execute on function public.mark_streak_badge_seen() to authenticated;

-- level = floor(streak weeks / 13), never decreasing
create or replace function public._streak_badge_on_profile() returns trigger language plpgsql security definer set search_path = public as $$
declare w int := coalesce(new.week_streak_count,0); lvl int := floor(coalesce(new.week_streak_count,0) / 13.0); prev int;
begin
  if tg_op = 'UPDATE' and w = coalesce(old.week_streak_count,0) then return new; end if;
  select level into prev from public.streak_badges where user_id = new.id;
  insert into public.streak_badges (user_id, level, best_weeks, reached_at)
  values (new.id, lvl, w, case when lvl > 0 then now() end)
  on conflict (user_id) do update
     set best_weeks = greatest(public.streak_badges.best_weeks, excluded.best_weeks),
         level      = greatest(public.streak_badges.level, excluded.level),
         reached_at = case when excluded.level > public.streak_badges.level then now() else public.streak_badges.reached_at end;
  if lvl > coalesce(prev,0) and to_regclass('public.push_outbox') is not null then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.id, 'achievement', 'Consistency badge levelled up',
            case lvl when 1 then 'Bronze' when 2 then 'Silver' when 3 then 'Gold' when 4 then 'Platinum' else 'Diamond' end
            || ' - ' || (lvl * 3) || ' months of complete weeks', '/#profile');
  end if;
  return new;
end; $$;
drop trigger if exists streak_badge_on_profile on public.profiles;
create trigger streak_badge_on_profile after insert or update of week_streak_count on public.profiles
  for each row execute function public._streak_badge_on_profile();

-- backfill from today's streaks, marked as seen (no animation flood)
insert into public.streak_badges (user_id, level, best_weeks, reached_at, seen_level)
select id, floor(coalesce(week_streak_count,0) / 13.0), coalesce(week_streak_count,0),
       case when coalesce(week_streak_count,0) >= 13 then now() end, floor(coalesce(week_streak_count,0) / 13.0)
  from public.profiles where coalesce(role,'trainee') = 'trainee'
on conflict (user_id) do nothing;

select count(*) as trainees, max(level) as top_level from public.streak_badges;
