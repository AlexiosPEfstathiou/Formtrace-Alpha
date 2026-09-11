# FormTrace — Product Log

Opened 2026-08-07. Ordered by dependency, not by size.

---

## BD. Alpha testing with 2 people

Logged as a milestone/activity, not a build task. Two people alpha
testing the live app (GitHub Pages + Supabase) - presumably one coach and
one trainee, which is the minimum to exercise the two-sided flows
end to end (offer -> accept -> engagement -> weekly assign -> pick a
session -> submit -> review, plus macros, nutrition goals, calendar,
streak). This is where most of the recent items surfaced from: the
"statement timeout" (AR/AZ), the calendar/database outage (AW), the
"3 planned but assign 1" chain (AT step 3 fixes), the vacation streak
count (still open, awaiting the diagnostic output), and the several
"Couldn't load the calendar" regressions. Worth treating tester reports
as the current priority queue.

Standing note for this phase: real accounts, real data, so migrations and
data-shape changes carry more weight than during solo dev - the
week-model cutover (AT) in particular is mid-flight (steps 1-4 live behind
`WEEK_MODEL`, step 5 not yet done), so testers are exercising the new
model on real engagements while the day-model code still exists underneath.

Open tester-reported items right now: vacation streak miscount (awaiting
diagnostic rows). No other unresolved reports outstanding.

---

## BC. Trim option when submitting a video: cut from the start and end

Requested: when submitting a workout video the submitter should be able to
trim parts off the beginning and end before it's sent.

Where it fits (checked, not assumed): recording already has a review step
(`#rreview`, shown when `recOpts.review`) between stopping and completing -
that is the natural place for a trim UI, before `onComplete(lastCapture)`
fires. Two in/out handles on a scrubber over `rplay` (the review
`<video>`), defaulting to full length.

**The real nuance, and why this isn't just a UI slider:** the captured
blob is paired with `lastCapture.frames` - per-frame pose landmarks, at
`lastCapture.fps` - and the whole point of these videos is pose grading
against the coach's reference. A trim has to cut BOTH in lockstep, or the
graded frames stop lining up with what's on screen. Frames are the easy
half (drop those outside [in,out] by timestamp). Re-cutting the actual
video blob is the hard half:
- WebM/MP4 from MediaRecorder can't be losslessly trimmed client-side
  without a mux library (none installable here - Artifactory/npm blocked),
  and re-encoding through a canvas + MediaRecorder is a real re-record
  pass (playback-speed, quality loss, battery).
- Cheaper alternative worth weighing first: don't recut the blob at all -
  store the chosen in/out offsets alongside it and have every player
  (`hydrateVideos`, the review, the voice-over recorder) start at `in`
  and stop at `out`. The uploaded file stays whole; playback and the
  graded frame set both honour the trim. Less "true" than a hard cut but
  far simpler and lossless, and it composes with the existing per-path
  rotation-correction pattern (item X) which already adds playback
  metadata without touching the file.

Recommend deciding between hard-recut and offset-based trim before
building. Not started.

---

## BB. Streak animation must show the whole streak, scaled to its length - DONE 2026-09-07 (built inside AT step 4, see there)

Requested: the streak animation should accurately show the streak - the
first and the last day always visible. Reported: on a 15-day streak the
animation shows only the last 6 days. Scaling rule (revised 2026-09-07 -
the unit follows the length, so the day-vs-week question below is
answered by the streak itself, not by a mode):
- under 3 weeks: one square per DAY, every day shown;
- 3 weeks up to 3 months: one square per WEEK, with a clear start date and
  current date;
- 3 months and beyond: one square per MONTH.

Where it lives (checked): the squares come from `streakDates()` (walks back
day by day from today, collecting the run) feeding `openStreakBurst()`,
which renders one animated square per date. Two candidates for the
6-day cutoff, to confirm before fixing rather than assume: the walk
stops after 7 consecutive rest days (`rest>=7` at ~2047), and the burst
markup may cap how many squares fit. Neither is the requested behaviour.

