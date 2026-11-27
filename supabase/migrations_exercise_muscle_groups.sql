-- JA (owner 2026-11-27): an exercise can belong to several muscle groups (e.g. Bulgarian split squat = Quads + Glutes).
-- muscle_groups holds them all in the coach's order; muscle_group stays as the PRIMARY one (= muscle_groups[1]) so every
-- older reader (workout icons, filters, wildcards) keeps working. Safe to run twice.
alter table public.exercises add column if not exists muscle_groups text[];
update public.exercises set muscle_groups = array[muscle_group]
 where muscle_group is not null and (muscle_groups is null or cardinality(muscle_groups) = 0);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'exercises_muscle_groups_valid') then
    alter table public.exercises add constraint exercises_muscle_groups_valid check (
      muscle_groups is null or (cardinality(muscle_groups) <= 6 and muscle_groups <@ array['chest','back','shoulders','biceps',
      'triceps','forearms','abs','glutes','quads','hamstrings','calves','full_body','cardio','mobility']::text[]));
  end if;
end $$;
-- Verify: every exercise with a group has it in the array; expect mismatched = 0
select count(*) filter (where muscle_group is not null) as with_group,
       count(*) filter (where muscle_group is not null and not (muscle_group = any(coalesce(muscle_groups,'{}')))) as mismatched
  from public.exercises;
