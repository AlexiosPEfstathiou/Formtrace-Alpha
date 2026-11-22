// Formtrace — connect-onboard Edge Function (Item DU: coach payouts via Stripe Connect).
// Coaches get an Express connected account with the TRANSFERS capability only: Formtrace
// charges the trainee (escrow, separate charges and transfers) and transfers each delivered
// week to the coach. Onboarding is hosted by Stripe (Account Links); the coach manages payouts
// in the Express Dashboard (login link). Body: { action: "onboard" | "status" | "dashboard" }.
// Secrets: STRIPE_SECRET_KEY. Optional APP_URL. Verify JWT: ON.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe";

const KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const LIVE = KEY.startsWith("sk_live_") || KEY.startsWith("rk_live_");
const stripe = new Stripe(KEY);
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_URL = Deno.env.get("APP_URL") ?? "https://formtrace.ie/";   // EF 2026-11-02: the app moved to formtrace.ie
/* GI-4 (2026-11-22): only the app's own addresses may call this from a browser (was "*"); a request from any other site is
   refused. Requests without an Origin header (not a browser) still need a signed-in user's token. Extra addresses (e.g. a
   preview) can be added with the ALLOWED_ORIGINS secret, comma-separated. */
const ALLOWED = new Set(["https://formtrace.ie", "https://www.formtrace.ie", "https://alexiospefstathiou.github.io",
  ...(Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean)]);
const okOrigin = (o: string | null) => !o || ALLOWED.has(o) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
const corsFor = (o: string | null) => ({
  ...(o && okOrigin(o) ? { "Access-Control-Allow-Origin": o, "Vary": "Origin" } : {}),
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
});
/* GI-4: the browser gets a fixed sentence; the detail goes to the function logs. Messages our own database functions raise on
   purpose (code P0001, e.g. "Not enough credit") are meant for the user and pass through. */
const SORRY = "Something went wrong on our side - please try again in a minute.";
const userMessage = (err: any) => (err && err.code === "P0001" && err.message) ? String(err.message) : SORRY;

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin"); const cors = corsFor(origin);   /* GI-4: per request - never shared between calls */
  const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "content-type": "application/json" } });
  if (!okOrigin(origin)) return new Response("Forbidden", { status: 403 });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return json({ error: "Sign in first" }, 401);
    const { data: prof } = await sb.from("profiles").select("role,country_code").eq("id", user.id).maybeSingle();
    if (!prof || prof.role !== "coach") return json({ error: "Only coaches set up payouts" }, 403);
    const { action = "status" } = await req.json().catch(() => ({}));

    let { data: row } = await sb.from("coach_stripe_accounts").select("*").eq("coach_id", user.id).maybeSingle();
    // an account made with test keys does not exist in live mode (and vice versa): start again
    if (row && row.livemode !== LIVE) { await sb.from("coach_stripe_accounts").delete().eq("coach_id", user.id); row = null; }

    const refresh = async (accountId: string) => {
      const a = await stripe.accounts.retrieve(accountId);
      const st = {
        details_submitted: !!a.details_submitted,
        payouts_enabled: !!a.payouts_enabled,
        transfers_active: a.capabilities?.transfers === "active",
        requirements_due: (a.requirements?.currently_due || []).length,
        updated_at: new Date().toISOString(),
      };
      await sb.from("coach_stripe_accounts").update(st).eq("coach_id", user.id);
      return st;
    };

    if (action === "status") {
      if (!row) return json({ connected: false, livemode: LIVE });
      return json({ connected: true, livemode: LIVE, ...(await refresh(row.account_id)) });
    }
    if (action === "dashboard") {
      if (!row) return json({ error: "Set up payouts first" }, 400);
      const link = await stripe.accounts.createLoginLink(row.account_id);
      return json({ url: link.url });
    }
    // onboard: create the account once, then always hand out a fresh onboarding link
    if (!row) {
      const country = String(prof.country_code || "IE").toUpperCase();
    const PLATFORM_COUNTRY = (Deno.env.get("PLATFORM_COUNTRY") || "IE").toUpperCase();   // the Stripe account's country
      const acct = await stripe.accounts.create({
        type: "express",
        country,
        email: user.email ?? undefined,
        business_type: "individual",
        capabilities: { transfers: { requested: true } },
        // EG finding 2026-10-30: Stripe allows the "recipient" agreement only for CROSS-BORDER payouts.
        // Same country as the platform (IE) must use the standard agreement; transfers-only capability stays.
        ...(country === PLATFORM_COUNTRY ? {} : { tos_acceptance: { service_agreement: "recipient" } }),
        metadata: { coach_id: user.id },
      } as any);
      await sb.from("coach_stripe_accounts").insert({ coach_id: user.id, account_id: acct.id, livemode: LIVE });
      row = { account_id: acct.id };
    }
    const link = await stripe.accountLinks.create({
      account: row.account_id,
      refresh_url: `${APP_URL}?stripe=refresh#profile`,
      return_url: `${APP_URL}?stripe=return#profile`,
      type: "account_onboarding",
    });
    return json({ url: link.url });
  } catch (err: any) {
    console.error("connect-onboard", err);
    return json({ error: userMessage(err) }, 500);   /* GI-4 */
  }
});
