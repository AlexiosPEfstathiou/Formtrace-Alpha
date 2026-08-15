-- =====================================================================
-- FormTrace — partial workout management: skip option
-- Run in the Supabase SQL editor. Requires migrations_wildcard_fill.sql.
--
-- DECIDED (per instruction, not a default): Submit stays gated on full
-- completion — this does NOT loosen that gate. Instead, "complete" now
-- includes explicitly SKIPPED items, so a trainee marks what they can't
-- finish as skipped (0 reps) rather than the button just becoming
-- available with things silently missing.
--
-- Wildcard skip is deliberately its OWN function, not routed through
-- fill_wildcard_slot, and does not touch the exercises table at all —
-- per the explicit ask, this needs to work even if the exercise-library
-- picker itself is broken for some future, unknown reason. It only ever
-- touches assigned_workouts, the same table its sibling function already
-- has permission to write.
-- =====================================================================

create or replace function public.skip_wildcard_slot(p_assigned uuid, p_item_index integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_aw record;
  item jsonb;
  new_item jsonb;
  new_snapshot jsonb;
begin
  select aw.id, aw.snapshot, aw.status, en.trainee_id
    into v_aw
  from public.assigned_workouts aw
  join public.engagements en on en.id = aw.engagement_id
  where aw.id = p_assigned;

  if not found then raise exception 'workout not found'; end if;
  if v_aw.trainee_id <> uid then raise exception 'not your workout'; end if;
  if v_aw.status <> 'assigned' then raise exception 'this workout has already been submitted'; end if;

  item := v_aw.snapshot->'items'->p_item_index;
  if item is null then raise exception 'that slot does not exist'; end if;
  if item->>'wildcard_mg' is null then raise exception 'that slot is not a wildcard'; end if;

  -- sets:0 so it contributes nothing to the set totals, matching how an
  -- unfilled wildcard already behaves — skipped is just "resolved, empty"
  new_item := item || jsonb_build_object('sets', 0, 'skipped', true);
  new_snapshot := jsonb_set(v_aw.snapshot, array['items', p_item_index::text], new_item);

  update public.assigned_workouts set snapshot = new_snapshot where id = p_assigned;
  return new_snapshot;
end;
$$;

revoke execute on function public.skip_wildcard_slot(uuid,integer) from public;
grant  execute on function public.skip_wildcard_slot(uuid,integer) to authenticated;

select proname from pg_proc where proname = 'skip_wildcard_slot';
