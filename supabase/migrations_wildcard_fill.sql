-- =====================================================================
-- FormTrace — fill a wildcard slot (server-side, replacing a blocked
-- direct client write)
--
-- REAL BUG, not introduced today: item E's wildcard-fill flow was built
-- to write assigned_workouts.snapshot directly from the client. That
-- worked when it was built, but migrations_status_enforce.sql later
-- locked the table down to client-writable (draft, opened) only —
-- everything else, snapshot included, moved behind SECURITY DEFINER
-- functions. Nobody caught this because nobody could reach the wildcard
-- flow at all until the exercises-read gap (fixed earlier) was closed —
-- this is the NEXT gap behind that one, on a different table.
--
-- Mirrors the validation the client's own picker already does (right
-- muscle group, sane sets/reps) but ENFORCED here, since that's the
-- actual point of a SECURITY DEFINER function — the client's checks are
-- UX, this is the guarantee.
-- =====================================================================

create or replace function public.fill_wildcard_slot(
  p_assigned uuid,
  p_item_index integer,
  p_exercise_id uuid,
  p_sets integer,
  p_reps integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  aw record;
  ex record;
  item jsonb;
  new_item jsonb;
  new_snapshot jsonb;
begin
  if p_sets is null or p_sets < 1 or p_sets > 20 then raise exception 'sets must be between 1 and 20'; end if;
  if p_reps is null or p_reps < 1 or p_reps > 100 then raise exception 'reps must be between 1 and 100'; end if;

  select aw.id, aw.snapshot, aw.status, en.trainee_id, en.coach_id
    into aw
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  -- record variables (not a %rowtype) are left genuinely UNASSIGNED on a
  -- zero-row match, not filled with nulls — touching aw.id here would
  -- itself raise "record is not assigned yet" instead of the intended
  -- exception. FOUND is the correct, safe check.
  if not found then raise exception 'workout not found'; end if;
  if aw.trainee_id <> uid then raise exception 'not your workout'; end if;
  if aw.status <> 'assigned' then raise exception 'this workout has already been submitted'; end if;

  item := aw.snapshot->'items'->p_item_index;
  if item is null then raise exception 'that slot does not exist'; end if;
  if item->>'wildcard_mg' is null then raise exception 'that slot is not a wildcard'; end if;

  select id, name, muscle_group, ref_video_path, landmarks into ex
  from public.exercises
  where id = p_exercise_id and coach_id = aw.coach_id;

  if not found then raise exception 'exercise not found in your coach''s library'; end if;
  if ex.muscle_group is distinct from item->>'wildcard_mg' then
    raise exception 'that exercise does not match this slot''s muscle group';
  end if;

  new_item := item
    || jsonb_build_object('exercise_id', ex.id, 'name', ex.name, 'sets', p_sets, 'reps', p_reps,
                           'ref_video_path', ex.ref_video_path, 'landmarks', ex.landmarks);
  -- wildcard_mg is kept in new_item (the || above only adds/overwrites keys),
  -- so the slot still reads as the trainee's own pick, same as the client did

  new_snapshot := jsonb_set(aw.snapshot, array['items', p_item_index::text], new_item);

  update public.assigned_workouts set snapshot = new_snapshot where id = p_assigned;

  return new_snapshot;
end;
$$;

revoke execute on function public.fill_wildcard_slot(uuid,integer,uuid,integer,integer) from public;
grant  execute on function public.fill_wildcard_slot(uuid,integer,uuid,integer,integer) to authenticated;

select proname from pg_proc where proname = 'fill_wildcard_slot';
