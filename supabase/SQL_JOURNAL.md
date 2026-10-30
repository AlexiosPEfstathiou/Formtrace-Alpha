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
| 2026-10-29 | DM | `migrations_stripe_checkout.sql` | given | Expected final select: 6. |
| 2026-10-29 | DN | push_outbox health query (kind, total, sent, errors) | run ✓ | offer 2/2, review 2/2, 0 errors; **no daily rows**. |
| 2026-10-29 | DN/DI | daily-digest diagnostic (job_active, last_run, last_status, users_with_tz, users_subscribed, digests_logged) | run ✓ | job active, last run 19:15 UTC succeeded; 1 user with tz, 1 subscribed, 0 digests (none due yet). |
| 2026-10-29 | DQ | `migrations_achievements_trigger_fix.sql` | run ✓ | 'goal updates fixed' - the self-test passed. |
| 2026-10-29 | DS | `migrations_journey_fix.sql` | run ✓ | weeks_check = 13. |
| 2026-10-29 | DT | `migrations_body_achievements_recheck.sql` | given | Final select lists each holder of Bulk up / Weight cut; removed = 1 for the 1600 kg case. |
| 2026-10-29 | DU | `migrations_stripe_connect.sql` | given | Expected: payments_via_stripe 0, accounts_table 1. |
| 2026-10-30 | EA/ED | `migrations_stripe_fees.sql` | run ✔ | stripe_rates 5, has_processing 1 (owner confirmed). |
| 2026-10-30 | DY | `migrations_weekly_release.sql` | run ✔ | table 1, job 1, hold 14 (owner). `release-send` deployed (JWT OFF) and the payment_releases webhook (Insert + Update) created. |
| 2026-10-30 | DY test | `update public.platform_rates set value = 0 where key = 'release_hold_days'` (sandbox test only; restore to 14 after EG) | given | Expected: UPDATE 1. |
