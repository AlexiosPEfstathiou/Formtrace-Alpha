-- HK (owner, 2026-11-21): weekly quests for trainees and coaches, and coach points for real actions.
-- Week = Monday 00:00 to Sunday in the user's time zone. weekly_quests_sync() works out every quest for the caller from
-- data already in the database, pays any quest that is complete and not yet paid (one points row per quest per week -
-- unique ref), and returns the list for the Home card. Points (owner, confirmed 2026-11-21):
--   trainee  50: all workouts done, calorie goal +-10% (5+ days logged), keep your streak
--            30: macros 5 days, weigh in 5 days, Personal Bests 3 (was 10 - GZ's step now pays 30 too)
--            20: weekly check-in photo, attend a coach call (arranged call whose time has passed), make a friend
--   coach    50: every session submitted this week reviewed within 24 h; 30: a call this week with every trainee;
--            30: next week's sessions assigned for every trainee; 10 per trainee whose week is on track (streak kept)
-- Coach actions (triggers, each catches its own errors - rule 7; one row per object - unique ref):
--   review a session 5 · assign a session 2 · answer a counter-offer 3 · a call accepted 3 · set calorie goals 2 ·
--   Stripe payouts ready 20 (once) · open Open goals 1 (once a day). Safe to re-run.

-- 0. the PB quest pays 30 (owner, HK)
do $$
declare src text;
begin
  src := pg_get_functiondef('public._pb_quest_step(uuid, text, integer, numeric, boolean)'::regprocedure);
  if position('v_pts int := 10' in src) > 0 then execute replace(src, 'v_pts int := 10', 'v_pts int := 30'); end if;
end $$;

-- 1. does a (possibly repeating) accepted call fall between two dates?
create or replace function public._call_occurs(p_date date, p_every integer, d1 date, d2 date) returns boolean
language sql immutable as $$
  select case
    when p_date is null or d2 < d1 or d2 < p_date then false
    when p_every is null or p_every < 1 then p_date between d1 and d2
    else exists (select 1 from generate_series(0, (d2 - p_date) / p_every) k where p_date + k * p_every between d1 and d2)
  end
$$;
revoke execute on function public._call_occurs(date, integer, date, date) from public, anon, authenticated;

-- 2. one points row (side effect - never blocks the action)
create or replace function public._award_points(p_user uuid, p_pts integer, p_reason text, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or coalesce(p_pts, 0) <= 0 then return false; end if;
  insert into public.points_ledger (user_id, amount, reason, ref) values (p_user, p_pts, p_reason, p_ref) on conflict (ref) do nothing;
  return found;
exception when others then
  raise warning 'points skipped (%): %', p_ref, sqlerrm; return false;
end $$;
revoke execute on function public._award_points(uuid, integer, text, text) from public, anon, authenticated;

-- 3. the weekly quests
create or replace function public.weekly_quests_sync() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); v_tz text; v_role text; v_local timestamp; v_today date; ws date; we date;
  q jsonb := '[]'::jsonb; out jsonb := '[]'::jsonb; x jsonb; v_ref text; v_paid boolean; v_just boolean; v_bal bigint;
  a_tot int; a_done int; n int; plan int; days int; avgk numeric; e record; ok int; tot int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(nullif(tz, ''), 'Europe/Dublin'), role into v_tz, v_role from public.profiles where id = uid;
  v_local := now() at time zone coalesce(v_tz, 'Europe/Dublin'); v_today := v_local::date;
  ws := date_trunc('week', v_local)::date; we := ws + 6;

  if v_role = 'coach' then
    -- reviewed within 24 h
    select count(*), count(*) filter (where exists (select 1 from public.reviews r where r.submission_id = s.id and r.withdrawn_at is null
                                                     and coalesce(r.sent_at, r.created_at) <= s.created_at + interval '24 hours'))
      into tot, ok
      from public.submissions s join public.assigned_workouts a on a.id = s.assigned_id join public.engagements en on en.id = a.engagement_id
     where en.coach_id = uid and (s.created_at at time zone coalesce(v_tz, 'Europe/Dublin'))::date between ws and we;
    q := q || jsonb_build_object('key','review24','name','Review every session within 24 hours','progress',ok,'goal',tot,'points',50,
                                 'done', tot > 0 and ok = tot, 'note', case when tot = 0 then 'No sessions submitted yet this week' end);
    select count(*) into tot from public.engagements where coach_id = uid and status = 'active';
    select count(*) into ok from public.engagements en where en.coach_id = uid and en.status = 'active'
       and exists (select 1 from public.call_proposals c where c.engagement_id = en.id and c.status = 'accepted' and public._call_occurs(c.proposed_date, c.recur_every_days, ws, we));
    q := q || jsonb_build_object('key','calls_all','name','A call this week with every trainee','progress',ok,'goal',tot,'points',30,'done', tot > 0 and ok = tot);
    select count(*) into ok from public.engagements en where en.coach_id = uid and en.status = 'active'
       and exists (select 1 from public.assigned_workouts a where a.engagement_id = en.id and coalesce(a.week_start, date_trunc('week', a.due_date)::date) = ws + 7);
    q := q || jsonb_build_object('key','assign_all','name','Next week''s sessions assigned for every trainee','progress',ok,'goal',tot,'points',30,'done', tot > 0 and ok = tot);
    -- trainees on track: 10 each, paid per trainee
    ok := 0;
    for e in select en.trainee_id from public.engagements en where en.coach_id = uid and en.status = 'active' loop
      select count(*), count(*) filter (where a.status in ('submitted', 'reviewed')) into a_tot, a_done
        from public.assigned_workouts a join public.engagements x2 on x2.id = a.engagement_id
       where x2.trainee_id = e.trainee_id and x2.status = 'active' and coalesce(a.week_start, date_trunc('week', a.due_date)::date) = ws;
      if a_tot > 0 and a_done >= a_tot then
        ok := ok + 1;
        perform public._award_points(uid, 10, 'Weekly quest: a trainee kept their streak', 'quest:coachstreak:' || uid || ':' || e.trainee_id || ':' || ws);
      end if;
    end loop;
    out := out || jsonb_build_object('key','streaks','name','Trainees who kept their streak','progress',ok,'goal',tot,'points',10,'each',true,
                                     'done', tot > 0 and ok = tot, 'paid', ok > 0, 'just_paid', false);
  else
    select count(*), count(*) filter (where a.status in ('submitted', 'reviewed')) into a_tot, a_done
      from public.assigned_workouts a join public.engagements en on en.id = a.engagement_id
     where en.trainee_id = uid and en.status = 'active' and coalesce(a.week_start, date_trunc('week', a.due_date)::date) = ws;
    q := q || jsonb_build_object('key','workouts','name','Do every workout this week','progress',a_done,'goal',a_tot,'points',50,'done', a_tot > 0 and a_done >= a_tot,
                                 'note', case when a_tot = 0 then 'No workouts assigned this week' end);
    q := q || jsonb_build_object('key','streak','name','Keep your streak','progress',a_done,'goal',a_tot,'points',50,'done', a_tot > 0 and a_done >= a_tot,
                                 'note', case when coalesce((select week_streak_count from public.profiles where id = uid), 0) > 0
                                              then (select week_streak_count from public.profiles where id = uid) || '-week streak' else 'Start a streak' end);
    select count(*) into n from public.pb_events where trainee_id = uid and week_start = ws;
    q := q || jsonb_build_object('key','pb3','name','Personal Bests this week','progress',least(n, 3),'goal',3,'points',30,'done', n >= 3);
    select count(distinct log_date) filter (where kcal is not null or protein_g is not null),
           count(distinct log_date) filter (where weight_kg is not null),
           count(*) filter (where kcal is not null), avg(kcal) filter (where kcal is not null)
      into n, ok, days, avgk from public.logs where trainee_id = uid and log_date between ws and we;
    q := q || jsonb_build_object('key','macros5','name','Log your macros on 5 days','progress',least(n, 5),'goal',5,'points',30,'done', n >= 5);
    q := q || jsonb_build_object('key','weigh5','name','Weigh in on 5 days','progress',least(ok, 5),'goal',5,'points',30,'done', ok >= 5);
    select mg.kcal into plan from public.macro_goals mg join public.engagements en on en.id = mg.engagement_id
     where en.trainee_id = uid and en.status = 'active' and mg.week_start = ws and mg.kcal is not null order by mg.updated_at desc nulls last limit 1;
    q := q || jsonb_build_object('key','calories','name','Hit your calorie goal (within 10%)','progress',least(days, 5),'goal', case when plan is null then 0 else 5 end,'points',50,
                                 'done', plan is not null and days >= 5 and abs(avgk - plan) <= plan * 0.10,
                                 'note', case when plan is null then 'No calorie goal set this week'
                                              when days > 0 then 'Average ' || round(avgk) || ' of ' || plan || ' kcal' end);
    select count(*) into n from public.checkins where trainee_id = uid and photo_path is not null and checkin_date between ws and we;
    q := q || jsonb_build_object('key','photo','name','Weekly check-in photo','progress',least(n, 1),'goal',1,'points',20,'done', n >= 1);
    select count(*) into n from public.call_proposals c join public.engagements en on en.id = c.engagement_id
     where en.trainee_id = uid and c.status = 'accepted'
       and (public._call_occurs(c.proposed_date, c.recur_every_days, ws, v_today - 1)
            or (public._call_occurs(c.proposed_date, c.recur_every_days, v_today, v_today) and c.end_time <= v_local::time));
    q := q || jsonb_build_object('key','call','name','Attend a call with your coach','progress',least(n, 1),'goal',1,'points',20,'done', n >= 1);
    select count(*) into n from public.connections where status = 'confirmed' and (a = uid or b = uid)
       and (confirmed_at at time zone coalesce(v_tz, 'Europe/Dublin'))::date between ws and we;
    q := q || jsonb_build_object('key','friend','name','Make a friend','progress',least(n, 1),'goal',1,'points',20,'done', n >= 1);
  end if;

  for x in select * from jsonb_array_elements(q) loop
    v_ref := 'quest:' || (x->>'key') || ':' || uid || ':' || ws; v_just := false;
    if (x->>'done')::boolean then
      v_just := public._award_points(uid, (x->>'points')::int, 'Weekly quest: ' || (x->>'name'), v_ref);
    end if;
    v_paid := exists (select 1 from public.points_ledger where ref = v_ref);
    out := out || (x || jsonb_build_object('paid', v_paid, 'just_paid', v_just));
  end loop;
  select coalesce(sum(amount), 0) into v_bal from public.points_ledger where user_id = uid;
  return jsonb_build_object('role', coalesce(v_role, 'trainee'), 'week_start', ws, 'resets', ws + 7, 'quests', out, 'balance', v_bal);
end $$;
revoke execute on function public.weekly_quests_sync() from public, anon, authenticated;
grant  execute on function public.weekly_quests_sync() to authenticated;

-- 4. coach points for real actions
create or replace function public._coach_action_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare j jsonb := to_jsonb(new); o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end; v_coach uuid; v_tz text;
begin
  begin
    if tg_table_name = 'reviews' then
      perform public._award_points((j->>'coach_id')::uuid, 5, 'Reviewed a session', 'coach:review:' || (j->>'submission_id'));
    elsif tg_table_name = 'assigned_workouts' then
      select coach_id into v_coach from public.engagements where id = (j->>'engagement_id')::uuid;
      if v_coach is not null and v_coach = auth.uid() then
        perform public._award_points(v_coach, 2, 'Assigned a session', 'coach:assign:' || (j->>'id'));
      end if;
    elsif tg_table_name = 'offers' then
      if (j->>'counter_resolved_at') is not null and (o->>'counter_resolved_at') is null then
        perform public._award_points((j->>'coach_id')::uuid, 3, 'Answered a counter-offer', 'coach:counter:' || (j->>'id'));
      end if;
    elsif tg_table_name = 'call_proposals' then
      if (j->>'status') = 'accepted' and coalesce(o->>'status', '') <> 'accepted' then
        select coach_id into v_coach from public.engagements where id = (j->>'engagement_id')::uuid;
        perform public._award_points(v_coach, 3, 'Arranged a call', 'coach:call:' || (j->>'id'));
      end if;
    elsif tg_table_name = 'macro_goals' then
      select coach_id into v_coach from public.engagements where id = (j->>'engagement_id')::uuid;
      if v_coach is not null and (j->>'set_by')::uuid = v_coach and ((j->>'kcal') is not null or (j->>'protein_g') is not null) then
        perform public._award_points(v_coach, 2, 'Set calorie goals', 'coach:macros:' || (j->>'engagement_id') || ':' || (j->>'week_start'));
      end if;
    elsif tg_table_name = 'coach_stripe_accounts' then
      if coalesce((j->>'details_submitted')::boolean, false) and coalesce((j->>'transfers_active')::boolean, false) then
        perform public._award_points((j->>'coach_id')::uuid, 20, 'Finished Stripe payout setup', 'coach:stripe:' || (j->>'coach_id'));
      end if;
    elsif tg_table_name = 'profiles' then
      if (j->>'role') = 'coach' and (j->>'last_market_at') is not null and (j->>'last_market_at') is distinct from (o->>'last_market_at') then
        v_tz := coalesce(nullif(j->>'tz', ''), 'Europe/Dublin');
        perform public._award_points((j->>'id')::uuid, 1, 'Checked Open goals',
                                     'coach:market:' || (j->>'id') || ':' || ((j->>'last_market_at')::timestamptz at time zone v_tz)::date);
      end if;
    end if;
  exception when others then raise warning 'coach points skipped (%): %', tg_table_name, sqlerrm; end;
  return new;
end $$;
revoke execute on function public._coach_action_points() from public, anon, authenticated;

drop trigger if exists coach_points_review on public.reviews;
create trigger coach_points_review after insert on public.reviews for each row execute function public._coach_action_points();
drop trigger if exists coach_points_assign on public.assigned_workouts;
create trigger coach_points_assign after insert on public.assigned_workouts for each row execute function public._coach_action_points();
drop trigger if exists coach_points_counter on public.offers;
create trigger coach_points_counter after update on public.offers for each row execute function public._coach_action_points();
drop trigger if exists coach_points_call on public.call_proposals;
create trigger coach_points_call after insert or update on public.call_proposals for each row execute function public._coach_action_points();
drop trigger if exists coach_points_macros on public.macro_goals;
create trigger coach_points_macros after insert or update on public.macro_goals for each row execute function public._coach_action_points();
do $$ begin
  if to_regclass('public.coach_stripe_accounts') is not null then
    execute 'drop trigger if exists coach_points_stripe on public.coach_stripe_accounts';
    execute 'create trigger coach_points_stripe after insert or update on public.coach_stripe_accounts for each row execute function public._coach_action_points()';
  end if;
end $$;
drop trigger if exists coach_points_market on public.profiles;
create trigger coach_points_market after update of last_market_at on public.profiles for each row execute function public._coach_action_points();

-- Check: expect  pb30 1 | sync_callable true | triggers 7
select
  (select count(*) from pg_proc where proname = '_pb_quest_step' and prosrc like '%v_pts int := 30%') as pb30,
  has_function_privilege('authenticated', 'public.weekly_quests_sync()', 'execute') as sync_callable,
  (select count(*) from pg_trigger where tgname like 'coach_points_%' and not tgisinternal) as triggers;
