-- =====================================================================
-- FormTrace — Item CG: workout levels (same workout, scaled reps and weight).
-- Run in the Supabase SQL editor.
-- level_scale on a workout: {"reps_step":2,"weight_step":2.5,"max":5}
--   Level L resolves an item as reps + (L-1)*reps_step and, when the item
--   has a base target weight, weight_kg + (L-1)*weight_step.
-- level on an engagement: the trainee's current level, remembered so the
--   coach's next assignment defaults to it; raising it is a visible
--   progression moment.
-- =====================================================================
alter table public.workouts add column if not exists level_scale jsonb
  default '{"reps_step":2,"weight_step":2.5,"max":5}'::jsonb;
alter table public.engagements add column if not exists level integer not null default 1
  check (level between 1 and 10);

select 'levels' as check,
  (select count(*) from information_schema.columns where table_schema='public' and table_name='workouts' and column_name='level_scale')
+ (select count(*) from information_schema.columns where table_schema='public' and table_name='engagements' and column_name='level') as columns_present;
