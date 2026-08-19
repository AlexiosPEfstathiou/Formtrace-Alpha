-- migrations_default_interval_exercise.sql
--
-- Referenced by loadCoachExerciseLibrary() in index.html, which was
-- already written and already wired into three call sites, but this
-- migration itself was never actually created -- the missing piece.
--
-- coach_id IS NULL marks a genuinely shared, global exercise: one row,
-- visible to every coach's library, editable/deletable by none of them.
-- The existing per-coach RLS policies only ever matched coach_id = auth.uid(),
-- so a NULL row was invisible until this policy exists.
--
-- REVISED after a real failed run: coach_id turned out to have a NOT NULL
-- constraint at the schema level, which the original version of this
-- migration -- and the pre-existing loadCoachExerciseLibrary() code it was
-- written for -- both assumed away without ever having been checked
-- against the actual schema. Relaxing it here is safe and backward
-- compatible: every existing row already has a real coach_id, so this only
-- adds a new possibility, it doesn't change anything already there.

-- 0. Allow coach_id to actually be null -- the step that was missing,
--    causing "null value in column coach_id violates not-null constraint"
--    on the insert below.
alter table public.exercises alter column coach_id drop not null;

-- 1. Allow every authenticated coach to SELECT shared (coach_id IS NULL) rows,
--    in addition to their own. Existing per-coach SELECT policy, whatever its
--    name, is untouched -- this is additive, not a replacement.
--    Drop-then-create rather than a bare create: genuinely unknown whether
--    this step already succeeded in the earlier failed run before the
--    insert below hit its own separate error, and CREATE POLICY has no
--    "if not exists" of its own to fall back on.
drop policy if exists "coaches can read shared exercises" on public.exercises;
create policy "coaches can read shared exercises"
  on public.exercises for select
  to authenticated
  using (coach_id is null);

-- 2. The default row itself. kind='interval' reuses the existing interval
--    exercise machinery entirely -- this migration only adds the shared row
--    and its read access; the richer segment/free-run data model lives in
--    each assigned workout's own snapshot, not on the exercise definition,
--    exactly like every other interval exercise already works.
insert into public.exercises (coach_id, name, kind, muscle_group, ref_video_path, landmarks)
values (null, 'Interval Running', 'interval', null, null, null)
on conflict do nothing;