**Reconcile with item AT before building:** the streak is being redefined
in WEEKS (`week_streak_count`, live since AT step 1; the day-based badge
is retired at AT step 5). The revised rule above already resolves this: a
streak under 3 weeks is shown in days regardless of how the streak is
COUNTED, so under the week model the day squares are the actual training
days within the completed weeks (the calendar has them - gold cells),
and from 3 weeks the unit is the week itself. The start square is the
first day (or first week's Monday) of the run; the current square is
today (or this week). Still best built once, on the week model, as part
of AT step 4/5.

Not started.

---

## BA. Open goals hygiene: hide, expiry, and pitches that don't stick forever - DONE 2026-09-07

Requested: coaches can hide an open goal so it stops reappearing; a
"Pitched" goal must not sit there forever - once the trainee picks someone
else, or the goal expires, it moves to Not selected; and goal postings
expire after one week. Needs `supabase/migrations_open_goals_hygiene.sql`.

Why the second one was happening: nothing ever expired a posting. When a
trainee accepted a rival offer the siblings were already auto-declined and
moved correctly; but a goal the trainee simply abandoned stayed `open`
indefinitely, so the coach's pitch stayed pending indefinitely. The expiry
rule is what closes that hole - it's one mechanism, not two.

- `listing_hides(coach_id, listing_id)`, RLS coach-own. Hide is offered on
  goals the coach hasn't pitched (a pitched one moves on its own); a
  "Show N hidden goals" toggle at the bottom reveals them with Unhide. The
  trainee's goal is untouched either way.
- `expire_listings()`: closes `open` postings older than 7 days with
  `closed_reason='expired'` (constraint extended) and marks their pending
  offers `expired`. Called when the Open goals tab or the trainee's goals
  screen loads - the same no-scheduler pattern as `close_weeks_due`. The
  client also treats week-old postings as expired even if the call fails.
- Expired pitches read "Not selected · goal expired" in the coach's
  outcomes; each open card shows "expires in N days"; the trainee's goal
  list shows an "expired" badge.

---

## AZ. Recurring "statement timeout" - the landmark payload, fixed at the source - DONE 2026-09-07

Kept coming back after the calendar_rows() fix. That fix cut what crossed
the NETWORK, not what the DATABASE had to do: `to_jsonb(row) - 'snapshot'`
still made Postgres load every row's full jsonb - the frozen pose landmarks
for every exercise - from disk before discarding it, so the server-side
work and the timeout were unchanged. And the audit turned up the real
scale: ELEVEN list sites pulled full snapshots, most of them for every
active engagement in parallel - homepage cards, coach home, notification
batches, the streak badge - megabytes per screen that nothing ever read.

Fixed where the cost is. Needs `supabase/migrations_snapshot_lite.sql`:
- Two light columns on assigned_workouts, `snap_name` and `snap_items`
  (item names/kind/sets/reps, no landmarks), kept in sync by a BEFORE
  INSERT/UPDATE OF snapshot trigger; one-off backfill.
- `calendar_rows()` rebuilt to never reference `snapshot` at all. Its
  column list is generated from information_schema at migration time, so
  re-running the migration after adding columns refreshes it - it can't
  silently drop one.
- Client: one helper, `assignedLiteByEng(engs)`, returns rows grouped per
  engagement in the order given (a drop-in for the old per-engagement
  Promise.all), with fallback to the full fetch only if the function is
  missing. All 11 sites now go through it; the only direct list() left is
  the helper's own fallback. Confirmed no list-fetched row ever needs
  landmarks - the workout screen loads its single full row separately.
Supersedes migrations_calendar_rows.sql (harmless if already run; the new
function replaces it).

---

## AY. Replace availability-based call scheduling with propose → accept → call in-app

Requested: the current way of setting up a video call - each side
declaring recurring weekly availability windows, and proposals only being
allowed inside the overlap - is not user friendly. Replace it with the
simplest possible flow: one of the two proposes a call (a specific date and
time), the other accepts, and the call happens inside the app.

**What already exists (checked, not assumed):** `call_proposals` with
accept / decline / counter, the homepage "call proposal needs your
response" card, and accepted calls rendered on the calendar. The part
being removed is the `availability_blocks` layer in front of proposing -
the recurring-window declaration, the overlap computation, and the
"only overlapping windows are ever offered" rule from item G. Proposing
becomes: pick a date and time, send. The receiving side's accept / decline
/ counter is already built and stays.

**The part that is NOT small:** "they have a video call in the app" is the
same open decision item G has been paused on - WebRTC (peer-to-peer,
needs a signalling channel and ideally a TURN server for reliability on
mobile networks) versus a hosted provider SDK (simpler, reliable, but a
third party and usually a cost). The scheduling simplification can ship
on its own and is worth doing first; the call itself waits on that
decision, and the in-app-only requirement from G still stands (no
external meeting links).

Not started. Supersedes the scheduling half of item G; G's call-technology
question remains open and becomes this item's second step.

---

## AX. Weekly nutrition goals: coach sets calories + protein, trainee sees % on logging - DONE 2026-09-07

Requested: a weekly task for the coach to set a caloric and protein goal
per trainee; when the trainee submits macros they're told how close they
came, as a percentage. Needs `supabase/migrations_macro_goals.sql` run.

**Design decisions, stated so they can be redirected:**
- The goal is a DAILY target (kcal/day, g protein/day), set PER WEEK by
  the coach - the weekly task is confirming or adjusting it. Macros are
  already logged per day, so the comparison is day-to-day.
- Carry-forward: a week with no explicit goal inherits the latest earlier
  one, so a missed week never leaves a trainee goalless. Both sides see
  "(carried)" when that's the case, and the coach's prompt on such a week
  reads "Set for this week" rather than "Adjust".
- Multiple coaches: the most recently updated goal wins (`my_macro_goal`
  orders by week then updated_at). Edge case, not a designed-for one.
- "Notified" = shown at the moment it matters: live percentages in the
  macro-log sheet as they type (gold when within 90-110%), and the save
  toast reads "Logged ✓ · Calories 92% · Protein 78% of your goal".

**Built:** `macro_goals(engagement_id, week_start, kcal, protein_g, set_by)`
unique per engagement-week, RLS parties-read / coach-write;
`my_macro_goal(date)` SECURITY DEFINER for the trainee's effective goal
from any screen (the macro sheet opens from the homepage too, with no
calendar state loaded). Client: a nutrition line under every week's slots
(coach taps to set/adjust for current and future weeks; trainee reads it);
goal sheet prefilled with the goal in force so "same as last week" is one
tap; saving redraws that week and every later week in place (inheritance
changes). Trainee macro sheet fetches the goal, shows targets and live %,
and the save toast carries the result.

**Follow-up 2026-09-07 - goal on the macro dashboard, both roles.**
`renderDashboard` (the Training-tab macro chart, already rendered for coach
and trainee alike) now shows the goal in force this week: a dashed protein
goal line on the grams axis - protein is the base segment of every bar, so
the comparison is direct - with the axis extended to fit it; the per-bar
kcal label turns gold when within ±10% of the calorie goal (kcal has no
axis on a grams chart, so colour carries it); and a header line stating
the goal, marked "(carried)" when inherited. Reads `macroGoals` already
loaded by `renderEngagement`, the chart's only caller - no extra fetch.

Reported "nothing visible" on first try. Two reasons it could show nothing,
both closed: the dashboard returned early with no macro logs in view,
before the macro card (and so the goal) was ever built - the goal header
now shows in that empty state too; and a goal set only for a FUTURE week
(the first row with slots in the coach's screenshot was 14-20 Sep, while
today is in the week of 7 Sep) isn't in force this week, so nothing drew -
it now shows as "Goal from 14-20 Sep: … (not in force yet)" instead of
being silently absent. The bar line and gold kcal colouring still only use
a goal actually in force, since a future goal shouldn't judge this week's
bars.---## AW. Incident: app stuck at "Starting FormTrace…", then "Failed to fetch" on sign-in - RESOLVED 2026-09-07

Not an app bug. The Supabase project's database went down at the TCP
layer (dashboard health: "CRITICAL - Database not usable - CONNECT_TIMEOUT").
Symptoms in order: boot hung at the splash (the first request to hit the
dead database was the profile lookup, which never returned - and the boot
catch only fires on a throw, not a hang, so no "Couldn't start" appeared);
later, sign-in showed "Failed to fetch" (a Cloudflare 522 with no CORS
headers is exactly what a browser reports that way). Resolved by
Settings → General → Restart project. All four services confirmed 200
afterwards; migration data intact.

**How it was diagnosed, for next time** (each step ruled something out):
1. Live file syntax-checked (`node --check` on the extracted module) - OK.
2. Module top level executed in Node with a stubbed DOM
   (`tools/toplevel-check.mjs`, new) - no startup throw.
3. Probed the backend directly from the user's machine: API gateway
   answered (401 with no key, instantly) but auth/data/storage all
   returned 522/544 - i.e. the gateway was up and everything behind it was
   unreachable. That pattern can only be the project's compute, not code.
4. Dashboard health confirmed the database itself was refusing TCP.

**Rule recorded:** "Failed to fetch" on sign-in, or a splash that never
clears with NO "Couldn't start" message, means check the Supabase project
health first - before touching the app. The two commits made just before
the outage (AV) were inside the calendar-open function and could not have
affected boot; I checked that before saying so.

**Could today's migrations have caused it?** A TCP connect timeout means
Postgres wasn't accepting connections at all; a bad query or trigger makes
a database slow, not unreachable, and nothing in migrations_week_model or
the week_start trigger loops unbounded or recurses. Still worth a glance
at Reports → Database for a CPU spike around the outage window - if one
shows, treat that as evidence against the new SQL first. Not verified
from here (dashboard-only).

---

## AV. Regression from AU: "Couldn't load the calendar - Cannot read properties of null (reading 'classList')" - DONE 2026-09-07

Reported after sending a review as a coach. My own regression, from the
latency audit (AU, signature 3): `openEngagement` was changed to show its
spinner immediately by clearing `#engagement-body` up front - but
`renderEngagement` re-parents `#eng-fab-row` (the Goal-complete button
row) INTO that body at the end of every render, and its guard that
rescues the row back out before clearing lives inside `renderEngagement`,
which runs after. So on every SECOND visit to an engagement (open →
review → return is exactly that), the new spinner line destroyed the fab
row before the guard could save it, and the later `fabRow.classList` read
hit null. The original comment on that guard warned about precisely this
failure; I reintroduced it one function upstream.

Fixed by applying the same rescue in `openEngagement` before anything is
cleared, and in `renderEngagement`'s own catch block, which also clears
the body and would otherwise have eaten the row on an error render and
poisoned the next one. Lesson, recorded for next time: any new
`#engagement-body.innerHTML =` must be preceded by the fab-row rescue -
there are now exactly three such sites, all guarded.

---

## AU. App-wide latency audit - DONE 2026-09-07

Requested: scan the whole app for latency, since many buttons don't
respond fast enough. Done systematically rather than by feel - after AR
and AS turned up two separate instances of the same anti-pattern within
a day, it was clear there'd be more. Scanned mechanically for three
signatures, then inspected every hit by hand to separate real problems
from false positives.

**Signature 1 - `await` inside a loop (sequential N+1).** 15 hits, 9
genuine. Fixed:
- `hydrateAvatars`, `hydrateVideos`, and the check-in photo strip - the
  shared media-hydration functions that run on nearly every screen. Each
  requested one signed URL per element, awaited in series - a screen with
  N videos or avatars paid N sequential round trips before the last one
  appeared. All three now resolve every URL in parallel first, then run
  the existing per-element DOM work unchanged. Each promise catches its
  own failure, so one bad path degrades one element instead of throwing
  out of the whole loop (which the old sequential version would have
  done). By far the highest-impact change in this pass.
- A third instance of the S/AS N+1 (one profile query per coach id not
  found in `coaches()`). Batched into one `.in()` query, same fix.
- `checkPendingReview` (runs on every login): one ratings query per past
  goal, in series, until it found an unrated one - so a user whose past
  goals are all rated (the normal state) paid one round trip per goal on
  every login. Now one batched ratings query, then a local Set lookup.
- Day-detail notes: one `dayNotes` query per engagement on every calendar
  day tap - now parallel.
- Set-label inserts on review submit, in two places: one insert per
  labelled set, in series - a 10-set review paid 10 sequential round
  trips on the Submit button. Both now parallel.
- Sibling offer auto-decline on accept: parallel instead of one at a time.
False positives left alone: a sync loop with an unrelated await after
it, an await inside a click handler *defined* in a loop (not run by it),
and the deliberate one-at-a-time large-video download in
`saveWorkoutVideos`, which is the right call for big files.

**Signature 2 - consecutive independent awaits.** 3 places fetching two
unrelated things in series (both engagement lists in `checkPendingReview`
and the profile screen's completed-goals section; pauses + engagements in
`renderGoals`). All now `Promise.all`.

**Signature 3 - screen activated only AFTER its data loads.** This is the
one that most directly produces "I tapped it and nothing happened". Five
open-screen functions did all their fetching first and switched the
screen on as the very last line, so the tap gave no visual response at
all until every round trip finished. Worst was `openEngagement` (tapping
a trainee card): three sequential awaits including the entire
`renderEngagement` load, then the screen switch. All five (`openEngagement`,
`openExEditor`, `openBuilder`, `openOffer`, `openGoals`) now switch the
screen immediately with a placeholder header and spinner, and fill in
behind it. `openBuilder` additionally had two independent fetches in
series, now parallel.

Net: 82 insertions, 38 deletions across the app file; smoke test clean;
re-ran the loop scan afterward and every remaining hit is one of the
identified false positives.

---

## AT. Calendar granularity: weeks instead of days - coaches assign per week, trainees pick their own day

Requested: change the whole calendar from day-level to week-level - a
coach assigns, say, "3 sessions this week" rather than pinning each one
to a specific day, and the trainee has the freedom to do each session
whenever suits them within that week.

Logged as-is, not sized down or reframed as smaller than it is. This is
one of the largest-scope items in this log, because "the calendar" isn't
one screen here - it's the load-bearing structure underneath most of the
app, and a genuine week-level model is a different shape of data, not
just a different grid:

- **Assignment itself.** `assignedWorkouts.due_date` is a specific day
  today. A week-based model needs something like a due_week (or a
  week-start date) instead, with the trainee choosing which day(s) within
  it they actually train - a real schema change, not a display tweak.
- **Streaks are explicitly day-based**, start to finish - "missed a
  workout," "complete tomorrow to reinstate," the whole reschedule-to-
  protect logic (item's own migrations: streak_redefine, streak_reschedule,
  streak_localdate) all reason in terms of a specific calendar day. A
  week-based model needs its own, different definition of what a streak
  even means - "every week's assigned sessions completed" is a
  plausible replacement, but it's a genuinely different rule, not a
  relabeling of the existing one.
- **The calendar UI itself** - the whole gold/pending/rest-day cell system
  built during the theme refresh - is a day-by-day grid by construction.
  Representing "3 sessions, do them whenever this week" probably needs a
  different visual unit entirely (a week row or card showing progress
  through that week's sessions), not a reskin of the existing day cells.
- **Vacation/pause mode** currently freezes specific days on the
  calendar; would need to move to week-level freezing.
- **Scheduled video calls** already have their own, separate day-and-time
  scheduling (availability blocks, specific proposed dates) - probably
  stays exactly as-is, since a call is inherently a fixed-time event even
  in a world where workouts aren't, but worth deciding explicitly rather
  than assuming.
- **Payment cadence (item B)** already thinks in workouts-per-week terms,
  not per-day - this piece may actually simplify or align well with a
  week-based model rather than needing rework.
- **Postponement and wildcard slots** exist specifically because a
  session is pinned to one day today; if the day itself becomes flexible
  within the week, postponement in particular may partly dissolve as a
  concept rather than needing a port to the new model - worth revisiting
  what "postpone" even means once "do it whenever this week" is already
  the default.

Not started. Worth a real design pass - deciding the actual replacement
rule for streaks in particular - before any of this is built, rather
than porting the day-based logic piece by piece and hoping it still
makes sense at the end.

### Design - DECIDED 2026-09-07

Four decisions taken, then the rest follows from them.

**1. Streak = consecutive closed weeks in which every session belonging
to that week was completed.** Counted in weeks, not days. The current,
still-open week never counts yet. A week with no sessions assigned, or
any overlap with a vacation/pause, is *neutral* - it neither extends nor
breaks the streak, it's skipped. Any other closed week with an unfinished
session breaks it. This replaces the day-based `refresh_my_streak` and
retires `reschedule_for_streak` entirely - "move a missed day to protect
the streak" has no meaning once the day was never fixed to begin with.

**2. Leftovers roll over and occupy a slot; workload never grows.** The
coach's weekly target is N (`workouts_per_week`, already on the offer
from item B - reused, not duplicated). When a week closes with unfinished
sessions, they carry into the next week, and that week's pool is still
capped at N: carried sessions fill slots first, oldest first, and any of
the coach's newly assigned sessions that no longer fit are bumped forward
a week. So a trainee always sees at most N this week. The consequence of
missing a session is the streak break (rule 1), never extra work. Weeks
are Monday-Sunday.

**3. Trainee picks on the day.** No pre-planning. Opening the app shows
"This week: 2 of 3 done" and a single *Start a session* action that lists
the week's remaining pool (carried ones first, labelled as carried).
Choosing one stamps it with today's date and starts it. That stamped
date is what puts it on the calendar.

**4. Consequences accepted:**
- Postponement dissolves as a feature. "Do it later this week" is the
  default; "do it next week" is rule 2. The postpone tables and RPCs
  (`request_postpone`, `decide_postpone`, `cancel_postpone`,
  `ack_postpone`) go dormant; removal is a later cleanup item.
- Explicit rest days disappear. A day with no session is just a day.
- The red "missed day" and grey "pending on this day" calendar states
  disappear with them; "streak at risk" becomes "X of N done - week
  closes in Y days".
- Vacation/pause, scheduled calls, check-ins, payments, wildcard slots:
  unchanged mechanically. Pause maps onto weeks as neutral (rule 1).
  Payment already reasons per week and per review, so it aligns.

**Data model.** `assigned_workouts` gains `week_start date` (the Monday
of the week it belongs to). `due_date` stays but becomes *the day it was
actually done* - null until the trainee picks it. Backfill for existing
rows: `week_start = Monday of due_date`, `due_date` unchanged, so every
existing completed session lands on the right day and week with no
visual change. New table `week_closures (engagement_id, week_start,
assigned_count, completed_count, neutral bool, closed_at)` - the streak
is computed from this, and it doubles as the audit trail for "why did my
streak break". A server function `close_week(engagement_id, week_start)`,
idempotent, does the transition: records the closure row, carries
unfinished sessions forward (`week_start += 7`), bumps overflow new
sessions so the new week's pool <= N. Triggered client-side on first
load after a week boundary (same pattern `refresh_my_streak` uses
today), not by a scheduler - nothing to run in the background.

**Calendar UI.** The month grid stays - calls, check-ins and photos still
live on days, and people know it - but the primary unit becomes a week
header row above each week: "7-13 Sep - 2/3 sessions", gold when
complete, neutral when paused/empty, red-marked only after it closes
incomplete. Day cells show completed sessions on the day they were done
(gold), and nothing else about sessions - no pending, no missed, no
rest. Coach sees the same weekly header per trainee, and assigns per
week ("Week of 14 Sep: 3 sessions") instead of per day.

**Build order** (each step deployable on its own; the app keeps working
on the day model until step 5 flips it):
1. Migration: `week_start` + backfill, `week_closures`, `close_week()`,
   new week-based streak function alongside the old one.
2. Trainee pick-a-session flow + week header on the trainee calendar,
   behind a flag.
3. Coach assign-per-week flow + weekly view of trainees.
4. Streak badge, warning copy, remove reschedule-to-protect and
   postponement UI.
5. Flip the flag, retire day-based streak RPCs, log cleanup (W, streak
   items, postponement items marked superseded).

**Step 1 written 2026-09-07 - `supabase/migrations_week_model.sql`, awaiting
run.** Grounded against the real schema first (status set is exactly
assigned/submitted/reviewed - skipping is item-level, not a workout
status; the cap is `offers.workouts_per_week_cap` via `engagements.offer_id`,
not on engagements; `due_date` was already nullable). Decisions made while
writing, beyond the design above:
- New streak goes in a NEW column `profiles.week_streak_count` via
  `refresh_my_week_streak()`; `streak_count` and the day functions are
  untouched, so both measures coexist until step 5.
- `week_closures` is backfilled from history (assigned/completed counts per
  engagement per week, pause overlap = neutral) so the week streak is
  continuous at cutover instead of resetting to zero. The backfill records
  only - it never carries or bumps, so months-old day-model leftovers are
  NOT resurrected into anyone's current pool. The pool is strictly
  `week_start = this Monday`, and only `close_week()` ever moves a row.
- `close_weeks_due(engagement)` is what the client will call: walks every
  unclosed past week in order. One lookup when nothing is due.
- Cap bumping tracks the exact carried row ids rather than inferring from
  created_at order (a coach can assign next week before this week), so a
  carried session can never be the one bumped.
- The bump cascade (bumped rows overflowing the week after) is resolved
  one close at a time, deliberately, not recursively.

**Step 1 RUN 2026-09-07** - sanity: 0 null week_starts, 37 closures
backfilled, 1 trainee already carrying a week streak from history.

**Step 2 DONE 2026-09-07 - trainee side, live.** `WEEK_MODEL=true` flag
(additive only; nothing day-based removed yet):
- Calendar switched to Monday-first (was Sunday-first) so grid rows line
  up with server weeks - `CAL_DOW` and the month-offset both changed; the
  engagement calendar was the only consumer.
- A header row above every week of the grid: date range + count. Past
  weeks read from `week_closures` (gold complete / red incomplete /
  muted neutral with "on a break" or "no sessions"); the current week
  shows done/target live; future weeks show sessions planned.
- "This week" card for trainees above the calendar: X of N done, progress
  bar, days until the week closes, and a single *Start a session* button.
  N is the summed `workouts_per_week_cap` of the active engagements, or
  the live count if no offer carries a cap.
- *Start a session* lists the week's remaining pool in the shared sheet,
  carried sessions first and labelled. Picking one stamps `due_date =
  today` (that is what places it on the calendar) and hands off to the
  existing `openAssigned` path - no second start flow.
- `close_weeks_due` runs per engagement at the top of the calendar fetch,
  BEFORE assigned workouts are read, since it can move rows. Non-fatal on
  error so the day model still renders if the migration is missing.
Coach side unchanged (step 3). Day states, postponement, day streak all
still present (steps 4-5).

**Verified live 2026-09-07:** this-week count matches, past-week headers
read correctly against what happened. One follow-up from the check:
month-edge weeks were cut off (the last August row showed only the 31st).
Fixed - the grid now iterates real dates from the first row's Monday to
the last row's Sunday, so out-of-month days render as ordinary, muted
cells (`cal-outside`) instead of blank fillers. A week is never shown
partially, in either direction.

**Step 3 DONE 2026-09-07 - coach side, live. Needs
`supabase/migrations_week_start_trigger.sql` run.**
- **Real gap found and closed:** the step-1 backfill set `week_start` once,
  but the app's own assignment insert had never set it - every workout
  assigned after that run had `week_start = NULL`, invisible to
  `close_week()` (never counted, never carried). `doAssign` now sets it,
  and a BEFORE INSERT/UPDATE trigger guarantees it on every code path,
  plus a one-off repair of the rows created in the gap.
- **Assigning is per week.** `doAssign` writes `week_start` (Monday of
  whatever day the coach tapped, or of today from the header/card) and
  leaves `due_date` null - the trainee picks the day. Tapping any day
  still works; it just lands the session in that day's week. The picker
  sheet is titled "Assign · week of 14-20 Sep".
- **Week headers are the assign surface for coaches:** current and future
  week rows show "+ Assign" and open the picker for that week. Past weeks
  don't.
- **Coach "This week" card** mirrors the trainee's numbers with an *Assign
  a session* action. Non-blocking notice when an assignment takes a week
  past the agreed cap ("That's 4 sessions ... the agreed number is 3") -
  the coach may mean it, but should know.
- **Unpicked sessions no longer sit on a day cell** - a session with no
  `due_date` belongs to its week header, not to its creation day (which
  is where the old indexing would have put it).
- **Trainees list:** each active card shows "2/3 this week" (gold when
  complete), from one batched query across all active engagements plus
  one for caps - never per card.
Known and accepted for now: the Trainees list reads live rows without
running the week transition first, so a trainee who hasn't opened the app
since the week rolled can show last week's unfinished sessions as still
"this week" until either party opens that engagement's calendar.

**Step 3 revised 2026-09-07 - session slots, per feedback.** Tested live:
assigning still felt date-based (the coach's day tap offered "Assign a
workout" for that date), and an assigned-but-unpicked session showed up
only as a number in the header with no day turning green and nothing to
tap - correct per the model, confusing in practice. Replaced with the
suggested design: every week header carries **one slot per agreed
session**, labelled Session 1..N (N = the cap; for past weeks or with no
cap, however many exist; a coach with nothing assigned gets one empty
slot to start from).
- Coach: empty slot → "+ Assign" opens the picker for that week; filled,
  unstarted slot → tap to remove (confirm dialog), freeing the slot.
- Trainee, current week: filled slot shows the workout name and "Start ▸";
  tapping stamps today and opens it. Future weeks show the name only.
- Done slots go gold with the day it was done; a past week's unfinished
  slot reads "not done" in red. Carried sessions are labelled.
- The coach's day tap no longer offers workout assignment under the week
  model - only the coaching-call proposal, which genuinely is a
  day-and-time event - with a one-line pointer to the slots.
- `startSession(a)` extracted so the slot and the Start-a-session sheet
  share one path.

**Step 3 fixes from live testing 2026-09-07. Needs
`supabase/migrations_calendar_rows.sql` run.**
1. **Statement timeout opening a trainee's calendar as coach - ROOT CAUSE
   FOUND (also the true cause behind AR).** Every `assigned_workouts` row
   carries `snapshot`, which freezes the reference pose LANDMARKS for every
   exercise at assign time - tens of KB per exercise, hundreds per session
   - and the calendar and every sheet it opens only ever read
   `snapshot.name` and the item names/count. A calendar with 40 sessions
   was pulling megabytes per open. New `calendar_rows(uuid[])` function
   returns the same rows with snapshot slimmed to names only, running as
   the caller (SECURITY INVOKER) so the table's RLS applies unchanged.
   `to_jsonb(row) - 'snapshot'` carries every other column automatically,
   so future columns need no change. Client falls back to the full fetch
   only if the function isn't installed. The AR-noted "initial fetch still
   unbounded" concern is largely moot now - the bound that mattered was
   bytes per row, not row count.
2. **"Sessions planned" must be the agreed frequency, not fluctuate.**
   Future-week headers showed however many the coach had assigned so far
   (2, then 1). Now "planned" = the accepted offer's `workouts_per_week_cap`
   always; the assigned-so-far count is shown alongside only when it
   differs ("3 sessions planned · 2 assigned"). Slots already used the cap.
3. **Assigning no longer re-renders the whole screen.** `doAssign` and the
   slot-remove action folded the change into the in-memory week index and
   redraw just that week's header/slots and the this-week card
   (`refreshWeekUI`; the card is now built by `thisWeekCardEl`, and each
   `.cal-week` carries `data-week`). No spinner flash.

**Follow-up 2026-09-07 - "3 planned but I can only assign 1", and a
trainee-side bug found while diagnosing it. Needs
`supabase/migrations_start_session.sql` run.**
- `doAssign` had no error handling at all: a rejected insert died silently
  inside the click handler - "Assigning…" then nothing - which is exactly
  what "I can only assign one" looks like. It now catches and shows the
  database's message verbatim. Diagnosis of the underlying rejection is
  pending that message; nothing on the client limits the count.
- **Trainee "Start ▸" was broken before anyone reached it.** Direct updates
  on `assigned_workouts` are column-restricted to (status, draft, opened)
  since the status/postpone enforcement migrations, and `set_due_date()` is
  deliberately coach-only ("not your trainee") - so the trainee had NO
  permitted way to stamp the day they trained. New `start_session(uuid)`,
  SECURITY DEFINER, scoped to own engagement + still 'assigned' + today
  only (records what happened, never schedules). `startSession()` calls it.
**Step 4 DONE 2026-09-07 - day-based pieces retired (all under the
`WEEK_MODEL` flag; step 5 removes the day code paths and RPCs).**
- **Streak is weeks.** `serverStreak()` calls `refresh_my_week_streak`;
  the badge reads e.g. "3w" with a "3-week streak" tooltip. "At risk" is
  now: sessions still owed this week AND the week closes today or
  tomorrow (`weekRisk()`), on the badge, the calendar warning card, and
  the homepage card - which no longer offers rescheduling (the day was
  never fixed, so there is nothing to move; the action is to train).
- **Calendar days.** A day shows only sessions DONE on it. No red missed
  day (an unfinished session is still owed this week, or carried - not a
  missed day), no gold "rest day" (a day with nothing is just a day).
  Legend entries for both hidden.
- **Postponement hidden:** the trainee's Postpone button, the coach's
  "Modify the workout instead" (move/approve), and the homepage
  postpone-requests card. Tables/RPCs untouched until step 5.
- **BB built here, on the week model** (item BB): the streak burst picks
  its unit from the streak's length - under 3 weeks one square per day a
  session was done; 3 weeks to 3 months one square per completed week;
  beyond, one per month - and always ends with a dashed "current" square
  (today, or this week's done/target). Subtitle states unit and
  "start → today". `weekStreakSquares()` uses calendar rows already in
  memory and fetches light rows only when opened from the homepage.
Known, deferred to step 5: `shareStreakStory` still draws from the day
list; `computeStreak`/`streakDates` remain for the non-flag path.

- **"Only one slot" - REAL CAUSE, and it was never a limit.** The screenshot
  showed a single "Session 1 + Assign" and no planned count: that is what
  renders when the agreed weekly number can't be found (`weekCap` null) -
  the fallback of one empty slot so a coach can at least start. The offers
  table originally stored the weekly number only as free text
  (`sessions_text`, "3 / week"); when `migrations_payment_ledger_v2` added
  the integer `workouts_per_week_cap` it never backfilled it, so every
  offer accepted before that migration has a null cap - and, consequence
  worth noting, the payment ledger's "agreed" denominator was null for
  those same engagements too. Fixed both ways: a one-line backfill parsing
  the leading integer (`migrations_offer_cap_backfill.sql`), and an
  `offerCap(o)` client fallback that parses `sessions_text` when the cap
  is null, used everywhere the cap is read. This also explains the
  earlier "2 planned, then 1" - same null, falling back to assigned-so-far.

---

## AS. Coach's "Trainees" tab also loads slowly - DONE 2026-08-20

Reported as the same slow-loading symptom as AR, on a different screen -
checked whether it was the same cause, and it wasn't, though it's the
same shape of bug. `renderTraineeHome` looks up each engagement's
counterpart profile by first checking `store.coaches()`, then falling
back to a direct profile lookup for anyone not found there. Trainees are
never in `coaches()` by definition, so for a coach viewing their
trainees, every single one of them fell through to that fallback - and
the fallback was a for-of loop doing one separate, sequential
`_sb.from("profiles")...single()` call per trainee, awaited in series,
before the screen could render anything. A coach with many trainees was
paying for that many full round trips back-to-back on every visit to
this tab.

This is the same N+1 shape already fixed once before, in
`renderCoachTrainees` under item S - a separate instance of it, in a
different function, that slipped through that earlier pass since nothing
connected the two at the time. Fixed the same way: batched into a single
`.in("id", missingIds)` query for whichever ids weren't already found via
`coaches()`, instead of one query per id.

---

## AR. Calendar month navigation sometimes hangs or fails with "statement timeout" - DONE 2026-08-20

Reported: clicking the calendar's month arrows sometimes does nothing, or
loads forever and then shows "Couldn't load the calendar - canceling
statement due to statement timeout" - a genuine Postgres-side timeout,
not a client display bug.

Traced to the actual cause rather than guessed at a workaround. The
month-prev/next buttons called `renderEngagement()` again in full on
every single click - re-fetching assigned workouts, pauses, logs, and
call proposals from scratch, every time, none of which depend on which
month is actually being viewed. The assigned-workouts query in particular
has no date-range filter at all - it's every workout ever assigned to
the engagement, unconditionally. For a long-running engagement this
grows without bound, so the exact same click that was instant on a fresh
goal keeps getting slower over months of accumulated history, until it
occasionally crosses the database's own statement timeout - matching the
intermittent, not-every-time nature of what was reported exactly.

Fixed by giving `renderEngagement` an optional `skipFetch` flag, passed
only by the two month-nav click handlers. With it set, the function skips
straight to re-rendering the calendar grid from whatever's already been
loaded into memory - the underlying data never depended on the visible
month, so nothing there needs to change between months anyway. Every
other call site (opening the engagement screen fresh) still fetches
normally and unconditionally, so nothing here trades correctness for
speed - it just stops re-fetching data a click never needed in the first
place.

**Worth knowing, not chased further right now:** the initial fetch itself
(on first opening the screen) still has no date-range bound - it's now
one fetch per screen-open instead of one per click, which should make
timeouts far rarer, but a coach with a very long-running trainee
relationship could still theoretically hit this on that first load.
Scoping the initial fetch to a bounded window would be a separate, larger
change - the streak calculation in particular may need history beyond
the visible month, so it isn't a simple date filter to bolt on without
checking what actually needs the full history versus just this month.

---

## AQ. Coach's Open goals tab: open goals first, sent offers second - DONE 2026-08-19

Investigated before assuming this was a simple reorder. First finding was
wrong and worth naming honestly: an initial code search for `renderMarket`
came back empty, which read as the whole screen being orphaned - reachable
via the bottom nav tab (already correctly wired, `data-go="market"`,
labeled "Open goals"), but with nothing populating its body and no render
function at all. Re-checked before reporting that conclusion, since the
scale of "unbuilt screen" versus "reorder two sections" are very different
tasks - a second, more careful search found `renderMarket` already fully
written a few hundred lines away. The first search result was a tool
glitch, not a real gap.

The actual function was already complete and working, just showing "Your
sent offers" before "Open goals" - the opposite of what was asked. Fixed
by restructuring into two independent, unconditional sections rather than
just swapping code order, since the old shape had two real bugs riding
along with the ordering: the "Open goals" header only ever got appended
INSIDE the sent-offers branch, so a coach with no sent-offer outcomes yet
saw no section label at all above the listing cards; and the old
early-return on zero open listings would have skipped the sent-offers
section entirely for a coach whose offers all belong to now-closed
listings. Both fixed as part of the same restructure.

---

## AP. Tapping a photo (check-in or profile) should expand to full view - DONE 2026-08-19

Checked before writing this down: no lightbox/zoom/fullscreen mechanism
exists anywhere in the app currently — confirmed via a direct search,
not assumed. Every photo the app shows is a fixed-size thumbnail with no
tap behavior at all, whether it's a weekly check-in photo or a profile
picture.

Worth noting for whoever builds this: profile pictures aren't one
one-off element — they're all filled through a shared `data-avatar`
hydration mechanism (`hydrateAvatars`-style, matching the existing
`hydrateVideos` pattern for rotation), already reused across several
screens (offer rows, coach profiles, presumably more). A fix built once
into that shared mechanism would cover every profile picture in the app
at once, rather than needing to be wired individually per screen.
Check-in photos are a separate display path (the measurements/timelapse
screen) and would need their own, similarly-shared tap handler, ideally
following the same visual treatment for consistency between the two.

Given the app has no existing full-screen photo viewer at all, this is
a real, if fairly contained, new UI pattern — not a small tweak to
something that already half-exists elsewhere.

**Built as planned above.** One shared `openPhotoLightbox(url)`/
`closePhotoLightbox()` pair — a centered, full-bleed overlay, deliberately
its own thing rather than a sheet variant, since a sheet stays anchored
to the bottom and a photo wants to be centered and as large as the
screen allows in both directions. Wired into `hydrateAvatars()` itself
(covers every profile picture in the app at once — offer rows, coach
profiles, anywhere else the attribute gets used going forward, with no
per-screen wiring needed) and separately into the check-in photo strip,
the only other place in the app using `data-photo` — confirmed via a
direct search before finishing, not assumed. Both only wire the tap
once a real photo has actually resolved; an initials-only fallback or a
missing photo has nothing to expand into. Dismisses on tap anywhere in
the overlay, including the photo itself — a simple tap-to-expand,
tap-to-dismiss pattern, not a pinch-zoom viewer, matching what was
actually asked for.

---

## AO. Check-in photos and exercise video quality — checked, then changed on request — DONE 2026-08-19

Asked whether the noticeably lower quality on both was intentional.
Traced both, found they were both deliberate but documented very
differently. Videos: capped at 1280x720, re-encoded through the
pose-overlay canvas at 1.6 Mbps, with an explicit comment already
justifying it ("~1.6 Mbps is ample for a short pose-overlay clip and
cuts upload size ~4x vs 6 Mbps") — these are short clips whose real job
is pose-detection accuracy, not visual showcase. Check-in photos: capped
at 1080px on the longer side and saved at 0.82 JPEG quality, with no
comment explaining why — read as a reasonable default rather than a
specifically reasoned choice, unlike the video setting.

Decision: keep the video policy exactly as it is, raise check-in photos
to maximum possible quality. Three changes, check-in capture only:
- `getUserMedia`'s width/height "ideal" raised from 1080/1440 to 4096/4096
  — still just a hint the browser negotiates down to whatever the actual
  camera supports, not a guarantee, but now asking for the device's own
  ceiling rather than an arbitrary target.
- The 1080px downscale cap in the capture canvas removed entirely, not
  just raised — captures now use the video stream's own native
  `videoWidth`/`videoHeight` directly. Removed rather than raised
  specifically because any fixed cap re-introduces the same tradeoff
  this request was about moving away from.
- JPEG quality raised from 0.82 to 1 (`toBlob`'s max).

Checked whether the file-picker fallback (when camera access fails or
isn't available) had its own separate resize logic that would need the
same change — it doesn't; that path has no dimension handling of its
own to update.

---

## AN. A trainee's calendar showed a DIFFERENT trainee's vacation — DONE 2026-08-19

Serious data-isolation bug, reported by a coach with two trainees: one
took a vacation, and the other trainee's calendar showed it too.

Traced to `isPausedOn()`, which checks a date against the entire
module-level `activePauses` array with no engagement awareness at all —
just a flat, unscoped list. `activePauses` itself is populated from
`my_active_pauses()`, which returns every active pause across ALL of
the calling user's engagements. For a trainee that's harmless — every
result is their own goal. For a coach with more than one trainee, it
returns pauses across entirely different people, and nothing filtered
that back down before the calendar rendered.

The function's own comment already explained the "any known range"
approximation clearly and correctly — but that reasoning was written
for a trainee's own multi-goal merged view (all the same person's
data), and never accounted for the coach-with-multiple-trainees case,
where the same array spans unrelated people entirely. A reasonable,
documented tradeoff in one context was a real privacy/correctness bug
in the other.

Fixed at the source rather than threading a new parameter through the
whole dependent chain (`dayState`, `dayComplete`, `dayMissedWorkout`,
the gold-connector checks, several more) — too large and risky a
refactor for what the bug actually needed. `loadActivePauses()` now
takes an optional engagement-id list and filters the RPC's result down
to just those before storing it; every downstream reader is unaffected
and automatically correct once the data itself is properly scoped.
The engagement screen's own call now passes exactly the engagement(s)
relevant to whichever screen is open (all of a trainee's own goals when
merged, or just the one engagement otherwise). The two other call sites
(app boot's streak-badge refresh, and the trainee's own "My Goals" list)
were checked and left passing no filter at all deliberately — both are
genuinely "all of one person's own data" already, never another
person's, so narrowing them would have fixed nothing and risked
breaking something that already worked.

---

## AM. Vacation-pause homepage notification: text fractured into a column one word wide — DONE 2026-08-19

Reported with a screenshot showing the "Resume" button apparently
consuming nearly the whole row, with the pause message wrapping one
word per line. Traced it to a real CSS specificity conflict, not a
sizing or text-length issue: `.vac-resume{width:auto;...}` and the
generic `.btn{width:100%;...}` are both single-class selectors, so
they carry equal specificity — and `.btn` is defined later in the
stylesheet (line 299 vs. `.vac-resume`'s 194), which means it won the
tie on source order alone, silently overriding the button's own
intended `width:auto`. The button was taking the whole row's width,
squeezing the text column (which does have `flex:1`) down to almost
nothing — that's the entire cause of the word-by-word wrapping, not a
message-length or font-size problem.

Fixed with a compound selector, `.btn.vac-resume`, which has higher
specificity than either single-class rule and wins outright regardless
of where either rule sits in the stylesheet — not just re-ordering the
two rules, which would have been fragile against a future edit moving
things around again. Checked every other `width:auto`/fixed-width rule
defined earlier in the stylesheet for the same trap; none of the others
are also classed with `.btn`, so this was an isolated case, not a
pattern needing further fixes elsewhere.

---

## AL. Interval Running: default library exercise + arbitrary segment builder — DONE 2026-08-18, everything, including audio cues, now done

Genuinely one of the largest single features this session. Asked one
clarifying question before building anything: for a "1km in 10 min"
segment, does the distance or the time actually end it? Confirmed
distance — time is a displayed pace target only, which meaningfully
simplified the data model (distance and "time+distance" collapse into
one mode, distinguished only by whether a target_seconds is also set).

**Part 1 (previous entry) covered the migration and the backward-
compatible data model. This part covers the actual builder UI a coach
uses to construct a sequence, replacing the old fixed walk/run/rounds
steppers entirely.**

New segment editor sheet, reusing the existing generic sheet mechanism
rather than building a new modal: a Structured/Free-run toggle at the
top; in Structured mode, a list of the item's current segments with
delete buttons, plus an add-a-segment sub-form (walk/run, time/distance,
the appropriate value inputs, and an optional pace-target toggle only
shown in distance mode); in Free-run mode, a single total-distance
input. `summarizeInterval()` gives the inline workout-builder row a
short, human-readable description of whatever's currently built, since
there's no longer room for the old three-stepper layout inline.

**Two real bugs caught and fixed in the same pass, before either
shipped:**
1. The sheet's "Add"/"Save" button is already reused across several
   existing flows (measurements, macro logging), each guarded by a flag
   checked at the top of one shared `addEventListener` handler — the
   established pattern here. Initially wired the interval editor's save
   action via a direct `.onclick=` assignment instead, which would have
   run *alongside* that existing listener forever after, not replaced
   it — meaning every later, completely unrelated "add exercises" click
   would have also silently re-run the interval save against a stale
   index. Fixed by following the same guard-flag convention already
   established for the other two flows, not inventing a new one.
2. That guard flag (`ivEdIdx`) needed resetting in every path that closes
   or reopens the shared sheet — including cancelling the interval editor
   without saving — or a stale value would incorrectly trigger the same
   bug the next time the button was used for something else entirely.
   Added to `closeSheet()` and `openSheet()` alongside the other two
   flags they already reset, matching what's already there.

**A second real schema gap found running the migration, not caught by
review.** First run failed on `exercises.kind` not existing at all — the
original interval-exercises migration from earlier this session had
apparently never actually been applied to the live database, meaning
the whole feature (including the version built before this one) may
never have worked in production. Fixed by running that migration first.
Second run then failed on `coach_id`'s NOT NULL constraint, which this
migration's whole premise — and the pre-existing `loadCoachExerciseLibrary()`
code it was written for — had assumed away without ever checking the
real schema. Revised to relax that constraint explicitly as its own
step, and made the policy-creation step drop-then-create rather than a
bare create, since it was genuinely unknown whether that part had
already succeeded before the insert failed separately.

**Editor refinements, 2026-08-19, from direct feedback:** up/down
reorder buttons on each segment row (previously delete-and-re-add was
the only way to fix an ordering mistake), and typed minutes+seconds
fields replacing the +/- steppers for duration and pace-target — reaching
an arbitrary value like 1:47 by clicking 15-second increments was slow.
First typed number input anywhere in this app; confirmed the existing
`.field input` CSS already covers `type=number` with no exclusion, so no
new styling was needed.

**DONE, 2026-08-18, part 3 — the tracker screen itself.** Extracted a
shared `advanceToNextSegment()`, called from both completion paths: a
time segment ending in the existing per-second tick, or a distance
segment (including the single "segment" that represents the whole
free-run mode) ending in the GPS callback once its target is reached.
A pace target on a distance segment is confirmed display-only, per the
clarifying question asked before any of this was built — shown as a
goal, never triggers completion itself.

Display branches on the current segment's mode: a time segment still
counts down as before; a distance segment shows elapsed time plus a
progress readout (covered/target) instead of a countdown, since there's
nothing to count down to; free-run mode drops the segment/round concept
entirely and shows total progress toward the one distance goal, with an
optional self-toggle ("Mark as Walking"/"Mark as Running") purely for
the trainee's own record — it doesn't affect completion, which is
distance-only. The summary screen and saved result both branch the same
way, including a separate run/walk time split specifically for free-run
results, and the review screen's own display was checked and needed no
change, since it only ever reads the unchanged top-level totals, never
the per-segment shape directly.

**All three parts of this feature are now complete**: the shared library
exercise, the full segment builder, and tracker execution across every
mode (time, distance, distance-with-pace-target, and free-run). Only
the audio-cues addition below remains open.

**Added to scope, 2026-08-18: audio cues on interval changes, for
headphones users.** Currently the only transition cue at all is a
best-effort vibration (`navigator.vibrate(300)`), silent and easy to
miss mid-run, especially for anyone running with headphones in rather
than watching the screen. Wants a spoken or tonal announcement
specifically when a segment changes — "switching to run", or similar —
not just at the very end of the whole exercise. **BUILT 2026-08-19.** Uses the standard Web Speech API (SpeechSynthesisUtterance) for a spoken announcement rather than a generic tone, since the request was specifically for an ANNOUNCEMENT of what changed, not just a signal that something did. Speaks Walk/Run on each transition and Workout complete at the end, with a distinct longer vibration pattern for the finish so it doesn't feel identical to a mid-workout transition. Vibration kept as a redundant complement, not replaced - speech synthesis being unavailable or inaudible (silent mode, unsupported browser) still leaves the original cue working on its own. Cancels any still-speaking prior announcement before starting a new one, so a fast segment doesn't queue announcements up behind each other.

**A real open question, deliberately deferred rather than chased now:**
asked whether browser autoplay policy or iOS silent mode could silently
block these announcements. Honest answer given: probably not — the
"Start" tap that begins the exercise is itself the genuine user gesture
most autoplay policies require, and speech synthesis specifically tends
to be less strictly gated than `<audio>`/`<video>` autoplay — but this
session already found one real case (the voice-over meter) where audio
that should have worked was silently swallowed by a suspended
`AudioContext`, so "probably fine in theory" isn't the same as
confirmed. **Decision: not worth chasing further right now** — once the
native app wrapper (already logged as an open option under item AD)
becomes the primary way to use FormTrace, native contexts don't carry
the same browser-specific autoplay/silent-mode quirks a web tab does,
which may make this whole question moot on its own. Revisit only if it
turns out to still matter once that decision is made, rather than
building a fallback for a browser constraint that might not need one.

---

## AK. Engagement fab (Complete goal, etc.) floats over scrolling content — DONE 2026-08-18

Reported specifically for the coach's "Goal complete" button, but the
underlying bug is shared across every state this same fab-row shows —
the trainee's own "Mark goal complete", and the post-completion "Rate
your coach/trainee" prompt all use the identical element. Checked before
assuming this was new: a near-identical fix was already made once, for
vacation's "Pause all" control — moved from a floating overlay to
ordinary in-flow content — but that fix was never extended to this fab,
despite a comment nearby that read as if it had been.

`#eng-fab-row` is `position:absolute; bottom:0` via the shared `.fab-row`
class — also used by `#coach-fab-row`, a genuinely floating "create"
button elsewhere that should stay fixed, so the class itself couldn't be
changed globally. Re-parented `#eng-fab-row` into the scrollable body,
after every other section, with its positioning overridden inline
(inline wins over the shared class without needing `!important`) — it's
now ordinary content, only visible once someone has actually scrolled
all the way down, not hovering permanently over everything else. Applies
uniformly to all three states this fab shows, not just the one reported.

**A real bug caught before it shipped, not after:** the very next line
in `renderEngagement()` sets `body.innerHTML` to a loading spinner on
every render — which destroys all child nodes, including the fab-row
itself once a prior render has already moved it inside that body. Left
as-is, every render after the first would have silently broken with a
null `#eng-fab-row` reference. Fixed by moving the fab-row back out to
its original static parent first, every time, before the body gets
cleared — checked for and caught during the same pass, not discovered
by testing afterward.

---

## AJ. Postponement requests should land on a coach's homepage — DONE 2026-08-18

Checked the existing system before building anything, rather than
assuming it didn't exist — it did, partially. A trainee's postpone
request was already visible to the coach in exactly one place: buried as
a single line inside the general activity feed (`renderCoachTrainees`'s
news section), sharing the same "missed workout" icon category as an
actual missed workout — genuinely easy to miss, not a dedicated,
actionable notification. The actual approve/decline UI already existed
too (`openCoachModify`'s sheet, calling the existing `decide_postpone`
RPC), just with no direct path TO it from the homepage — a coach would
need to already know which specific workout had a pending request and
navigate there themselves.

Built `renderHomePostponeRequests`, following the same batched-fetch
pattern already established for `renderHomeReviewDue` (one parallel
fetch per engagement plus a single batched profiles query, not N+1).
Jumps straight to the real approve/decline sheet in one tap — navigates
to the correct engagement first, since that sheet relies on the same
context being set that normal navigation would set, then opens the
specific request. If several are pending across different trainees, the
notification names all of them but the tap leads to the first — a
genuine, small tradeoff of "one notification, one action," not
something worth a more complex multi-target tap for.

---

## W. Trainee calendar: three different "done" states currently look identical — DONE 2026-08-18

Two related asks, both about the gold "complete day" star on the
trainee's own calendar — checked the actual rendering logic before
writing either down, since both are real conflations, not cosmetic
nitpicks.

**1. A reviewed-but-unopened day looks exactly like one the trainee has
already seen.** Wanted: the existing glisten shine (already used
elsewhere — the pending-offer flash, the new-goal CTA) on a gold day
where the coach's review hasn't been opened yet.

**First checked whether "has the trainee seen this review" exists
anywhere — concluded no, started building a new `reviews.trainee_seen_at`
column and a `mark_review_seen()` function. Wrong: it already exists.**
`assigned_workouts.opened` already does double duty — before review it
means "the trainee has opened this workout," and `mark_reviewed()` (the
server function a coach's submission calls) already does
`set status='reviewed', opened=false` in the same atomic update,
specifically so `opened` means "seen this review" from that point on.
`openReview()` already sets it back to `true` the moment a trainee views
their own review, read-only. Caught this by tracing the actual code
before shipping the new migration — deleted it, reverted the batch-fetch
it needed, no schema change was ever necessary.

**The real gap wasn't missing data, it was the frontend not using data it
already had — plus a genuine CSS bug once traced further.** The glisten
trigger (`attnNew`) already checks `reviewed && !opened` and was already
being applied to the cell's class list. What actually suppressed the
effect: `.cal-gold` is declared in the stylesheet AFTER `.cal-glisten`,
and both set `box-shadow` at equal specificity — gold's silently won the
cascade, so the lime attention-ring that makes glisten recognizable
everywhere else in the app was being visually erased on a gold day
specifically, even though the class was present and correct. Fixed with
a `.cal-gold.cal-glisten` combined selector that wins the ring back.

**2. A pure rest day and an actual completed-workout day currently render
identically — both get the same gold star.** Checked why: `dayComplete()`
returns true whenever a day isn't "missed," and a day with literally
nothing assigned trivially isn't missed. The gold-star cell-coloring logic
built for the streak feature never distinguished "did a workout and
finished it" from "there was nothing scheduled" — both were always meant
to not-break a streak, which is correct for the NUMBER, but conflates two
very different days visually. Asked for: same gold family, visually
distinct — not a different color scheme, a different treatment within it.

**Put together, there are actually (at least) three states colliding into
one visual right now, not two:**
- Workout day, reviewed, already seen — the fully-resolved case.
- Workout day, reviewed, NOT yet seen — needs the glisten.
- Pure rest day, nothing assigned — needs its own gold-family look,
  distinct from an actual completed workout.

**A fourth, adjacent case, resolved the same way rather than left open:**
a workout that's submitted but not yet reviewed by the coach at all also
currently reads as a plain gold star under the same logic, identical to a
fully-resolved day. **DECIDED: also visually different, same theme** —
the same principle extended to this case too, rather than leaving it as
an unremarkable gold star indistinguishable from a day that's genuinely
fully resolved.

**Four states now, not three, all needing their own look within the same
gold family:**
1. Workout day, reviewed, already seen by the trainee — fully resolved.
2. Workout day, reviewed, NOT yet seen — needs the glisten.
3. Workout day, submitted, not yet reviewed by the coach — awaiting them.
4. Pure rest day, nothing assigned at all — nothing to distinguish from
   an actual completed workout.

**DONE 2026-08-11 — all four built, no schema change, no new RPC.** State
1 unchanged (`cal-gold`, ★). State 2 is the `.cal-gold.cal-glisten` fix
above. States 3 (`cal-gold-wait`, muted fill, ⏳ badge) and 4
(`cal-gold-rest`, outline only, no fill, no badge) are new CSS variants,
selected in JS purely from `wl` — already-loaded data, no extra fetch —
since within a "complete" day, `wl` can only ever contain
`submitted`/`reviewed` items, never `assigned` (the existing missed/
complete logic already rules that out), making the four-way split
exhaustive and safe. The gold connector chain excludes rest days
specifically: a solid gold bar sprouting from an outlined cell would read
as a rendering glitch, not a deliberate design.

---

## X. Voice-over videos should adopt rotation corrections - DONE 2026-08-11 (see body below - heading was never updated to match)

If a clip is badly oriented and someone corrects it (the existing
per-path rotation fix, "one correction propagates everywhere the clip
appears"), the voice-over recorder and player should show it corrected
too — right now they don't.

**Confirmed, not assumed.** Rotation correction only ever gets applied
through `hydrateVideos()`, triggered by a `data-video` attribute that
looks up the saved rotation for that storage path and applies a CSS
transform. Checked both video elements this feature uses — the one shown
DURING recording (`#vo-vid`) and the one shown during preview/playback
(`buildSyncPlayer()`'s `<video>`) — and neither uses that attribute or
goes through that pipeline at all. Both set `src` directly on a bare
`<video>` tag. So a clip that displays correctly everywhere else in the
app — My Goals, the review screen, the trainee's own workout view — would
still show sideways specifically inside this one feature, since it never
asks whether a correction exists in the first place.

Fix is mechanical, not a design question: give both video elements the
same `data-video` treatment (or call the same rotation-lookup/transform
logic `hydrateVideos()` already has) rather than constructing them as
plain, rotation-unaware tags.

**DONE 2026-08-11.** Built as its own standalone helper
(`applyRotationToBox`/`wireRotation`) rather than refactoring
`hydrateVideos()`'s existing, already-working logic — same aspect-ratio-
swap math, kept separate to avoid any risk of touching stable code for
an unrelated feature. Wired into both places: `#vo-vid` (shown while
recording) and `buildSyncPlayer()`'s video, which needed a new
`videoPath` parameter threaded through both of its call sites so it has
something to look the rotation up by — it previously only ever received
already-resolved URLs, never the raw storage path a rotation is keyed on.
An unrotated clip is left completely untouched (the lookup returns
nothing, layout code never runs), so this only ever changes anything for
a clip that actually needed correcting.

---

## Y. Voice-over: extra time to wrap up after the clip ends - DONE (verified 2026-08-19: manual Stop-recording button already exists - recordBtn toggles onclick to stopRecording - and buildSyncPlayer already keys pause off audio's own ended event, not video's, exactly matching the approach just chosen)

Recording currently stops the instant the clip finishes playing
(`vid.addEventListener("ended", stopRecording)`), cutting the coach off
mid-sentence if they're still narrating when the video reaches its last
frame. Requested: pause on that last frame and give the coach room to
finish talking before recording actually stops.

**One part of this may already happen for free.** Standard video
behavior: a clip that finishes without looping just stops advancing and
sits on its last frame — it doesn't go black or reset. If that's already
true here (needs confirming, not assumed), the visual half of this
request may need no work at all; what's missing is purely the timing —
recording stops immediately, before any "extra time" exists to use.

**A real design choice, not decided here: a timed buffer, or a manual
"I'm done" button?** A fixed few-second grace period (say, 3–5 seconds)
is simple but is a guess at how long any given coach needs to wrap up —
too short for someone genuinely finishing a thought, wasted dead air for
someone who was already done. A manual stop control removes the guessing
entirely: the video freezes on its last frame, recording keeps running,
and the coach taps "Finish" whenever they're actually done, however long
that takes.

**Playback has a real technical consequence worth flagging now, before
this is built, since it affects a piece that already exists.** Once a
recording can run longer than its clip, video and audio have different
durations by design — the sync player's own correction logic currently
assumes they're close to equal, nudging the video's position to match the
audio's every time they drift. If the video reaches ITS end (duration
maxed) while the audio still has extra seconds left, that logic would try
to push `currentTime` past what the video actually has — and more
seriously, `buildSyncPlayer()`'s shared pause handler is wired to the
VIDEO's own `ended` event, which would fire early and cut the AUDIO off
too, silencing exactly the extra commentary this feature exists to
capture. Whatever gets built here needs the pause logic to key off
whichever track is actually longer, not just the video's own end.

**DECIDED and DONE 2026-08-11: manual stop.** Turned out simpler than
either option first described — a Stop button already sits on screen for
the whole recording; the actual bug was the clip's own end silently
overriding it. Fix was removing that override: the video's `ended` event
no longer calls `stopRecording()`, it just updates the status text to
tell the coach the clip's done and they can keep talking. The last-frame
freeze needed no extra code — that's just how a video without `loop`
already behaves.

**The playback fix flagged above was built alongside this, not
separately** — shipping manual stop without it would have meant the
extra commentary got silently cut on playback the moment anyone actually
listened to it, which would have defeated the feature entirely.
`buildSyncPlayer()`'s video `ended` listener no longer calls the shared
pause; only the audio's own end does now, since audio can only be equal
to or longer than video going forward, never shorter. The periodic
drift-correction loop also stops trying to nudge the video's position
once it's finished, rather than repeatedly attempting a no-op seek past
its own duration every 800ms for the rest of playback.

---

## Z. "Increase reps" / "Increase weight" reminder buttons on review — DONE 2026-08-11

While reviewing a set, the coach gets two buttons — "Increase reps" and
"Increase weight." Tapping either means the trainee sees a reminder to do
that, shown the next time they perform the same exercise.

**Checked before logging this — it hooks directly into a mechanism that
already exists, not something new.** `loadPrevSeries()` already reads a
coach's per-set comment from the previous review
(`rev.per_set[].comment`) into `prevSeries.notes[exerciseName]`, shown to
the trainee as a pre-set note before their next attempt — the exact same
placement already used for the personal-best "can you beat it?" note.
`reviews.per_set` is the same flexible jsonb blob tags and comments
already live in (confirmed by item U — no schema change was needed
there either), so a new `directive` key alongside the existing `label`/
`comment`/`voiceover_path` fields is the natural fit, read into a new
`prevSeries.directives[exerciseName]` map the same way notes already are.

**Proceeded with stated defaults on both open questions, since neither
was answered before this was picked up:**
1. **Plain nudge, not a specific target.** Matches the literal ask —
   just "increase," no number. A coach wanting an exact figure still has
   the existing free-text comment for that.
2. **Its own distinct look, not folded into the coach's amber note.**
   Violet — already an established accent colour in this app (macros,
   weight) — distinct from lime (tags), amber (ordinary comment), and
   gold (personal best). An instruction reads differently from an
   achievement or a plain note.

Buttons are independently toggleable (a coach can flag both reps and
weight on the same set), stored as `directives: string[]` alongside the
existing tags/comment on the same `reviews.per_set` entry. No schema
change needed — same reasoning as item U's persistence.

---

## AA. Voice-over preview: no sound, and no way to visually confirm it recorded

Reported by the coach: previewing a just-recorded voice-over produces no
audible sound. Requested fix: an obvious volume meter during preview, so
whether the voice was actually captured can be confirmed by eye rather
than by ear alone.

**Checked the actual preview code before logging this.** `showPreview()`
(inside `openVoiceoverRecorder`) creates a fresh blob URL from the
just-recorded audio and hands it to `buildSyncPlayer()`, which builds a
real `<audio src="...">` element and calls `.play()` on it directly from
a button tap — a genuine user gesture, so browser autoplay restrictions
shouldn't be blocking it. Nothing in this code path explicitly mutes or
zeroes the audio element's volume. On paper it should produce sound; not
reproducible without a device to test on, so the actual cause isn't
confirmed here, only narrowed down.

**Candidates worth checking first, in rough likelihood order:**
1. **Mobile audio-session routing.** A real, well-known quirk on both
   iOS and Android web views: recording through `getUserMedia` can leave
   the browser's audio output routed strangely afterward (e.g. through
   the earpiece rather than the main speaker) until something explicitly
   resets it for playback. Would produce exactly this symptom — a
   correctly-built player that's technically playing but inaudible.
2. **Genuinely silent capture.** The recording settings
   (`echoCancellation`, `noiseSuppression`, `autoGainControl`, all on)
   are reasonable defaults but can occasionally over-suppress a quiet or
   poorly-positioned mic to the point of near-silence, especially
   combined with a device where the mic permission was granted but the
   OS-level input is muted or misrouted.
3. Less likely, but real: a MediaRecorder codec (`audio/webm;codecs=opus`
   preferred, falling back to `audio/webm`/`audio/mp4`) that recorded
   fine but the specific device's `<audio>` element can't decode cleanly.

**The requested volume meter is the right diagnostic regardless of which
of these turns out to be true**, and is concretely buildable: a Web
Audio API `AnalyserNode` can tap either the live mic stream while
recording (catching a dead mic in the moment, before the coach even
finishes) or the recorded blob during preview via a
`MediaElementAudioSourceNode` on the `<audio>` element (confirming the
played-back level, which is specifically what was asked for — visual
proof during preview, not just during capture). Worth building both: a
live meter while recording would have caught this before the coach ever
got to preview at all.

**DONE 2026-08-11 — both meters built, as recommended above.** A live
meter shows during recording, reading the raw mic stream via an
`AnalyserNode` — deliberately wired as a dead end (never connected to
`audioCtx.destination`), so the coach's own voice is never fed back
through their speakers while they're talking. A second meter reacts to
the ACTUAL played-back audio in `buildSyncPlayer()` — the shared player
used both for the coach's own preview and anyone viewing a saved
voice-over afterward — so it's visible everywhere this feature is used,
not just the one screen that was reported.

**The real risk in building this, handled deliberately:**
`createMediaElementSource()` reroutes an `<audio>` element's output
through the Web Audio graph — connecting the analyser as a dead end (the
correct approach for the LIVE mic case) would have silenced the played-
back audio entirely, adding a second, worse silence bug on top of the one
being diagnosed. Wired in-line instead — source → analyser → destination
— so the meter reads the signal without ever being able to cut it off.

**Still true, not resolved by building the meter:** the underlying cause
of the original "no sound" report is not confirmed. The three candidates
above are still just candidates. What this actually gives is the tool to
tell them apart — if the coach records again and the live meter never
moves, the mic itself is dead or misrouted (candidates 2/3); if the meter
moves fine live but the PREVIEW meter stays flat, the issue is specific
to played-back audio (candidate 1, the mobile routing quirk). Worth
retesting with the meters in place before assuming this is closed.

**Reported still not working after the meter fix — added a mic-check
step BEFORE recording, 2026-08-11.** The meter told us whether audio was
present; it couldn't fix a wrong device being selected in the first
place. New pre-recording step: input device selector, the live meter
(reused, now shown here instead of only during recording), an output
device selector, and a "play test sound" button — all before the actual
"Start recording" button becomes reachable. The stream acquired during
this check is the SAME stream reused for actual recording, not
re-requested — this is what guarantees the device confirmed working in
the check is the one that's actually recorded from, rather than the
browser silently defaulting to something else a second time.

**Output device selection has a real, unavoidable platform gap:**
`setSinkId()` is Chrome/Edge/Android-Chrome only — genuinely absent on
Safari and iOS. Detected at runtime, not assumed; the speaker dropdown
hides itself and says so plainly on a device where it can't work, rather
than offering a control that silently does nothing. Given voice-over
recording happens on a phone, an iPhone user will only ever get the mic
selector and test tone (still useful — confirms sound plays at all) —
worth knowing before expecting the output picker to be the fix on iOS
specifically.

**A gap caught before shipping, not after:** the mic-check step acquires
a live microphone stream much earlier than recording used to — as soon as
the sheet opens, not only once "Start recording" is tapped. `closeSheet()`
only knows to release a stream it can see in a shared tracking variable,
which was previously only set once actual recording began. Left as
written, backing out during the check step (the X button, tapping
outside) would have left the microphone running invisibly. Fixed by
tracking the stream from the moment it's acquired, not from the moment
recording starts.

**Root cause confirmed 2026-08-11 — and it's genuinely different from any
of the three original candidates.** The mic-check step itself gave the
decisive evidence: the live input meter moved correctly (mic input was
never the problem), but the OUTPUT test tone was silent — a freshly
synthesised tone, unrelated to MediaRecorder, codecs, or any recorded
blob. That ruled out all three original candidates and pointed at
something more fundamental: an `AudioContext` never being explicitly
resumed. Mobile browsers can create a new `AudioContext` in a `suspended`
state even inside a genuine click handler, despite the spec saying it
should start running on a user gesture — plenty of engines don't honour
that reliably. Anything scheduled on a suspended context plays completely
silently, with no error anywhere.

Fixed in both places that create an `AudioContext`: the test-tone handler,
and — more importantly — `buildSyncPlayer()`'s playback meter, which
routes the ENTIRE voice-over audio element through the same context via
`createMediaElementSource`. **Worth being honest about:** it's genuinely
plausible the playback meter itself, added to diagnose this, was
accidentally the proximate cause of the silence persisting — before that
meter existed, the audio element played directly with no Web Audio graph
involved at all, so a suspended context couldn't have silenced it that
way. Whether that's the FULL story or the original report had some other
contributing cause too isn't fully certain, but the confirmed, reproduced
mechanism is fixed either way.

---

## AB. Graphical and aesthetic improvements — DONE 2026-08-18 (see the full theme-refresh entries below)

Logged as-is — genuinely open-ended, not a specific feature to size.
Nothing wrong identified, nothing broken; just a category to come back to
with concrete direction (which screens, what feels off, what the bar is)
whenever that's ready to give. Not starting from a blank slate: the app
already has an established dark-UI visual language (lime/amber/violet
accents, the gold streak-chain styling, the calm blue treatment vacation
mode got instead of urgent red) that any future pass should stay
consistent with rather than introduce a second style alongside.

**DONE, 2026-08-18 — full theme refresh, worked out through an extended
interview rather than guessed at, then built across three parts.**

Decisions locked in during the interview: pill-shaped buttons and badges,
moderately-rounded cards (the existing 18px already qualified — no change
needed there), minimal/quiet motion only, flat glow-free bar charts
against glowing smooth-curve line charts, and a full calendar rework.

**Primary accent moved from lime (#C8FF3D) to a warm yellow (#F0D231/
#FBE577)** — chosen from a set of colorblind-safe candidates specifically
to avoid colliding with the calendar's gold, while staying distinguishable
from blue/red/violet elsewhere. Colorblind mode's own teal override was
deliberately left untouched — a dedicated accessibility path, not
something that should shift in lockstep with the general default.
Introduced `--lime-light` as a real theme variable so the new gradient
button fill still correctly reaches colorblind mode. Found and bulk-fixed
33 hardcoded `rgba(200,255,61,...)`/`#C8FF3D` references scattered across
badges, chips, and animations that would not have picked up the new
color via the variable alone.

**A real near-miss caught mid-build:** glisten (the "look at this" shine
used for unseen reviews, pending offers, the new-goal CTA) was hardcoded
to `var(--lime)` — meaning it silently inherited the new warm yellow the
moment the accent changed, quietly losing its own long-established
lime-green identity. Introduced a dedicated `--attn` variable, kept at
the historic lime-green (and the colorblind-safe teal in that mode), and
repointed every glisten-related rule to it — buttons, role cards, the
home-nav tab, the pending-offer flash, and both calendar glisten
selectors.

**Buttons**: pill radius, gradient fill, subtle glow — replacing the old
flat single-color fill with no shadow at all. Secondary/ghost buttons
stay quiet at rest and get a subtle border+glow specifically on press,
so a tap still gets a moment of feedback without the accent competing
with primary everywhere.

**Charts**: both existing line charts (weight trend, body measurements)
smoothed with a shared Catmull-Rom-to-Bezier helper, plus a gradient area
fill and soft glow — checked and deliberately did NOT override an
existing "straight segments only, no interpolation implied" data-honesty
principle in spirit: the curve still passes exactly through every real
point rather than freely curving past what was actually measured. Bar
charts (macros) confirmed already flat and glow-free, left untouched.

**Follow-up fixes, 2026-08-18, both from direct testing feedback:**
- **A third weight chart, missed entirely in the original pass.** The
  homepage sparkline and the measurements chart were both found and
  updated, but a third, much more elaborate weight chart inside
  `renderDashboard()` — the one actually shown on the Training tab, with
  value-pill labels, gridlines, and a whole separate goal-progress-band
  overlay — was missed. Same Catmull-Rom smoothing, gradient fill, and
  glow applied, built carefully around the existing goal-band comparison
  logic rather than disturbing it.
- **Colorblind mode's own accent reversed back to yellow, on request** —
  the earlier decision to leave it as its own teal was deliberate at the
  time but wasn't what was wanted once seen in practice. Uses the actual
  Wong-palette yellow (#F0E442), not the same hex as the regular-mode
  warm yellow, since this is a genuine accessibility palette rather than
  a general look. `--attn` (glisten) stays teal in this mode regardless —
  it has to read as distinct from whatever the primary accent is, in
  every mode, or an unseen-review glow would be invisible against a
  yellow button, the same class of problem already caught once this
  session.
- **A genuine pre-existing logic bug, not related to the theme work
  itself — just surfaced because the visual changes prompted a closer
  look.** The weight chart's delta ("+3.7 kg") was computed as the last
  bucket minus the very first one, always — correct for week/day mode,
  wrong specifically in goal mode, where the chart deliberately shows a
  week of pre-goal context before the goal's own start ("week before
  shown unshaded"). The first bucket there is that context point, not the
  weight on the day the goal actually began, so the delta silently
  measured from the wrong moment — exactly the reported symptom, sign
  flip included, since the pre-goal week can run in the opposite
  direction from the goal itself. The correct reference point already
  existed elsewhere in the same function, for the comparison line drawn
  on the chart — computed once, earlier, and reused for both rather than
  duplicated.
- **Macro bar chart refined — corners and colors both, per direct
  feedback.** Top-segment rounding increased from 3px to 6px, kept modest
  since a large radius on a narrow bar segment starts to look like a
  pill, which isn't the intent for this chart. Colors refined toward
  less saturated, more cohesive tones — same hue family (red=protein,
  green=carbs, amber=fat) kept for anyone who's already learned the
  association, just less basic/neon. Fat shifted slightly more orange
  than before, deliberately away from the new primary accent's own
  yellow, so the two don't read as the same hue in different contexts.
  Left the underlying pattern-fill system (dot texture for protein,
  stripe for fat) untouched — that's a distinguishability mechanism,
  not something the color refresh should risk disturbing.

**Calendar, the largest single piece**: gold's achievement-day color was
never actually broken in the real app (only in my own mockup previews,
which briefly and mistakenly substituted lime) — genuinely new here is
gold-wait becoming a darker/muted gold rather than a translucent tint,
gold-rest becoming a filled gold (previously outline-only) with a sleep
badge, paused becoming white with an airplane instead of blue with a
beach chair, and the "macros logged today" diagonal-split triangle
switching from violet to an antique-bronze gold variation so it stays
within the gold family rather than introducing a fourth unrelated hue.
The diagonal split itself, and its exact orientation, already existed in
the real code (`.cal-split`, `.tri-top`/`.tri-bot`) — confirmed matching
what was approved in the mockups before touching anything. One thing
deliberately left alone rather than guessed at: the bottom triangle's
existing solid-color fill for an ordinary to-do day (lime/blue/amber by
status) was untouched, even though my own quick mockup showed it empty —
that mockup was a simplification for demonstrating the top triangle
specifically, not an explicit request to remove an existing, still-useful
signal from every to-do day generally. Legend swatches updated to match
every change above.

---

## AC. Latency optimization — trainee homepage DONE 2026-08-11

Logged as-is. Some of this ground is already covered — item S found and
fixed two real bottlenecks on the coach homepage (four notification
loaders running in series instead of parallel, and an N+1 profile query
per trainee) — so there's a working pattern and a precedent for how this
kind of audit gets done here.

**One concrete, already-identified candidate for next time this is
picked up:** the trainee's own homepage (`renderHome()`'s non-coach
branch) has the identical shape of problem — ten separate card renders
(today's workout, milestone, streak-risk, vacation, reviews, postpone,
macro, macro-gaps, check-in, measurements) awaited one after another
rather than run together. Flagged when item S shipped, deliberately left
untouched since only the coach side was asked for at the time.

**Built — but checked for a real hazard first, not just copy-pasted the
coach-side fix.** The coach side's four cards were safe to blindly
parallelize because they were genuinely independent. The trainee side
isn't quite that simple: `renderHomeMilestone` sets a shared
`milestoneShowing` flag that other cards read to enforce the one-high-
priority-notification rule, and blindly running everything at once risks
a card reading that flag before milestone has actually set it. Checked
every one of the ten calls for a reference to that flag rather than
assume independence — exactly two read it (`renderHomeStreakRisk`,
`renderHomeCheckin`); the other eight don't touch it at all.

Built as two phases: milestone runs alongside `renderHomeToday` first
(the two don't depend on each other), then the remaining eight run
together once milestone has genuinely finished and the flag is settled.
Cuts ten sequential round trips down to roughly two — one for whichever
of the first pair is slower, one for whichever of the remaining eight is
slowest — while the ordering the priority system actually needs stays
intact.

---

## AD. Make the app downloadable and installable — DONE 2026-08-11 (installability only)

Logged as-is — this is PWA support (installable to a home screen,
launches like a native app), and checked before writing this down: there
is currently no web manifest and no service worker anywhere in the app.
Confirmed this directly while investigating an unrelated bug earlier —
so this is a real, clean gap, not something partially there already.

**Worth flagging honestly rather than sizing this as small:** the
manifest and "Add to Home Screen" piece is genuinely straightforward. A
FULL offline-capable service worker is a much bigger, riskier undertaking
for an app like this specifically — nearly everything here is a live
Supabase query (assigned workouts, streaks, offers, payment cycles), and
a naive cache-everything service worker risks serving stale data for
exactly the things that most need to be current (has this been reviewed
yet, is this goal still active, did the coach just decline). If this is
picked up, "installable" and "works offline" should probably be treated
as two separate decisions, not one — the first is cheap and safe, the
second needs real design thought about what's safe to cache and what
never should be.

**Built exactly that split, deliberately not the offline piece.**
`manifest.json` (name, icons, standalone display, dark theme colour) plus
`sw.js` — a service worker that exists purely to satisfy install criteria
some platforms check for, with a `fetch` handler that's a pure pass-
through to the network. No caching at all; every request behaves exactly
as if the service worker didn't exist. `apple-mobile-web-app-*` meta tags
extended (one, `-capable`, already existed) so a saved iOS icon launches
full-screen with a dark status bar and the right home-screen label.

**The SVG-only icon gap turned out to be a real functional bug, not just
a cosmetic shortfall — found when Android Chrome only offered "Create
shortcut," never "Install app."** Chrome's actual installability check is
stricter than the general manifest spec: it wants real PNG icons at
specific sizes (192×192, 512×512), and a spec-valid SVG-only icon set
doesn't reliably satisfy it. Without a qualifying icon, Chrome falls back
to the plain bookmark-shortcut option instead of the real, standalone-app
install flow — which is the actual difference between a genuine PWA
install and just a home-screen link to the page.

**Fixed properly, not worked around.** No AI image-generation tool was
available, but Windows ships with .NET's drawing library, which is
enough to render real PNGs directly — no new software needed. Generated
`icon-192.png`, `icon-512.png`, and a 180px `apple-touch-icon.png`
locally via PowerShell driving `System.Drawing`, same dark-and-lime "FT"
mark as the SVG, then verified by actually viewing the rendered image
before wiring it in rather than trusting the "file written" confirmation
alone. Manifest now lists the PNGs first (what Chrome's check actually
needs) with the SVG kept as a scalable fallback entry alongside them.

**REGRESSION REPORTED, 2026-08-17 — a real contradiction, not yet
reconciled.** Reported as still not actually working, despite the above
and despite "Install app" having been confirmed appearing correctly on
Android Chrome with real icons earlier this session. Genuinely
unconfirmed whether this means: install still isn't offered at all,
install works but the installed app itself is broken somehow, or
something else entirely. Not investigated further per an explicit pause
— worth real priority whenever work resumes here, since it underlies why
item AE/F was also paused (NFC's browser-support story is complicated
enough without an unreliable PWA install on top of it).

**Concrete symptom reported: Chrome only offers a shortcut/bookmark, not
a real install.** Verified everything server-side is correct — manifest
served with the right content-type, valid JSON, service worker correctly
registered — so this isn't a deployment or file problem. Two remaining,
well-documented Chrome behaviors likely explain it, neither verifiable
remotely: Chrome's own engagement heuristic (it withholds the real
install option until it judges the user has visited enough — an
anti-spam measure), or stale cached installability state from visiting
this exact page before the manifest/service worker existed.

**BUILT 2026-08-17 — an explicit in-app install control, Settings.**
Rather than only relying on Chrome's own menu (opaque about why it's
withholding the option), this captures `beforeinstallprompt` globally the
moment the browser fires it — which only happens once Chrome's own
criteria, heuristic included, are actually satisfied — and shows a real
"Install FormTrace" button the app controls directly. Three states, not
one button: already installed (a plain confirmation, detected via the
`display-mode: standalone` media query), iOS (instructions, since iOS has
no programmatic install API at all — nothing can trigger it from a
website), or Chromium not yet ready (honest, diagnostic messaging rather
than hiding this silently, since "not offered yet, try revisiting" IS the
actual answer to why this doesn't appear yet). Doubles as a live
diagnostic for the regression above: if the button never appears after
several real visits, that confirms the engagement heuristic (or
something else) rather than a code defect.

**Confirmed with a real test, 2026-08-17: "not offered yet" on a genuine
first-time check.** This exposed a real, hard platform limit, not a bug —
Chrome's engagement heuristic is deliberate, documented behavior, and no
client-side code can make `beforeinstallprompt` fire before Chrome
decides to. iOS has no such gate at all (Safari's Add to Home Screen is
available on a first visit, already covered), but a brand-new Android
Chrome user genuinely cannot get a real standalone-app install on day
one through this mechanism — worse, their FIRST visit's menu typically
only offers a plain shortcut (opens in a regular tab, address bar and
all), not even a real install.

**Option added, not yet decided or started: a native app wrapper.**
Package this same web app via Android's Trusted Web Activity (or a
framework like Capacitor) for real Play Store / App Store distribution,
side-stepping Chrome's engagement gate entirely since installation then
happens through the store, not through PWA heuristics. Genuinely
different and much larger in scope than anything built for AD so far —
developer accounts, store review processes, a separate build pipeline to
maintain going forward. Worth being explicit that this is a real decision
to make deliberately, not a small follow-on to the work already done
here.

**Re-raised, 2026-08-18: "a wrapped app that everybody can download
regardless of browser."** Same option as above, not a separate ask —
logged here rather than as a duplicate entry so this doesn't fragment
across two places. Worth noting as a genuine signal of priority now that
it's come up a second time, independently of the specific Android-Chrome
symptom that first surfaced it.

---

## AE. NFC "Friendlist"

Logged as-is, and flagged honestly: unclear what this refers to exactly,
not guessed at here. Two real possibilities that would lead to very
different builds: (a) this is the mechanism for populating the
already-logged Team tab (item F) — tap phones to add a training partner
— in which case it's a FEATURE of that larger item, not a separate one;
or (b) a standalone contacts/friends feature unrelated to Team. NFC itself
(Web NFC) is also a real constraint worth knowing going in: browser
support is narrow (Chrome on Android only, as of this app's knowledge),
so whatever this turns out to mean, it likely can't be the only way to
add a friend — needs a fallback for iOS and desktop regardless of what
"Friendlist" itself turns out to mean.

**RESOLVED, 2026-08-17 — this IS item F's connection mechanism, and the
earlier fallback assumption was wrong.** F's scope is narrowed to exactly
this: a friend/connection system working exclusively via NFC — no iOS or
desktop fallback wanted, despite the real browser-support gap flagged
above (Chrome/Android only). That gap doesn't go away; it's now an
accepted constraint rather than something to design around. Challenges
(the other half of F) are explicitly out of scope for now — this is
connections only.

**PAUSED, 2026-08-17, alongside item G.** Not started. Paused specifically
because item AD (PWA installability) was reported as still not actually
working, despite being marked DONE and confirmed live earlier this
session — worth flagging directly rather than quietly accepted: this is a
real contradiction with an earlier verification, not yet reconciled. See
AD below.

---

## AF. Running exercises with flexibility (walking/running alternations, specific durations) — DONE 2026-08-11

Logged as-is. Worth naming plainly: this is a structurally different kind
of exercise from everything built so far, not a variant of one. Every
recording flow in this app — the camera, the pose overlay, `countReps()`,
the whole rep-vs-target comparison — is built around discrete,
REP-counted movements. A walk/run interval ("walk 2 min, run 1 min,
repeat 5×") isn't reps at all, it's DURATION-based, and pose detection
has no obvious role in tracking it — nobody needs a skeleton overlay to
confirm someone is walking.

Building this well likely means a genuinely separate exercise type
(alongside the existing rep-based one) with its own recording flow — a
timer/interval structure, not the camera+pose pipeline — rather than
trying to force it through the existing rep-counting UI. Not sized
further here since that's a real design decision, not a small addition.

**DECIDED: GPS + distance, the bigger of the two options offered.** Built
in full — this touched more of the app than any other single item this
session:

- `exercises.kind` (`'reps'` or `'interval'`) — a coach picks the type
  when creating an exercise; an interval exercise skips the reference-
  video step entirely (no pose overlay has any role here) both in the
  editor and in the library list, which previously showed every exercise
  as "no reference — won't be graded" regardless of kind.
- The actual walk/run/rounds structure is chosen at the WORKOUT-BUILDER
  step, same place sets/reps already live for a reps exercise — not fixed
  on the exercise itself, so one "Interval Run" exercise can be assigned
  differently each time.
- **A real bug caught mid-build, not after:** the workout-save handler
  explicitly rebuilt each item as exactly `{exercise_id, wildcard_mg,
  sets, reps}` — correct for the two kinds it knew about, but it would
  have silently discarded every interval field the moment a workout was
  saved, even though the builder held them correctly in memory right up
  until that line. Fixed to preserve whatever shape an item actually has.
- **Two more found the same way** — `total` (progress count) and the
  `localResults`/`reshapeResults` array sizing all assumed `it.sets` was
  a number; an interval item's `undefined` sets would have produced
  `NaN` progress or relied on an accidental (and fragile) JS quirk to
  behave correctly. Made explicit rather than left to luck.
- A genuinely new full-screen flow (`#s-interval`) — a timer counting
  down through the walk/run sequence, live GPS distance via
  `watchPosition`, a Haversine distance calculation, and a SPEED-based
  filter (not a flat per-ping cap) to reject GPS noise without rejecting
  real fast running. Vibration cue at each segment transition where
  supported. A confirm-before-discard on exit, since closing mid-run
  would otherwise silently lose already-tracked time and distance.
- Treated as ONE result per item (`localResults[i][0]`), not per-set —
  there's no discrete "set" in an interval, so it reuses the app's
  existing skip/submit/draft-save machinery rather than needing its own.
- Review screen: a coach sees a summary card (total time, total
  distance, optional comment) instead of the rep-tag/video/PB/directive
  UI, none of which applies to a result that's a duration and a distance
  rather than a rep count. Explicitly excluded from the `set_labels`
  backfill too — that table is rep-grading data specifically.

---

## AG. Partial workout management — DONE 2026-08-11

A trainee who completes 6 of 7 exercises has no way to submit what they
did — the workout just sits unsubmitted until the due date passes, at
which point it silently reads as a fully missed day rather than a mostly
finished one. Fix: allow submitting a partial workout as genuinely
complete; anything never attempted is recorded as an explicit 0-rep
entry, not left blank.

**Checked the exact mechanism before logging this — it's precise, not a
vague "somewhere in the flow."** `submitToCoach()` itself has no
completeness gate at all; it would happily build a report from whatever
`localResults` holds, empty entries included. The actual block is purely
cosmetic: `submitBtn.classList.toggle("hidden", locked||!allDone||unfilled)`
hides the Submit button entirely unless every single exercise is marked
done. A trainee who can't finish the last one never even sees a way to
submit — not a disabled button with an explanation, just nothing there.

**Open design question, not decided here:** should Submit simply become
available once ANY progress exists, or should hitting it while incomplete
require an explicit confirmation ("1 exercise wasn't attempted — it'll be
recorded as 0 reps. Submit anyway?") so a partial submission is always a
deliberate choice rather than something that could happen by accident?
Leaning toward the confirmation, given how consequential a 0-rep record
is downstream (streak, personal bests, a coach's grading), but not
deciding that silently.

**DECIDED 2026-08-11 — resolved differently than either option above:**
Submit stays gated on full completion exactly as it was. "Complete" now
includes an explicit Skip, which counts toward completion the same as a
real recorded set. This is the confirmation built INTO the action itself
— skipping is always a deliberate tap, never something that happens by
just being allowed to submit with gaps.

**Wildcard specifically gets Skip on the card itself, before the picker
even opens** — a separate, explicit requirement: if that picker is ever
stuck for any reason (this session alone found two real bugs in it), the
trainee still isn't blocked from finishing. `skip_wildcard_slot()` is
deliberately its own function, not routed through `fill_wildcard_slot` —
it never touches the `exercises` table at all, only `assigned_workouts`,
so a future exercises-related bug can't take this escape hatch down with
it. Regular exercises get per-SET skip (not per-EXERCISE) — the natural
unit the calendar already tracks completion in; skipping every set in an
exercise is equivalent to skipping the exercise, so this covers both
cases the request named without needing two separate mechanisms.

A skipped set is recorded as a real entry — `{reps:0, skipped:true}` — not
left blank, satisfying "any incomplete set or exercise should be saved as
0 reps" literally. Shows as "— skipped" in the grade badge, distinct from
an honest 0-rep performance.

**Worth noting as a positive side effect, not the main point:** a
workout that's genuinely submitted (even with skips) stops being derived
as "missed" for streak purposes, and stops inflating a coach's
missed-review numbers (item O) with something that was never actually a
no-show — it was attempted, just not entirely finished. Fixing the
trainee-facing gap here also makes those other two signals more honest.

---

## AH. The pose overlay sometimes doesn't appear, cause unknown

Reported as-is: sometimes the camera doesn't produce the skeleton lines,
reason not yet known. Checked the actual detection loop before logging
this — it isn't a fresh mystery so much as an existing safeguard with a
gap, and there's a concrete, evidence-based lead rather than nothing.

**This exact symptom already happened once before.** `rLoop()` carries its
own comment: forcing a monotonic timestamp and wrapping every frame's
`detectForVideo` call individually exists specifically because a shared-
millisecond timestamp used to throw and "permanently kill the overlay —
lines just stopped appearing mid-session." That fix works as designed:
a `poseFails` counter climbs on repeated failure and triggers
`resetPoseEngine()` once it hits 15, which tears down and rebuilds the
whole pose landmarker (their own comment names GPU context loss on a long
session as the expected cause).

**The gap: `resetPoseEngine()`'s own rebuild can fail, and if it does,
nothing tells anyone.** It calls `ensureModel()` again, and if THAT throws
— genuinely lost GPU access for the rest of the session, not merely a
transient stutter — the catch block only does `console.error("pose engine
rebuild failed")`. No UI message, no retry, no visible state change.
`landmarker` stays `null` permanently. Recording itself keeps working
untouched (video capture doesn't depend on it), but the overlay is gone
for the rest of that session, and rep counting silently stops working
alongside it, since both read from the same landmarks. Nothing in the UI
would tell a trainee any of this happened — only a console error a normal
user would never see.

A second, related gap in the same area: the FIRST-load path
(`ensureModel()` called directly when the recorder opens, before any of
this) fails into a catch that shows one of exactly two messages —
"Camera permission denied" or "Camera needs HTTPS" — neither of which is
accurate if the pose ENGINE failed to load (e.g. a slow or blocked CDN
fetch for the WASM/model files) while the camera itself was fine. Someone
hitting this would be told to fix HTTPS or permissions for a problem that
has nothing to do with either.

**Revised: no desktop console needed to confirm this.** Checked before
assuming otherwise — every `console.error()` call in the app is already
wrapped and automatically sent to `client_errors`, visible on the Admin
screen's error log on any device, phone included. Both "pose detect
failed" and "pose engine rebuild failed" are already being captured this
way with no code change required. Checking that screen after the next
occurrence is the actual next step, not a browser console anyone would
need a computer for.

If the rebuild-failure path IS what's firing, the fix is a visible,
honest banner ("Form tracking stopped working this session — recording
will still work, but reps won't be counted") shown in the recorder itself
at the moment it happens, rather than a failure that only ever reaches an
admin screen after the fact.

**DONE 2026-08-11 — built ahead of confirming the cause,** since both gaps
found were worth closing regardless of which one turns out to be firing:
- `#r-posewarn`, a persistent banner (not `toast()` — the condition
  doesn't resolve itself in a few seconds) shown whenever `landmarker` is
  null after either the initial load or a failed mid-session rebuild, and
  hidden again on a successful rebuild or when the recorder closes.
- **A separate, real bug closed alongside it:** the initial-load path
  used to let a failed pose-engine load (e.g. a slow or blocked CDN fetch)
  block the ENTIRE recorder — camera included — even though recording
  itself never depended on pose detection at all. `ensureModel()`'s
  failure is now caught locally and logged, and the camera starts
  regardless; only the overlay and rep-counting are lost, matching what
  the banner now says honestly rather than stopping trainees from
  recording over an unrelated failure.
- Degrading to zero-reps-detected when pose genuinely isn't available
  composes cleanly with the trainee's existing "Correct my reps" flow,
  already built to handle exactly this shape of problem (a wrong or
  missing auto-count) — no new correction mechanism needed.

Still true regardless: checking the Admin error log after an occurrence
is what would confirm which of the two original leads was actually
firing, if that's ever wanted for certainty — this fix didn't require
waiting for that confirmation first.

---

## AI. Wildcard picker: trainees could never read a coach's exercise library — DONE 2026-08-11

Reported as "wildcard slot says the coach hasn't added exercises, but the
library has two." Traced live, step by step, rather than guessed at:
confirmed the muscle-group key matched exactly, confirmed the coach ID
resolved was genuinely correct, then confirmed — same call, same coach_id,
run as the coach versus run as the trainee — one returns rows, the other
returns nothing. Not a data problem, not a client bug: a permissions gap.

**The original schema never granted a trainee any read access to the
`exercises` table at all.** The only policy on it is "coach manages own
exercises," scoped to `coach_id = auth.uid()`. This never surfaced before
because every other place a trainee sees exercise data comes from the
assigned workout's SNAPSHOT — a frozen copy taken at assign time, needing
no live read. The wildcard-slot feature is the one place that genuinely
needs to read the coach's CURRENT library live, and that read was never
granted when the feature was built.

Fixed with an additive SELECT policy — a trainee may read a coach's
exercises only while they have an active engagement with that specific
coach, same scoping already used for `set_labels`' equivalent policy. No
client code changed; `openWildcardPicker` was already correct.

Also added, mid-diagnosis: `window.__ft` (currentAssigned, currentEng,
engById, traineeEngs as live getters) — the app's script is a module, so
its own state was invisible to a plain DevTools console, which cost a
round trip when a suggested diagnostic snippet threw a ReferenceError for
something that genuinely exists.

---

## Wildcard picker, part 2: filling a slot was blocked by the same class of gap — DONE 2026-08-11

Reported once the read-side fix above unblocked people far enough to
actually reach this: "permission denied for table assigned_workouts"
when tapping "Add to my workout" after choosing a wildcard exercise.

**A hardening migration from an earlier session locked this down after
the wildcard-fill feature was built, and nobody reconciled the two.**
`migrations_status_enforce.sql` revokes blanket UPDATE on
`assigned_workouts` and grants clients write access to exactly two
columns — `draft` and `opened`. Every other column, `snapshot` included,
was moved behind SECURITY DEFINER functions from that point on. The
wildcard-fill code was calling `assignedWorkouts.update(id,
{snapshot:...})` directly — correct when it was written, silently
incompatible with the table lockdown that came later. Nobody had reached
this code path at all until the read-side fix above cleared the way to it.

Fixed with `fill_wildcard_slot(assigned_id, item_index, exercise_id,
sets, reps)` — a real function, not a bypass: verifies the caller owns
the workout and it's still unsubmitted, that the target slot genuinely is
a wildcard, and that the chosen exercise belongs to the right coach AND
actually matches the slot's muscle group, before writing. The picker's
own filtering already implied all of that; this is where it's actually
enforced, consistent with every other trainee-asserted write in this app
going through a checked function rather than a raw column grant.

---

## A. Public coach profiles - DONE (verified 2026-08-19: badges, sub-ratings, all-time stats, expertise, languages, bio all present in renderCoachProfile/coach_public_profile)

Reachable by tapping a coach's name anywhere they appear — offers, the
marketplace, an engagement header. Viewable by any signed-in user.

**Badges**
| Badge | Meaning | How it's granted |
|---|---|---|
| Verified | Admin approved the coach application | Automatic on approval (already happens) |
| Professional | Coaches full time, this is their profession | Mechanism TBD — see open questions |
| Certified Professional | Professional + fitness certifications reviewed and approved | Admin review of submitted certificates |

Certified Professional is an *evolution* of Professional, not a parallel
badge — a coach cannot be Certified without being Professional first.

**Publicly displayed**
- All-time trainees (distinct trainees ever engaged)
- All-time goals (engagements, with completed count)
- Reviews and ratings
- Expertise — single field, coach-authored
- Sub-ratings: Professionalism · Communication · Motivation · Price · Instructions

**Notes**
- Sub-ratings replace the single star score in the rating flow. Existing
  ratings keep their overall score; sub-ratings start empty and accumulate.
  **Correction 2026-08-11:** this was true of the database columns and the
  profile display from day one, but the rate-submission SCREEN itself was
  never actually updated to ask for them — a real user testing a rating
  found nothing there. Fixed: `openRate()` now shows five optional star
  rows (Professionalism, Communication, Motivation, Price, Instructions)
  when a trainee is rating a coach, and none when a coach is rating a
  trainee, since Price/Instructions don't apply to a trainee. Each
  sub-rating is submitted only if actually tapped.
- Show the rating COUNT beside every average. An average without an n is
  close to meaningless and invites over-reading two reviews.
- `profiles` is already readable for coaches (role = 'coach'), so no policy
  change is needed for public visibility.

---

## B. Make the payment cadence visible (lower first commitment) - DONE (verified 2026-08-19: coach_payment_summary RPC, cycle_payment_date math, workouts_per_week cap, and per-trainee totals all present and wired; the provider/settlement piece remains deliberately deferred, matching this item's own stated scope - display and accounting only)

Accepting an offer is not a lump sum. Payment is periodic, tied to review,
so a trainee can stop at any point without owing the remainder of the goal.
This must be prominent at the moment of accepting, because that is where
perceived risk is highest.

**Interviewed 2026-08-08. Mechanics decided:**

**Cadence.** Weekly cycles. A workout becomes payable only once REVIEWED —
never for merely being performed. At the end of the week, everything
reviewed-but-unpaid is queued; the trainee is actually charged and the coach
actually paid **at the end of the following week** (one cycle of float).

**Rate.** Whatever the accepted offer states, per workout reviewed. No
platform floor or ceiling at this stage — the offer is the sole source of
truth for price.

**The review deadline is the sharp edge of this design.** A coach has until
the payment date to review a given week's workouts. If they miss it, that
week's reviews are no longer payable — not delayed, gone. If they review
late but before the *next* payment date, it rolls into that cycle instead.
This is a genuine forcing function: it protects trainees from ever being
charged for a workout nobody looked at, and it gives a coach a real reason
to stay on top of reviews. It also means the system needs to be exact about
"the deadline for week N" versus "the payment run for week N" — those are
two different dates and the wording must never conflate them.

**The three cancellation/no-show cases, each different:**
| Situation | Outcome |
|---|---|
| Coach assigns nothing that week | Trainee may cancel, owes nothing |
| Trainee misses their workout(s) | Trainee owes a **fraction** of the per-workout rate — this fraction must be visible in the offer itself, not discovered later |
| Trainee performs, coach never reviews | No charge that cycle; payable next cycle if the coach reviews late (before ITS deadline) |

The missed-workout fraction is a NEW field on the offer (alongside the
per-workout rate), because it has to be shown to the trainee before they
accept, per point 2.

**Coach-facing summary**, per point 5 — the coach needs to see obligation and
protection at once, broken down per trainee:
- Next payment date
- Per trainee: rate/workout agreed · workouts/week agreed · reviewed-and-
  pending count · computed total
- The "workouts/week agreed" cap matters for protecting trainees from being
  billed beyond what they signed up for — if an offer says 3/week and 5 get
  reviewed, only 3 are payable that cycle. Needs explicit confirmation this
  cap is wanted, but it falls out of point 5's framing and I'm building on
  that assumption unless corrected.

**Provider — explicitly deferred.** No research done, no preference yet.
Per instruction, this is pushed to the end of the sprint, after every other
log item. Until then this phase is display/accounting only: the app computes
and shows exactly what is owed, to whom, and why — no money actually moves.
That is not a simplification for now, it is the whole of what's being built
in this pass; settlement is a separate, later piece of work once a provider
is chosen.

**Data model consequence (not yet built):** this needs a `payment_cycles` or
equivalent ledger — something that can answer "what was reviewed, when, was
it inside its deadline, has it been included in a payout yet" per assigned
workout. This is materially bigger than originally scoped as "make the
existing cadence visible" — it is really "build the accounting model, then
surface it." Flagging that before starting the build.

**Follow-up decided 2026-08-08 (round 2):**

**No-show fee now waits for the payment date too.** Originally specified as
triggering the day after a missed workout — that created a visible
asymmetry (trainee charged immediately, coach's earning question open for
two weeks) which is now removed. Both billing events settle together, once
per week, at the same payment date.

**Billing is per-cycle, not per-line-item.** A trainee is charged ONE number
per week: `(reviewed / agreed) x weekly rate + (missed / agreed) x weekly
rate x noshow_fraction`. Example given: 3 of 4 agreed workouts reviewed →
3/4 of the weekly rate, plus 1/4 x the no-show fraction, summed to one
charge. This means `rate_per_workout_cents` reframes as the derived
per-workout share of a WEEKLY rate (`weekly_rate_cents / workouts_per_week`),
not an independently-set per-workout price — the offer states a weekly
figure and a workouts/week count; per-workout is arithmetic, not a separate
input.

**Coach review deadline gets a 24-hour advance warning**, high priority, on
the coach's homepage — not just a silent cutoff. This is a NEW notification
type, following the same one-high-priority-at-a-time rule as the milestone
and check-in cards.

**Repeated missed deadlines are a coaching-quality problem, not a billing
one.** Per instruction: routinely missing reviews should lead to the coach
being cancelled by trainees and/or removed by the FormTrace team — this is
a moderation/retention signal, not something the ledger itself enforces.

**DECIDED 2026-08-08:** admin controls to surface coaches drifting into
inactivity (e.g. a rising `expired`/missed-review count) and let the
FormTrace team contact them will be built later, as their own item. Not
designed yet; logged here so the payment ledger's data (once it tracks
missed deadlines rather than just charges) is the natural source for it.

---

## C. Streak protection on a missed workout — DONE 2026-08-11

When a missed workout would break a streak, notify the trainee and offer:
- **Reschedule** — move the workout later in the calendar, streak intact
- **Break my streak** — accept it

**DECIDED 2026-08-07:** no coach approval needed, but the new date must fall
**within the next 6 days**, and the trainee must be clearly notified of what
they're doing. This keeps streaks recoverable without letting a trainee push
a workout indefinitely or quietly rewrite the coach's programme.

Built as `reschedule_for_streak(assigned_id, new_date)`, a SECURITY DEFINER
function separate from `request_postpone` (which is coach-approved and has
no day ceiling) — this one commits immediately, only on a workout that's
genuinely overdue, only within the 6-day window, both enforced in SQL so
the client can't widen either. Homepage card sits at the same priority as
the milestone card (highest of the trainee notifications) since a streak
at risk is more time-critical than the weekly check-in's week-long window.
"Break my streak" dismisses that specific miss per-device rather than
deleting anything — the workout stays reachable through the normal
calendar tools if the trainee changes their mind.

Note on the mechanism, since it wasn't obvious until built: the day-state
rule reads a workout's CURRENT due_date, not history, so moving an overdue
workout's date off the day it was due doesn't just avoid a future miss —
it retroactively turns that past day into a rest day. The reschedule is
what actually recovers the streak; there is no separate "un-miss" step.

---

## D. Muscle-group labels on exercises - DONE (verified 2026-08-19: muscle_group field present throughout exercise editor and library filtering)

Coach labels each exercise with a muscle group. Filter the library by muscle
group when building a workout.

Small, self-contained, and a **prerequisite for E**. Good first build.

---

## E. Wildcard muscle-group slots in workouts - DONE (verified 2026-08-19: coach picks group, trainee picks exercise, wired in the workout builder)

A workout can contain a slot like "Wildcard Abs" instead of a named
exercise. The trainee taps it, sees every Abs-labelled exercise in their
coach's library, and picks one. The workout updates with their choice.
Sets and reps are the trainee's to choose.

Depends on **D**.

---

## F. Team tab

Trainee plus friends, group challenges.

Needs a social graph — friend requests, membership, challenge definitions,
shared progress. Large. Also the surface where the wellbeing concerns around
comparison are sharpest; challenges should be built on consistency and
effort, not body outcomes.

**RESOLVED/NARROWED, 2026-08-17 — see item AE.** The connection half of
this (friend requests, membership) turned out to be exactly what AE's
"NFC Friendlist" already meant — scoped down to an NFC-exclusive
connection system, no fallback. Challenges are explicitly out of scope
for now. **PAUSED** alongside AE and G, pending the AD (PWA) regression
being reconciled first.

---

## H. Profile pictures on profiles — DONE 2026-08-11

Avatar upload already exists for the social profile (`profiles.avatar_path`,
`uploadAvatar`, shrunk to 256px on device before upload). Two gaps closed
together, since building K without also fixing this would have meant a
coach's photo appearing on the offer row and then vanishing on their profile:

- The public coach profile now shows the actual photo when one is set,
  via a generic `hydrateAvatars()` helper mirroring `hydrateVideos()` —
  any element with `data-avatar="<path>"` upgrades from initials to a real
  image once its signed URL resolves, initials rendering instantly as the
  fallback so there's no empty circle while it loads.
- Storage policy already allows avatars to be read by anyone
  (`profiles.avatar_path` is in the storage read policy), so no policy work.

Still open: coaches have no obvious in-app prompt to add a photo. Worth a
homepage nudge similar to the check-in/milestone cards, since most coaches
won't have set one and a photo is a cheap trust signal on a marketplace
profile.

---

## I. Age displayed on profiles - DONE (verified 2026-08-19: coach_public_profile computes and returns it, DOB stays private)

**DECIDED 2026-08-07:** age is visible on all profiles. The consent notice is
updated to say so and `CONSENT_VERSION` bumped, which re-prompts every
existing user before their age becomes visible.

Date of birth stays in `profile_private` (owner-only). `coach_public_profile()`
computes the age and returns only the integer, so the birth date itself is
never exposed — a coach's exact DOB is not derivable from their profile.

---

## J. Find a coach - offers grouped by goal - DONE (verified 2026-08-19: auto-decline confirmation text and Archive section both present)

The current screen mixes every offer regardless of goal or status. Rework so a
trainee can tell at a glance what they're working on versus deciding on.

**Show only Pending and Accepted**, visually distinct, so live goals and
decisions-to-make are instantly separable. Finished offers move to an
**Archive** section rather than cluttering the list.

**Group by goal.** A trainee with several goals browses one goal at a time,
with certainty about which goal they're looking at — the current flat list
makes it easy to accept an offer against the wrong goal.

**Visual states needed:** viewed vs unviewed, declined, pending, accepted.
Some of this exists (`unviewed` class) but it isn't systematic.

**Accept confirmation:** "This will auto-decline all other offers for this
goal. Would you like to proceed?" The auto-decline already happens in
`acceptOffer` — it is just silent, which is the actual problem. A trainee
currently declines three coaches without being told.

Note: `openConfirm` already exists and takes exactly this shape.

---

## K. Profile pictures in Find a coach — DONE 2026-08-11

Correction to how this was originally logged: item H had NOT actually been
built when K was written — the public profile rendered initials only, same
as everywhere else. Checking found the gap was in three places, not one:
the offer row, the expanded offer card, and the profile screen itself
(H). All three now use the `data-avatar` / `hydrateAvatars()` mechanism
built for this, so a coach's photo is consistent everywhere a trainee
encounters them in this flow.

Left out of scope: the coach's own trainee-list avatar on their homepage
has the identical gap (initials only), but that's a different surface from
"Find a coach" and wasn't part of this ask — noted here in case it should
be picked up as a quick follow-on.

---

## L. Languages on profiles — DONE 2026-08-11

Add a languages field to both trainee and coach profiles. For a coach this
is a real filtering/matching signal (a trainee who only speaks Spanish
needs to know before messaging); for a trainee it's mostly informational
for the coach.

**Built as a fixed list** (ISO 639-1 codes), not free text — the actual
reason this was requested is marketplace filtering, and free text can't
be filtered reliably without normalising it server-side. Same pattern
already used for country: store the code, let `Intl.DisplayNames` render
the localised name client-side, so no name list ships or needs keeping in
sync.

**Revised 2026-08-11: the ~35-chip picker took too much visible space,
and the actual purpose turned out to be narrower than "profile field" —
it's specifically so a trainee can see language match on an OFFER,
without opening the coach's full profile.** Two changes from the original
build: the picker is now a compact type-ahead (type, pick a suggestion or
press Enter, get a small removable chip) rather than a wall of every
option at once — still backed by the same fixed list, so typing doesn't
mean free text underneath. And a one-line "🗣 language, language" indicator
was added to both the collapsed offer row and the expanded offer card,
omitted entirely when a coach hasn't set any — this is the piece that
didn't exist in the first pass, since the original ask only said "on
profiles."

**Checked before building: no marketplace filter UI exists to consume
this.** "Find a coach" is a reverse marketplace — coaches respond to
posted goals, trainees don't browse a directory — so filtering by
language is still a separate, later piece of work if a browse screen is
ever built. Display (profile + offers) is what exists now.

---

## M. Vacation mode — trainee-initiated — DONE 2026-08-11

A trainee pauses their OWN goal. While paused:
- the streak freezes for both the trainee AND their coach (a coach's own
  "days since last assigned" style numbers shouldn't degrade because their
  trainee is away)
- no workouts are due, none can be marked missed
- a vacation message is visible to the coach, presumably in place of or
  alongside the normal engagement status

**DECIDED 2026-08-11, proceeding on this default since the question was
never answered:** a paused week bills nothing at all — not a pro-rated
partial charge. Simplest reading consistent with "no workouts are due,"
and avoids inventing a day-by-day proration mechanism nobody asked for.

**REVISED 2026-08-11:** pausing is now a whole-account action for the
trainee — one button, every active goal — same shape as the coach's
"pause all trainees" (item N), not per-goal. Reasoning given at the time:
since a pause already meant "everything," scattering the trigger per-goal
on My Goals didn't match how it actually behaves. The trigger moved to a
single button at the bottom of the Training tab (repurposing the fab that
had no other job there, since completion/rating already happens inside a
specific goal). Per-goal `start_pause`/`end_pause` are unchanged underneath
and still exist; `start_pause_all_mine`/`end_pause_all_mine` are the new
"do it to every active goal" wrappers, mirroring `start_pause_all` exactly.
My Goals still shows a paused goal's message, but it's read-only now —
the action lives in one place. **Traded away by this change:** a trainee
running two goals at once can no longer pause just one while keeping the
other active — accepted, since that's what was asked for.

**Built as one shared table and function set with item N** — see N for
what they have in common. The underlying `start_pause`/`end_pause`
primitive is unchanged; only the trainee-facing trigger moved and gained
a bulk wrapper.

**A day only reads as 'paused' when EVERY one of the trainee's active
goals is paused for it** — checked deliberately, not assumed: a trainee
with two goals who pauses only one still has the other's workouts count
normally, since their calendar is genuinely still live for that goal.

**Two real gaps, named rather than hidden:**
1. **The payment ledger doesn't know about pauses yet.** `recompute_cycle`
   still bills a paused week normally. The "bills nothing" decision above
   is only true in the streak/calendar sense right now, not the money
   sense — that needs its own pass on the ledger, which wasn't touched
   here given how sensitive that logic already is.
2. **No server-side block on assigning a workout into a paused window.**
   A coach can still do it today. The day-state fix means it simply won't
   count as missed if they do, but nothing stops the assignment itself.

**A duplicate-logic trap caught mid-build, worth recording:** the
calendar's own cell-coloring code computes "missed" independently of
`dayState()`/`dayMissedWorkout()` — the functions that were actually
fixed for pauses. Fixing only those would have left the calendar itself
still painting a paused day red. Fixed separately, in both the coach and
trainee rendering branches, including making sure a pause doesn't fall
through to the gold-star "achievement" styling either (`dayComplete()`
correctly returns true for a paused day, which is right for the streak
count but wrong for a visual that's specifically meant to celebrate real
completed days).

---

## N. Vacation mode — coach-initiated — DONE 2026-08-11

Same mechanism as M, but the coach pauses ALL their active trainees at
once, with one message shown to all of them.

**Built exactly as suggested here** — one underlying primitive
(`engagement_pauses`: per-engagement, who-triggered, message, start, end),
not two mechanisms. `start_pause_all(message, ends_on)` is the literal bulk
version: one call per active engagement, same table, same day-state logic,
same everything M uses. Entry point is "Pause all trainees" on the coach's
Profile screen, since it's account-wide rather than tied to any one
engagement's screen.

Homepage banner (both roles, calm styling — not the urgent/pulsing
treatment used for streak-risk or check-in, since a pause is a deliberate
choice, not something to react to) shows each active pause with its
message and a Resume button, via `my_active_pauses()`.

**REVISED 2026-08-11:** removed the per-trainee "Pause this trainee"
button that had lived on the coach's individual engagement screen —
symmetric with M's revision, vacation is a whole-account action on the
coach's side too, not something to trigger one trainee at a time. "Pause
all trainees" on Profile is now the coach's ONLY pause trigger. The
underlying `start_pause`/`end_pause(engagement_id)` functions are
unchanged in the database; nothing in the UI calls them for a single
engagement any more on either side (M's revision already removed the
trainee's own per-goal caller) — kept as the underlying primitive rather
than deleted, in case a future feature wants single-engagement
granularity again.

**Not done:** a legend entry for the calendar's new paused-day swatch —
cosmetic, skipped to keep this landing rather than open-ended.

---

## O. Admin: coach inactivity / missed-review monitoring — DONE 2026-08-11

Carried over from item B's interview. Admin-visible signal for coaches
routinely missing their review deadline, so the FormTrace team can contact
them — this is the moderation lever behind "a coach who does this
routinely will probably get cancelled and/or removed."

**Refined the signal before building — "reviewed_count low relative to
agreed_count" alone isn't clean.** A low reviewed count can mean the coach
didn't review, OR the trainee never submitted (`missed_count`), which is
the trainee's fault, not the coach's. The part that's genuinely on the
coach is `agreed_count - reviewed_count - missed_count` — submitted, and
nobody ever graded it. That's the number actually surfaced.

**DECIDED: a raw sorted list, not an auto-"flagged" verdict.** Inventing a
numeric threshold for what counts as "routine" negligence wasn't asked
for and isn't obviously right at any specific number — an admin looking
at coaches sorted by unreviewed count can judge severity themselves. A
hard threshold is a small addition on top of this later if wanted, not a
redesign now.

Window is the coach's last 8 *finalized* weeks (`status <> 'pending'`)
across all their engagements combined, not per-trainee — a coach with
several trainees gets one combined signal, not one row per relationship.
Added as a new section on the existing admin screen, above the coach
applications list, rather than a separate screen — this is the same kind
of thing.

---

## P. The Journey - goal-completion recap - DONE (verified 2026-08-19: full screen with timelapse, weight chart, streak overview, share button all present)

When a goal completes and its final review is submitted, replace the current
thin recap with a richer summary of the whole goal:

1. **Timelapse of every check-in photo taken during the goal**
2. **Weight change over the goal's X weeks**, visualised
3. **Streak overview** — the highest streak reached during the goal
4. **Share button, trainee-only** — a shareable summary of the above

**What already exists, checked before writing this down rather than assumed:**

- `openTimelapse(traineeId, {intro, onDone})` already exists and already
  fires right after a rating is submitted (`openRate`'s submit handler) —
  but it fetches **every check-in the trainee has ever logged**, with no
  date filtering, despite its own empty-state message already saying "for
  this goal." Needs a `fromDate`/`toDate` (or `engagementId`) parameter so
  it actually scopes to the goal that just finished, not the trainee's
  whole history.
- The weight chart's **'goal' dashboard mode** (built for the macro/weight
  dashboard) already computes exactly this: the goal's date span, a shaded
  band, and a start-weight reference line. That rendering logic is directly
  reusable here, not a new chart.
- `openGoalRecap(e, coach)` is the CURRENT recap — a plain sheet with goal
  title, duration, coach name, outcome. This is what "The Journey" replaces
  for the trainee's own completed goals.
  **DECIDED 2026-08-11: a new dedicated screen**, not an upgrade to the
  existing bottom sheet — a timelapse plus a chart doesn't fit that sheet's
  small footprint. `openGoalRecap` stays as-is for the COACH's view of a
  finished goal (no timelapse/chart/share was asked for on that side); the
  new screen is trainee-only per the original ask, reached instead of the
  sheet when the trainee is the one opening a completed goal.
- **Highest streak during the goal does not exist anywhere.** Current streak
  logic (`compute_streak` / `dayState`) only ever computes the streak ending
  at "today" — there is no "longest run within an arbitrary past window"
  query. This is new logic: walk the goal's date range day-by-day (same
  done/rest/missed rule, same 7-rest-day break) and track the longest run
  rather than just the most recent one. Probably a new SQL function
  (`peak_streak_in_range(engagement_id)`) mirroring `compute_streak`'s
  structure, since doing this client-side would mean fetching the whole
  goal's assigned-workout history just to count.
- **Share** has a direct precedent: `shareStreakStory()` /
  `drawStreakStory()` already render a canvas image and hand it to the
  native share sheet with a desktop-download fallback. A "Journey" share
  image is the same mechanism with different canvas content (a collage or
  a few key numbers rather than a single streak count) — build path is
  proven, just needs new artwork.

**Trainee-only** is explicit in the ask — a coach viewing the same completed
goal should NOT get a share button, presumably because the photos and
weight data are the trainee's personal data to choose to share, not the
coach's.

---

## G. Scheduled video calls

**REVISED — the original spec (coach offers three slots, trainee picks one)
was superseded by a more specific design:** both coach and trainee declare
recurring available hours; the trainee proposes a specific time block that
falls within a window BOTH have declared; the coach has 24 hours to accept
or propose an alternate block that's also commonly available.

Largest item, and the only one needing infrastructure we don't have — the
actual video call TECHNOLOGY (WebRTC vs. a paid provider) is still a
separate, undecided question (see below). What's built here is the
SCHEDULING layer that sits in front of whichever gets chosen — a real,
usable feature on its own even before that decision is made.

**Design decisions made explicit, not left implicit:**
- Availability is a RECURRING WEEKLY pattern (day-of-week + time range),
  not per-date — the only realistic thing a person would actually
  maintain, and the natural reading of "hours on their calendar."
- Availability is per-PERSON, not per-engagement. A coach has one real
  schedule; it doesn't change depending on which trainee they're
  scheduling with.
- The 24-hour deadline is a derived check against a stored `expires_at`
  timestamp, not a cron job — same philosophy as every other "missed"/
  "expired" state already in this app (dayMissedWorkout, postpone
  deadlines). This project has no scheduled-job infrastructure; building
  one just for this would be a separate, bigger decision than what was
  asked for.
- The opening proposal is trainee-initiated, matching the spec exactly.
  A coach's counter becomes a new pending proposal under the hood, using
  the same accept/counter mechanism symmetrically — so the workflow
  naturally extends to further rounds without needing a second, separate
  code path for "coach responds" versus "trainee responds."

**DONE — schema, availability declaration, and the full propose/accept/
counter workflow, 2026-08-11.** `availability_blocks` (per-user, recurring)
and `call_proposals` (per-engagement, with `expires_at`). `propose_call`
and `respond_to_call_proposal` are SECURITY DEFINER functions — the
accept/counter logic has real cross-party rules (only the party who did
NOT just act may respond; a proposal can't be accepted twice; a counter
must itself fall within genuine overlap) that a raw insert/update policy
can't express cleanly, so this follows the same pattern as every other
trainee/coach-asserted write in this app. The server independently
re-validates the overlap on every call — the client's own overlap
computation can only ever under-offer valid times, never let an invalid
one through, even if its own logic were wrong.

Built on Profile: an availability editor (day + start + end, add/remove).
Built on the engagement screen (proposing itself is single-goal only —
overlap needs one specific counterpart, so there's no place to propose
FROM the merged multi-goal calendar): a live proposal state (pending/
accepted/expired), a trainee's "propose a time" flow that computes real
overlap for a chosen date and only offers genuinely valid windows, and a
coach's accept-or-counter choice with the 24-hour deadline shown plainly.

**Reported bug, FIXED 2026-08-17: an accepted call didn't show on the
calendar at all.** Root cause was a real design mistake I made, not a
one-off glitch — the coaching-day calendar lookup was gated to the
single-engagement view on the reasoning that "call scheduling needs one
specific counterpart." True for PROPOSING a call, wrong to also apply to
DISPLAYING one that's already accepted — an accepted call has a definite
`engagement_id` and can be attributed to a date exactly like a workout
already is on the merged calendar. Any trainee with multiple active
goals, whose default view is that merged calendar, would never have seen
an accepted coaching day at all. Fixed to aggregate across every active
engagement when merged, the same pattern `engAssignedByDate` already
uses for workouts.

**Still genuinely open, not decided here:** the video call technology
itself. An accepted proposal currently just displays as a confirmed time
— there's deliberately no "join call" button yet, since there's nowhere
for it to lead. See the open questions below for the WebRTC-vs-provider
tradeoff, which is a separate decision from the scheduling layer that's
now built.

**NEW REQUIREMENT, 2026-08-17 — the call must happen INSIDE the app.**
Stated reason: so coaches and trainees can maintain the relationship
without ever exchanging social media or personal contact info. This
meaningfully narrows the earlier open question rather than leaving it
fully open — it rules out the simplest "just hand them a Zoom/Meet link"
approach outright, since that would require exchanging an external
account or contact detail exactly like the constraint says not to. What
it leaves standing: WebRTC embedded directly in the app (no third party
sees the call at all, more build effort, no per-minute cost), or a
provider's SDK embedded in-app rather than linked out to (Daily, Twilio,
Whereby all offer this — the account/contact stays external to the
person, only the SDK is inside the app, but a processor still handles
the actual media). Both satisfy "no social media exchanged"; they differ
on cost, build time, and whether a third party's infrastructure ever
touches the call.

**REVISED AGAIN, 2026-08-17 — initiation direction reversed to match how
workouts are already assigned.** The coach now picks the date and starts
the proposal, not the trainee. This reverses the earlier trainee-proposes
model, not adds a second path alongside it.

Nothing changed on the SERVER for this — `propose_call`/
`respond_to_call_proposal` were already written to check "which party is
this" rather than assume one specific role on either side, so the
reversal is a client-and-placement change, not a schema or function one.
What moved:
- **Entry point**: a coach's tap on an otherwise-empty calendar day now
  offers a choice — assign a workout (existing) or propose a coaching
  call (new) — instead of jumping straight to the workout assigner. The
  chosen date pre-fills the propose sheet, skipping its date picker
  entirely; only the overlap-window step remains.
- The old bottom-of-screen "Video call" card lost its own "propose"
  button and is now purely a status display — waiting, needs your
  response with the 24h countdown, or a plain hint pointing the coach
  back to the calendar when there's nothing pending. Accept/counter for
  whichever party didn't just act still lives there, unchanged.
- **Calendar visual, new**: an ACCEPTED coaching call now replaces that
  date's normal rendering entirely, for either role — a solid blue fill
  (`cal-coaching`), same visual weight as the gold "complete day"
  treatment but a distinct hue, so a coaching day reads as its own
  category rather than a variant of workout/streak coloring. Checked
  first and unconditionally in the cell loop, same priority as the pause
  check beside it.

**Reported bugs, not yet investigated (2026-08-17):**
1. Availability times can be duplicated — nothing stops adding the same
   day and time range more than once.
   **FIXED 2026-08-17.** Checked for genuine overlap before inserting
   (start < existing end AND end > existing start), not just an exact-
   match duplicate — two blocks like 18:00–20:00 and 19:00–21:00 aren't
   identical but are exactly the redundant clutter this was about. Clear
   toast naming the conflicting block on rejection.
2. Coach UI reportedly still shows "No call scheduled yet. Waiting for
   your trainee to propose a time." even after availability has been
   declared. Logged exactly as reported — worth noting honestly, not
   glossed over: that exact wording matches the PRE-reversal coach
   messaging, from before initiation moved to the coach.
   **CHECKED — ruled out as a current code issue.** Searched the live
   codebase directly for that exact string: zero matches, cleanly, not an
   ambiguous or partial result. This was very likely an observation made
   before the coach-initiated redesign had actually deployed, not a bug
   in what's live now.
3. No notification anywhere for a pending proposal — homepage, badge, or
   otherwise. A trainee (or coach, for a counter) only ever sees one by
   navigating to that specific goal and landing on the status card.
   Flagged as a real gap when this was first placed, not new information,
   but now explicitly logged as its own item — worth real weight given
   there's an actual 24-hour clock running against silence.
   **BUILT 2026-08-17.** `renderHomeCallProposal`, role-agnostic (unlike
   the postpone/reviewdue cards, which are single-role) — shows ONLY the
   "needs your response" case, not "you're waiting," since there's
   nothing actionable in waiting and the engagement's own status card
   already covers it for anyone who visits. Wired into both homepage
   render batches, in the already-independent group with no ordering
   dependency on milestoneShowing.
4. Reported: a trainee doesn't see a proposal a coach sent, with a guess
   that deployment might be lagging. **Checked directly — it isn't.** The
   live site is confirmed running the exact commit with the coach-
   initiated flow (`openCoachDayChoice`, `cal-coaching`, `presetDate` all
   present and live). Deployment lag is ruled out as the cause; something
   else is behind this report. Needs a genuine end-to-end test — one
   account proposing, a second account checking the trainee-side card
   directly — to actually diagnose, not further guessing. Possibilities
   not yet distinguished: the proposal never actually got created (an
   error at `propose_call` that wasn't surfaced clearly), the two
   accounts don't share the engagement being checked, a real fetch/
   display bug on the trainee's card, or the browser's own cache serving
   a stale copy of the page independent of server deployment.

---

# Open questions

**C — does streak-protection rescheduling need coach approval?**
Resolved — see section C.

**A — how is Professional granted?**
**DECIDED 2026-08-07:** admin-granted only. It signals experience rather than
credentials — Certified Professional is the credentialed tier above it. Exact
criteria and required proof still to be set, after consulting fitness experts,
lawyers and doctors on who can defensibly be branded professional. Until then
the badge exists, is admin-settable, and is granted to nobody by default.

Implementation consequence: `pro_status` is deliberately excluded from the
client's column grant on `profiles`, so a coach cannot award it to themselves
even through the API. Self-declared badges get discounted by buyers anyway,
so making it forgeable would waste the signal.

**B — payment interview**
- What is the cadence: weekly, per workout reviewed, or both?
- Who sets the amount — coach in the offer, or a platform rate?
- What happens to a partially completed week when someone cancels?
- Is there a payment provider chosen yet, or is this display-only for now?
- Does the coach see expected income anywhere?

**G — build or buy?**
WebRTC directly is free but means signalling, TURN servers and mobile
browser quirks. A provider (Daily, Twilio, Whereby, Jitsi) is days rather
than weeks, but costs per minute and adds a processor holding health-adjacent
conversations — which affects the privacy notice.

---

## Q. Bug fixes from testing round (2026-08-11) — DONE

Four defects found by testing, fixed together rather than as separate
lettered features:

1. **Training tab doesn't highlight; Home does instead.** Checked the whole
   chain (`TAB_SECTION`, `go()`, `openTraineeCalendar`) and the mapping
   reads correctly on paper — `engagement` resolves to the same tab-section
   key as `trainee-home`. Couldn't reproduce a smoking gun via static
   reading alone, so rather than keep guessing at a root cause, made the
   highlight authoritative: `openTraineeCalendar` now force-sets the tab
   button classes directly as its last step, so whatever raced it, this
   wins.
2. **Rotated videos don't adopt their rotation in thumbnails.** The
   rotation logic in `hydrateVideos` was gated entirely on `isPlayer`
   (`.video-card` class) — thumbnails (`.ex-thumb`) fetched the same
   rotation value but never applied it. Added a simple transform for the
   non-player case.
3. **Own profile screen shows initials even with a photo set.** `#sp-avatar`
   had CSS already anticipating an `<img>` but the markup only ever
   rendered initials — the same gap fixed elsewhere (H/K) for OTHER
   people's avatars, missed on the one screen showing your own. Wired into
   the same `data-avatar`/`hydrateAvatars()` mechanism.
4. **Streak-risk card should only fire within 7 days of the miss.** It was
   picking the oldest overdue workout with no lower bound — a workout
   missed a month ago would nag forever even though, per the streak rules,
   whatever it broke is long since resolved one way or the other. Bounded
   to `due_date >= today - 7`.

---

## R. Personal bests per exercise - DONE (verified 2026-08-19: personal_bests_in_range/my_personal_bests/recompute_personal_best all wired)

Each trainee gets a best-ever record per exercise: reps, weight (null for
bodyweight movements like push-ups), and when it was set. Shown before the
set — "Your personal best for this exercise is 10 reps. Can you beat it?"
— using the same "read it before you perform, not after" placement already
established for the coach's previous-workout note. Beating it triggers a
milestone notification, "[Exercise] — New personal best," and the PB is
archived and shown on the trainee's own profile above body measurements,
and again on The Journey (item P) when the goal it was set during completes.

**DECIDED 2026-08-11:** if both reps and weight go up, it's a PB. If one
goes up and the other goes down, it's left unlogged — genuinely unclear
which is the improvement, and no scoring formula is being invented to
force an answer. So four outcomes per set: more reps + same/more weight →
PB; same reps + more weight → PB; one up and one down → no change; neither
improves → no change.

**Keyed on exercise NAME, not exercise_id — proceeding on the recommendation
below since it wasn't overridden.** The same tension as the workout-comparison
feature: a coach can delete and recreate an exercise, two different coaches
can each have their own "Push-ups" row, and the wildcard-slot mechanism
(item E) lets a trainee freely pick between different underlying exercise
records for the same muscle group. Keying on `exercise_id` would mean a
trainee's push-up PB resets every time any of that happens, which doesn't
match "your push-up PB" as a trainee would expect it. Keying on a
normalised name merges those cases correctly but also merges two genuinely
different movements that happen to share a name across coaches — accepted
as the smaller cost.

**Checked when RECORDED, not when reviewed.** Rep counts already work this
way elsewhere (the trainee's own corrected count drives the vs-last-time
comparison without waiting on the coach), so a new PB would show and
notify immediately on the trainee's confirmed number. Worth confirming a
coach is comfortable with an unreviewed set being able to set a PB, since
it's a small trust extension beyond what currently exists.

**Reuses three things already built, all in the codebase now:**
- The previous-note placement pattern (before the set, not after) from the
  workout-comparison feature.
- The milestone notification mechanism and its one-high-priority-at-a-time
  rule — a new PB needs its own slot in that arbitration alongside the
  streak milestone, streak-risk, and check-in cards. Priority against the
  existing streak milestone isn't decided; recommend PB below streak
  milestone (rarer, more consequential) but above check-in.
- The Journey screen (item P) already has a card-based layout for
  goal-completion facts; "Personal bests reached this goal" is a new card
  there, not a new screen.

**New data model, not yet built:** a `personal_bests` table keyed on
(trainee_id, exercise_key), holding reps/weight/achieved_at/assigned_id,
written only by a SECURITY DEFINER function — consistent with every other
trainee-asserted number that matters in this app (the streak, the payment
ledger, workout status) being server-checked rather than client-writable.

---

## S. Make coach notifications load faster - DONE (verified 2026-08-19: N+1 query eliminated in renderCoachTrainees, batched profile lookups)

Checked the actual coach homepage load path before writing this down.
Two real, well-defined bottlenecks; two other parts of the same path are
already fine and shouldn't be touched.

**1. The four notification loaders run one after another, not in parallel.**
`renderHome()`'s coach branch does:
```
await renderHomeReviewDue(...);
await renderHomeDeclined(...);
await renderCoachHome(...);
await renderCoachTrainees(...);
```
None of these four depend on each other's output, and each writes to its
own DOM node. Run serially, total wait is the SUM of all four round trips;
run via `Promise.all`, it's roughly the SLOWEST of the four. This is the
single biggest, safest win — same class of fix as the trainee-side
`renderHome()` already went through, just the ordering this time rather
than the stale-render bug found there.

**2. `renderHomeReviewDue` fetches one trainee's name per engagement,
separately.** Inside its per-engagement loop it does two round trips —
`assignedWorkouts.list`, then a SEPARATE single-row `profiles` query for
that one trainee's `display_name` — repeated once per active engagement.
For a coach with many trainees that's N profile queries where one batched
`select id,display_name from profiles where id in (...)` would do, plus
each engagement's own two queries are sequential when they don't need to
be. `renderCoachTrainees` (a different function, also called from the same
`renderHome()`) already solved exactly this problem — it has a comment
noting it used to be "4N+1 queries" and is now "four queries total,
regardless of trainee count," via batched `.in()` calls. `renderHomeReviewDue`
should get the same treatment.

**Already fine, checked and left alone:** `renderCoachHome` (one engagements
query, then a properly parallel `Promise.all` across engagements) and
`renderCoachTrainees` (already batched to a fixed 4 queries). Worth stating
so nobody "fixes" something that isn't broken while addressing the above.

---

## T. Audio on exercise/reference recordings — DONE 2026-08-11

All videos were silent for four of six recording types. Checked `startCam()`
before treating this as a from-scratch build, and it wasn't one: audio
capture already existed, gated behind a per-call flag —

> "Pitch videos are spoken to camera, so they ask for the mic. Set videos
> and references stay silent."

So marketplace pitch videos already recorded sound; exercise sets, coach
references, video notes, and per-set feedback videos were silent by a
design decision already in the code, not an oversight.

**DECIDED 2026-08-11:** enabled for every recording type, matching the
request as given rather than scoping it down over the unaddressed gym-
privacy question. `wantAudio` is now passed for the Reference recorder,
the exercise-set recorder, the coach's "Video note," and the per-set
"Feedback video" — the two that already asked for it (goal/pitch videos)
are untouched. Preview-only calls (playback, not recording) were correctly
left alone throughout.

Consent notice updated to say recordings now include sound, and
`CONSENT_VERSION` bumped to `2026-08-v3` so every existing user is
re-prompted before microphone capture starts for them — same treatment as
the age-visibility change, since this is the same class of "a new kind of
data is now being captured" event.

---

## U. Grading: drop the numeric score, make the tags multi-select — DONE 2026-08-11

**Checked the actual review screen before logging this — it changed the
scope a lot.** The five tags in the request already existed verbatim in
the code: "Nailed it," "Good," "Watch depth," "Slow down," "Fix form."
They sat alongside a required 1–10 numeric grade (`form_grade`), and were
single-select.

**A wrong turn worth recording honestly, since it nearly shipped.** First
pass concluded the tag/comment were never persisted anywhere at all — only
`set_labels.form_grade` existed as a column, no `label` or `comment`
column did — and started writing a migration to add `form_tags text[]`
and `coach_comment text`. That was solving a problem that didn't exist:
`reviews.per_set` (a jsonb blob, written once when a review is submitted)
was already the real, working persistence path for the tag and comment —
just checked in the wrong table. Caught before running the migration;
that file is now a note explaining the wrong turn, same treatment as the
superseded v1 payment-ledger file. **No schema change was needed for this
item at all.**

While restructuring the review screen around this correction, an edit
briefly left `if(readonly){}else{}else if(...)` in the file — not valid
JavaScript — plus an orphaned closing brace from a removed wrapper.
Neither was caught by eye; both were caught by re-reading the file
directly and confirmed fixed by the smoke test passing, which is what
should be trusted here, not my own confidence.

**What actually shipped:** the numeric grade UI is gone. Tags toggle
independently (multi-select) and save as `labels: string[]` inside the
existing `reviews.per_set` blob — old reviews that saved one tag as
singular `label` still display correctly (read as a one-item array). The
"leave without saving" and "send without grading" checks now look for a
tag instead of a numeric grade. The trainee-facing read-only view (the
same screen, gated by `readonly`) shows the saved tags and comment, which
is the actual point of grading — the trainee is meant to see it.

---

## V. Coach voice-over an existing (trainee) video — DONE 2026-08-11

Coach records their own audio commentary while watching the trainee's
submitted clip play, so the trainee can watch their form with the coach
talking over it — not a second video, a voice track added to the one that
already exists.

**Built as option 1 from the two logged here** (proceeding on the
recommendation since it wasn't overridden): audio-only capture, no video
re-encoding. No muxing library, no server step.

**Genuinely new code, not a variant of anything existing** — `openRecorder`
is built around the camera (preview, pose detection, countdown), which
doesn't fit "play back a clip that already exists while capturing only
the mic." Built as its own small flow inside the review screen's shared
bottom sheet: the trainee's clip plays (muted) while `getUserMedia({audio:
true})` records; the recorder starts an instant before playback rather
than after, so a few ms of recorded silence at the front is harmless where
a missed first instant of speech wouldn't be. The clip's own `ended` event
stops the recording automatically, which is what actually keeps the two
in sync — they started together and the clip's own length decided when
they stopped.

**No schema change** — same lesson as item U: `reviews.per_set` already
takes arbitrary keys, so `voiceover_path` is just a new field in the same
jsonb blob, alongside the existing `video_path` (a full feedback video) and
`comment`. A coach can use either, neither, or in principle both; they're
independent.

**Playback is a small synced dual-track player** (silent trainee video +
coach's audio, one shared play/pause button, periodic drift correction
rather than trusting two independent media clocks to stay matched over a
whole clip) — used identically whether it's the coach previewing their own
recording before saving, or the trainee viewing it afterwards on the
read-only review screen.

**Caught before it became a real leak:** the generic review-sheet close
button and the tap-outside-to-dismiss scrim both call one shared
`closeSheet()`, which had no way to know a microphone stream was open if
someone closed the sheet mid-recording — the stream and recorder were
local to the recording function and would have been silently orphaned
with the mic still live. Tracked in a small module-level `voState` so
`closeSheet()` can stop both if it needs to, rather than assuming the
happy path (Stop, then Save) is the only way this screen gets left.

---

Risk register fully closed: storage lockdown, account deletion,
consent + age gate, private profile fields, server-enforced scheduling and
status, streak redefinition, error reporting, query batching.

Features: postpone requests + notifications, streak celebration +
milestones + shareable story, workout-vs-previous comparison, macro/weight
dashboard rework, landscape recording + post-hoc video rotation, single
rep-correction button, one-high-priority-notification rule.
