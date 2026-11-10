// Formtrace — push-send Edge Function (Item CE)
// Called by a Database Webhook on INSERT into public.push_outbox (header x-webhook-secret, see GE below). Loads the
// recipient's subscriptions, honours their per-type prefs, sends a Web Push to
// each, and records the result on the outbox row. Prunes dead subscriptions.
//
// Secrets (Dashboard → Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (mailto:you@domain)
//   SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:hello@example.com",
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!,
);

// GE (security review 2026-11-10): only the Database Webhook may call this function. The webhook sends the header
// x-webhook-secret; it must equal the WEBHOOK_SECRET secret. While WEBHOOK_SECRET is not set the check is off (so the
// function can be deployed first, the header added to the webhook second, and the secret set last).
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") ?? "";
function sameSecret(a: string, b: string) { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i); return d === 0; }
const authorized = (req: Request) => !WEBHOOK_SECRET || sameSecret(req.headers.get("x-webhook-secret") ?? "", WEBHOOK_SECRET);

Deno.serve(async (req) => {
  if (!authorized(req)) return new Response("unauthorized", { status: 401 });
  let payload: any;
  try { payload = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const rec = payload?.record ?? payload;
  if (!rec?.id) return new Response("no row", { status: 400 });
  // GE: never trust the request for who gets what - re-read the row the database queued; a row already sent is not sent again
  const { data: row } = await sb.from("push_outbox").select("id,to_user,kind,title,body,url,sent_at").eq("id", rec.id).maybeSingle();
  if (!row) return new Response("no row", { status: 400 });
  if (row.sent_at) return new Response("already sent", { status: 200 });

  // per-type opt-out
  const { data: prof } = await sb.from("profiles").select("push_prefs").eq("id", row.to_user).maybeSingle();
  const prefs = (prof?.push_prefs ?? {}) as Record<string, boolean>;
  if (prefs[row.kind] === false || prefs.all === false) {
    if (row.id) await sb.from("push_outbox").update({ sent_at: new Date().toISOString(), error: "muted" }).eq("id", row.id);
    return new Response("muted", { status: 200 });
  }

  const { data: subs } = await sb.from("push_subscriptions").select("*").eq("user_id", row.to_user);
  if (!subs?.length) {
    if (row.id) await sb.from("push_outbox").update({ sent_at: new Date().toISOString(), error: "no subscription" }).eq("id", row.id);
    return new Response("no subs", { status: 200 });
  }

  const msg = JSON.stringify({ title: row.title, body: row.body, url: row.url ?? "/", kind: row.kind, tag: row.kind + ":" + (row.id ?? "") });
  let ok = 0; const errors: string[] = [];
  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, msg, { TTL: 60 * 60 * 6 });
      ok++;
      await sb.from("push_subscriptions").update({ last_ok_at: new Date().toISOString(), fail_count: 0 }).eq("endpoint", s.endpoint);
    } catch (e: any) {
      const code = e?.statusCode ?? 0;
      errors.push(`${code}`);
      if (code === 404 || code === 410) await sb.from("push_subscriptions").delete().eq("endpoint", s.endpoint);   // gone for good
      else await sb.from("push_subscriptions").update({ fail_count: (s.fail_count ?? 0) + 1 }).eq("endpoint", s.endpoint);
    }
  }));
  if (row.id) await sb.from("push_outbox").update({ sent_at: new Date().toISOString(), error: errors.length ? errors.join(",") : null }).eq("id", row.id);
  return new Response(JSON.stringify({ sent: ok, failed: errors.length }), { headers: { "content-type": "application/json" } });
});
