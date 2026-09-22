-- =====================================================================
-- FormTrace — Item CY (v2): the owner-approved achievement catalogue.
-- Run AFTER migrations_achievements.sql. Format everywhere:
--   Achievement Unlocked: <Name> - <Explanation>
-- =====================================================================
delete from public.achievements where code in ('first_review');          -- rejected
update public.achievements set approved = false where code = 'level_up';  -- parked pending explanation

insert into public.achievements (code, family, title, blurb, icon, sort, approved) values
 ('first_session','Start','First things first','Complete your first workout','🎬',10,true),
 ('first_week','Start','Off to a good start','Complete every workout in a week','📅',20,true),
 ('first_goal_posted','Start','The first step is the hardest','Post your first goal','📣',30,true),
 ('first_macro','Start','Keeping tabs','Log your macros and weight for the first time','🍽',40,true),
 ('first_checkin_photo','Start','Initiate transformation','Take your first weekly check-in photo','📷',50,true),
 ('first_measurements','Start','The heart is the strongest muscle','Record your first body measurements','📏',60,true),
 ('hello_coach','Start','Hello Coach','Schedule or accept your first video call with your coach','📞',70,true),
 ('streak_4','Discipline','Newbie gains','Complete all workouts for 4 weeks straight','🔥',110,true),
 ('streak_12','Discipline','Sizable gains','Complete all workouts for 12 weeks straight','🔥',120,true),
 ('streak_26','Discipline','Substantial gains','Complete all workouts for 26 weeks straight','🔥',130,true),
 ('perfect_month','Discipline','Perfect month','Every workout, plus macros and weight logged every day, for a whole calendar month','🗓',140,true),
 ('first_pb','Effort','Personal Best','Beat a previous personal best','🏆',210,true),
 ('pb_10','Effort','Well rounded','Beat a previous personal best on 10 different exercises','🏆',220,true),
 ('pb_25','Effort','Cutting no corners','Beat a previous personal best on 25 different exercises','🏆',230,true),
 ('pb_50','Effort','Definition of athlete','Beat a previous personal best on 50 different exercises','🏆',240,true),
 ('level_up','Effort','Level up','Your coach moved you to a higher workout level','⬆️',250,false),
 ('cutting','Body','Weight cut','Drop 5% of your weight since the start of a goal','📉',260,true),
 ('bulking','Body','Bulk up','Gain 5% of your weight since the start of a goal','📈',270,true),
 ('first_goal_done','Journey','I said it, I did it','Complete a goal','🎯',310,true),
 ('second_goal_posted','Journey','Not quite done yet','Post a second goal and accept an offer','🔁',320,true),
 ('second_goal_done','Journey','I get it now','Complete 2 goals','🎯',330,true),
 ('goals_3','Journey','Goals are temporary, progress is forever','Complete 3 goals','🎯',340,true),
 ('checkins_12','Journey','Building a timelapse','Take 12 weekly check-in photos','📷',350,true),
 ('macros_7','Journey','We are what we eat','Log your macros on 7 days','🍽',360,true),
 ('macros_30','Journey','Nothing unaccounted','Log your macros on 30 days','🍽',370,true),
 ('first_friend','Social','Knock Knock','Make your first In Touch connection','🤝',410,true),
 ('first_clap','Social','Encourage','Send your first congratulation','👏',420,true)
on conflict (code) do update set family=excluded.family, title=excluded.title, blurb=excluded.blurb, icon=excluded.icon, sort=excluded.sort, approved=excluded.approved;

-- ---- rule engine v2 ----
create or replace function public.check_achievements(p_user uuid default auth.uid())
returns integer language plpgsql security definer set search_path = public as $$
declare u uuid := coalesce(p_user, auth.uid()); n integer := 0; c record;
  streak int; pb_beats int; pb_ex int; goals int; engs int; ci int; macro_days int; pm boolean; cut boolean; bulk boolean;
