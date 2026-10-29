// FormTrace — checkout-create Edge Function (Item DM, Stripe Checkout, sandbox first).
// The trainee pays the whole goal as a DEPOSIT to FormTrace (escrow: separate charges and
// transfers). Weekly transfers to the coach and refunds come later and link to this charge
// through transfer_group / metadata. Parameters marked "Checkout Studio" are the owner's
// configuration and are used exactly; ToS consent is deliberately OFF (owner, 2026-10-29).
// Secrets: STRIPE_SECRET_KEY (sk_test_… while testing). Optional: APP_URL.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);   // API version: account default (not guessed)
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_URL = Deno.env.get("APP_URL") ?? "https://alexiospefstathiou.github.io/Formtrace-Alpha/";
const ISO: Record<string, string> = { "€": "eur", "$": "usd", "¥": "jpy" };   // the coach's pitch currencies
const ZERO_DECIMAL = new Set(["jpy"]);                                         // Stripe amounts in whole yen
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "content-type": "application/json" } });

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
    const { data: rates } = await sb.from("platform_rates").select("key,value").in("key", ["trainee_fee_pct", "trainee_fee_min"]);
    const r = Object.fromEntries((rates || []).map((x: any) => [x.key, Number(x.value)]));
    const weeklyCents = Number(o.rate_per_workout_cents), weeks = Number(o.length_weeks);
    const feePerWeek = (r.trainee_fee_pct > 0 || r.trainee_fee_min > 0)
      ? Math.max(Math.round(weeklyCents * (r.trainee_fee_pct || 0) / 100), Math.round((r.trainee_fee_min || 0) * 100)) : 0;
    const unit = (cents: number) => ZERO_DECIMAL.has(currency) ? Math.round(cents / 100) : Math.round(cents);

    const line_items: any[] = [{
      quantity: 1,
      price_data: { currency, unit_amount: unit(weeklyCents * weeks), product_data: { name: `${e.goal_title || "Coaching goal"} · ${weeks} week${weeks === 1 ? "" : "s"}` } },
    }];
    if (feePerWeek > 0) line_items.push({ quantity: 1, price_data: { currency, unit_amount: unit(feePerWeek * weeks), product_data: { name: "FormTrace service fee" } } });

    const meta = { engagement_id: e.id, trainee_id: e.trainee_id, coach_id: e.coach_id };
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
    return json({ url: session.url });
  } catch (err: any) {
    console.error("checkout-create", err);
    return json({ error: String(err?.message || err) }, 500);
  }
});
