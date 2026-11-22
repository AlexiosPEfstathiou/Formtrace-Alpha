-- HN (owner, 2026-11-22): one consolidated coach note per exercise per trainee. Set comments stay with that set's review;
-- the exercise note is shown every time the trainee does the exercise (workout card and on the camera while recording).
-- One row per coach + trainee + exercise, replaced when the coach edits it; written only through set_exercise_note(),
-- called by the app when the coach sends the review. Safe to re-run.
create table if not exists public.coach_exercise_notes (
  id            uuid primary key default gen_random_uuid(),
  coach_id      uuid not null references auth.users(id) on delete cascade,
  trainee_id    uuid not null references auth.users(id) on delete cascade,
  exercise_key  text not null,
  exercise_name text not null,
  note          text not null,
  updated_at    timestamptz not null default now(),
  unique (coach_id, trainee_id, exercise_key)
);
create index if not exists coach_exercise_notes_trainee_idx on public.coach_exercise_notes (trainee_id, exercise_key);
alter table public.coach_exercise_notes enable row level security;
drop policy if exists "parties read exercise notes" on public.coach_exercise_notes;
create policy "parties read exercise notes" on public.coach_exercise_notes for select using (coach_id = auth.uid() or trainee_id = auth.uid());
revoke all on public.coach_exercise_notes from anon, authenticated;
grant select on public.coach_exercise_notes to authenticated;

create or replace function public.set_exercise_note(p_trainee uuid, p_exercise text, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_key text := lower(btrim(coalesce(p_exercise, ''))); v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if v_key = '' then raise exception 'exercise name required'; end if;
  if not exists (select 1 from public.engagements where coach_id = uid and trainee_id = p_trainee) then raise exception 'not your trainee'; end if;
  if v_note is null then
    delete from public.coach_exercise_notes where coach_id = uid and trainee_id = p_trainee and exercise_key = v_key;
    return jsonb_build_object('deleted', true);
  end if;
  insert into public.coach_exercise_notes (coach_id, trainee_id, exercise_key, exercise_name, note, updated_at)
  values (uid, p_trainee, v_key, btrim(p_exercise), left(v_note, 2000), now())
  on conflict (coach_id, trainee_id, exercise_key) do update set note = excluded.note, exercise_name = excluded.exercise_name, updated_at = now();
  return jsonb_build_object('saved', true);
end $$;
revoke execute on function public.set_exercise_note(uuid, text, text) from public, anon, authenticated;
grant  execute on function public.set_exercise_note(uuid, text, text) to authenticated;

-- Check: expect  table 1 | rls true | callable true
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'coach_exercise_notes') as "table",
  (select relrowsecurity from pg_class where relname = 'coach_exercise_notes') as rls,
  has_function_privilege('authenticated', 'public.set_exercise_note(uuid,text,text)', 'execute') as callable;
