-- HH (owner, 2026-11-20): completing every task on the trainee's daily checklist pays a 10-point bonus, once per local day.
-- Called by the app when the checklist reaches "Day complete". Some tasks are ticked on the phone only (sleep, calorie
-- budget, rest day), so the server checks what it can: the day must be today in the trainee's time zone, today's weight
-- and yesterday's macros must be logged, and the reference is unique per person per day (no double pay). Safe to re-run.
create or replace function public.claim_daily_bonus(p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_tz text; v_today date; v_paid boolean := false; v_bal bigint; v_pts int := 10;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(nullif(tz, ''), 'Europe/Dublin') into v_tz from public.profiles where id = uid;
  v_today := (now() at time zone coalesce(v_tz, 'Europe/Dublin'))::date;
  if p_day is distinct from v_today then raise exception 'only today''s checklist can be claimed'; end if;
  if not exists (select 1 from public.logs where trainee_id = uid and log_date = v_today and weight_kg is not null)
     or not exists (select 1 from public.logs where trainee_id = uid and log_date = v_today - 1 and (kcal is not null or protein_g is not null)) then
    raise exception 'the checklist is not complete';
  end if;
  insert into public.points_ledger (user_id, amount, reason, ref)
  values (uid, v_pts, 'Daily checklist complete', 'daily:all:' || uid || ':' || v_today)
  on conflict (ref) do nothing;
  v_paid := found;
  select coalesce(sum(amount), 0) into v_bal from public.points_ledger where user_id = uid;
  return jsonb_build_object('paid', v_paid, 'points', case when v_paid then v_pts else 0 end, 'balance', v_bal);
end $$;
revoke execute on function public.claim_daily_bonus(date) from public, anon, authenticated;
grant  execute on function public.claim_daily_bonus(date) to authenticated;

-- Check: expect  callable true
select has_function_privilege('authenticated', 'public.claim_daily_bonus(date)', 'execute') as callable;
