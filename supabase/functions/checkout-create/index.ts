// FormTrace — checkout-create Edge Function (Item DM, Stripe Checkout, sandbox first).
// The trainee pays the whole goal as a DEPOSIT to FormTrace (escrow: separate charges and
// transfers). Weekly transfers to the coach and refunds come later and link to this charge
// through transfer_group / metadata. Parameters marked "Checkout Studio" are the owner's
// configuration and are used exactly; ToS consent is deliberately OFF (owner, 2026-10-29).
// FC (2026-11-02): the trainee's CREDIT (trainee_credits, from a coach-ended goal) comes off the
// price. Credit covering price + payout costs = no card payment at all (paid here, at once);
// otherwise the card pays the rest (never below Stripe's 0.50 minimum). The credit is taken off
// the balance when the deposit lands (stripe-webhook), so an abandoned Checkout keeps it.
// Secrets: STRIPE_SECRET_KEY (sk_test_… while testing). Optional: APP_URL.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const LIVE = KEY.startsWith("sk_live_") || KEY.startsWith("rk_live_");
const stripe = new Stripe(KEY);   // API version: account default (not guessed)
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_URL = Deno.env.get("APP_URL") ?? "https://formtrace.ie/";   // EF 2026-11-02: the app moved to formtrace.ie
const ISO: Record<string, string> = { "€": "eur", "$": "usd", "¥": "jpy" };   // the coach's pitch currencies
const ZERO_DECIMAL = new Set(["jpy"]);                                         // Stripe amounts in whole yen
const MIN_CHARGE_CENTS = 50;                                                   // Stripe's minimum card charge (EUR 0.50)
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "content-type": "application/json" } });
const eur = (c: number) => "€" + (c / 100).toFixed(2);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in first" }, 401);

    const { engagement_id } = await req.json();
    const { data: e } = await sb.from("engagements").select("*").eq("id", engagement_id).maybeSingle();
    if (!e || e.trainee_id !== user.id) return json({ error: "Not your goal" }, 403);
    if (e.status !== "active") return json({ error: "This goal is not active" }, 400);
    if (e.deposit_at) return json({ error: "This goal is already paid" }, 400);

    const { data: o } = await sb.from("offers").select("*").eq("id", e.offer_id).maybeSingle();
    if (!o || o.rate_per_workout_cents == null || !o.length_weeks) return json({ error: "The offer has no price" }, 400);
    const sym = ((o.price_text || "").match(/^[^\d\s]+/) || ["€"])[0];
    const currency = ISO[sym];
    if (!currency) return json({ error: `Unsupported currency ${sym}` }, 400);

    // trainee fee from platform_rates (0 during the pilot): max(pct of the week, minimum) per week
    const { data: rates } = await sb.from("platform_rates").select("key,value").in("key", ["trainee_fee_pct", "trainee_fee_min", "stripe_card_pct", "stripe_card_fixed", "stripe_payout_pct", "stripe_payout_fixed", "stripe_account_monthly"]);
    const r = Object.fromEntries((rates || []).map((x: any) => [x.key, Number(x.value)]));
    const weeklyCents = Number(o.rate_per_workout_cents), weeks = Number(o.length_weeks);
    const feePerWeek = (r.trainee_fee_pct > 0 || r.trainee_fee_min > 0)
      ? Math.max(Math.round(weeklyCents * (r.trainee_fee_pct || 0) / 100), Math.round((r.trainee_fee_min || 0) * 100)) : 0;
    const unit = (cents: number) => ZERO_DECIMAL.has(currency) ? Math.round(cents / 100) : Math.round(cents);

    const priceCents = weeklyCents * weeks, feeCents = feePerWeek * weeks;
    const baseCents = priceCents + feeCents;
    // EA: Connect costs (one payout per released week, one account fee per started month) - incurred however the goal is paid
    const payoutCents = weeks * (Math.round(weeklyCents * (r.stripe_payout_pct || 0) / 100) + Math.round((r.stripe_payout_fixed || 0) * 100));
    const accountCents = Math.ceil(weeks / 4) * Math.round((r.stripe_account_monthly || 0) * 100);
    const connectCents = payoutCents + accountCents;

    // FC: the trainee's credit in this currency
    const { data: cr } = await sb.from("trainee_credits").select("amount_cents").eq("trainee_id", e.trainee_id).eq("currency", currency);
    const creditBal = Math.max(0, (cr || []).reduce((t: number, x: any) => t + Number(x.amount_cents || 0), 0));
    const connectRounded = connectCents > 0 ? Math.ceil(connectCents / 100) * 100 : 0;
    const fullNeed = baseCents + connectRounded;
    const meta: Record<string, string> = { engagement_id: e.id, trainee_id: e.trainee_id, coach_id: e.coach_id };

    // FC: credit covers everything - no card payment; the goal is paid here
    if (creditBal > 0 && creditBal >= fullNeed) {
      const now = new Date().toISOString();
      const { data: paid, error: updErr } = await sb.from("engagements").update({
        deposit_at: now, deposit_amount: 0, deposit_processing: connectRounded, deposit_credit_cents: fullNeed,
        deposit_currency: currency, deposit_livemode: LIVE,
      }).eq("id", e.id).is("deposit_at", null).select("id").maybeSingle();
      if (updErr) throw updErr;
      if (!paid) return json({ error: "This goal is already paid" }, 400);
      await sb.from("trainee_credits").insert({ trainee_id: e.trainee_id, amount_cents: -fullNeed, currency, used_engagement: e.id, note: "credit used for this goal (paid in full)" });
      try {
        const { data: p } = await sb.from("profiles").select("display_name").eq("id", e.trainee_id).maybeSingle();
        await sb.from("push_outbox").insert({ to_user: e.coach_id, kind: "offer", title: `💶 ${(p && p.display_name) || "Your trainee"} paid the deposit with credit${LIVE ? "" : " (test)"}`, body: `${e.goal_title || "Goal"} · held by FormTrace, released to you week by week`, url: "/#coach" });
      } catch (pushErr) { console.error("checkout-create push", pushErr); }
      return json({ paid_with_credit: true, credit_cents: fullNeed });
    }

    // FC: part credit - the card pays the rest (at least Stripe's minimum)
    const creditUsed = creditBal > 0 ? Math.max(0, Math.min(creditBal, baseCents - MIN_CHARGE_CENTS)) : 0;
    const chargedBase = baseCents - creditUsed;
    const goalLine = Math.max(0, priceCents - creditUsed);
    const feeLine = feeCents - Math.max(0, creditUsed - priceCents);
    const line_items: any[] = [];
    if (goalLine > 0) line_items.push({
      quantity: 1,
      price_data: { currency, unit_amount: unit(goalLine), product_data: { name: `${e.goal_title || "Coaching goal"} · ${weeks} week${weeks === 1 ? "" : "s"}`, ...(creditUsed > 0 ? { description: `${eur(priceCents)} less ${eur(Math.min(creditUsed, priceCents))} of your FormTrace credit` } : {}) } },
    });
    if (feeLine > 0) line_items.push({ quantity: 1, price_data: { currency, unit_amount: unit(feeLine), product_data: { name: "FormTrace service fee" } } });

    // EA (owner, 2026-10-29): the trainee covers Stripe's costs, so the platform nets the full price.
    // Exact parity on the gross: Stripe keeps p*G + f on the card plus the Connect costs (one payout
    // per released week, one account fee per started month). G = (base + connect + f) / (1 - p).
    // The line is rounded UP to the whole euro (never down). All rates live in platform_rates;
    // set stripe_card_pct and the others to 0 to switch the line off. Fixed fees are in euro.
    // FC: the card part only (chargedBase) - credit carries no card fee.
    const p = (r.stripe_card_pct || 0) / 100, fCents = Math.round((r.stripe_card_fixed || 0) * 100);
    const grossCents = p < 1 ? (chargedBase + connectCents + fCents) / (1 - p) : chargedBase;
    const rawLine = Math.max(0, grossCents - chargedBase);
    const processingCents = rawLine > 0 ? Math.ceil(rawLine / 100) * 100 : 0;        // up to the whole euro
    if (processingCents > 0) line_items.push({ quantity: 1, price_data: { currency, unit_amount: unit(processingCents), product_data: { name: "Payment processing", description: "Card and payout costs charged by Stripe, passed on at cost and rounded up to the euro" } } });

    Object.assign(meta, { processing_cents: String(processingCents), base_cents: String(baseCents), credit_cents: String(creditUsed) });
    const session = await stripe.checkout.sessions.create({
      // Checkout Studio configuration (exact):
      ui_mode: "hosted_page",
      billing_address_collection: "auto",
      phone_number_collection: { enabled: false },
      automatic_tax: { enabled: false },
      allow_promotion_codes: true,
      submit_type: "pay",
      locale: "en",
      integration_identifier: "hosted_mobile_app_0001",
      origin_context: "mobile_app",
      // FormTrace values:
      mode: "payment",
      line_items,
      success_url: `${APP_URL}?checkout=success&session_id={CHECKOUT_SESSION_ID}#listings`,
      cancel_url: `${APP_URL}?checkout=cancel#listings`,
      customer_email: user.email,
      client_reference_id: e.id,
      metadata: meta,
      payment_intent_data: { transfer_group: `eng_${e.id}`, metadata: meta },
    } as any);

    await sb.from("engagements").update({ stripe_checkout_session: session.id }).eq("id", e.id);
    return json({ url: session.url, credit_cents: creditUsed });
  } catch (err: any) {
    console.error("checkout-create", err);
    return json({ error: String(err?.message || err) }, 500);
  }
});
