-- =====================================================================
-- FormTrace — coach-graded form + rep-count labelling
-- Run this whole file once in the Supabase SQL editor.
--
-- WHAT THIS DOES
--   1. Archives every existing submission report, then strips the
--      machine-generated grade fields out of the live reports.
--   2. Creates set_labels: one row per recorded set, holding the rep-count
--      label from the trainee and the form grade from the coach, alongside
--      the trainee video and the coach's reference video. This is the
--      table to export from when training a model later.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1 - archive, then clear the auto-grades
-- ---------------------------------------------------------------------
create table if not exists public.legacy_auto_grades (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null,
  report        jsonb not null,
  archived_at   timestamptz not null default now()
);

-- Admin-only archive. RLS ON with NO policies = no client can read it through
-- the REST API (the anon key is public), while the SQL editor and service role
-- still see everything because they bypass RLS. Without this the archived
-- reports would be world-readable.
alter table public.legacy_auto_grades enable row level security;

-- archive once (safe to re-run; will not duplicate)
insert into public.legacy_auto_grades (submission_id, report)
select s.id, s.report
from public.submissions s
where s.report is not null
  and not exists (
    select 1 from public.legacy_auto_grades l where l.submission_id = s.id
  );

-- strip grade / shape / rom / tempo / ungraded from every set result
do $$
declare
  r           record;
  item        jsonb;
  res         jsonb;
  new_items   jsonb;
  new_results jsonb;
begin
  for r in select id, report from public.submissions where report ? 'items' loop
    new_items := '[]'::jsonb;
    for item in select value from jsonb_array_elements(r.report->'items') loop
      new_results := '[]'::jsonb;
      for res in select value from jsonb_array_elements(coalesce(item->'results','[]'::jsonb)) loop
        if res = 'null'::jsonb then
          new_results := new_results || 'null'::jsonb;
        else
          new_results := new_results || jsonb_build_array(
            res - 'grade' - 'shape' - 'rom' - 'tempo' - 'ungraded'
          );
        end if;
      end loop;
      new_items := new_items || jsonb_build_array(jsonb_set(item,'{results}',new_results));
    end loop;
    update public.submissions set report = jsonb_set(r.report,'{items}',new_items) where id = r.id;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- PART 2 - per-set labels (rep count + coach form grade)
-- ---------------------------------------------------------------------
create table if not exists public.set_labels (
  id             uuid primary key default gen_random_uuid(),
  submission_id  uuid references public.submissions(id) on delete cascade,
  assigned_id    uuid not null references public.assigned_workouts(id) on delete cascade,
  trainee_id     uuid not null references public.profiles(id) on delete cascade,
  coach_id       uuid references public.profiles(id) on delete set null,
  item_index     int not null,
  set_index      int not null,
  exercise_name  text,
  trainee_video_path        text,
  coach_ref_video_path      text,
  coach_feedback_video_path text,
  reps_counted   int,
  reps_label     text check (reps_label in ('correct','incorrect')),
  reps_corrected int,
  form_grade     int check (form_grade between 1 and 10),
  form_grade_source text default 'coach' check (form_grade_source in ('coach','auto')),
  graded_at      timestamptz,
  created_at     timestamptz not null default now(),
  unique (assigned_id, item_index, set_index)
);

alter table public.set_labels enable row level security;

drop policy if exists "trainee manages own set labels" on public.set_labels;
create policy "trainee manages own set labels"
  on public.set_labels for all to authenticated
  using (trainee_id = auth.uid())
  with check (trainee_id = auth.uid());

drop policy if exists "coach reads set labels on their engagements" on public.set_labels;
create policy "coach reads set labels on their engagements"
  on public.set_labels for select to authenticated
  using (exists (
    select 1
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where aw.id = set_labels.assigned_id
      and e.coach_id = auth.uid()
  ));

drop policy if exists "coach grades set labels on their engagements" on public.set_labels;
create policy "coach grades set labels on their engagements"
  on public.set_labels for update to authenticated
  using (exists (
    select 1
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where aw.id = set_labels.assigned_id
      and e.coach_id = auth.uid()
  ))
  with check (exists (
    select 1
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where aw.id = set_labels.assigned_id
      and e.coach_id = auth.uid()
  ));

-- coaches also need INSERT so they can grade workouts that were submitted
-- before this table existed (the app backfills the missing rows on review)
drop policy if exists "coach creates set labels on their engagements" on public.set_labels;
create policy "coach creates set labels on their engagements"
  on public.set_labels for insert to authenticated
  with check (exists (
    select 1
    from public.assigned_workouts aw
    join public.engagements e on e.id = aw.engagement_id
    where aw.id = set_labels.assigned_id
      and e.coach_id = auth.uid()
  ));

create index if not exists set_labels_assigned_idx on public.set_labels(assigned_id);
create index if not exists set_labels_trainee_idx  on public.set_labels(trainee_id);
create index if not exists set_labels_grade_idx    on public.set_labels(form_grade);

-- ---------------------------------------------------------------------
-- OPTIONAL - destroy the archive of old machine grades for good:
--   drop table public.legacy_auto_grades;
-- ---------------------------------------------------------------------
