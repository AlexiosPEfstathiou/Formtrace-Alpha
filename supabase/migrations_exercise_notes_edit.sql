-- Item EZ-6b (owner, 2026-11-05): the coach can edit or delete the accumulated notes - e.g. a comment duplicated because the
-- trainee keeps making the same mistake. Notes live inside reviews.per_set (one entry per set), so:
-- 1) exercise_notes() now also returns who wrote each note (coach_id), its position in the review (entry_no) and when it
--    was last edited (edited_at). Its output columns change, so it is dropped and re-created (nothing stores its results).
-- 2) edit_exercise_note(review, entry, text) - only the coach who wrote the review; empty text removes the comment (the set's
--    tags and voice-over stay); records comment_edited_at / comment_removed_at in the entry. Safe to re-run.
drop function if exists public.exercise_notes(uuid, uuid[], text[]);
create function public.exercise_notes(p_trainee uuid, p_exercise_ids uuid[], p_names text[])
returns table (exercise_id uuid, exercise_name text, noted_at timestamptz, set_no int, comment text, coach_name text,
               review_id uuid, submission_id uuid, voiceover_path text, telestration jsonb, video_path text,
               coach_id uuid, entry_no int, edited_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not (auth.uid() = p_trainee
     or exists (select 1 from public.engagements e where e.trainee_id = p_trainee and e.coach_id = auth.uid())) then
    return;
  end if;
  return query
  with ent as (
    select r.id as rid, r.submission_id as sid, r.created_at as at, r.coach_id as cid, s.report as rep, a.snapshot as snap, p.e as e, p.ord as ord,
           case when (p.e->>'item_index') ~ '^\d+$' then (p.e->>'item_index')::int end as ii,
           case when (p.e->>'set_index')  ~ '^\d+$' then (p.e->>'set_index')::int  end as si
      from public.reviews r
      join public.submissions s on s.id = r.submission_id
      left join public.assigned_workouts a on a.id = s.assigned_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(r.per_set) = 'array' then r.per_set else '[]'::jsonb end) with ordinality as p(e, ord)
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
         y.rep->'items'->y.ii->'results'->y.si->>'video_path',
         y.cid, (y.ord - 1)::int,
         case when (y.e->>'comment_edited_at') is not null then (y.e->>'comment_edited_at')::timestamptz end
    from y left join public.profiles pr on pr.id = y.cid
   where (nullif(btrim(y.e->>'comment'), '') is not null or nullif(y.e->>'voiceover_path', '') is not null)
     and ((y.xid is not null and y.xid = any(coalesce(p_exercise_ids, '{}'::uuid[])))
          or (y.e->>'exercise') = any(coalesce(p_names, '{}'::text[])))
   order by y.at desc, (case when (y.e->>'set') ~ '^\d+$' then (y.e->>'set')::int end) nulls last;
end $$;
revoke execute on function public.exercise_notes(uuid, uuid[], text[]) from public, anon;
grant  execute on function public.exercise_notes(uuid, uuid[], text[]) to authenticated;

create or replace function public.edit_exercise_note(p_review uuid, p_entry int, p_comment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.reviews; e jsonb; txt text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  select * into r from public.reviews where id = p_review for update;
  if not found then raise exception 'That note was not found.'; end if;
  if r.coach_id is distinct from auth.uid() then raise exception 'Only the coach who wrote this note can change it.'; end if;
  if jsonb_typeof(r.per_set) is distinct from 'array' or p_entry is null or p_entry < 0 or p_entry >= jsonb_array_length(r.per_set) then
    raise exception 'That note was not found.'; end if;
  if txt is not null and length(txt) > 2000 then raise exception 'A note can be at most 2000 characters.'; end if;
  e := r.per_set -> p_entry;
  if txt is null then e := (e - 'comment' - 'comment_edited_at') || jsonb_build_object('comment_removed_at', now());
  else e := e || jsonb_build_object('comment', txt, 'comment_edited_at', now()); end if;
  update public.reviews set per_set = jsonb_set(per_set, array[p_entry::text], e) where id = p_review;
  return e;
end $$;
revoke execute on function public.edit_exercise_note(uuid, int, text) from public, anon;
grant  execute on function public.edit_exercise_note(uuid, int, text) to authenticated;

-- Check: expect  functions_ok = 2
select count(*) as functions_ok from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('exercise_notes', 'edit_exercise_note');