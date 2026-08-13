-- =====================================================================
-- FormTrace — personal bests per exercise (item R)
-- Run in the Supabase SQL editor.
--
-- RULE (decided 2026-08-11):
--   more reps AND same-or-more weight  -> new PB
--   same reps AND more weight          -> new PB
--   one up, one down                   -> unclear, NOT logged
--   neither improves                   -> not logged
--
-- KEYED ON EXERCISE NAME, not exercise_id — a coach recreating an exercise,
-- or the wildcard-slot mechanism letting a trainee pick between different
-- underlying exercise rows for the same muscle group, must not reset a
-- trainee's PB. Accepted trade-off: two different coaches' same-named
-- exercises share one PB. Name is lower-cased + trimmed so "Push-ups" and
-- "push-ups " are the same key.
--
-- CHECKED AT RECORD TIME, not on coach review — matches how the rep count
-- itself already works (the trainee's own corrected count, not a
-- coach-graded one, drives the vs-last-time comparison).
--
-- Write-locked: only recompute_personal_best() may insert or update a row,
-- consistent with every other trainee-asserted number in this app (streak,
-- payment ledger, workout status) being server-checked rather than
-- client-writable.
-- =====================================================================

create table if not exists public.personal_bests (
  id           uuid primary key default gen_random_uuid(),
  trainee_id   uuid not null references public.profiles(id) on delete cascade,
  exercise_key text not null,      -- lower(trim(exercise_name))
  exercise_name text not null,     -- display form, as last achieved
  reps         integer not null,
  weight_kg    numeric,            -- null = bodyweight
  assigned_id  uuid references public.assigned_workouts(id) on delete set null,
  achieved_at  timestamptz not null default now(),
  unique (trainee_id, exercise_key)
);

alter table public.personal_bests enable row level security;

drop policy if exists "trainee reads own PBs" on public.personal_bests;
create policy "trainee reads own PBs"
  on public.personal_bests for select to authenticated
  using (trainee_id = auth.uid());

-- a coach needs to read their own trainees' PBs too, for the Journey recap
drop policy if exists "coach reads trainee PBs" on public.personal_bests;
create policy "coach reads trainee PBs"
  on public.personal_bests for select to authenticated
  using (
    exists (select 1 from public.engagements e
            where e.trainee_id = personal_bests.trainee_id and e.coach_id = auth.uid())
  );
-- no client insert/update/delete policy — written only by the function below

create index if not exists personal_bests_trainee_idx on public.personal_bests (trainee_id);

-- ---------------------------------------------------------------------
-- Evaluate one set against the current PB for that exercise. Returns the
-- new PB row as jsonb if one was set, or null if nothing changed — the
-- caller uses a non-null result to decide whether to fire the milestone
-- notification, so the return value IS the "did this just happen" signal.
-- ---------------------------------------------------------------------
create or replace function public.recompute_personal_best(
  p_exercise_name text,
  p_reps integer,
  p_weight_kg numeric,
  p_assigned_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  key text := lower(btrim(p_exercise_name));
  cur record;
  reps_up boolean;
  weight_up boolean;
  weight_same boolean;
  out jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_exercise_name is null or btrim(p_exercise_name) = '' then raise exception 'exercise name required'; end if;
  if p_reps is null or p_reps < 0 then raise exception 'invalid rep count'; end if;

  select * into cur from public.personal_bests
   where trainee_id = uid and exercise_key = key;

  if cur.id is null then
    -- first time this exercise has ever been recorded: it IS the PB
    insert into public.personal_bests (trainee_id, exercise_key, exercise_name, reps, weight_kg, assigned_id)
    values (uid, key, btrim(p_exercise_name), p_reps, p_weight_kg, p_assigned_id)
    returning to_jsonb(personal_bests.*) into out;
    return out;
  end if;

  reps_up      := p_reps > cur.reps;
  weight_same  := coalesce(p_weight_kg,0) = coalesce(cur.weight_kg,0);
  weight_up    := coalesce(p_weight_kg,0) > coalesce(cur.weight_kg,0);

  -- more reps + same-or-more weight, OR same reps + more weight
  if (reps_up and (weight_same or weight_up))
     or (p_reps = cur.reps and weight_up) then
    update public.personal_bests
       set reps = p_reps, weight_kg = p_weight_kg, exercise_name = btrim(p_exercise_name),
           assigned_id = p_assigned_id, achieved_at = now()
     where id = cur.id
     returning to_jsonb(personal_bests.*) into out;
    return out;
  end if;

  return null;   -- unchanged, or the up/down case that's deliberately not logged
end;
$$;

revoke execute on function public.recompute_personal_best(text,integer,numeric,uuid) from public;
grant  execute on function public.recompute_personal_best(text,integer,numeric,uuid) to authenticated;

-- ---------------------------------------------------------------------
-- All of a trainee's PBs, for their own profile screen.
-- ---------------------------------------------------------------------
create or replace function public.my_personal_bests()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(row order by achieved_at desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'exercise_name', exercise_name, 'reps', reps, 'weight_kg', weight_kg, 'achieved_at', achieved_at
    ) as row
    from public.personal_bests where trainee_id = auth.uid()
  ) s;
$$;

revoke execute on function public.my_personal_bests() from public;
grant  execute on function public.my_personal_bests() to authenticated;

-- ---------------------------------------------------------------------
-- PBs achieved DURING one goal, for The Journey (item P).
-- ---------------------------------------------------------------------
create or replace function public.personal_bests_in_range(p_trainee uuid, p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_trainee <> auth.uid() and not exists (
    select 1 from public.engagements e where e.trainee_id=p_trainee and e.coach_id=auth.uid()
  ) then
    raise exception 'not authorised';
  end if;
  return coalesce((
    select jsonb_agg(row order by achieved_at desc)
    from (
      select jsonb_build_object(
        'exercise_name', exercise_name, 'reps', reps, 'weight_kg', weight_kg, 'achieved_at', achieved_at
      ) as row
      from public.personal_bests
      where trainee_id = p_trainee
        and achieved_at::date >= p_from and achieved_at::date <= p_to
    ) s
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.personal_bests_in_range(uuid,date,date) from public;
grant  execute on function public.personal_bests_in_range(uuid,date,date) to authenticated;

select proname from pg_proc
where proname in ('recompute_personal_best','my_personal_bests','personal_bests_in_range')
order by proname;
