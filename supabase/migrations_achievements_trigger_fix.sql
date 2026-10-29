-- =====================================================================
-- FormTrace — DQ: achievement triggers blocked every goal status/level change.
-- _ach_trainee_of_engagement read new.engagement_id, which engagements do not have
-- ("record new has no field engagement_id"), so ending/completing a goal and raising a
-- level failed since 2026-09-22. Fix: read the id safely for both tables, and make every
-- achievement / badge trigger catch its own errors - a reward must never block the action.
-- =====================================================================
create or replace function public._ach_trainee_of_engagement() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid; eid uuid;
begin
  begin
    -- week_closures carry engagement_id; engagements are the goal itself
    eid := coalesce((to_jsonb(new)->>'engagement_id')::uuid, case when tg_table_name = 'engagements' then (to_jsonb(new)->>'id')::uuid end);
    select trainee_id into t from public.engagements where id = eid;
    if t is not null then perform public.check_achievements(t); end if;
  exception when others then
    raise warning '_ach_trainee_of_engagement skipped: %', sqlerrm;
  end;
  return new;
end; $$;

create or replace function public._ach_on_review() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  begin
    select trainee_id into t from public.submissions where id = new.submission_id;
    if t is not null then perform public.check_achievements(t); end if;
  exception when others then
    raise warning '_ach_on_review skipped: %', sqlerrm;
  end;
  return new;
end; $$;

create or replace function public._ach_on_connection() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status = 'confirmed' then perform public.check_achievements(new.a); perform public.check_achievements(new.b); end if;
  exception when others then
    raise warning '_ach_on_connection skipped: %', sqlerrm;
  end;
  return new;
end; $$;

create or replace function public._streak_badge_on_profile() returns trigger language plpgsql security definer set search_path = public as $$
declare w int := coalesce(new.week_streak_count,0); lvl int := floor(coalesce(new.week_streak_count,0) / 13.0); prev int;
begin
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
  exception when others then
    raise warning '_streak_badge_on_profile skipped: %', sqlerrm;
  end;
  return new;
end; $$;

-- proof: a no-op status update on one goal must now succeed (rolled back, changes nothing)
do $$ declare e uuid; begin
  select id into e from public.engagements limit 1;
  if e is not null then
    begin
      update public.engagements set status = status where id = e;
      raise exception 'rollback-ok';
    exception when others then
      if sqlerrm <> 'rollback-ok' then raise; end if;
    end;
  end if;
end $$;

select 'goal updates fixed' as check;
