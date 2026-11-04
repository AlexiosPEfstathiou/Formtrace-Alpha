# Formtrace - expense log (living, PRODUCT_LOG FW)

Everything Formtrace costs. Add a row whenever a cost starts, changes or stops. Amounts in the currency billed;
"to confirm" = not yet known - check the invoice or the account's billing page and fill it in.

## Running costs

| Vendor | What | Price | VAT | Cycle | Started | Renews / next charge | Paid by | Receipts | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Blacknight | Domain formtrace.ie | to confirm | to confirm | yearly | 2026-10-30 | 2026-10-30 (expires 30 Oct 2027; reminder FA 30 Sep 2027) | owner (personal) | Blacknight account | Registered in the owner's name |
| Blacknight | Titan Email 5GB - 1 mailbox (contact@formtrace.ie) | EUR 1.50 | EUR 0.35 (23%) | monthly | 2026-11-02 | monthly | owner (personal) | Blacknight invoices | EUR 1.85/month incl. VAT |
| Stripe | Card processing (per payment) | per transaction | - | per payment | sandbox only | - | deducted by Stripe | Stripe dashboard | Passed on to trainees as the "Payment processing" line (EA) |
| Stripe | Connect payouts and active accounts | per payout / per account month | - | per use | sandbox only | - | deducted by Stripe | Stripe dashboard | Included in the processing line (EA) |
| Stripe | Radar Standard | to confirm (Stripe lists "from USD 10/month" or per screened transaction) | to confirm | monthly | trial | paid from 2027-01-22 | Stripe balance / card | Stripe dashboard | Owner decision 2026-11-04: keep Standard |
| Stripe | Dispute fee | per dispute | - | per dispute | - | - | deducted by Stripe | Stripe dashboard | Tracked in payment_disputes (EJ) |
| Supabase | Database, auth, storage, Edge Functions | to confirm (plan: to confirm) | to confirm | monthly | to confirm | to confirm | owner | Supabase billing | |
| GitHub | Pro plan (private repository with Pages) | about USD 4 | to confirm | monthly | planned (FT) | - | owner | GitHub billing | Not yet bought |
| Anthropic | Claude subscription (personal account), 12 months | EUR 221.40 | to confirm (incl.?) | yearly | 2026-04-12 | 2027-04-12 | owner (personal) | Invoice 9BF0758D-671408 | Bought before Formtrace began; also personal use - share to attribute to Formtrace to decide |

## One-off payments

| Date | Vendor | What | Amount | VAT | Paid by | Receipt | Notes |
|---|---|---|---|---|---|---|---|
| 2026-04-12 | Anthropic | Claude subscription, 12 months (personal account) | EUR 221.40 | to confirm | owner | Invoice 9BF0758D-671408 | Covers 12 Apr 2026 - 11 Apr 2027 |
| 2026-10-30 | Blacknight | formtrace.ie registration (first year) | to confirm | to confirm | owner | Blacknight invoice | |
| 2026-11-02 | Blacknight | Titan Email first month | EUR 1.85 | incl. | owner | Blacknight invoice + payment confirmation | |

## Not paying for (on purpose)
- Zoho Mail - dropped (no free plan here; Mail Lite asked for a UK phone number). Titan instead.
- Radar Plus / Pro custom rules - not needed for the pilot.