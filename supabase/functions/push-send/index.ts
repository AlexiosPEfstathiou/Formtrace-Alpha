// FormTrace — push-send Edge Function (Item CE)
// Called by a Database Webhook on INSERT into public.push_outbox. Loads the
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

Deno.serve(async (req) => {
  let payload: any;
  try { payload = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const row = payload?.record ?? payload;               // webhook shape or direct call
  if (!row?.to_user || !row?.title) return new Response("no row", { status: 400 });

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
