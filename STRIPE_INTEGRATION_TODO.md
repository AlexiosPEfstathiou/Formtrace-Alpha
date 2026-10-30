# Stripe integration — to do (Item DM)

**This file is the single source of truth for the remaining Stripe setup.**
Hosted Stripe Checkout: the trainee is sent to a Stripe-hosted payment page and pays
the whole goal as a **deposit** held by FormTrace (escrow — *separate charges and
transfers*). Weekly releases to coaches and refunds are later parts of DM.
Status: **sandbox / test mode only.** Pilot users do not see it.

## Values to Replace

The Checkout parameters that the Stripe document gives as placeholders were replaced
with real values computed for each goal, so **no placeholders remain**:

**Files:**
- [supabase/functions/checkout-create/index.ts](supabase/functions/checkout-create/index.ts)

| Field | Value used | Note |
|-------|-----------|------|
| mode | `payment` | One deposit per goal. `payment_method_collection` applies only to subscriptions, so it is omitted. |
| success_url | `APP_URL?checkout=success&session_id={CHECKOUT_SESSION_ID}#listings` | `APP_URL` defaults to the GitHub Pages URL; set the `APP_URL` secret if the app moves. |
| cancel_url | `APP_URL?checkout=cancel#listings` | Returns to the Goal tab. |
| line_items | `price_data` built from the accepted offer: weekly price × weeks (+ a "FormTrace service fee" line when the trainee fee is above 0) | No catalogue Price IDs - each goal has its own price. Currency from the pitch: € → eur, $ → usd, ¥ → jpy (zero-decimal). |

## Configured Parameters

From Checkout Studio, used exactly:

**Files:**
- [supabase/functions/checkout-create/index.ts](supabase/functions/checkout-create/index.ts)

| Parameter | Value |
|-----------|-------|
| ui_mode | `hosted_page` — **SDK dependency:** `npm:stripe` resolves to the latest SDK; versions below 21.0.0 need `hosted`. If Stripe answers "invalid ui_mode", change it to `hosted`. |
| billing_address_collection | `auto` |
| phone_number_collection | `{ enabled: false }` |
| automatic_tax | `{ enabled: false }` — until the VAT advice (BI prerequisite 2) |
| allow_promotion_codes | `true` — must not stack with FormTrace vouchers (BW) later |
| submit_type | `pay` |
| locale | `en` |
| integration_identifier | `hosted_mobile_app_0001` |
| origin_context | `mobile_app` |
| consent_collection | **omitted** — owner decision 2026-10-29: no Terms of Service page yet. Add `{ terms_of_service: "required" }` once a ToS URL is set in Stripe (Settings → Public details). |

## Setup (sandbox)

1. **SQL:** run `supabase/migrations_stripe_checkout.sql` (deposit fields + a guard so
   only the server can write them). Final select: `6`.
2. **Edge Function `checkout-create`:** Dashboard → Edge Functions → Deploy a new
   function → Via Editor → paste the file → Deploy. **Verify JWT: ON.**
3. **Edge Function `stripe-webhook`:** same, paste
   [supabase/functions/stripe-webhook/index.ts](supabase/functions/stripe-webhook/index.ts).
   **Verify JWT: OFF** (Stripe cannot send a Supabase token; the Stripe signature is the check).
4. **Stripe webhook endpoint** (Stripe Dashboard, sandbox → Developers → Webhooks →
   Add destination): URL
   `https://paovvevuxbbpawtmrffl.supabase.co/functions/v1/stripe-webhook`, events
   `checkout.session.completed` and `checkout.session.async_payment_succeeded`. Copy its
   **signing secret** (`whsec_…`).
5. **Edge Function secrets** (Supabase): `STRIPE_SECRET_KEY` = the sandbox **secret key**
   (`sk_test_…`, Stripe → Developers → API keys) and `STRIPE_WEBHOOK_SECRET` = the
   `whsec_…`. **Never paste either into a chat or the repo.** No publishable key is
   needed: Checkout is opened by the server.

No new dependencies on any machine: the functions import `npm:stripe` and
`npm:@supabase/supabase-js@2`, fetched by Supabase's cloud at deploy.

## Coach payouts (Item DU) - setup

6. **SQL:** run `supabase/migrations_stripe_connect.sql` (the switch `payments_via_stripe`,
   off; the private `coach_stripe_accounts` table; `coach_payouts_ready`). Final select:
   `0 | 1`.
