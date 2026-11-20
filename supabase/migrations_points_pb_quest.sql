-- GZ (owner, 2026-11-20): the first weekly quest - "Personal Bests this week" (3 per week, Monday 00:00 in the trainee's
-- time zone) - and the points ledger it pays into. Owner decisions: 10 points for completing it (for now - a combined
-- daily / weekly / monthly reward system is HA); a first record of an exercise counts as a personal best.
-- Points are written only by the server (security definer); users can read their own. Safe to re-run.

create table if not exists public.points_ledger (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  amount     integer not null,
  reason     text not null,
  ref        text not null unique,          -- one award per reference, e.g. quest:pb3:<user>:<week>
  created_at timestamptz not null default now()
);
create index if not exists points_ledger_user_idx on public.points_ledger (user_id, created_at desc);
alter table public.points_ledger enable row level security;
drop policy if exists "own points" on public.points_ledger;
create policy "own points" on public.points_ledger for select using (user_id = auth.uid());
revoke all on public.points_ledger from anon, authenticated;
grant select on public.points_ledger to authenticated;

-- every personal best as an event (personal_bests keeps only the current best per exercise)
create table if not exists public.pb_events (
  id           uuid primary key default gen_random_uuid(),
  trainee_id   uuid not null references auth.users(id) on delete cascade,
  exercise_key text not null,
  reps         integer,
  weight_kg    numeric,
  first_record boolean not null default false,
  week_start   date not null,
  created_at   timestamptz not null default now()
);
create index if not exists pb_events_week_idx on public.pb_events (trainee_id, week_start);
alter table public.pb_events enable row level security;
drop policy if exists "own pb events" on public.pb_events;
create policy "own pb events" on public.pb_events for select using (trainee_id = auth.uid());
revoke all on public.pb_events from anon, authenticated;
grant select on public.pb_events to authenticated;

-- one quest step: record the event, count this week's personal bests, pay 10 points on the 3rd (once per week)
create or replace function public._pb_quest_step(p_uid uuid, p_key text, p_reps integer, p_weight numeric, p_first boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_tz text; v_week date; v_after int; v_paid boolean := false; v_bal bigint; v_goal int := 3; v_pts int := 10;
begin
  select coalesce(nullif(tz, ''), 'Europe/Dublin') into v_tz from public.profiles where id = p_uid;
  v_week := date_trunc('week', now() at time zone coalesce(v_tz, 'Europe/Dublin'))::date;   -- Monday, local
  insert into public.pb_events (trainee_id, exercise_key, reps, weight_kg, first_record, week_start)
  values (p_uid, p_key, p_reps, p_weight, coalesce(p_first, false), v_week);
  select count(*) into v_after from public.pb_events where trainee_id = p_uid and week_start = v_week;
  if v_after = v_goal then
    insert into public.points_ledger (user_id, amount, reason, ref)
    values (p_uid, v_pts, 'Weekly quest: 3 personal bests', 'quest:pb3:' || p_uid || ':' || v_week)
    on conflict (ref) do nothing;
    v_paid := found;
  end if;
  select coalesce(sum(amount), 0) into v_bal from public.points_ledger where user_id = p_uid;
  return jsonb_build_object('name', 'Personal Bests this week', 'before', v_after - 1, 'after', v_after, 'goal', v_goal,
                            'completed', v_paid, 'points', case when v_paid then v_pts else 0 end, 'balance', v_bal);
end $$;
revoke execute on function public._pb_quest_step(uuid, text, integer, numeric, boolean) from public, anon, authenticated;

-- personal best as before, plus the quest step (a quest failure never stops the personal best - rule 7)
create or replace function public.recompute_personal_best(p_exercise_name text, p_reps integer, p_weight_kg numeric, p_assigned_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  key text := lower(btrim(p_exercise_name));
  cur record; reps_up boolean; weight_up boolean; weight_same boolean; out jsonb; q jsonb; v_first boolean := false;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_exercise_name is null or btrim(p_exercise_name) = '' then raise exception 'exercise name required'; end if;
  if p_reps is null or p_reps < 0 then raise exception 'invalid rep count'; end if;

  select * into cur from public.personal_bests where trainee_id = uid and exercise_key = key;

  if cur.id is null then
    insert into public.personal_bests (trainee_id, exercise_key, exercise_name, reps, weight_kg, assigned_id)
    values (uid, key, btrim(p_exercise_name), p_reps, p_weight_kg, p_assigned_id)
    returning to_jsonb(personal_bests.*) into out;
    v_first := true;
  else
    reps_up     := p_reps > cur.reps;
    weight_same := coalesce(p_weight_kg, 0) = coalesce(cur.weight_kg, 0);
    weight_up   := coalesce(p_weight_kg, 0) > coalesce(cur.weight_kg, 0);
    if (reps_up and (weight_same or weight_up)) or (p_reps = cur.reps and weight_up) then
      update public.personal_bests
         set reps = p_reps, weight_kg = p_weight_kg, exercise_name = btrim(p_exercise_name),
             assigned_id = p_assigned_id, achieved_at = now()
       where id = cur.id
       returning to_jsonb(personal_bests.*) into out;
    else
      return null;
    end if;
  end if;

  begin
    q := public._pb_quest_step(uid, key, p_reps, p_weight_kg, v_first);
    out := out || jsonb_build_object('quest', q);
  exception when others then
    raise warning 'pb quest skipped: %', sqlerrm;
  end;
  return out;
end $$;

-- Check: expect  tables 2 | rls 2 | step_internal true | pb_callable true
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('points_ledger', 'pb_events')) as tables,
  (select count(*) from pg_class where relname in ('points_ledger', 'pb_events') and relrowsecurity) as rls,
  not has_function_privilege('authenticated', 'public._pb_quest_step(uuid,text,integer,numeric,boolean)', 'execute') as step_internal,
  has_function_privilege('authenticated', 'public.recompute_personal_best(text,integer,numeric,uuid)', 'execute') as pb_callable;
