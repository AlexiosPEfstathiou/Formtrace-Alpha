# FormTrace Coach — Handover (as of 2026-10-29)

## Session 2026-11-03 (personal account) - summary
- **EH DONE:** mailbox `contact@formtrace.ie` (Titan); owner decision: it is the **only public address** (no aliases) - terms.html and the app's "Contact support" link (`SUPPORT_EMAIL`) use it. DKIM verified, DMARC `p=none` added, Gmail check SPF/DKIM/DMARC PASS. `VAPID_SUBJECT` = `mailto:contact@formtrace.ie`.
- Titan admin panel for Blacknight: https://manage-euc1.titan.email/ (Email Reputation = DKIM).
- Later: DMARC -> `quarantine` after a few weeks; optional Supabase SMTP via Titan.
- **No SQL this session.** Next item code still **FM**.

## Session 2026-11-02 (evening) - summary
- **Domain (EF) DONE:** formtrace.ie live on GitHub Pages with HTTPS enforced (4 A, www CNAME, GitHub TXT at Blacknight; old github.io address redirects). Supabase Site URL + redirect `https://formtrace.ie/**`, `APP_URL` secret, Stripe sandbox website set by the owner. Edge Function defaults (`checkout-create`, `connect-onboard`) now `https://formtrace.ie/` (take effect on next deploy; the secret already applies). Phones: reinstall from formtrace.ie, allow notifications, remove the old icon. The Lilly laptop's Zscaler blocks the new domain - test from the phone.
- **2026-11-03:** first mailbox **`contact@formtrace.ie`** created (Titan). Owner decision: **contact@ is the only public address** (no aliases); terms.html and the app's support link now use it. DKIM verified and DMARC (`p=none`) added 2026-11-03. `VAPID_SUBJECT` set. **EH DONE 19:20:** Gmail Show original - SPF, DKIM, DMARC all PASS. Later only: DMARC -> `quarantine` in a few weeks.
- **Email (EH) IN PROGRESS:** Zoho dropped (no free plan here; Mail Lite demanded a UK phone). **Blacknight Titan Email 5GB bought** (EUR 1.85/month). MX + SPF in the zone; SPF tidied. **Next session: DKIM (Titan admin panel - owner could not find it), DMARC, Gmail test, aliases.** Titan servers for this account (corrected 2026-11-03): SMTP **`smtp0101.titan.email:465` SSL**, IMAP `imap0101.titan.email:993`, POP `pop0101.titan.email:995` (the generic `smtp.titan.email` gave 535 in Supabase).
- **EU rest timer BUILT:** 2:30 after each submitted set; blocks the next set/exercise ("Take a break to rest before the next set"); stopwatch ring depleting clockwise, neon green -> red; no rest after the last set. To do: a per-exercise rest field in the builder (the app already reads `rest_seconds`).
- **FI fix:** "Choose now" (coach-ended goal) opens the credit/refund choice in a panel instead of the Goal tab.
- **Decisions:** no native app until there is a userbase (web-reachable integrations first, ET/FK); living design-assets list `docs/DESIGN_ASSETS.md` is the openart brief (EW) - add a row for every new visual element.
- **No SQL this session.** Next item code still **FM**.

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

## Latest (2026-11-02, Lilly account) - read with "Start here" below
- **formtrace.ie registered**; Blacknight order still *pending* - **EF blocked** (records to
  enter are in the EF entry).
- **Group 1 of the pending list is DONE and live** (all migrations run): EM between-goals
  card · EO payment map per goal · EN first-call push · EQ tab badges · ER pay straight after
  accept + payouts prompt for coaches · DP admin liability card (disputes/losses wait for EJ).
