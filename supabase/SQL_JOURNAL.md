# SQL journal

Every SQL command handed to the owner, newest at the bottom. **Both Claude accounts read
this at the start of every session.** When SQL is given: add a row with status
`given`. When the owner confirms: change to `run ✓` with the date and the result the
final `select` showed. Never mark `run ✓` without the owner's confirmation.

**Note:** the Supabase SQL editor shows only the LAST statement's result - give one `select` per check.

Statuses: `given` (handed over, not yet confirmed) · `run ✓` (owner confirmed) ·
`pending` (deliberately not run yet) · `unknown` (before this journal; check with the
query below).

## Check what is actually in the database
Run this when a status is `given` or `unknown`; each row says whether that migration's
signature object exists.
```sql
select * from (values
  ('connect_handles',        to_regclass('public.handle_shares') is not null),
  ('connect: set_my_handles',exists (select 1 from pg_proc where proname = 'set_my_handles')),
  ('push',                   to_regclass('public.push_outbox') is not null),
  ('end_goal_early',         exists (select 1 from information_schema.columns where table_schema='public' and table_name='engagements' and column_name='end_kind')),
  ('achievements',           to_regclass('public.user_achievements') is not null),
  ('achievements_v2 (27)',   (select count(*) from public.achievements) = 27),
  ('level_up approved',      exists (select 1 from public.achievements where code='level_up' and approved)),
  ('achievements_backfill',  exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_achievements' and column_name='backfilled')),
  ('dismissals',             to_regclass('public.dismissals') is not null),
  ('streak_badge',           to_regclass('public.streak_badges') is not null),
  ('daily_digest',           to_regclass('public.daily_digest_log') is not null),
  ('daily_digest: pg_cron',  exists (select 1 from pg_extension where extname='pg_cron')),
  ('payment_tracker',        to_regclass('public.coach_payout_details') is not null),
  ('payment_way_out',        exists (select 1 from pg_proc where proname = 'request_payout_details')),
  ('pilot_settings (fees 0)',(select value from public.platform_rates where key='trainee_fee_pct') = 0)
) as t(migration, applied);
```
The two lines that read tables (`achievements_v2`, `level_up`, `pilot_settings`) error
if their table is missing - run the earlier rows first in that case.

