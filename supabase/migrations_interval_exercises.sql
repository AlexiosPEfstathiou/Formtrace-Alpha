-- =====================================================================
-- FormTrace — duration-based interval exercises (walk/run alternations,
-- GPS distance tracked)
--
-- Genuinely a new exercise TYPE, not a variant of the existing rep-based
-- one — checked and confirmed nothing in this app's recording pipeline
-- (camera, pose detection, countReps) has any role here; an interval
-- needs a timer and a GPS distance readout, not a skeleton overlay.
--
-- kind lives on the exercise itself (like name, muscle_group) — the
-- actual segment structure (which walk/run durations, how many rounds)
-- follows the SAME pattern sets/reps already use: chosen per workout-ITEM
-- at build time, not fixed on the exercise. An exercise is just "Interval
-- Run"; a coach decides the actual walk/run mix each time they assign it,
-- exactly like they already choose sets/reps for a rep-based exercise.
-- =====================================================================

alter table public.exercises add column if not exists kind text not null default 'reps';
alter table public.exercises drop constraint if exists exercises_kind_check;
alter table public.exercises add constraint exercises_kind_check check (kind in ('reps','interval'));

select column_name, column_default from information_schema.columns
where table_name='exercises' and column_name='kind';
