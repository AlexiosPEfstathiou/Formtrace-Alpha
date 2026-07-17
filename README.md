# FormTrace Coach — Alpha

Two-sided (coach ↔ trainee) alpha: single-page app on **GitHub Pages**,
data + auth + video on **Supabase**.

## What's in this folder

| File | Purpose |
|---|---|
| `index.html` | The app. (Copy your latest `coachtrace.html` here — see step 4.) |
| `store.supabase.js` | Data layer: auth, tables, video upload/playback, realtime. Exposes `window.store`. |
| `config.js` | Your Supabase URL + anon key. **Edit this.** |
| `config.example.js` | Template for the above. |
| `supabase/schema.sql` | Entire database: tables, security policies, storage bucket. Paste once. |

## Roles model

Everyone signs up as a **trainee**. In their profile they tap **Apply for Coach
profile**, fill a short form → row in `coach_applications` (status `pending`).
An **admin** approves it, which flips their `profiles.role` to `coach`. Approval
runs through the `approve_coach_application` SQL function (admin-only, enforced
server-side).

---

## Setup — do these in order

### 1. Create the Supabase project
1. Go to supabase.com → **New project**. Pick a name, a strong DB password, a region near your testers.
2. Wait for it to finish provisioning (~2 min).

### 2. Run the schema
1. Left sidebar → **SQL Editor** → **New query**.
2. Open `supabase/schema.sql`, copy **everything**, paste, click **Run**.
3. You should see "Success. No rows returned." That created every table, all
   security policies, and the private `videos` storage bucket.

### 3. Get your keys into config.js
1. Left sidebar → **Project Settings** → **API**.
2. Copy **Project URL** → paste into `SUPABASE_URL` in `config.js`.
3. Copy **anon public** key → paste into `SUPABASE_ANON_KEY` in `config.js`.
   - The anon key is meant to live in client code; RLS is your real protection.
   - Do **not** use the `service_role` key here.

### 4. Wire the app to Supabase
Your app currently uses IndexedDB via its internal `store`. For the alpha:
1. Copy your latest `coachtrace.html` into this folder as **`index.html`**.
2. In `index.html`, just before the app's own `<script>`, add these three lines
   (order matters):
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   <script src="config.js"></script>
   <script src="store.supabase.js"></script>
   ```
3. Replace the app's IndexedDB `store` calls with the new `window.store` surface.
   This is the real porting work; we'll do it together, screen by screen, after
   you confirm the site loads and sign-up works. (Auth + a first coach approval
   are the first things to test.)

### 5. Push to GitHub
```bash
cd "formtrace-alpha"
git init
git add .
git commit -m "FormTrace alpha scaffold"
git branch -M main
git remote add origin https://github.com/YOUR-USER/formtrace-alpha.git
git push -u origin main
```
(Create the empty repo on github.com first, then run the above.)

### 6. Enable GitHub Pages (HTTPS — required for camera)
1. Repo → **Settings** → **Pages**.
2. **Source**: Deploy from a branch. **Branch**: `main`, folder `/ (root)`. Save.
3. Wait ~1 min. Your app is at `https://YOUR-USER.github.io/formtrace-alpha/`.
   HTTPS here is what lets MediaPipe and the camera recorder work.

### 7. Make yourself admin (one time)
1. Open the site, **sign up** with your email. That creates your profile.
2. Back in Supabase → **SQL Editor**, run (with your email):
   ```sql
   update public.profiles set is_admin = true
   where id = (select id from auth.users where email = 'you@example.com');
   ```
3. You can now approve coach applications from the in-app admin view
   (we'll build/verify that view during the port).

---

## Test plan for the alpha (after the port)
1. Sign up two accounts (two browsers / a phone + laptop): a trainee and a would-be coach.
2. Would-be coach applies; you (admin) approve; confirm their role flips to coach.
3. Trainee posts a goal listing.
4. Coach sends an offer **with a recorded video pitch**; trainee sees it play back.
5. Trainee accepts → engagement created → coach assigns a workout →
   trainee submits a performed workout → coach reviews → both rate at completion.

Each of those maps to a table in `schema.sql`; if something fails, the failing
step tells us which policy or call to check.

## Security notes (read before inviting testers)
- **Email confirmation**: by default Supabase emails a confirmation link. For a
  fast alpha you can turn this off in Authentication → Providers → Email
  ("Confirm email" off), but turn it back on before any wider release.
- **Video bucket** is private; the app reads via short-lived signed URLs. The
  alpha lets any signed-in user request a signed URL — fine for trusted testers,
  tighten to engagement-scoped access before a public beta.
- **Vouchers**: the $20 renewal voucher must be validated server-side before it
  can affect any real payment. No payments are wired in this alpha; treat the
  voucher as display-only until we add an Edge Function to redeem it.
