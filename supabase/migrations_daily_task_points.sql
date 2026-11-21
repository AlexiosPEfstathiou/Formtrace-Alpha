-- HJ (owner, 2026-11-21): every trainee daily task pays points when it is completed, once per task per local day.
-- Owner's points: Open Formtrace 1 · Slept 8 hours 2 · See today's calorie budget 2 · Weigh yourself 3 ·
-- Log yesterday's macros 5 · Workout done today 10 (or a rest day / week already complete 3). The all-done bonus (10)
-- stays in claim_daily_bonus (HH). The server checks what it can see: the day must be today in the trainee's time zone;
-- weigh = today's weight logged; macros = yesterday's macros logged; workout = a set submitted today. Sleep, budget,
-- opening the app and a rest day are ticked on the phone and cannot be checked. Workout and rest share one reference,
-- so a day pays one or the other. Safe to re-run.
create or replace function public.claim_daily_task(p_task text, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_tz text; v_today date; v_pts int; v_key text; v_paid boolean := false; v_bal bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(nullif(tz, ''), 'Europe/Dublin') into v_tz from public.profiles where id = uid;
  v_today := (now() at time zone coalesce(v_tz, 'Europe/Dublin'))::date;
  if p_day is distinct from v_today then raise exception 'only today''s tasks can be claimed'; end if;
  v_pts := case p_task when 'login' then 1 when 'sleep' then 2 when 'budget' then 2 when 'weigh' then 3
                       when 'macros' then 5 when 'workout' then 10 when 'rest' then 3 else null end;
  if v_pts is null then raise exception 'unknown task'; end if;
  v_key := case when p_task in ('workout', 'rest') then 'workout' else p_task end;
  if p_task = 'weigh' and not exists (select 1 from public.logs where trainee_id = uid and log_date = v_today and weight_kg is not null) then
    raise exception 'no weight logged today'; end if;
  if p_task = 'macros' and not exists (select 1 from public.logs where trainee_id = uid and log_date = v_today - 1 and (kcal is not null or protein_g is not null)) then
    raise exception 'yesterday''s macros are not logged'; end if;
  if p_task = 'workout' and not exists (select 1 from public.submissions where trainee_id = uid
       and (created_at at time zone coalesce(v_tz, 'Europe/Dublin'))::date = v_today) then
    raise exception 'no workout recorded today'; end if;
  insert into public.points_ledger (user_id, amount, reason, ref)
  values (uid, v_pts,
          'Daily task: ' || case v_key when 'login' then 'opened Formtrace' when 'sleep' then 'slept 8 hours' when 'budget' then 'saw the calorie budget'
                                       when 'weigh' then 'weighed in' when 'macros' then 'logged macros'
                                       else case p_task when 'rest' then 'rest day' else 'workout' end end,
          'daily:' || v_key || ':' || uid || ':' || v_today)
  on conflict (ref) do nothing;
  v_paid := found;
  select coalesce(sum(amount), 0) into v_bal from public.points_ledger where user_id = uid;
  return jsonb_build_object('task', p_task, 'paid', v_paid, 'points', case when v_paid then v_pts else 0 end, 'balance', v_bal);
end $$;
revoke execute on function public.claim_daily_task(text, date) from public, anon, authenticated;
grant  execute on function public.claim_daily_task(text, date) to authenticated;

-- Check: expect  callable true
select has_function_privilege('authenticated', 'public.claim_daily_task(text,date)', 'execute') as callable;