7. **Edge Function `connect-onboard`:** deploy
   [supabase/functions/connect-onboard/index.ts](supabase/functions/connect-onboard/index.ts),
   **Verify JWT ON**. Uses the same `STRIPE_SECRET_KEY` secret.
8. **Connect branding (required before hosted onboarding works):** Stripe → Settings →
   Connect → Branding: business name **FormTrace**, an icon, and a brand colour (#F0D231).
9. **Test (sandbox):** a coach phone opened once with `?stripetest=1` → Profile → **Get paid
   with Stripe → Set up payouts** → Stripe's test onboarding (use test data; Stripe shows
   the test values to enter) → back in the app the card reads **Payouts ready ✓**.

## The switch

`platform_rates.payments_via_stripe` = **1** turns Stripe escrow on for everyone: the
manual route (coach payment details, I've paid, Ask for details) disappears for goals not
yet paid; trainees see **Pay by card**; the map shows Deposit as the payment step; coaches
see the payouts card on Profile. Goals already paid directly keep their record.
`update public.platform_rates set value = 1 where key = 'payments_via_stripe';`
(0 turns it back.) In the sandbox, flipping it on means test cards only - flip it on for
real only after go-live below.

## Go-live checklist (before the pilot starts)

- [ ] Sandbox: one test deposit and one coach onboarding, end to end
- [ ] Weekly release and refunds built and tested (next DM parts)
- [ ] BI prerequisites: VAT advice; coach countries (accounts are created in the coach's
      profile country, default IE)
- [ ] Outside-activity check
- [ ] Stripe live activation complete; live secret key + live webhook endpoint and signing
      secret replace the test ones in Supabase secrets
- [ ] Connect branding set in live mode too
- [ ] Offer wording fixed ("never a lump sum" is untrue under escrow)
- [ ] Optional: Terms of Service page, then re-enable consent_collection
- [ ] Flip `payments_via_stripe` to 1; restore launch rates only if pilot fees should end
## How it works

1. Trainee, on a phone opened once with `?stripetest=1`, opens the accepted goal →
   Payment → **Pay by card (Stripe test)**.
2. The app calls `checkout-create` with the trainee's session. The function checks the
   trainee owns the goal, it is active and unpaid, prices it from the offer, creates the
   Checkout Session (tagged `transfer_group = eng_<goal id>` and metadata
   engagement/trainee/coach), and returns the URL.
3. Stripe's page takes the payment and returns to the app (`?checkout=success`).
4. Stripe calls `stripe-webhook`; it verifies the signature and writes `deposit_at`,
   amount, currency, test/live mode, session and PaymentIntent IDs on the goal
   (idempotent), then pushes the coach "paid the deposit (test)".
5. The tracker's **Deposit** step turns ✓ and the goal moves to Training.

## Testing

- Card `4242 4242 4242 4242`, any future expiry, any CVC, any postcode.
- 3-D Secure: `4000 0025 0000 3155`. Declined: `4000 0000 0000 0002`.
- Turn the test button off on a phone: open the app with `?stripetest=0`.
- Check: Stripe Dashboard → Payments (sandbox) shows the charge with metadata;
  Supabase → Edge Functions → logs; `select deposit_at, deposit_amount, deposit_currency,
  deposit_livemode from engagements where stripe_checkout_session is not null;`

## Next steps (rest of DM)

- **Coach onboarding** (Connect Express, embedded onboarding) - a coach must be ready to
  receive transfers before trainees pay for real.
- **Weekly release** job → Transfers with `source_transaction` = the deposit charge.
- **Refunds** for unreleased weeks on an early end.
- **Offer copy:** the pitch form says payment is "per week reviewed, never a lump sum" -
  untrue under escrow (one deposit, weekly release). Update before going live.
- Terms of Service page → re-enable `consent_collection`.
- After the BI prerequisites: live keys, `STRIPE_LIVE = true`, restore launch rates.

## Resources
- https://support.stripe.com
- https://docs.stripe.com/mcp

**2026-10-30 (EA + ED):** after running `supabase/migrations_stripe_fees.sql`, **redeploy** `checkout-create` and `stripe-webhook` (both changed). Confirm the five `stripe_*` rates against Stripe's Irish pricing page. Create the 100%-off coupon + promotion code (ED) in sandbox and live.
