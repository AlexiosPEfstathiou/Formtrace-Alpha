-- IB-2 (owner rule 2026-11-23: rewards are claimed, never auto-paid). Weekly quests no longer pay inside
-- weekly_quests_sync; a done quest is paid only when the trainee taps "Claim +N" (claim_weekly_quest). The sync
-- still reports done / paid. The coach's per-trainee "streaks" quest is unchanged. Safe to re-run.
do $$ declare d text; begin
  select pg_get_functiondef('public.weekly_quests_sync()'::regprocedure) into d;
  if position('ft.quest_claim' in d) = 0 then
    d := replace(d, 'if (x->>''done'')::boolean then', 'if (x->>''done'')::boolean and (x->>''key'') = coalesce(current_setting(''ft.quest_claim'', true), '''') then');
    if position('ft.quest_claim' in d) = 0 then raise exception 'anchor not found in weekly_quests_sync'; end if;
    execute d;
  end if;
end $$;

create or replace function public.claim_weekly_quest(p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  perform set_config('ft.quest_claim', coalesce(p_key, ''), true);
  return public.weekly_quests_sync();
end $$;
revoke execute on function public.claim_weekly_quest(text) from public, anon, authenticated;
grant execute on function public.claim_weekly_quest(text) to authenticated;

select position('ft.quest_claim' in pg_get_functiondef('public.weekly_quests_sync()'::regprocedure)) > 0 as sync_waits_for_claim,
       to_regprocedure('public.claim_weekly_quest(text)') is not null as claim_fn;
