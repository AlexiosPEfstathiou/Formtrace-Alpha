# FormTrace Coach — Handover (as of 2026-10-29)

Written so any Claude session (or person) can continue without the original chat.
Refreshed every 5 owner prompts (see the session routine in `CLAUDE.md`).
Working rules: `CLAUDE.md`. Full history and every decision: `PRODUCT_LOG.md`.

## Where things stand
The app is **ready for a closed pilot**. Built and live: goals, offers, counter-offers,
acceptance, workout builder v2 (library in the builder, drag and drop, templates),
levels, recording, coach review with voice-over and drawing, check-ins (body-fitting
crop), macros/weight/measurements, streaks and the Consistency badge, achievements,
In Touch (knock to connect, congratulations, shared handles), referral by QR,
ending a goal early with reasons and surveys, forgot password, **push notifications
(live)** including a **morning summary at ~08:00 local time**, and the **pilot
payment tracker**.

**Not built: real payments (BI).** Stripe sandbox opened and integration plan made
(2026-10-29, PRODUCT_LOG "BI plan"); **build on hold** until three owner prerequisites
are done (loss liability, VAT advice, coach countries).

## The plan now — the coach pilot (PRODUCT_LOG DK, DL)
- 3–5 coaches in a group chat agree to pitch to every trainee goal for 4–6 weeks.
  Invitation drafted (see the chat or rewrite from DK).
- **Trainees pay a reduced pilot price, directly to the coach** (bank transfer /
  Revolut / PayPal). One price agreed with the coaches together — no bidding war.
- **Platform fee 0% during the pilot** (`supabase/pilot_settings.sql`; launch values
  saved as `launch_*` rows, restore statement in the file).
- Incentive: **Founding badge = 0% platform commission for life** (BQ). Keep the group
  small. Granted by email in `pilot_settings.sql` (no admin button).
- Before inviting: owner walks `docs/TEST_DAY.md` (v2) on two phones; the trainee joins
  through the coach's referral QR.
- In parallel: create the Stripe account so verification is done by the pilot's end.

## The payment model (owner decision — do not drift from it)
**Escrow.** FormTrace receives the trainee's payment as a **deposit**, **releases it to
the coach as the service is delivered**, or **refunds the trainee** if it was not.
Tracking is an **order-tracking steps map** (Accepted → Deposit → Paid → Training week
k of n → Complete; early end → Refund). In the pilot there is no escrow: the Deposit
step is drawn **skipped** ("paid directly to the coach") until `STRIPE_LIVE=true`.
The real implementation is Stripe Connect (BI). Pilot refund rule is provisional, in
one constant `PILOT_REFUND_REASONS` — change it to the agreed pilot terms.

## Stripe status (refreshed 2026-10-29 evening, Lilly account)
- Account and sandbox ready. Checkout Studio configured (PRODUCT_LOG **DM**). Plan:
  PRODUCT_LOG **BI plan**. **Hold lifted for sandbox-only work** (owner); ToS consent
  off until a Terms page exists.
- **DM part 2 BUILT (sandbox):** `checkout-create` + `stripe-webhook` Edge Functions,
  `migrations_stripe_checkout.sql` (journal: given), test-only "Pay by card" button
  (`?stripetest=1`). **Owner setup in progress:** deploy both functions (webhook with
  Verify JWT OFF), Stripe webhook endpoint, secrets `STRIPE_SECRET_KEY` and
  `STRIPE_WEBHOOK_SECRET` - steps in **`STRIPE_INTEGRATION_TODO.md`** (single source
  of truth). Then the first test payment.
- BI prerequisite 1 (loss liability) **set** 2026-10-29: Connect platform setup = buyers
  purchase from FormTrace, sellers paid individually, hosted onboarding, Express
  Dashboard, platform responsible for refunds/chargebacks (onboarding shown complete,
  Connect Platform Agreement accepted). Still open: **VAT advice**, **coach countries**.
- Next DM parts: coach onboarding (Connect Express), weekly release, refunds; fix the
  offer copy "per week reviewed, never a lump sum" before live.

## Push status (2026-10-29)
- Delivery healthy (DN): 4/4 sent, 0 errors. Only **one** user had push on → **DO**
  built: push on by default (silent if allowed, one explained prompt, sticky opt-out).
- Morning summary (DI): job active and succeeding every 15 min; none sent yet because
  timezones are recorded only since today - first send expected next morning ~08:00.
  Pending check: the user with a timezone is the one with push on (query given).
- DN code comparison waits for the owner to paste the deployed push-send code.
## Open decisions (owner)
- Pilot price, period and early-ending rule — to agree with the coaches.
- Streak rewards: 12-month reward TBD; cap on the €5 monthly credit (BW economics note).
- Branding / name (BJ) — final mark replaces `badge-96.png` and the placeholder colours.
- DE equipment tag (low priority).

