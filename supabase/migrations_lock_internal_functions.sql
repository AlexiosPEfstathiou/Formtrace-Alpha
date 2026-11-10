-- Item GD (security review 2026-11-10): lock the internal database functions.
-- Most earlier migrations wrote "revoke execute ... from public". On Supabase the anon and authenticated roles hold their
-- own grants, so that locked nothing: internal SECURITY DEFINER functions stayed callable from outside (confirmed on the
-- live database 2026-11-10). This migration, for EVERY security-definer function in the public schema:
--   1) revokes execute from public, anon and authenticated;
--   2) grants it back to authenticated only for the functions the app calls (or that row-level-security policies use);
--   3) keeps service_role (Edge Functions). The owner (cron jobs, the SQL editor) is unaffected.
-- Functions that are NOT security definer are left alone: they run with the caller's own rights.
-- anon (not signed in) gets nothing: the landing page calls no function.
-- Rule from now on (CLAUDE.md): every revoke names "public, anon, authenticated"; app-facing functions get an explicit
-- "grant execute ... to authenticated". Safe to re-run - also re-run it after adding functions, as a safety net (a new
-- app-facing function must be added to the list below, or granted in its own migration AFTER this file is re-run).
do $$
declare
  r record;
  keep text[] := array[
    'ack_goal_end', 'ack_postpone', 'admin_coach_activity', 'admin_coach_inactivity', 'admin_dispute_evidence',
    'admin_disputes', 'admin_liability_stats', 'admin_review_certification', 'admin_set_badges', 'approve_coach_application',
    'are_connected', 'cancel_postpone', 'check_achievements', 'choose_goal_end', 'claim_referral',
    'close_weeks_due', 'coach_end_goal', 'coach_payment_summary', 'coach_public_profile', 'coach_todo_targets',
    'confirm_connection', 'confirm_received', 'confirm_refund_received', 'congratulate', 'congratulate_all',
    'connect_by_token', 'counter_offer', 'decide_postpone', 'delete_my_account', 'edit_exercise_note',
    'effective_rates', 'end_goal_early', 'end_pause', 'end_pause_all_mine', 'exercise_notes',
    'expire_counters', 'expire_listings', 'fast_reviewer_coaches', 'fill_wildcard_slot', 'in_touch_feed',
    'is_admin', 'issue_connect_token', 'journey_summary', 'mark_my_offers_seen', 'mark_paid',
    'mark_refund_sent', 'mark_reviewed', 'mark_social_seen', 'mark_streak_badge_seen', 'mark_submitted',
    'my_active_pauses', 'my_data_summary', 'my_macro_goal', 'my_personal_bests', 'my_tab_badges',
    'personal_bests_in_range', 'propose_call', 'recompute_personal_best', 'referral_stats', 'refresh_coach_streak_scores',
    'refresh_my_streak', 'refresh_my_week_streak', 'register_knock', 'request_payout_details', 'request_postpone',
    'reschedule_for_streak', 'respond_counter', 'respond_to_call_proposal', 'revoke_handle', 'set_call_meeting_url',
    'set_call_tz', 'set_due_date', 'set_my_handles', 'set_my_payout_details', 'set_my_tz',
    'set_push_prefs', 'share_handle', 'skip_wildcard_slot', 'start_pause', 'start_pause_all',
    'start_pause_all_mine', 'start_session'
  ];
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef and p.prokind = 'f'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')   -- not an extension's function
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
    if r.proname = any(keep) then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;

-- Check: expect  anon_callable = 0 | internal_still_open = 0 | app_functions_locked = 0
with f as (
  select p.oid, p.proname, (p.prorettype = 'trigger'::regtype) as is_trigger,
         has_function_privilege('anon', p.oid, 'execute') as anon_ok,
         has_function_privilege('authenticated', p.oid, 'execute') as user_ok
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef and p.prokind = 'f'
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
), k(name) as (select unnest(array[
    'ack_goal_end', 'ack_postpone', 'admin_coach_activity', 'admin_coach_inactivity', 'admin_dispute_evidence',
    'admin_disputes', 'admin_liability_stats', 'admin_review_certification', 'admin_set_badges', 'approve_coach_application',
    'are_connected', 'cancel_postpone', 'check_achievements', 'choose_goal_end', 'claim_referral',
    'close_weeks_due', 'coach_end_goal', 'coach_payment_summary', 'coach_public_profile', 'coach_todo_targets',
    'confirm_connection', 'confirm_received', 'confirm_refund_received', 'congratulate', 'congratulate_all',
    'connect_by_token', 'counter_offer', 'decide_postpone', 'delete_my_account', 'edit_exercise_note',
    'effective_rates', 'end_goal_early', 'end_pause', 'end_pause_all_mine', 'exercise_notes',
    'expire_counters', 'expire_listings', 'fast_reviewer_coaches', 'fill_wildcard_slot', 'in_touch_feed',
    'is_admin', 'issue_connect_token', 'journey_summary', 'mark_my_offers_seen', 'mark_paid',
    'mark_refund_sent', 'mark_reviewed', 'mark_social_seen', 'mark_streak_badge_seen', 'mark_submitted',
    'my_active_pauses', 'my_data_summary', 'my_macro_goal', 'my_personal_bests', 'my_tab_badges',
    'personal_bests_in_range', 'propose_call', 'recompute_personal_best', 'referral_stats', 'refresh_coach_streak_scores',
    'refresh_my_streak', 'refresh_my_week_streak', 'register_knock', 'request_payout_details', 'request_postpone',
    'reschedule_for_streak', 'respond_counter', 'respond_to_call_proposal', 'revoke_handle', 'set_call_meeting_url',
    'set_call_tz', 'set_due_date', 'set_my_handles', 'set_my_payout_details', 'set_my_tz',
    'set_push_prefs', 'share_handle', 'skip_wildcard_slot', 'start_pause', 'start_pause_all',
    'start_pause_all_mine', 'start_session'
  ]))
select (select count(*) from f where anon_ok)                                                          as anon_callable,
       (select count(*) from f where user_ok and proname not in (select name from k))                  as internal_still_open,
       (select count(*) from k where exists (select 1 from f where f.proname = k.name and not f.user_ok)) as app_functions_locked;