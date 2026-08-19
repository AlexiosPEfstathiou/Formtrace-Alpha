# FormTrace Coach

A two-sided fitness coaching app connecting **coaches** and **trainees** —
coaches build and review workouts with real form feedback; trainees train,
log progress, and see exactly what they're paying for and why.

Single-file Progressive Web App (`index.html`, no build step), backed by
Supabase (auth, database, storage), hosted on GitHub Pages.

**Live:** https://alexiospefstathiou.github.io/Formtrace-Alpha/

---

## What it does

### Finding a coach and getting started
- A trainee posts a **goal listing**; coaches send **offers** with a rate,
  workouts/week, and a video pitch — every pitch is recorded in-app, never
  a file upload.
- Offers are shown **grouped by goal**, with pending/accepted separated from
  a completed **Archive**, and an explicit confirmation before accepting one
  offer auto-declines every other offer on that same goal.
- **Public coach profiles** show badges (Verified / Professional / Certified
  Professional), all-time stats (trainees, goals, goals completed, workouts
  reviewed), sub-ratings (Professionalism, Communication, Motivation, Price,
  Instructions — not a single compressed star score), expertise, languages,
  age, and bio.
- Everyone signs up as a trainee; applying to become a coach goes through an
  admin-approval flow.

### Building and assigning workouts
- A coach's **exercise library** is labelled by muscle group, with per-exercise
  reference videos recorded in-app.
- **Wildcard slots** let a coach assign "any Chest exercise" and leave the
  specific choice, sets, and reps to the trainee.
- **Interval Running** is its own exercise type with a full segment builder:
  any sequence of run/walk segments, each independently timed, distance-based
  (tracked live via GPS), or distance-with-a-displayed-pace-target, plus a
  separate **Free run** mode (just a total distance goal, no fixed structure).
  It's a shared exercise available in every coach's library automatically,
  not something each coach has to build themselves.
- Partial workouts, wildcard fills, and postponement requests (with a real
  coach approve/decline flow, not a silent auto-accept) are all handled
  explicitly rather than as edge cases bolted on afterward.

### Training and feedback
- Every performed set is **video-recorded and pose-graded** — per-rep form
  scoring against the coach's own reference recording, not a generic model.
- A coach can **voice-over** a trainee's submitted video directly, narrating
  over the footage rather than typing separate notes.
- Grading uses multi-select tags rather than a single numeric score, since a
  single number compresses too much real signal about what actually needs
  work.

### Progress tracking
- **Weekly check-in photos**, captured at full camera resolution, with a
  timelapse view across a goal.
- **Body measurements** and a **weight trend chart** — smoothed, with a
  gradient fill, and a genuine goal-progress comparison (current weight
  against the weight on the day the goal actually started, not an
  arbitrary earlier date).
- **Personal bests** per exercise, tracked automatically and celebrated with
  a milestone notification the moment one is beaten.
- **Streaks**, computed server-side, with reschedule-to-protect logic so a
  trainee who moves a missed workout doesn't just avoid a future miss but
  genuinely recovers the streak.
- **The Journey** — a full recap once a goal completes: a photo timelapse,
  weight change over the goal's whole span, the highest streak reached, and
  a trainee-only share button.
- Tapping any check-in photo or profile picture expands it to a full-screen
  view.

### Staying connected
- **Scheduled video calls** — each person declares recurring weekly
  availability, either side can propose a specific time (only genuinely
  overlapping windows are ever offered), and the other side accepts,
  declines, or counters. Calls happen entirely within the app.
- **Vacation mode**, initiated by either a trainee or a coach, freezes the
  goal's calendar and streak rather than penalizing a planned break — shown
  clearly on the calendar, distinct from a genuine missed workout.
- Homepage notifications surface exactly what needs attention — a review
  that's due soon, a postponement request waiting on a decision, a call
  proposal, a pending offer — rather than requiring anyone to go looking.
- Admin tooling flags coach inactivity and missed review windows before they
  become a trainee's problem.

### Payments — visibility built, settlement not yet wired
- Payment is **periodic, tied to review**, never for merely performing a
  workout — a trainee can stop at any point owing nothing for work not yet
  reviewed.