- **Decided:** EK refund fee = costs only · EL = "Reviews within a day" mark + 7-day release.
- **Built:** ES daily checklist on Home (app only) · **EK** coach ends a goal (trainee: credit or costs-only refund; default credit after 14 days) · **EL** "Reviews within a day" mark + 7-day release · **FC** credit used at the next Checkout (payouts credit-first from the balance; refunds return unused credit as credit; deposit_processing/credit now server-only). All migrations run; checkout-create, stripe-webhook, release-send redeployed. **Next: a sandbox test of the credit path.**
- **From the owner's tests (2026-11-02), built:** Goal tab - Answer-offers button, lands on Offers, refresh on return, badge = offers to answer (FJ) · checklist re-drawn after saving (FE) · coach-ended goal card in Notifications (FI) · weekly workout line + I'll take a rest day (FF) · Slept 8 hours first · coach Trainees badge = to assign + to review, Offer accepted / N to assign + glisten (FD). **Since then (all migrations run):** badges on every tab - Social (requests to answer + friends' new achievements + congratulations), Home (coach checklist items not done) · Trainees list: red = to assign this week, green = to review · **coach daily checklist** on Home (reviews, assign, counter-offers, weekly calls per trainee, calorie goals, payouts, open goals); tapping review / assign / calls / calorie goals opens the next trainee who needs it; calls item runs a walkthrough (this week's days glisten, then Propose a call) · Trainee activity rows open the goal page only.
- Owner skipped group 2 (owner tasks) for now; working through the backlog next.
- Logged: FA renewal reminder 30 Sep 2027 · FB management calendar (later).
- Always check the log's highest item code before allocating (both accounts write items).
## Start here next session (refreshed 2026-10-30 night, Lilly account)
**EG PASSED in the sandbox (2026-10-30 night):** coach onboarding (IE Express, transfers-only,
standard agreement), deposit with the EA line, weekly release (Transfer), refund (partial Refund,
trainee_stopped rule), free code. Hold back to 14. **Tooling: the owner connected the official
Supabase MCP connector on the PERSONAL Claude account** - from there Claude can run SQL and
deploy Edge Functions directly (still journal every statement; the Lilly account cannot use it).
**Stripe settings DONE (owner, 2026-10-30 18:19, personal account):** Adaptive Pricing off and
payment methods = cards + Apple Pay + Google Pay (Link optional) in sandbox **and** live; live code
`ALHATEST` deleted. `checkout-create` sets no payment methods in code - the Dashboard governs
(optional hardening offered: `payment_method_types: ['card']`). **Next (C):** EO (map
variant per goal), EM, EN, EQ, ER small items; **DP**; then **DW** live keys -> live EG with the
ED code -> **EB**. EF still waits for formtrace.ie to resolve; DX terms need the lawyer.
**Earlier on 2026-10-30:**
**2026-10-30 evening - the escrow loop is complete in code and deployed in the sandbox:** EA
(processing line), ED (free code, webhook), **DY** (weekly releases: `payment_releases`, cron 09:10
UTC, `release-send` + webhook), **DZ** (refunds: `payment_refunds`, trigger on ended, `refund-send`
+ webhook; evidence rule = submitted session unreviewed past **5 business days**; released weeks
are **final**; flagged rows for the owner). All migrations run (journal). `release_hold_days` is
**0 in the sandbox** - restore to 14 before go-live. Terms updated. New items: EI bank account,
EJ chargeback risk, EK coach-ends-goal (fee TBD), EL early review incentive (decision pending).
**Next: owner does EC (deploy `connect-onboard`, Connect branding, onboard the test coach), then
walks `docs/EG_TEST.md`.** Claude: fix the EG findings, then EK / EL once decided, DP, DW, EB.
EF (domain) still waits for formtrace.ie to resolve.
**Earlier today:**
**2026-10-30:** **EE decided and bought - ormtrace.ie at Blacknight** (1 yr EUR 5.99,
renewal ~EUR 28; registry Ireland-connection check pending - the name did not resolve in DNS
as of midday). **EF postponed by the owner until registration completes**; the step list
(GitHub Pages custom domain, Blacknight A/AAAA/CNAME, Supabase Site URL + redirect URLs +
APP_URL secret, Enforce HTTPS, Stripe public details) is in the chat and in EF; the app
needs **no code change** (all paths relative; EF verified). **EH** logged: Zoho Mail on the
domain. **DX drafted:** 	erms.html (ToS + Privacy Notice, 28 bracketed items for
owner/lawyer); not yet linked from the app, Stripe consent still off. formtrace.com declined
(premium ~EUR 6k), .app taken, GoDaddy dropped. Next: EF when DNS resolves; ED + EA; link
terms.html from the consent screen and Profile.
**Earlier (end of 2026-10-29):**
**The pending work is IN ORDER at the top of `PRODUCT_LOG.md` ("PENDING - IN ORDER").**
Begin with section A: **DV** outside-activity check → **BJ** name → **EE** buy the domain →
**EF** point it at GitHub / Supabase / Stripe → **DX** Terms page → the three pending
migrations → the Stripe sandbox setup in STRIPE_INTEGRATION_TODO.md.
State at close: the pilot uses **Stripe escrow** (DU; supersedes DK's direct route); the
switch `payments_via_stripe` is **0**; Checkout deposit and coach onboarding are built for
the sandbox but not yet deployed or tested; EA (trainee pays Stripe costs, rounded up to
the whole euro) is decided, not built; DY / DZ / ED not built. BI prerequisites settled.
Tonight's fixes, already verified: goal completion (DQ), the journey recap (DR, DS);
awaiting the owner's migration run: weight plausibility and body-achievement re-check (DT).
## Recent fixes (2026-10-29) - re-test these
- **DQ:** an achievement trigger had blocked every goal status / level change since
  2026-09-22 (ending, completing, cancelling a goal; raising a level). Fixed and verified;
  all side-effect triggers now catch their own errors. Re-do any level raise from the
  last five weeks that did not stick.
- **DR:** the journey recap after completing a goal called a misnamed store function.
  Fixed; new gate check `tools/store-check.mjs` (gate is now four parts).
- BI prerequisite 1 (loss liability) done: Connect onboarding complete. Liability review
  triggers proposed in **DP** (owner to confirm the numbers).
## Push status (2026-10-29)
- Delivery healthy (DN): 4/4 sent, 0 errors. Only **one** user had push on → **DO**
  built: push on by default (silent if allowed, one explained prompt, sticky opt-out).
- Morning summary (DI): job active and succeeding every 15 min; none sent yet because
  timezones are recorded only since today - first send expected next morning ~08:00.
  Pending check: the user with a timezone is the one with push on (query given).
- DN code comparison waits for the owner to paste the deployed push-send code.
## Open decisions (owner)
- **Decided 2026-11-02: no native app until FormTrace has a userbase.** It stays a web app (PWA); integrations that need a native app (Apple Health, Health Connect) wait - explore web-reachable routes first (brand cloud APIs, aggregators, OAuth account linking).
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
