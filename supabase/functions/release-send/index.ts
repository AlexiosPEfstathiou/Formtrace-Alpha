// FormTrace – release-send Edge Function (Item DY: weekly releases).
// Called by a Database Webhook on INSERT and UPDATE of public.payment_releases (same pattern
// as push_outbox -> push-send). For a 'queued' row it creates ONE Stripe Transfer from the
// deposit's charge to the coach's connected account (source_transaction keeps it valid before
// the funds settle; transfer_group ties it to the deposit). Idempotent through Stripe's
// idempotency key release_<id>, and through the row's status.
// Deploy with Verify JWT OFF; the webhook is the only caller (no public link to this function).
// Secrets: STRIPE_SECRET_KEY. SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ok = (t: string) => new Response(t, { status: 200 });
const money = (cents: number, cur: string) => (cur === "jpy" ? String(cents) : (cents / 100).toFixed(2)) + " " + cur.toUpperCase();
const weekOf = (d: string) => new Date(d + "T00:00:00Z").toLocaleDateString("en-IE", { day: "numeric", month: "short", timeZone: "UTC" });

async function push(to_user: string, kind: string, title: string, body: string, url: string) {
  try { await sb.from("push_outbox").insert({ to_user, kind, title, body, url }); }
  catch (e) { console.error("release-send push", e); }                       // a missed notification never fails a release
}

Deno.serve(async (req) => {
  let payload: any;
  try { payload = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const rec = payload?.record ?? payload;
  if (!rec?.id) return new Response("no row", { status: 400 });

  // always re-read: the webhook row may be stale, and only 'queued' rows are actionable
  const { data: rel } = await sb.from("payment_releases").select("*").eq("id", rec.id).maybeSingle();
  if (!rel || rel.status !== "queued") return ok("nothing to do");

  const { data: e } = await sb.from("engagements")
    .select("id,coach_id,trainee_id,goal_title,stripe_payment_intent,deposit_livemode,deposit_currency").eq("id", rel.engagement_id).maybeSingle();
  if (!e) return ok("no engagement");
  const { data: acct } = await sb.from("coach_stripe_accounts").select("account_id,transfers_active,details_submitted,livemode").eq("coach_id", e.coach_id).maybeSingle();

  // coach not onboarded yet: leave it queued, nudge once a day (the cron re-fires the webhook)
  if (!acct || !acct.transfers_active || !acct.details_submitted || !!acct.livemode !== !!e.deposit_livemode) {
    const fresh = !rel.nudged_at || (Date.now() - new Date(rel.nudged_at).getTime()) > 23 * 3600 * 1000;
    await sb.from("payment_releases").update({ error: "coach not onboarded", nudged_at: fresh ? new Date().toISOString() : rel.nudged_at, attempts: rel.attempts + 1 }).eq("id", rel.id);
    if (fresh) await push(e.coach_id, "offer", "A payment is waiting for you",
      `${money(rel.amount_cents, rel.currency)} for the week of ${weekOf(rel.week_start)} is ready. Finish your Stripe setup in Profile to receive it.`, "/#profile");
    return ok("waiting for onboarding");
  }

  try {
    if (!e.stripe_payment_intent) throw new Error("deposit has no PaymentIntent");
    const pi = await stripe.paymentIntents.retrieve(e.stripe_payment_intent);
    const charge = typeof pi.latest_charge === "string" ? pi.latest_charge : pi.latest_charge?.id;
    if (!charge) throw new Error("deposit charge not found");

    const tr = await stripe.transfers.create({
      amount: rel.amount_cents,
      currency: rel.currency,
      destination: acct.account_id,
      source_transaction: charge,
      transfer_group: `eng_${e.id}`,
      description: `FormTrace – ${e.goal_title || "Coaching goal"} – week of ${weekOf(rel.week_start)}`,
      metadata: { release_id: rel.id, engagement_id: e.id, week_start: rel.week_start, coach_id: e.coach_id, gross_cents: String(rel.gross_cents), commission_cents: String(rel.commission_cents) },
    }, { idempotencyKey: `release_${rel.id}` });

    await sb.from("payment_releases").update({ status: "sent", stripe_transfer_id: tr.id, sent_at: new Date().toISOString(), error: null, attempts: rel.attempts + 1 }).eq("id", rel.id);
    const amt = money(rel.amount_cents, rel.currency), test = e.deposit_livemode === false ? " (test)" : "";
    await push(e.coach_id, "offer", `${amt} released to you${test}`, `${e.goal_title || "Goal"} · week of ${weekOf(rel.week_start)} delivered. It reaches your bank on Stripe's payout schedule.`, "/#coach");
    await push(e.trainee_id, "offer", `Week of ${weekOf(rel.week_start)} paid to your coach${test}`, `${money(rel.gross_cents, rel.currency)} released from your deposit for ${e.goal_title || "your goal"}.`, "/#listings");
    return ok("sent");
  } catch (err: any) {
    console.error("release-send transfer", err);
    await sb.from("payment_releases").update({ status: "failed", error: String(err?.message || err).slice(0, 500), attempts: rel.attempts + 1 }).eq("id", rel.id);
    return ok("failed");                                   // 200: a webhook retry would not help; the row carries the reason
  }
});