## Blocked / waiting
| Item | On |
|---|---|
| BI payments (and BL, BR, BS, vouchers, fee discounts) | on hold: loss liability accepted, VAT advice, coach countries |
| CX iPhone install | no iPhone to test on |
| BJ branding | name shortlist |
| CZ scalable achievement tiers | a month of live data |
| DC custom SMTP | postponed — ≤30 users for three months |

## Infrastructure
- **Repo:** `AlexiosPEfstathiou/Formtrace-Alpha` (public), branch `main` → GitHub Pages
  `https://alexiospefstathiou.github.io/Formtrace-Alpha/`. Deploy = push; verify by
  fetching the live page with a cache-busting query and checking for the new code.
- **Supabase:** Auth (email + password; redirect URL = the Pages URL), Postgres with
  RLS everywhere, Storage for videos/photos, **Edge Function `push-send`**
  (`supabase/functions/push-send/index.ts`; secrets VAPID_PUBLIC_KEY,
  VAPID_PRIVATE_KEY, VAPID_SUBJECT), **Database Webhook** `push_outbox_send` on
  INSERT into `push_outbox`, **pg_cron** job `formtrace-daily-digest` every 15 min.
- **Push:** triggers compose rows in `push_outbox`; the webhook calls `push-send`. Setup
  guide: `docs/PUSH_SETUP.md`. VAPID public key is in `push_config`.
- **Secrets:** the VAPID private key was generated on the owner's Lilly laptop into
  `C:\Users\L004281\formtrace-vapid-keys.txt` — move it to a personal password manager
  and delete the file. It also lives in the Edge Function secrets.
- **Rates:** `platform_rates` (fees, commissions, streak grace) — editable without a
  deploy.

## SQL status
**What has actually been run is in `supabase/SQL_JOURNAL.md`** (with a query that
checks the database). As of 2026-10-29 every migration is confirmed applied, and
`pilot_settings.sql` has run: **pilot pricing (0% fees) is live**, launch rates saved
for the restore. Open: grant Founding to the pilot coaches by email once they sign up
(only Georgios Politakis holds it today).

## Migrations — run order
All in `supabase/`, run in the SQL editor in this order (each is idempotent):
schema · streak · grading · measurements · setweight · postpone · account_deletion ·
storage_access · consent_age · profile_privacy · postpone_enforce · error_log ·
status_enforce · streak_localdate · postpone_notify · streak_redefine · milestones ·
video_rotation · coach_profiles · muscle_groups · age_public · payment_ledger ·
payment_ledger_v2 · offer_decline_seen · listing_cancel · journey · streak_reschedule ·
appearance_sync · personal_bests · form_tags · languages · vacation ·
vacation_trainee_bulk · admin_inactivity · exercises_trainee_read · wildcard_fill ·
workout_skip · interval_exercises · scheduled_calls · default_interval_exercise ·
week_model · week_start_trigger · calendar_rows · start_session · offer_cap_backfill ·
macro_goals · snapshot_lite · open_goals_hygiene · propose_any_time · recurring_calls ·
committed_length · video_trim · referrals · founding · call_meeting_url ·
offer_start_date · badges · cert_seen · referral_trainees_only · top1 ·
platform_rates · goal_feedback · exit_survey · direct_offers · counter_offers ·
counter_guard · coach_activity · streak_grace · workout_levels · in_touch ·
in_touch_fix · in_touch_feed_since · in_touch_profiles · call_tz · in_touch_week ·
connect_handles · push · end_goal_early · achievements · achievements_v2 ·
achievements_backfill (once) · dismissals · streak_badge · daily_digest ·
payment_tracker · payment_way_out — then `pilot_settings.sql` when the pilot starts.
(`schema.sql` first; names above omit the `migrations_` prefix. `diagnostic_*` files
are read-only checks.) Also: `update public.achievements set approved = true where
code = 'level_up';`

## Moving off the Lilly machine
This is a personal project. It has been built on a Lilly laptop with Lilly's Claude
account; continue on a personal computer and personal Claude account, and check
Lilly's outside-activity guidance before the pilot takes money. On a personal
machine: clone the repo, install Node (any LTS), run the three checks in `CLAUDE.md`,
and work with Claude Code in the repo folder — it reads `CLAUDE.md` automatically.
No Artifactory constraint applies there.

## Next code items once the pilot is running
1. Lock / prefill pitch prices to the agreed pilot price (DK, optional).
2. Change `PILOT_REFUND_REASONS` to the agreed terms.
3. BI: Stripe Connect escrow — deposit, weekly releases, refunds; then flip
   `STRIPE_LIVE`, restore the launch rates, enable vouchers (BW) and the voucher QR (DG).
