# EG – Sandbox test of the whole escrow loop (deposit → release → refund → free code)

Written 2026-10-30. Walk it on two phones (coach + trainee) and a laptop with Stripe and
Supabase open. Everything is **Stripe sandbox**; no real money. Tick each check; if one
fails, stop and report the step number and what you saw (screenshot of the app, the
Edge Function log line, or the Stripe object).

## 0. Prerequisites (EC) – once

- [ ] `connect-onboard` deployed (Verify JWT **ON**).
- [ ] Stripe → Settings → Connect → Branding (sandbox): name FormTrace, icon, colour #F0D231.
- [ ] Both test phones opened once with `?stripetest=1` (shows the test-only buttons).
- [ ] Sandbox `release_hold_days` = 0 (done 2026-10-30). Remember: back to 14 before go-live.
- [ ] A fresh goal: trainee posts a goal (2 weeks is enough), coach pitches a weekly price
      (e.g. €25 × 2 weeks), trainee accepts. Do **not** pay yet.

## 1. Coach onboarding (EC / DU)

1. Coach phone → Profile → **Get paid with Stripe → Set up payouts**.
2. Stripe's hosted test onboarding opens. Use the test values Stripe displays (test
   phone 000 000 0000, SMS code 000 000, test IBAN, and so on).
3. Back in the app the card reads **Payouts ready ✔**.
- [ ] Supabase → Table editor → `coach_stripe_accounts`: one row, `transfers_active = true`,
      `details_submitted = true`, `livemode = false`.
- [ ] Stripe → Connect → Accounts: the Express account, "Transfers" enabled.
      **This is the open question from DU** (transfers-only + recipient agreement for an
      Irish Express account). If Stripe refuses or the capability stays "pending", report
      the exact message.

## 2. Deposit (DM + EA)

4. Trainee phone → the accepted goal → Payment → **Pay by card (Stripe test)**.
5. Checkout shows two lines: the goal (€50) and **Payment processing** (expect **€4.00** for
   €25 × 2 weeks with the default rates; working in the note* below).
   Pay with `4242 4242 4242 4242`, any future date, any CVC.
6. The app returns with `?checkout=success`; the tracker's **Deposit** step turns ✔ and
   reads "Deposit of €54 incl. €4 payment processing received…" (or whatever Checkout showed).
- [ ] Coach phone gets the push "… paid the deposit (test)".
- [ ] SQL: `select deposit_at, deposit_amount, deposit_processing, deposit_livemode,
      stripe_payment_intent from engagements order by deposit_at desc nulls last limit 1;`
      → amount = Checkout total in cents, processing = the processing line in cents,
      livemode false, a `pi_…` id.
- [ ] Stripe → Payments: the charge, metadata `engagement_id`, `processing_cents`, `base_cents`.

\*Processing line for €25 × 2 weeks with the default rates: payouts 2 × (0.0625 + 0.10) =
€0.33, account ceil(2/4) × €2 = €2.00, fixed €0.25 → gross = (50 + 0.33 + 2 + 0.25)/0.981
= €53.60 → line €3.60 → **€4.00**. Total **€54.00**. If Checkout shows a different number,
report it; the rates are in `platform_rates` (`stripe_*`).

## 3. Weekly release (DY)

7. A release needs a **closed week**. Either wait for Monday's week close, or simulate one
   now (sandbox only; journaled):
   ```sql
   insert into public.week_closures (engagement_id, week_start, assigned_count, completed_count, neutral)
   select id, (date_trunc('week', now() at time zone 'UTC')::date - 7), 1, 1, false
     from public.engagements where deposit_at is not null order by deposit_at desc limit 1
   on conflict do nothing;
   select public.queue_weekly_releases();   -- expect 1
   ```
8. The webhook fires `release-send` within seconds.
- [ ] SQL: `select week_start, gross_cents, amount_cents, status, stripe_transfer_id, error
      from payment_releases order by created_at desc limit 3;` → one row `sent`, `tr_…`,
      amount = €25.00 (commission 0 in the pilot).
- [ ] Stripe → Connect → Transfers: the Transfer, destination the coach's account,
      `transfer_group eng_<id>`, metadata `week_start`.
- [ ] Coach push "€25.00 released to you (test)"; trainee push "Week of … paid to your coach".
- [ ] Tracker (both phones): "1 of 2 weeks released to your coach (€25)".
- [ ] Negative path (optional, worth once): before step 1, run step 7 with the coach **not**
      onboarded → row stays `queued`, `error = coach not onboarded`, coach push "A payment
      is waiting for you". Then onboard, run `select public.queue_weekly_releases();` the
      next day (or `update payment_releases set attempts = attempts where status='queued';`
      to re-fire the webhook now) → `sent`.

## 4. Refund (DZ)

9. Trainee phone → the goal → **End this goal early** → reason "No time right now"
   (a trainee-stopped reason).
10. The trigger queues the refund; the webhook fires `refund-send`.
- [ ] SQL: `select price_cents, processing_cents, amount_cents, rule, flagged, status,
      stripe_refund_id from payment_refunds order by created_at desc limit 1;` →
      rule `trainee_stopped`, flagged false, status `sent`, `re_…`. Amount: unreleased
      €25 minus the week in progress €25 = **€0 → status `skipped`** if the current week
      is not released. To see money move instead, end with reason **"Coach not responding"**
      on a goal where a submission has sat unreviewed past 5 business days – hard to
      stage; alternatively end a 3-week goal after one release: unreleased €50 − €25 = €25
      + its processing share.
- [ ] Stripe → Payments → the deposit: a partial refund of that amount.
- [ ] Tracker: "Ended early. Refund of €… returned to your card …" (or the skipped text).
- [ ] A claimed coach failure without evidence: end another test goal with "Coach not
      responding" while all submissions are reviewed → `rule trainee_stopped`,
      `flagged true`, `flag_note` filled.

## 5. Free code (ED)

11. Stripe sandbox → Product catalogue → Coupons → New: 100 % off, once; add a promotion
    code (e.g. `FT-TEST-…`), max redemptions 10, expiry.
12. New goal; at Checkout enter the code → total €0, no card asked.
- [ ] Tracker: "Deposit of €0 (free code)"; SQL `deposit_amount = 0`, `deposit_processing = 0`.
- [ ] Step 7 again on this goal → a `skipped` release row (step still moves, no Transfer).

## 6. After the test

- [ ] `update public.platform_rates set value = 14 where key = 'release_hold_days';`
- [ ] Delete the simulated `week_closures` rows if they bother the streak views:
      `delete from public.week_closures where engagement_id in (<test goal ids>);`
- [ ] Report back: which boxes failed, and the DU open question's answer (step 1).

Pass = steps 2, 3, 4 and 5 each produce the Stripe object and the matching row. Then
**DW** (live keys) and **EB** (the switch) are the only steps left before the pilot.
