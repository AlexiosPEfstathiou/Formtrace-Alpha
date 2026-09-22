-- =====================================================================
-- FormTrace — Item CY: Achievements. Run in the Supabase SQL editor.
-- Visible to the owner and to In Touch friends only - never public.
-- =====================================================================
create table if not exists public.achievements (
  code   text primary key,
  family text not null,
  title  text not null,
  blurb  text not null,
  icon   text not null,
  sort   integer not null
);
alter table public.achievements enable row level security;
drop policy if exists "anyone reads the catalogue" on public.achievements;
create policy "anyone reads the catalogue" on public.achievements for select to authenticated using (true);

insert into public.achievements (code, family, title, blurb, icon, sort) values
 ('first_session','Start','First session','Complete your first assigned session','🎬',10),
 ('first_week','Start','First week','Finish every session in a week','📅',20),
 ('first_goal_posted','Start','Goal posted','Post your first goal for coaches','📣',30),
 ('first_review','Start','First review','Receive your first coach review','📝',40),
 ('streak_4','Discipline','4-week streak','Four complete weeks in a row','🔥',110),
 ('streak_12','Discipline','12-week streak','Twelve complete weeks in a row','🔥',120),
 ('streak_26','Discipline','26-week streak','Half a year of complete weeks','🔥',130),
 ('perfect_month','Discipline','Perfect month','Four complete weeks inside one month','🗓',140),
 ('first_pb','Effort','First PB','Set your first personal best','🏆',210),
 ('pb_10','Effort','10 PBs','Personal bests on ten exercises','🏆',220),
 ('pb_50','Effort','50 PBs','Personal bests on fifty exercises','🏆',230),
 ('level_up','Effort','Level up','Your coach moved you up a level','⬆️',240),
 ('first_goal_done','Journey','Goal complete','Complete your first goal','🎯',310),
 ('goals_3','Journey','Three goals','Complete three goals','🎯',320),
 ('checkins_12','Journey','12 check-ins','Twelve weekly check-in photos','📷',330),
 ('macros_30','Journey','30 days logged','Macros logged on thirty days','🍽',340),
 ('first_friend','Social','First friend','Knock phones with someone','🤝',410),
 ('first_clap','Social','First cheer','Congratulate a friend','👏',420)
on conflict (code) do update set title=excluded.title, blurb=excluded.blurb, icon=excluded.icon, sort=excluded.sort, family=excluded.family;

create table if not exists public.user_achievements (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  code      text not null references public.achievements(code) on delete cascade,
  earned_at timestamptz not null default now(),
  seen_at   timestamptz,
  primary key (user_id, code)
);
alter table public.user_achievements enable row level security;
drop policy if exists "own achievements" on public.user_achievements;
create policy "own achievements" on public.user_achievements for select to authenticated using (user_id = auth.uid());
drop policy if exists "friends read achievements" on public.user_achievements;
create policy "friends read achievements" on public.user_achievements for select to authenticated using (public.are_connected(auth.uid(), user_id));
drop policy if exists "owner marks seen" on public.user_achievements;
create policy "owner marks seen" on public.user_achievements for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---- the rule engine: evaluates every rule for one user, inserts what is newly earned ----
create or replace function public.check_achievements(p_user uuid default auth.uid())
returns integer language plpgsql security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid()); n integer := 0; c record;
  streak int; pbs int; goals int; ci int; logs int; goodwk int;
