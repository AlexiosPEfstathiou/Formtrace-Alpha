-- HW (owner, 2026-11-22): 12 demo goals from 12 demo trainee accounts, to judge the Open goals tab with a full list.
-- Demo accounts: email demo-goal-NN@formtrace.invalid, no password (nobody can sign in as them), name tagged in the
-- profile bio as DEMO. Goals are posted 0-5 days ago, so they stay open for 2-7 days (open goals expire after 7 days).
-- Remove everything with the block at the bottom. Safe to re-run (skips accounts that exist).
do $$
declare
  d record; uid uuid;
begin
  for d in select * from (values
    (1,  'Siobhán Murphy',  'Cork',     'Strength',    'First pull-up by spring',            'Can do 3 negatives. Want a plan for 3 sessions a week at home with a bar.', 1),
    (2,  'Daniel Okafor',   'Dublin',   'Muscle gain', 'Add 5 kg of muscle in 12 weeks',     'Gym 4x a week, eating around 2,600 kcal. Need structure and form checks on compounds.', 0),
    (3,  'Aoife Kelly',     'Galway',   'Endurance',   'Run my first 10K under 60 minutes',   'Currently 5K in 33 min. Race on 15 March.', 2),
    (4,  'Marco Rossi',     'Limerick', 'Mobility',    'Touch my toes again',                 'Desk job, tight hamstrings and hips. 15 minutes a day is realistic.', 3),
    (5,  'Niamh Byrne',     'Cork',     'Weight loss', 'Lose 8 kg before my wedding',         'Wedding in June. Prefer home workouts plus walking; vegetarian.', 0),
    (6,  'Tomás Walsh',     'Waterford','Strength',    'Deadlift 1.5x bodyweight',            'Bodyweight 82 kg, current best 100 kg. Want technique coaching on video.', 4),
    (7,  'Grace Chen',      'Dublin',   'Mobility',    'Pain-free squats after knee rehab',   'Cleared by physio. Need a careful progression and someone to watch my form.', 1),
    (8,  'Liam Doyle',      'Kilkenny', 'Endurance',   'Cycle 100 km in one day',             'Ride 2x a week, longest ride 55 km. Event in May.', 5),
    (9,  'Fatima Haddad',   'Cork',     'Muscle gain', 'Build glutes and legs',               '3 gym sessions a week, beginner with machines. Want to learn free weights.', 2),
    (10, 'Seán O''Brien',   'Sligo',    'Weight loss', 'Get back under 100 kg',               'At 108 kg. Bad knees, so low impact please. Can train 4 days.', 3),
    (11, 'Emma Novak',      'Dublin',   'Strength',    'First strict handstand push-up',      'Can hold a wall handstand for 40 seconds. Calisthenics at home.', 0),
    (12, 'Rory Gallagher',  'Donegal',  'Endurance',   'Hike Carrauntoohil without stopping', 'Planning it for April. Need leg strength and cardio, weekends free.', 4)
  ) as t(n, name, city, focus, title, details, days)
  loop
    if exists (select 1 from auth.users where email = 'demo-goal-' || lpad(d.n::text, 2, '0') || '@formtrace.invalid') then continue; end if;
    uid := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
    values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'demo-goal-' || lpad(d.n::text, 2, '0') || '@formtrace.invalid', '', now(),
            jsonb_build_object('display_name', d.name), '{"provider":"email","providers":["email"]}'::jsonb, now(), now());
    update public.profiles set city = d.city, bio = 'DEMO account (HW) - not a real person', role = 'trainee' where id = uid;
    insert into public.listings (trainee_id, title, focus, details, status, created_at)
    values (uid, d.title, d.focus, d.details, 'open', now() - make_interval(days => d.days, hours => (d.n * 3) % 20));
  end loop;
end $$;

-- Check: expect  demo_accounts 12 | demo_open_goals 12
select
  (select count(*) from auth.users where email like 'demo-goal-%@formtrace.invalid') as demo_accounts,
  (select count(*) from public.listings l join auth.users u on u.id = l.trainee_id where u.email like 'demo-goal-%@formtrace.invalid' and l.status = 'open') as demo_open_goals;

-- REMOVE the demo data later (run on its own):
-- delete from public.offers   where listing_id in (select l.id from public.listings l join auth.users u on u.id = l.trainee_id where u.email like 'demo-goal-%@formtrace.invalid');
-- delete from public.listings where trainee_id in (select id from auth.users where email like 'demo-goal-%@formtrace.invalid');
-- delete from auth.users      where email like 'demo-goal-%@formtrace.invalid';
