// FormTrace – refund-send Edge Function (Item DZ: refunds).
// Called by a Database Webhook on INSERT into public.payment_refunds (push_outbox pattern).
// For a 'queued' row it creates ONE partial Stripe Refund on the deposit's PaymentIntent.
// Idempotent through Stripe's idempotency key refund_<id> and the row's status.
// Deploy with Verify JWT OFF; the webhook is the only caller.
// Secrets: STRIPE_SECRET_KEY. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ok = (t: string) => new Response(t, { status: 200 });
const money = (cents: number, cur: string) => (cur === "jpy" ? String(cents) : (cents / 100).toFixed(2)) + " " + cur.toUpperCase();

async function push(to_user: string, title: string, body: string, url: string) {
  try { await sb.from("push_outbox").insert({ to_user, kind: "offer", title, body, url }); }
  catch (e) { console.error("refund-send push", e); }
}

Deno.serve(async (req) => {
  let payload: any;
  try { payload = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const rec = payload?.record ?? payload;
  if (!rec?.id) return new Response("no row", { status: 400 });

  const { data: r } = await sb.from("payment_refunds").select("*").eq("id", rec.id).maybeSingle();
  if (!r || r.status !== "queued") return ok("nothing to do");
  const { data: e } = await sb.from("engagements").select("id,coach_id,trainee_id,goal_title,stripe_payment_intent,deposit_livemode").eq("id", r.engagement_id).maybeSingle();
  if (!e) return ok("no engagement");

  try {
    if (!e.stripe_payment_intent) throw new Error("deposit has no PaymentIntent");
    const rf = await stripe.refunds.create({
      payment_intent: e.stripe_payment_intent,
      amount: r.amount_cents,
      reason: "requested_by_customer",
      metadata: { refund_id: r.id, engagement_id: e.id, rule: r.rule, end_reason: r.reason || "", price_cents: String(r.price_cents), processing_cents: String(r.processing_cents) },
    }, { idempotencyKey: `refund_${r.id}` });

    const now = new Date().toISOString();
    await sb.from("payment_refunds").update({ status: "sent", stripe_refund_id: rf.id, sent_at: now, error: null, attempts: r.attempts + 1 }).eq("id", r.id);
    // the tracker's Refund step reads these two stamps (manual flow reused): sent and received at once
    await sb.from("engagements").update({ refund_sent_at: now, refund_received_at: now }).eq("id", e.id);
    const amt = money(r.amount_cents, r.currency), test = e.deposit_livemode === false ? " (test)" : "";
    await push(e.trainee_id, `${amt} refunded${test}`, `${e.goal_title || "Your goal"} ended early. The unused weeks go back to your card within 5-10 business days.`, "/#listings");
    await push(e.coach_id, `Goal ended - ${amt} refunded to the trainee${test}`, `${e.goal_title || "Goal"} · weeks already released to you are unaffected.`, "/#coach");
    return ok("sent");
  } catch (err: any) {
    console.error("refund-send", err);
    await sb.from("payment_refunds").update({ status: "failed", error: String(err?.message || err).slice(0, 500), attempts: r.attempts + 1 }).eq("id", r.id);
    return ok("failed");
  }
});
