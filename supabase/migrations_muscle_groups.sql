-- =====================================================================
-- FormTrace — muscle-group labels on exercises
-- Run in the Supabase SQL editor.
--
-- Lets a coach label each exercise, filter their library when building a
-- workout, and — once E lands — offer "Wildcard Abs" style slots the trainee
-- fills from the matching exercises.
--
-- Stored as free text with a CHECK rather than an enum: adding a group to an
-- enum needs a migration and locks the type, whereas a CHECK can be widened
-- in place. The client owns the canonical list and its ordering.
-- =====================================================================

alter table public.exercises
  add column if not exists muscle_group text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='exercises_muscle_group_chk') then
    alter table public.exercises add constraint exercises_muscle_group_chk
      check (muscle_group is null or muscle_group in (
        'chest','back','shoulders','biceps','triceps','forearms',
        'abs','glutes','quads','hamstrings','calves',
        'full_body','cardio','mobility'
      ));
  end if;
end $$;

-- the library filter and the wildcard picker both query coach + group
create index if not exists exercises_coach_mg_idx
  on public.exercises (coach_id, muscle_group);

-- how many exercises are still unlabelled, per coach
select p.display_name,
       count(*) filter (where e.muscle_group is null) as unlabelled,
       count(*) as total
from public.exercises e
join public.profiles p on p.id = e.coach_id
group by p.display_name
order by unlabelled desc;