- A coach sees, per trainee: the agreed rate, the workouts/week cap (so
  billing can never exceed what was actually agreed to), the reviewed-and-
  pending count, and the computed total — with a real, hard review deadline
  that protects trainees from ever being charged for a workout nobody
  looked at.
- This phase is **display and accounting only** — the app computes and shows
  exactly what's owed, to whom, and why. No money actually moves yet; that's
  a separate, later piece of work once a payment provider is chosen.

### The app itself
- Installable as a PWA, with an explicit in-app "Install" control (Chrome's
  own install prompt is gated by an engagement heuristic outside any app's
  control, so this gives a clear, direct path instead of leaving it to
  chance).
- A full visual theme — warm-yellow accent, a distinct gold family for
  calendar achievement states, smooth glowing line charts, and a dedicated
  Wong-palette colorblind mode that swaps every relevant color, not just
  the accent.
- Every camera/microphone flow (reference videos, submissions, voice-overs,
  check-in photos) is built in-app; nothing here is a file picker.

---

## Architecture

| Piece | What it is |
|---|---|
| `index.html` | The entire app — single file, no build step, no framework. |
| `store.supabase.js` | Data layer: auth, tables, video upload/playback, realtime. Exposes `window.store`. |
| `config.js` | Supabase project URL + anon key (not committed — see `config.example.js`). |
| `supabase/*.sql` | Every schema and migration, applied directly through the Supabase SQL editor. |
| `sw.js` / `manifest.json` | PWA service worker and manifest. |
| `tools/check.mjs` | A smoke test — parses the app, checks every referenced element ID exists, every navigation target resolves, every RPC the app calls is at least referenced. Run before every deploy. |

Hosted on GitHub Pages; backend on Supabase (Postgres + Row Level Security,
Storage for video/photos, realtime subscriptions).

## What isn't built yet

- **Payment settlement** — no provider chosen, no money actually moves (see
  above). This app currently answers "what's owed," not "how does it get
  paid."
- **A downloadable, store-distributed app** — currently a browser-installed
  PWA only. An Android package (via Trusted Web Activity) is a planned,
  not-yet-started option; iOS is explicitly out of scope for now.
- **A social/friends layer** — an NFC-based trainee-to-trainee connection
  system is designed but paused, pending the installability question above.
- The actual video-calling technology (WebRTC vs. a hosted provider) — the
  scheduling layer around it is built; what actually carries the call once
  proposed isn't decided yet.

---

## Setup (for a fresh instance)

### 1. Create the Supabase project
Go to supabase.com → **New project**. Pick a name, a strong DB password, a
region near your users.

### 2. Apply the schema and migrations
**SQL Editor → New query.** Run `supabase/schema.sql` first, then every file
in `supabase/migrations_*.sql`, in the order they were added (check file
timestamps, or `PRODUCT_LOG.md` for the feature each one belongs to).

### 3. Configure `config.js`
Copy `config.example.js` to `config.js`. Fill in your project's **Project URL**
and **anon public** key from Project Settings → API. Never put the
`service_role` key here — RLS policies are the real protection layer.

### 4. Push to GitHub and enable Pages
```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR-USER/YOUR-REPO.git
git push -u origin main
```
Repo → **Settings → Pages** → Source: Deploy from a branch → `main`, `/ (root)`.
HTTPS here is required for camera/microphone access to work at all.

### 5. Make yourself admin
Sign up in the live app first (creates your profile), then in Supabase's
SQL Editor:
```sql
update public.profiles set is_admin = true
where id = (select id from auth.users where email = 'you@example.com');
```

### 6. Verify before you rely on it
```bash
node tools/check.mjs
```
This catches broken IDs, dead navigation targets, and RPC calls the schema
doesn't yet support — run it after any change, before deploying.

---

## Security notes

- **Email confirmation** is on by default in Supabase Auth — leave it on for
  anything beyond local testing.
- The **video/photo storage bucket** is private; the app always reads
  through short-lived signed URLs, never a public path.
- Payments are currently **display-only** — no voucher, rate, or balance
  shown in the app has any effect on real money until a settlement provider
  is integrated and wired server-side.
