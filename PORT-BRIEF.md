# FormTrace Coach — Port Brief (for the next conversation)

Purpose: hand a fresh session everything it needs to port the FormTrace app onto
the already-built Supabase backend. Read this file first, then the files it
references in this same folder (formtrace-alpha).

## Current status (what is DONE and verified)
- Supabase project is live. Schema applied cleanly ("Success. No rows returned.").
- Backend verified end-to-end via smoke-test.html — ALL checks passed, including
  the video round-trip (record -> upload to Storage -> signed-URL playback).
- These files exist in this folder and are correct; DO NOT rebuild them:
  - supabase/schema.sql      (tables, RLS policies, triggers, storage bucket)
  - store.supabase.js        (the data layer; exposes window.store)
  - config.js                (filled with the real project URL + publishable key)
  - smoke-test.html          (standalone backend verifier)
  - README.md                (setup + test plan)

## The ONE remaining task
Port the FormTrace app (single HTML file, ~164 KB, internally called
coachtrace.html) so that it uses `window.store` instead of its old IndexedDB
`store`, add an auth gate, and layer in the role logic. Save the result as
`index.html` in this folder, then push to GitHub Pages.

## IMPORTANT BLOCKER discovered on 2026-07-17
The app source is NOT on the user's machine and NOT recoverable locally:
- Searched entire user profile: no coachtrace.html / formtrace-coach.html.
- No HTML > 80 KB in Downloads or Documents.
- Content search for "PoseLandmarker"/"hysteresis": no matches.
- ftbundle.b64 in the FT Project folder is CORRUPT (gzip fails at byte 0) — delete it.
The app lives only in the Anthropic sandbox. The next session MUST retrieve it
from the sandbox (bash/view/present_files tools) and deliver it to the user as a
download to drop into this folder. If the sandbox has reset and the file is gone,
fall back to a REBUILD (see "Rebuild inputs" below).

## window.store API surface (from store.supabase.js — already built)
All methods are async. Import order in index.html (before app code):
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script src="config.js"></script>
  <script src="store.supabase.js"></script>

- store.auth.signUp(email, password, displayName)
- store.auth.signIn(email, password)
- store.auth.signOut()
- store.auth.currentUser()            -> user | null
- store.auth.myProfile()              -> {id, role, is_admin, display_name, ...}
- store.auth.updateProfile(patch)
- store.auth.onChange(cb)             -> fires on login/logout

- store.video.upload(blob, ext='webm')-> storage path (string)
- store.video.signedUrl(path, secs)   -> playable URL
- store.video.remove(path)

- store.coachApps.apply(form)         -> trainee submits coach application
- store.coachApps.mine()
- store.coachApps.pending()           -> admin: list pending
- store.coachApps.approve(appId)      -> admin: flips role to 'coach'
- store.coachApps.reject(appId)

- Table helpers (each has .list(match), .get(id), .add(row), .update(id,patch), .remove(id)):
  store.exercises, store.workouts, store.listings, store.offers,
  store.engagements, store.assignedWorkouts, store.submissions,
  store.reviews, store.ratings, store.logs

- store.coaches()                     -> list profiles where role='coach'
- store.subscribe(table, filter, cb)  -> realtime; returns an unsubscribe fn

## Roles model (decided with user)
- Everyone signs up as a TRAINEE (default in schema).
- In profile, trainee taps "Apply for Coach profile" -> fills a form ->
  row in coach_applications (status 'pending').
- An ADMIN approves via store.coachApps.approve() (calls the SQL function
  approve_coach_application, admin-only) which flips profiles.role to 'coach'.
- Make the first admin by running, once, in Supabase SQL editor:
    update public.profiles set is_admin=true
    where id=(select id from auth.users where email='YOUR_EMAIL');

## Non-negotiable product rules
- VIDEO-FIRST, NO ATTACHMENTS: every pitch/offer/review/goal-listing uses the
  in-app recorder (getUserMedia + MediaRecorder, front/back flip, record/stop
  timer, re-record, Use). Uploads go via store.video.upload(); playback via
  store.video.signedUrl(). No file pickers anywhere.
- Auth gate: the app must require sign-in before any screen; role decides which
  tabs show (trainee vs coach vs admin view).
- Keep it a single HTML file + Supabase JS from CDN (user confirmed).
- Pose grading is already validated (per-rep hysteresis + DTW + dominant-joint
  ROM; coach reference = single median rep; tempo removed). DO NOT change it
  during the port — only swap persistence + add auth/video/roles.

## Old app data model -> new tables (mapping guide for the port)
The old IndexedDB store (db "formtrace-db", v8) had these stores; map each to
window.store:
  exercises  -> store.exercises      (add coach_id = current user)
  workouts   -> store.workouts       (add coach_id)
  assigned   -> store.assignedWorkouts (needs engagement_id + snapshot jsonb)
  reviews    -> store.reviews        (per-set jsonb; video paths not blobs)
  trainees   -> profiles (role='trainee') + engagements
  logs       -> store.logs           (add trainee_id, log_date unique)
  photos     -> store.video / Storage (no local blobs)
  profile    -> store.auth.myProfile / updateProfile
  listings   -> store.listings
Key change: everything that was a local Blob/objectURL becomes a Storage path
(string) via store.video.upload(); render with store.video.signedUrl().
The .ftr.json report (landmark frames + grades) is stored in submissions.report
(jsonb) — it stays landmark-only and does NOT carry video.

## Build + verify order (do the port in this sequence, test each vs live DB)
1. Auth gate + sign-up/login screen. Verify a profile row appears.
2. Profile screen with "Apply for Coach profile" form. Verify pending app row.
3. Admin view: list pending, approve. Verify role flips to 'coach'.
4. Coach: Library (exercises + workouts) with reference video recording.
5. Trainee: post a goal listing WITH a recorded video.
6. Coach: send an offer WITH a required video pitch; trainee sees it play back.
7. Trainee: accept -> engagement created.
8. Coach: assign a workout -> trainee submits performed workout (pose grading) ->
   coach reviews (per-set labels + optional video) -> both rate at completion.
Each step maps to one table; a failing step points at one policy/call.

## Rebuild inputs (ONLY if the sandbox no longer has coachtrace.html)
Reconstruct the UI from assets already on disk in the FT Project folder:
  - previews/app.css  (the full design system: dark theme, lime accent, tokens)
  - previews/formtrace-goal-complete-preview.html  (celebration + mutual review)
  - previews/formtrace-next-goal-preview.html      (offer w/ video recorder + playback)
  - previews/formtrace-coach-profiles-preview.html (coach profile layouts)
  - previews/formtrace-trainee-profile-preview.html(trainee stats/reputation)
The data layer and schema fully specify persistence. The pose/skeleton engine
would be the only part needing careful reconstruction — flag this to the user
early, as it is the hardest piece and may need its validated algorithm re-derived.

## Housekeeping
- Turn Supabase email confirmation OFF while testing (Auth -> Providers -> Email),
  back ON before external testers.
- Delete the corrupt ftbundle.b64 from the FT Project folder.
- Live app URL after Pages rebuild: https://<user>.github.io/Formtrace-Alpha/
  (note the capital F and A — the repo name is case-sensitive).