begin
  if u is null then return 0; end if;
  -- checking any user is harmless: it only awards what the data already justifies (triggers run in the caller's request context, so no JWT-based guard here)
  select coalesce(week_streak_count,0) into streak from public.profiles where id = u;
  select count(*) into pbs   from public.personal_bests where trainee_id = u;
  select count(*) into goals from public.engagements where trainee_id = u and status = 'completed';
  select count(*) into ci    from public.checkins where trainee_id = u and photo_path is not null;
  select count(*) into logs  from public.logs where trainee_id = u and (kcal is not null or protein_g is not null);
  select count(*) into goodwk from public.week_closures wc join public.engagements e on e.id = wc.engagement_id
   where e.trainee_id = u and not wc.neutral and wc.assigned_count > 0 and wc.completed_count >= wc.assigned_count
     and wc.week_start >= (date_trunc('week', current_date)::date - 28);

  for c in
    select code from public.achievements a where not exists (select 1 from public.user_achievements ua where ua.user_id = u and ua.code = a.code)
  loop
    if (c.code = 'first_session'     and exists (select 1 from public.assigned_workouts aw join public.engagements e on e.id = aw.engagement_id where e.trainee_id = u and aw.status in ('submitted','reviewed')))
    or (c.code = 'first_week'        and exists (select 1 from public.week_closures wc join public.engagements e on e.id = wc.engagement_id where e.trainee_id = u and not wc.neutral and wc.assigned_count > 0 and wc.completed_count >= wc.assigned_count))
    or (c.code = 'first_goal_posted' and exists (select 1 from public.listings where trainee_id = u))
    or (c.code = 'first_review'      and exists (select 1 from public.reviews r join public.submissions s on s.id = r.submission_id where s.trainee_id = u))
    or (c.code = 'streak_4'  and streak >= 4) or (c.code = 'streak_12' and streak >= 12) or (c.code = 'streak_26' and streak >= 26)
    or (c.code = 'perfect_month' and goodwk >= 4)
    or (c.code = 'first_pb' and pbs >= 1) or (c.code = 'pb_10' and pbs >= 10) or (c.code = 'pb_50' and pbs >= 50)
    or (c.code = 'level_up'          and exists (select 1 from public.engagements where trainee_id = u and coalesce(level,1) >= 2))
    or (c.code = 'first_goal_done' and goals >= 1) or (c.code = 'goals_3' and goals >= 3)
    or (c.code = 'checkins_12' and ci >= 12) or (c.code = 'macros_30' and logs >= 30)
    or (c.code = 'first_friend'      and exists (select 1 from public.connections where status = 'confirmed' and (a = u or b = u)))
    or (c.code = 'first_clap'        and exists (select 1 from public.celebrations where from_user = u))
    then
      insert into public.user_achievements (user_id, code) values (u, c.code) on conflict do nothing;
      n := n + 1;
      if to_regclass('public.push_outbox') is not null then
        insert into public.push_outbox (to_user, kind, title, body, url)
        select u, 'achievement', '🏅 Achievement unlocked', a.icon || ' ' || a.title || ' - ' || a.blurb, '/#notifications' from public.achievements a where a.code = c.code;
      end if;
    end if;
  end loop;
  return n;
end; $$;
revoke execute on function public.check_achievements(uuid) from public;
grant  execute on function public.check_achievements(uuid) to authenticated;

-- ---- triggers for the server-side events; the client calls check_achievements() on sign-in and after its own actions ----
create or replace function public._ach_trainee_of_engagement() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid; begin
  select trainee_id into t from public.engagements where id = coalesce(new.engagement_id, new.id);
  if t is not null then perform public.check_achievements(t); end if; return new; end; $$;
drop trigger if exists ach_on_week_close on public.week_closures;
create trigger ach_on_week_close after insert on public.week_closures for each row execute function public._ach_trainee_of_engagement();
drop trigger if exists ach_on_engagement on public.engagements;
create trigger ach_on_engagement after update of status, level on public.engagements for each row execute function public._ach_trainee_of_engagement();

create or replace function public._ach_on_review() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid; begin select trainee_id into t from public.submissions where id = new.submission_id; if t is not null then perform public.check_achievements(t); end if; return new; end; $$;
drop trigger if exists ach_on_review on public.reviews;
create trigger ach_on_review after insert on public.reviews for each row execute function public._ach_on_review();

create or replace function public._ach_on_connection() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.status = 'confirmed' then perform public.check_achievements(new.a); perform public.check_achievements(new.b); end if; return new; end; $$;
drop trigger if exists ach_on_connection on public.connections;
create trigger ach_on_connection after update of status on public.connections for each row execute function public._ach_on_connection();

-- ---- feed: achievements are the third win type; congratulate_all counts them ----
create or replace function public.in_touch_feed()
returns jsonb language sql stable security definer set search_path = public as $$
  with mine as (
    select case when a = auth.uid() then b else a end as other, coalesce(confirmed_at, created_at) as since
      from public.connections where status='confirmed' and (a = auth.uid() or b = auth.uid())
  ),
  ev as (
    select p.trainee_id as user_id, 'pb' as kind, p.id::text as ref, p.achieved_at as at,
           p.exercise_name || ' ' || case when p.weight_kg is not null then p.weight_kg || ' kg × ' || p.reps else p.reps || ' reps' end as text
      from public.personal_bests p join mine m on m.other = p.trainee_id
     where p.achieved_at > m.since and p.achieved_at > now() - interval '30 days'
    union all
    select e.trainee_id, 'goal', e.id::text, e.completed_at, 'Completed "' || coalesce(e.goal_title,'a goal') || '"'
      from public.engagements e join mine m on m.other = e.trainee_id
     where e.status = 'completed' and e.completed_at > m.since and e.completed_at > now() - interval '30 days'
    union all
    select ua.user_id, 'achievement', ua.code, ua.earned_at, a.icon || ' ' || a.title
      from public.user_achievements ua join public.achievements a on a.code = ua.code join mine m on m.other = ua.user_id
     where ua.earned_at > m.since and ua.earned_at > now() - interval '30 days'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', ev.user_id, 'display_name', pr.display_name, 'avatar_path', pr.avatar_path, 'avatar_initials', pr.avatar_initials,
           'kind', ev.kind, 'ref', ev.ref, 'at', ev.at, 'text', ev.text,
           'congratulated', exists (select 1 from public.celebrations c where c.from_user = auth.uid() and c.to_user = ev.user_id and c.event_kind = ev.kind and c.event_ref = ev.ref)
         ) order by ev.at desc), '[]'::jsonb)
    from ev join public.profiles pr on pr.id = ev.user_id;
$$;

create or replace function public.congratulate_all(p_to uuid, p_text text default 'this week''s progress')
returns integer language plpgsql security definer set search_path = public as $$
declare n integer := 0; r record; wk date := date_trunc('week', current_date)::date;
begin
  if not public.are_connected(auth.uid(), p_to) then raise exception 'you are not connected'; end if;
  for r in
    select 'pb' as kind, p.id::text as ref from public.personal_bests p where p.trainee_id = p_to and p.achieved_at >= wk
    union all
    select 'goal', e.id::text from public.engagements e where e.trainee_id = p_to and e.status='completed' and e.completed_at >= wk
    union all
    select 'achievement', ua.code from public.user_achievements ua where ua.user_id = p_to and ua.earned_at >= wk
  loop
    insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text, seen_at)
    values (auth.uid(), p_to, r.kind, r.ref, '(part of the week''s congratulation)', now())
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text)
  values (auth.uid(), p_to, 'week', wk::text, left(coalesce(p_text,'this week''s progress'), 120))
  on conflict (from_user, to_user, event_kind, event_ref) do update set created_at = now(), seen_at = null, event_text = excluded.event_text;
  return n;
end; $$;

select 'achievements' as check, (select count(*) from public.achievements) as catalogue;
