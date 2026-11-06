-- Item EZ-6 (owner, 2026-11-05): cumulative coach notes per exercise.
-- Every review comment (and voice-over) a trainee has received on an exercise, newest first, with its date - for the
-- trainee's workout player ("Your coach's notes") and the coach's review screen ("Your notes on this exercise").
-- Reviews store notes per set by exercise NAME; this matches by the exercise's ID where the submission (or the assigned
-- snapshot) records it - so a renamed exercise keeps its history - and falls back to the name for older reviews.
-- Joined and filtered inside the database: a submission carries the pose frames, far too large to download for notes.
-- Only the trainee, or a coach with a goal with that trainee, gets rows. Read-only. Safe to re-run.
create or replace function public.exercise_notes(p_trainee uuid, p_exercise_ids uuid[], p_names text[])
returns table (exercise_id uuid, exercise_name text, noted_at timestamptz, set_no int, comment text, coach_name text,
               review_id uuid, submission_id uuid, voiceover_path text, telestration jsonb, video_path text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not (auth.uid() = p_trainee
     or exists (select 1 from public.engagements e where e.trainee_id = p_trainee and e.coach_id = auth.uid())) then
    return;
  end if;
  return query
  with ent as (
    select r.id as rid, r.submission_id as sid, r.created_at as at, r.coach_id as cid, s.report as rep, a.snapshot as snap, p.e as e,
           case when (p.e->>'item_index') ~ '^\d+$' then (p.e->>'item_index')::int end as ii,
           case when (p.e->>'set_index')  ~ '^\d+$' then (p.e->>'set_index')::int  end as si
      from public.reviews r
      join public.submissions s on s.id = r.submission_id
      left join public.assigned_workouts a on a.id = s.assigned_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.per_set) = 'array' then r.per_set else '[]'::jsonb end) as p(e)
     where s.trainee_id = p_trainee
  ), x as (
    select ent.*,
           coalesce(nullif(ent.rep->'items'->ent.ii->>'exercise_id', ''), nullif(ent.snap->'items'->ent.ii->>'exercise_id', '')) as xid_txt
      from ent
  ), y as (
    select x.*, case when x.xid_txt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.xid_txt::uuid end as xid
      from x
  )
  select y.xid, y.e->>'exercise', y.at,
         case when (y.e->>'set') ~ '^\d+$' then (y.e->>'set')::int end,
         nullif(btrim(y.e->>'comment'), ''),
         pr.display_name, y.rid, y.sid,
         nullif(y.e->>'voiceover_path', ''), y.e->'telestration',
         y.rep->'items'->y.ii->'results'->y.si->>'video_path'
    from y left join public.profiles pr on pr.id = y.cid
   where (nullif(btrim(y.e->>'comment'), '') is not null or nullif(y.e->>'voiceover_path', '') is not null)
     and ((y.xid is not null and y.xid = any(coalesce(p_exercise_ids, '{}'::uuid[])))
          or (y.e->>'exercise') = any(coalesce(p_names, '{}'::text[])))
   order by y.at desc, (case when (y.e->>'set') ~ '^\d+$' then (y.e->>'set')::int end) nulls last;
end $$;
revoke execute on function public.exercise_notes(uuid, uuid[], text[]) from public, anon;
grant  execute on function public.exercise_notes(uuid, uuid[], text[]) to authenticated;

-- Check: expect  function_ok = 1  (it returns no rows in the SQL editor - there is no signed-in user there)
select count(*) as function_ok from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'exercise_notes';