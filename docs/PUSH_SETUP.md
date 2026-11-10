# Push notifications — setup (Item CE)

The app side is deployed. Push needs four one-time steps on the server side,
all in the Supabase dashboard (no CLI, no npm — the corporate machine is fine).

## 1. Run the SQL
`supabase/migrations_push.sql` — tables `push_subscriptions`, `push_config`,
`push_outbox`, `profiles.push_prefs`, and the triggers that compose a push for:
claps, shared handles, knock requests / confirmations, offers (new, countered,
answered, accepted), reviews, call proposals / acceptances.

## 2. Generate a VAPID key pair
Any of these works — you need the two strings once:
- https://vapidkeys.com (in the browser; generate, copy both)
- or in the Supabase SQL editor you cannot; or with Node if available:
  `node -e "const w=require('web-push');console.log(w.generateVAPIDKeys())"`

Then store the **public** key in the database:
```sql
update public.push_config set value = 'YOUR_PUBLIC_KEY' where key = 'vapid_public';
```
The private key never goes in the database.

## 3. Create the Edge Function
Dashboard → **Edge Functions → Deploy a new function → via Editor**.
Name: `push-send`. Paste the contents of `supabase/functions/push-send/index.ts`.
Deploy. Then **Secrets** (same page):
- `VAPID_PUBLIC_KEY` = the public key
- `VAPID_PRIVATE_KEY` = the private key
- `VAPID_SUBJECT` = `mailto:you@yourdomain` (any real address)
(`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically.)

## 4. Wire the Database Webhook
Dashboard → **Database → Webhooks → Create a new hook**:
- Name: `push_outbox_send`
- Table: `public.push_outbox`, Events: **Insert**
- Type: **Supabase Edge Functions** → `push-send`
- Method POST; add HTTP header `Authorization: Bearer <SERVICE_ROLE_KEY>`
  (Edge Functions verify the JWT by default; the service role key satisfies it.)
Save. Every new outbox row now calls the function within a second or two.

## 5. Try it
On an installed phone: **Settings → Notifications → Push notifications** on.
Grant the permission; a test buzz appears immediately (that one is local, not
from the server). Then have someone congratulate you or share a handle — that
buzz comes from the server. `select * from push_outbox order by id desc limit 10`
shows each event, when it was sent, and any error (`no subscription`, `muted`,
or an HTTP status from the push service).

## Notes
- iPhone: Web Push works only for the home-screen-installed app on iOS 16.4+.
- Per-type switches live under the main toggle; "muted" rows in the outbox mean
  the recipient turned that type off.
- Subscriptions that the push service reports gone (404/410) are deleted
  automatically; others count failures in `fail_count`.
- Quiet hours and call reminders ("in 10 minutes") are follow-ups: reminders
  need a scheduled job (pg_cron → outbox), not a trigger.

## Webhook secret (GE, 2026-11-10) - required for push-send, release-send and refund-send
These three functions run with **Verify JWT off** (they are called by Database Webhooks, not by users), so they check a shared
secret instead. Until the secret exists the check is off; set things up in this order so nothing is interrupted:
1. **Deploy** the three functions from `supabase/functions/` (Verify JWT stays off).
2. **Database -> Webhooks**: open each of the three webhooks (`push_outbox` -> push-send, `payment_releases` -> release-send,
   `payment_refunds` -> refund-send) and add an **HTTP header**: name `x-webhook-secret`, value = a long random string
   (PowerShell: `[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')`). The same value on all three.
3. **Edge Functions -> Secrets**: add `WEBHOOK_SECRET` with that same value. From this moment a call without the header gets 401.
To rotate it: change the header on the three webhooks and the secret together (a few seconds of refused calls at most; releases
are re-tried by the daily job, a notification sent in that gap is lost).