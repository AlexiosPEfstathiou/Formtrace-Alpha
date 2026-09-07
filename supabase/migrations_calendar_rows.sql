-- =====================================================================
-- FormTrace — calendar_rows(): assigned workouts WITHOUT the landmark payload.
-- Run in the Supabase SQL editor.
--
-- Root cause of the calendar "statement timeout" (items AR and now AT step 3
-- testing): every assigned_workouts row carries `snapshot`, which freezes the
-- reference pose LANDMARKS for every exercise at assign time — tens of KB per
-- exercise, so a workout of five exercises is a few hundred KB, and a calendar
-- with 40 assigned sessions was pulling megabytes per open. The calendar and
-- every sheet it opens only ever read snapshot.name and snapshot.items[].name
-- (and the item count). This returns exactly that shape, with landmarks and
-- reference video paths stripped, and everything else on the row untouched.
--
-- SECURITY INVOKER (the default): runs as the caller, so the table's own RLS
-- decides what comes back — a coach sees their trainees' rows, a trainee
-- their own, exactly as with a direct select. Nothing new is exposed.
-- `to_jsonb(a) - 'snapshot'` carries every other column automatically, so
-- future columns added to assigned_workouts need no change here.
-- =====================================================================
create or replace function public.calendar_rows(p_engagements uuid[])
returns setof jsonb
language sql
stable
set search_path = public
as $$
  select (to_jsonb(a) - 'snapshot') || jsonb_build_object(
           'snapshot', jsonb_build_object(
             'name',  a.snapshot->>'name',
             'items', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'name',        i->>'name',
                        'kind',        i->>'kind',
                        'exercise_id', i->>'exercise_id',
                        'wildcard_mg', i->>'wildcard_mg',
                        'sets',        i->'sets',
                        'reps',        i->'reps'))
                 from jsonb_array_elements(coalesce(a.snapshot->'items','[]'::jsonb)) i
             ), '[]'::jsonb)))
    from public.assigned_workouts a
   where a.engagement_id = any(p_engagements)
   order by a.created_at;
$$;
grant execute on function public.calendar_rows(uuid[]) to authenticated;

-- sanity: compare payload size for one engagement's rows, full vs slim
select 'full bytes'  as what, coalesce(sum(length(to_jsonb(a)::text)),0) from public.assigned_workouts a
union all
select 'slim bytes', coalesce(sum(length(r::text)),0) from public.calendar_rows((select array_agg(id) from public.engagements)) r;