## Journal
| Date | Item | SQL | Status | Result / note |
|---|---|---|---|---|
| ≤ 2026-09-19 | many | every `migrations_*.sql` from `schema` to `in_touch_week` (order in HANDOVER.md) | unknown (likely ✓) | The live app uses these features daily, so they are almost certainly applied. |
| 2026-09-21 | CT | `migrations_connect_handles.sql` | run ✓ | Handles saving confirmed working after the grant + `set_my_handles` fixes. |
| 2026-09-21 | CT | `grant update/select (whatsapp, instagram, snapchat, last_market_at) on profiles` | run ✓ | Did not fix the save on its own; the cause was the missing function. |
| 2026-09-21 | CT | `create function set_my_handles(...)` | run ✓ | "It worked now." |
| 2026-09-22 | CN-10 | `migrations_end_goal_early.sql` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-09-22 | CY | `migrations_achievements.sql` | run ✓ | Prerequisite of v2, which ran. |
| 2026-09-22 | CY | `migrations_achievements_v2.sql` | run ✓ | catalogue v2: total 27, approved 26. |
| 2026-09-25 | CY | `update achievements set approved = true where code = 'level_up'` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-09-25 | CY | `migrations_achievements_backfill.sql` (first version) | failed | `push_outbox` did not exist yet; whole script rolled back. |
| 2026-09-25 | CY | `migrations_achievements_backfill.sql` (guarded) | run ✓ | backfilled 18, trainees 2. Run once only. |
| 2026-09-25 | CN-11 | `migrations_dismissals.sql` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-09-25 | BW | `migrations_streak_badge.sql` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-09-25 | DI | `migrations_daily_digest.sql` | run ✓ | Confirmed by the check query 2026-10-29, pg_cron enabled. |
| 2026-09-25 | CE | `migrations_push.sql` (trigger-guarded) + `update push_config` with the VAPID public key | run ✓ | `vapid_public | BCtRlTVgGpgn…`. |
| 2026-09-25 | CE | test `insert into push_outbox …` | run ✓ | Notification arrived on Android; status-bar icon was a white box (fixed, DJ). |
| 2026-10-29 | DL | `migrations_payment_tracker.sql` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-10-29 | DL | `migrations_payment_way_out.sql` | run ✓ | Confirmed by the check query 2026-10-29. |
| 2026-10-29 | DK | `pilot_settings.sql` | run ✓ | Fees 0 (trainee_fee_pct, trainee_fee_min, coach_commission_pct); launch values saved: 5.9 / 1.00 / 11.9. Founding part matched nobody (example emails). **Pilot pricing is live.** |
| 2026-10-29 | journal | the check query above | run ✓ | All 15 rows true, including pilot_settings (fees 0) - unexpected, see DK row. |
| 2026-10-29 | DK | `select key, value from platform_rates where key in (... fee keys and launch_* keys)` + Founding list | run ✓ (partly) | The editor shows only the last statement: Founding = Georgios Politakis since 2026-09-19 (granted before pilot_settings existed). Rates result not seen. |
| 2026-10-29 | DK | the platform_rates select on its own | run ✓ | Six rows - the script ran. |
| 2026-10-29 | DK | Founding grant by the pilot coaches' emails (`update profiles set founding_at …`) | pending | Run once the coaches have signed up. Current Founding: Georgios Politakis (since 2026-09-19). |
| after the pilot | BI | restore launch rates (`update platform_rates … from launch_*`, in pilot_settings.sql) | pending | Only when Stripe is live. |
| 2026-10-29 | DM | `migrations_stripe_checkout.sql` | run ✔ | Confirmed 2026-10-30 by check query (deposit_at exists). |
| 2026-10-29 | DN | push_outbox health query (kind, total, sent, errors) | run ✓ | offer 2/2, review 2/2, 0 errors; **no daily rows**. |
| 2026-10-29 | DN/DI | daily-digest diagnostic (job_active, last_run, last_status, users_with_tz, users_subscribed, digests_logged) | run ✓ | job active, last run 19:15 UTC succeeded; 1 user with tz, 1 subscribed, 0 digests (none due yet). |
| 2026-10-29 | DQ | `migrations_achievements_trigger_fix.sql` | run ✓ | 'goal updates fixed' - the self-test passed. |
| 2026-10-29 | DS | `migrations_journey_fix.sql` | run ✓ | weeks_check = 13. |
| 2026-10-29 | DT | `migrations_body_achievements_recheck.sql` | run ✔ | 2026-10-30: as expected (owner). |
| 2026-10-29 | DU | `migrations_stripe_connect.sql` | run ✔ | 2026-10-30: payments_via_stripe 0, accounts_table 1 (found missing during EG step 1 - the first onboarding attempt could not be recorded). |
| 2026-10-30 | EA/ED | `migrations_stripe_fees.sql` | run ✔ | stripe_rates 5, has_processing 1 (owner confirmed). |
| 2026-10-30 | DY | `migrations_weekly_release.sql` | run ✔ | table 1, job 1, hold 14 (owner). `release-send` deployed (JWT OFF) and the payment_releases webhook (Insert + Update) created. |
| 2026-10-30 | DY test | `update public.platform_rates set value = 0 where key = 'release_hold_days'` (sandbox test only) | run ✔ | Run during EG step 3 (after the diagnostic showed 14); restored to 14 at step 6. |
| 2026-10-30 | DY | `update public.platform_rates set value = 14 where key = 'release_hold_days'` | run ✔ | Hold restored to 14 after EG (owner). |
| 2026-10-30 | EG | delete simulated `week_closures` for Stripe test goals (closed today) | run ✔ | Owner. |
| 2026-10-30 | DZ | `migrations_refunds.sql` | run ✔ | Owner: refunds_table 1, trigger 1, cancelled_allowed 1; `refund-send` deployed (JWT OFF), webhook created. |
| 2026-10-30 | DZ-2 | `migrations_refunds_evidence.sql` | run ✔ | flagged_col 1, window 72 (owner). Superseded by DZ-3 below. |
| 2026-10-30 | DZ-3 | `migrations_refunds_business_days.sql` | run ✔ | ran fine (owner). |
| 2026-10-30 | DY test | simulated `week_closures` insert (this week) + `select public.queue_weekly_releases()` | run ✔ | 1 queued -> sent (tr_...). Rows deleted at step 6. |
| 2026-11-02 | EN | `migrations_first_call_push.sql` | run ✓ (owner reported 2026-11-02; result not shown) | Expected: goals_marked = number of existing goals, triggers = 2. |
| 2026-11-02 | EQ | `migrations_tab_badges.sql` | run ✓ (owner reported 2026-11-02; result not shown) | Expected: seen_column 1, functions 2. |
| 2026-11-02 | ER + DP | `migrations_payouts_prompt_liability_card.sql` | run ✓ | approval_trigger 1, stats_function 1. |
| 2026-11-02 | EK + EL | `migrations_coach_end_goal_fast_reviews.sql` (fixed version: function header on its own line) | run ✓ | functions 6, tables 2, fast_hold_days 7. |
| 2026-11-02 | FC | `migrations_credit_at_checkout.sql` | run ✓ | new_columns 3, functions 5. checkout-create, stripe-webhook, release-send redeployed (owner reported). |
| 2026-11-02 | FJ | `migrations_goal_badge_to_answer.sql` | run ✓ | has_to_answer = true. |
| 2026-11-02 | FD | `migrations_trainees_badge.sql` | run ✓ | has_new_counts = true. |
| 2026-11-02 | FG | `migrations_social_badge.sql` | run ✓ (implied) | The coach checklist migration reads social_seen_at and ran cleanly. |
| 2026-11-02 | FH | `migrations_coach_checklist.sql` | run ✓ | has_coach_counts = true. |
| 2026-11-02 | FH | `migrations_coach_checklist_targets.sql` | run ✓ | has_weekly_calls true, has_targets true. |
| 2026-11-04 | EJ | `migrations_disputes.sql` | run ✓ 2026-11-04 (1 | 7 | 2, as expected) | First run failed: 42601 "unexpected end of function definition" at line 159 - Claude's push-link edit put `);` inside a `--` comment; fixed in the file. Expect `table_ok 1 | functions 7 | triggers 2`. Then redeploy stripe-webhook and add the charge.dispute.* events in Stripe. |
| 2026-11-04 | FO | `migrations_refund_credit_fees.sql` | run ✓ 2026-11-04 (fixed = 2) | Expect `fixed = 2`. queue_refund + queue_end_choice: full-credit goals return the payout-cost share as credit. |
| 2026-11-04 | FO test | one-off: EUR 1,000 test credit to the owner's test trainee (insert into trainee_credits by email; email not recorded - public repo) | run ✓ 2026-11-04 (as expected) | Expect 1 row inserted; balance shown. |
| 2026-11-04 | FP | `migrations_refund_explain.sql` | run ✓ 2026-11-04 (as expected) | Expect `column_ok 1 | functions 3`. |
| 2026-11-04 | FQ | `migrations_ledger_refs.sql` | run ✓ 2026-11-04 (missing 0, unique_indexes 2, sample CR-F34A-FB5F-AF25-A99C) | Expect `missing 0 | unique_indexes 2 | sample CR-xxxx-xxxx-xxxx-xxxx`. |
| 2026-11-04 | FP push | diagnosis (read only): push_outbox rows + push_subscriptions for the test trainee | run (part) | Subscriptions: 1, newest 2026-10-29 19:43 (before the move to formtrace.ie, i.e. the old github.io app), last delivered 2026-11-04 15:48. Outbox rows not yet reported. | Look at result: muted / no subscription / codes / sent_at null. |
| 2026-11-04 | EJ | `migrations_three_ds.sql` | run ✓ 2026-11-04 (checkout-create redeployed by the owner) | Expect `three_ds_min_cents | 0`. Then redeploy checkout-create (Verify JWT ON). |
| 2026-11-04 | FU | one-off: delete push_subscriptions created before 2026-11-02 20:00 UTC (old github.io app) | run ✓ (verified by Claude via Supabase MCP 2026-11-04 23:15: old_left 0) | Expect old_left = 0. |
| 2026-11-04 | FV | `migrations_brand_name.sql` | run ✓ 2026-11-04 (functions_left 0; run without RLS - temp report table; data report: push_outbox.body 11 = already-sent pushes, left as history; platform_rates.note 1) | Expect `functions_left = 0`; report the data list (may be empty). |
| 2026-11-04 | FV | follow-up: platform_rates.note + unsent push_outbox rows -> Formtrace | run ✓ 2026-11-05 (notes_left 0, unsent_left 0) | Expect `notes_left 0 | unsent_left 0`. |
| 2026-11-04 | FP push | test: one refund-style push_outbox row to blisscrank@gmail.com (copy of the FP push) | run ✓ 2026-11-04 23:16 (row 61 sent 23:16:07, error null; owner saw it in Chrome on the phone) | Expect a buzz on the phone; check query shows `sent_at` filled and `error` empty. |
| 2026-11-04 | EJ part 3 | `migrations_dispute_cancels_goal.sql` (applied by Claude via Supabase MCP, migration `dispute_cancels_goal`) | run ✓ 2026-11-04 23:5x (end_kind_ok 1, evidence_fixed 1, open_disputes_on_active_goals 0; rolled-back test: a payout queued for the lost-dispute goal 3wg comes out `cancelled` / "dispute lost - the cardholder got the money back") | Expect `1 | 1 | 0`. |
| 2026-11-05 | EZ-6 | `migrations_exercise_notes.sql` | run ✓ 2026-11-05 (function_ok 1) | Expect `function_ok = 1` (returns no rows in the SQL editor - no signed-in user). |
| 2026-11-05 | EZ-6b | `migrations_exercise_notes_edit.sql` | run ✓ 2026-11-05 (functions_ok 2) | Expect `functions_ok = 2`. |
| 2026-11-10 | GD | `migrations_lock_internal_functions.sql` | run ✓ 2026-11-10 (anon_callable 0, internal_still_open 0, app_functions_locked 0) | Expect `anon_callable 0`, `internal_still_open 0`, `app_functions_locked 0`. Then click through the app (both roles). |
| 2026-11-10 | GE | refund status check (GE): `select status, count(*), min(created_at), max(created_at) from public.payment_refunds group by status` | given (read-only) | To tell whether `refund-send` ever ran: rows stuck at `queued` = never sent. |
| 2026-11-10 | GE | GE-T1 test notification: `insert into push_outbox (to_user, kind, title, body, url) select id, 'offer', 'Formtrace test', ..., '/#listings' from profiles where display_name = ...` + check select | run ✓ 2026-11-10 (row id 76) | Notification arrived on the phone. The check showed sent_at NULL only because it ran in the same instant as the insert. |
| 2026-11-10 | GF | `migrations_handle_rules.sql` | run ✓ 2026-11-10 (results as expected: rules 4) | Expect `rules = 4`; `profiles_to_correct` / `shares_to_correct` ideally 0 (older values the rule would refuse). |
| 2026-11-10 | GG | `migrations_offers_goals_write_lock.sql` | given | Expect `offers_insert 17, offers_update 3, goals_insert 7, goals_update 5, table_level_writes 0, guards 2, missing` empty. Then test every offer / goal flow (GG-T1..T6). |
