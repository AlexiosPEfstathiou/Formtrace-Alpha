// Formtrace — stripe-webhook Edge Function (Item DM).
// Stripe calls this; it cannot send a Supabase JWT, so deploy with **Verify JWT OFF** -
// the Stripe signature check below is the authentication.
// Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET (whsec_… from the Stripe webhook endpoint).
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const crypto = Stripe.createSubtleCryptoProvider();   // Deno has no Node crypto for the sync verifier

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature!, Deno.env.get("STRIPE_WEBHOOK_SECRET")!, undefined, crypto);
  } catch (err: any) {
    console.error("stripe-webhook signature", err?.message);
    return new Response("Webhook signature verification failed", { status: 400 });
  }

  try {
    if (event.type === "checkout.session.completed" || event.type === "checkout.session.async_payment_succeeded") {
      const s = event.data.object as Stripe.Checkout.Session;
      // ED: a 100%-off promotion code completes with payment_status = "no_payment_required" (no PaymentIntent).
      if (s.payment_status === "paid" || s.payment_status === "no_payment_required") {
        const free = s.payment_status === "no_payment_required" || !s.amount_total;
        const processing = Number((s.metadata && s.metadata.processing_cents) || 0) || 0;   // EA: the pass-through line, kept apart from the price
        const credit = Number((s.metadata && s.metadata.credit_cents) || 0) || 0;           // FC: the trainee's credit applied to this goal
        const id = (s.metadata && s.metadata.engagement_id) || s.client_reference_id;
        const pi = typeof s.payment_intent === "string" ? s.payment_intent : s.payment_intent?.id ?? null;
        const { data: e, error: updErr } = await sb.from("engagements")
          .update({
            deposit_at: new Date().toISOString(),
            deposit_amount: s.amount_total ?? 0,                 // 0 = comp (ED): DY/DZ move the steps, not money
            deposit_processing: free ? 0 : processing,          // EA: excluded from releases and refunds
            deposit_credit_cents: credit,                        // FC: paid with credit (released first, from the balance)
            deposit_currency: s.currency,
            deposit_livemode: s.livemode,
            stripe_checkout_session: s.id,
            stripe_payment_intent: pi,
          })
          .eq("id", id).is("deposit_at", null)          // idempotent: Stripe may retry
          .select("id,coach_id,trainee_id,goal_title").maybeSingle();
        if (updErr) throw updErr;                        // DB failure -> 500 below, so Stripe retries
        if (e && credit > 0) {                            // FC: take the credit off the balance now that the deposit landed (once: only the first update matches)
          const { error: crErr } = await sb.rpc("confirm_credit", { p_engagement: e.id, p_cents: credit, p_currency: s.currency });   // GH: the reservation made at checkout becomes final (or, for an older checkout, the use is recorded now)
          if (crErr) console.error("stripe-webhook credit ledger", crErr);
        }
        if (e) {
          try {
          const { data: p } = await sb.from("profiles").select("display_name").eq("id", e.trainee_id).maybeSingle();
          await sb.from("push_outbox").insert({
            to_user: e.coach_id, kind: "offer",
            title: `💶 ${(p && p.display_name) || "Your trainee"} paid the deposit${free ? " (free code)" : ""}${s.livemode ? "" : " (test)"}`,
            body: `${e.goal_title || "Goal"} · held by Formtrace, released to you week by week`,
            url: "/#coach",
          });
          } catch (pushErr) { console.error("stripe-webhook push", pushErr); }   // a missed notification must not fail the webhook
        }
      }
    }
    // EJ (2026-11-04): card disputes. Every charge.dispute.* event (created, updated, closed, funds_withdrawn,
    // funds_reinstated) goes to record_dispute(): it keeps the newest state, holds that goal's payouts and refunds
    // while the dispute is open, releases or cancels them when it closes, and alerts the admins by push.
    if (event.type.startsWith("charge.dispute.")) {
      const dp = event.data.object as Stripe.Dispute;
      const idOf = (x: any) => (typeof x === "string" ? x : x?.id ?? null);
      const fee = ((dp as any).balance_transactions || []).reduce((t: number, bt: any) => t + Math.max(0, Number(bt?.fee || 0)), 0);   // Stripe's dispute fee
      const { error: dErr } = await sb.rpc("record_dispute", { p: {
        id: dp.id, charge: idOf(dp.charge), payment_intent: idOf((dp as any).payment_intent),
        amount: dp.amount, currency: dp.currency, reason: dp.reason, status: dp.status,
        due_by: dp.evidence_details?.due_by ?? null, livemode: dp.livemode,
        type: event.type, event_created: event.created, fee,
      } });
      if (dErr) throw dErr;                             // DB failure -> 500 below, so Stripe retries
    }
  } catch (err) {
    console.error("stripe-webhook handling", err);
    return new Response("Handler failed - Stripe will retry", { status: 500 });
  }
  return new Response(JSON.stringify({ received: true }), { headers: { "content-type": "application/json" } });
});
