# SQL journal

Every SQL command handed to the owner, newest at the bottom. **Both Claude accounts read
this at the start of every session.** When SQL is given: add a row with status
`given`. When the owner confirms: change to `run ✓` with the date and the result the
final `select` showed. Never mark `run ✓` without the owner's confirmation.

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
| ≤ 2026-09-19 | many | every `migrations_*.sql` from `schema` to `in_touch_week` (order in HANDOVER.md) | unknown | The live app uses these features daily, so they are almost certainly applied. |
| 2026-09-21 | CT | `migrations_connect_handles.sql` | run ✓ | Handles saving confirmed working after the grant + `set_my_handles` fixes. |
| 2026-09-21 | CT | `grant update/select (whatsapp, instagram, snapchat, last_market_at) on profiles` | run ✓ | Did not fix the save on its own; the cause was the missing function. |
| 2026-09-21 | CT | `create function set_my_handles(...)` | run ✓ | "It worked now." |
| 2026-09-22 | CN-10 | `migrations_end_goal_early.sql` | given | Not confirmed in chat. |
| 2026-09-22 | CY | `migrations_achievements.sql` | run ✓ | Prerequisite of v2, which ran. |
| 2026-09-22 | CY | `migrations_achievements_v2.sql` | run ✓ | catalogue v2: total 27, approved 26. |
| 2026-09-25 | CY | `update achievements set approved = true where code = 'level_up'` | given | Not confirmed. |
| 2026-09-25 | CY | `migrations_achievements_backfill.sql` (first version) | failed | `push_outbox` did not exist yet; whole script rolled back. |
| 2026-09-25 | CY | `migrations_achievements_backfill.sql` (guarded) | run ✓ | backfilled 18, trainees 2. Run once only. |
| 2026-09-25 | CN-11 | `migrations_dismissals.sql` | given | Not confirmed. |
| 2026-09-25 | BW | `migrations_streak_badge.sql` | given | Not confirmed. |
| 2026-09-25 | DI | `migrations_daily_digest.sql` | given | Not confirmed; needs pg_cron. |
| 2026-09-25 | CE | `migrations_push.sql` (trigger-guarded) + `update push_config` with the VAPID public key | run ✓ | `vapid_public | BCtRlTVgGpgn…`. |
| 2026-09-25 | CE | test `insert into push_outbox …` | run ✓ | Notification arrived on Android; status-bar icon was a white box (fixed, DJ). |
| 2026-10-29 | DL | `migrations_payment_tracker.sql` | given | Expected final select: 4, 1. |
| 2026-10-29 | DL | `migrations_payment_way_out.sql` | given | Run after payment_tracker. |
| 2026-10-29 | DK | `pilot_settings.sql` | pending | Run when the pilot starts, with the coaches' emails. Restore statement in the file. |
