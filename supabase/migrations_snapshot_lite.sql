-- =====================================================================
-- FormTrace — stop reading the landmark payload on every list.
-- Run in the Supabase SQL editor. Replaces calendar_rows() from
-- migrations_calendar_rows.sql (which reduced NETWORK bytes but not DATABASE
-- work: to_jsonb(row) - 'snapshot' still had to load every row's full jsonb
-- from disk before discarding it, so the statement timeout kept returning).
--
-- Fix: keep a small pre-computed copy of what lists actually read — the
-- workout name and the item names — in their own columns, maintained by a
-- trigger, and rebuild calendar_rows() so it never references `snapshot`
-- at all. The column list is generated from information_schema at run time,
-- so re-running this migration after adding columns to assigned_workouts
-- refreshes the function; nothing here needs hand-maintenance.
-- =====================================================================

-- 1. light columns
alter table public.assigned_workouts
  add column if not exists snap_name  text,
  add column if not exists snap_items jsonb;

-- 2. keep them in sync on every write that touches snapshot
create or replace function public.assigned_workouts_snap_lite()
returns trigger
language plpgsql
as $$
begin
  new.snap_name  := new.snapshot->>'name';
  new.snap_items := coalesce((
      select jsonb_agg(jsonb_build_object(
               'name',        i->>'name',
               'kind',        i->>'kind',
               'exercise_id', i->>'exercise_id',
               'wildcard_mg', i->>'wildcard_mg',
               'sets',        i->'sets',
               'reps',        i->'reps'))
        from jsonb_array_elements(coalesce(new.snapshot->'items','[]'::jsonb)) i
    ), '[]'::jsonb);
  return new;
end;
$$;
drop trigger if exists assigned_workouts_snap_lite_trg on public.assigned_workouts;
create trigger assigned_workouts_snap_lite_trg
  before insert or update of snapshot on public.assigned_workouts
  for each row execute function public.assigned_workouts_snap_lite();

-- 3. one-off backfill (the only time the full payload is read for this)
update public.assigned_workouts a
   set snap_name  = a.snapshot->>'name',
       snap_items = coalesce((
           select jsonb_agg(jsonb_build_object(
                    'name', i->>'name', 'kind', i->>'kind', 'exercise_id', i->>'exercise_id',
                    'wildcard_mg', i->>'wildcard_mg', 'sets', i->'sets', 'reps', i->'reps'))
             from jsonb_array_elements(coalesce(a.snapshot->'items','[]'::jsonb)) i), '[]'::jsonb)
 where a.snap_name is null;

-- 4. calendar_rows(): every column EXCEPT snapshot (and the two lite columns,
--    which are re-exposed under the familiar `snapshot` key). Generated from
--    the live column list so it can never silently drop a column.
do $$
declare cols text;
begin
  select string_agg(format('a.%I', column_name), ', ' order by ordinal_position)
    into cols
    from information_schema.columns
   where table_schema='public' and table_name='assigned_workouts'
     and column_name not in ('snapshot','snap_name','snap_items');

  execute format($f$
    create or replace function public.calendar_rows(p_engagements uuid[])
    returns setof jsonb
    language sql
    stable
    set search_path = public
    as $b$
      select to_jsonb(x) || jsonb_build_object('snapshot',
               jsonb_build_object('name', a.snap_name, 'items', coalesce(a.snap_items, '[]'::jsonb)))
        from public.assigned_workouts a
        cross join lateral (select %s) x
       where a.engagement_id = any(p_engagements)
       order by a.created_at
    $b$;
  $f$, cols);
end $$;
grant execute on function public.calendar_rows(uuid[]) to authenticated;

select 'rows without snap_name (should be 0)' as check, count(*) from public.assigned_workouts where snap_name is null
union all
select 'calendar_rows sample ok', count(*) from public.calendar_rows((select array_agg(id) from public.engagements));