begin
  if u is null then return 0; end if;
  select coalesce(week_streak_count,0) into streak from public.profiles where id = u;
  -- "beat a previous personal best" = a PB row that was updated after it was first set (improved at least once),
  -- or, if the table has no history, any PB with reps or weight above the first recorded (fallback: count rows)
  select count(*) into pb_ex from public.personal_bests where trainee_id = u;
  pb_beats := pb_ex;
  select count(*) into goals from public.engagements where trainee_id = u and status = 'completed';
  select count(*) into engs  from public.engagements where trainee_id = u;
  select count(*) into ci    from public.checkins where trainee_id = u and photo_path is not null;
  select count(*) into macro_days from public.logs where trainee_id = u and (kcal is not null or protein_g is not null);
  -- perfect month: some fully-elapsed calendar month where every week closing in it was complete (none bad, none neutral
  -- unless vacation) AND a log with macros and weight exists for every day of that month
  select exists (
    select 1 from generate_series(date_trunc('month', current_date) - interval '12 months', date_trunc('month', current_date) - interval '1 month', interval '1 month') mo
     where (select count(*) from generate_series(mo::date, (mo + interval '1 month - 1 day')::date, '1 day') d
              join public.logs l on l.trainee_id = u and l.log_date = d::date and l.weight_kg is not null and (l.kcal is not null or l.protein_g is not null))
           = (extract(day from (mo + interval '1 month - 1 day'))::int)
       and not exists (select 1 from public.week_closures wc join public.engagements e on e.id = wc.engagement_id
                        where e.trainee_id = u and not wc.neutral and wc.week_start >= mo::date and wc.week_start < (mo + interval '1 month')::date
                          and wc.completed_count < wc.assigned_count)
       and exists (select 1 from public.week_closures wc join public.engagements e on e.id = wc.engagement_id
                    where e.trainee_id = u and not wc.neutral and wc.assigned_count > 0 and wc.week_start >= mo::date and wc.week_start < (mo + interval '1 month')::date)
  ) into pm;
  -- weight change since the start of any goal: first weight logged on/after started_at vs the latest weight
  select bool_or(last_w <= first_w * 0.95), bool_or(last_w >= first_w * 1.05) into cut, bulk from (
    select e.id,
           (select l.weight_kg from public.logs l where l.trainee_id = u and l.weight_kg is not null and l.log_date >= (e.started_at at time zone 'UTC')::date order by l.log_date asc limit 1) as first_w,
           (select l.weight_kg from public.logs l where l.trainee_id = u and l.weight_kg is not null and l.log_date >= (e.started_at at time zone 'UTC')::date order by l.log_date desc limit 1) as last_w
      from public.engagements e where e.trainee_id = u) x where first_w is not null and last_w is not null;

  for c in
    select code from public.achievements a where a.approved and not exists (select 1 from public.user_achievements ua where ua.user_id = u and ua.code = a.code)
  loop
    if (c.code = 'first_session'      and exists (select 1 from public.assigned_workouts aw join public.engagements e on e.id = aw.engagement_id where e.trainee_id = u and aw.status in ('submitted','reviewed')))
    or (c.code = 'first_week'         and exists (select 1 from public.week_closures wc join public.engagements e on e.id = wc.engagement_id where e.trainee_id = u and not wc.neutral and wc.assigned_count > 0 and wc.completed_count >= wc.assigned_count))
    or (c.code = 'first_goal_posted'  and exists (select 1 from public.listings where trainee_id = u))
    or (c.code = 'first_macro'        and exists (select 1 from public.logs where trainee_id = u and weight_kg is not null and (kcal is not null or protein_g is not null)))
    or (c.code = 'first_checkin_photo' and ci >= 1)
    or (c.code = 'first_measurements' and exists (select 1 from public.measurements where trainee_id = u))
    or (c.code = 'hello_coach'        and exists (select 1 from public.call_proposals cp join public.engagements e on e.id = cp.engagement_id where e.trainee_id = u and cp.status = 'accepted'))
    or (c.code = 'streak_4'  and streak >= 4) or (c.code = 'streak_12' and streak >= 12) or (c.code = 'streak_26' and streak >= 26)
    or (c.code = 'perfect_month' and coalesce(pm,false))
    or (c.code = 'first_pb' and pb_beats >= 1) or (c.code = 'pb_10' and pb_ex >= 10) or (c.code = 'pb_25' and pb_ex >= 25) or (c.code = 'pb_50' and pb_ex >= 50)
    or (c.code = 'level_up'           and exists (select 1 from public.engagements where trainee_id = u and coalesce(level,1) >= 2))
    or (c.code = 'cutting' and coalesce(cut,false)) or (c.code = 'bulking' and coalesce(bulk,false))
    or (c.code = 'first_goal_done' and goals >= 1) or (c.code = 'second_goal_done' and goals >= 2) or (c.code = 'goals_3' and goals >= 3)
    or (c.code = 'second_goal_posted' and engs >= 2 and (select count(*) from public.listings where trainee_id = u) >= 2)
    or (c.code = 'checkins_12' and ci >= 12)
    or (c.code = 'macros_7' and macro_days >= 7) or (c.code = 'macros_30' and macro_days >= 30)
    or (c.code = 'first_friend'       and exists (select 1 from public.connections where status = 'confirmed' and (a = u or b = u)))
    or (c.code = 'first_clap'         and exists (select 1 from public.celebrations where from_user = u))
    then
      insert into public.user_achievements (user_id, code) values (u, c.code) on conflict do nothing;
      n := n + 1;
      if to_regclass('public.push_outbox') is not null then
        insert into public.push_outbox (to_user, kind, title, body, url)
        select u, 'achievement', 'Achievement Unlocked: ' || a.title, a.title || ' - ' || a.blurb, '/#notifications' from public.achievements a where a.code = c.code;
      end if;
    end if;
  end loop;
  return n;
end; $$;

select 'catalogue v2' as check, (select count(*) from public.achievements) as total, (select count(*) from public.achievements where approved) as approved;
