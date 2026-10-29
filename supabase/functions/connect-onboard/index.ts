// FormTrace — connect-onboard Edge Function (Item DU: coach payouts via Stripe Connect).
// Coaches get an Express connected account with the TRANSFERS capability only: FormTrace
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
const APP_URL = Deno.env.get("APP_URL") ?? "https://alexiospefstathiou.github.io/Formtrace-Alpha/";
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
      const acct = await stripe.accounts.create({
        type: "express",
        country,
        email: user.email ?? undefined,
        business_type: "individual",
        capabilities: { transfers: { requested: true } },
        tos_acceptance: { service_agreement: "recipient" },   // coaches receive transfers; they do not take card payments
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
    return json({ error: String(err?.message || err) }, 500);
  }
});
