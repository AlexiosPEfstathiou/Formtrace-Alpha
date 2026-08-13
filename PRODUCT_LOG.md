# FormTrace — Product Log

Opened 2026-08-07. Ordered by dependency, not by size.

---

## A. Public coach profiles  ← STARTING HERE

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

## B. Make the payment cadence visible (lower first commitment)  ← NEXT

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

## D. Muscle-group labels on exercises  ← STARTING HERE

Coach labels each exercise with a muscle group. Filter the library by muscle
group when building a workout.

Small, self-contained, and a **prerequisite for E**. Good first build.

---

## E. Wildcard muscle-group slots in workouts

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

## I. Age displayed on profiles

**DECIDED 2026-08-07:** age is visible on all profiles. The consent notice is
updated to say so and `CONSENT_VERSION` bumped, which re-prompts every
existing user before their age becomes visible.

Date of birth stays in `profile_private` (owner-only). `coach_public_profile()`
computes the age and returns only the integer, so the birth date itself is
never exposed — a coach's exact DOB is not derivable from their profile.

---

## J. Find a coach — offers grouped by goal

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

## L. Languages on profiles

Add a languages field to both trainee and coach profiles. For a coach this
is a real filtering/matching signal (a trainee who only speaks Spanish
needs to know before messaging); for a trainee it's mostly informational
for the coach.

Open question: free text, or a fixed list with multi-select? A fixed list
is filterable on the marketplace (find a coach who speaks X); free text
is not, without normalising it server-side. Recommend fixed list given the
marketplace-filtering use case is the actual reason this was requested.

---

## M. Vacation mode — trainee-initiated

A trainee pauses their OWN goal. While paused:
- the streak freezes for both the trainee AND their coach (a coach's own
  "days since last assigned" style numbers shouldn't degrade because their
  trainee is away)
- no workouts are due, none can be marked missed
- a vacation message is visible to the coach, presumably in place of or
  alongside the normal engagement status

Interacts directly with the streak redefinition (register item, now closed)
and the payment ledger (item B): a paused week should presumably not bill
either the reviewed-share or the no-show-share, which needs its own case in
`recompute_cycle` — a vacation week is neither reviewed nor missed, it's
exempt. Needs deciding before building: does a vacation week bill nothing,
or a pro-rated nothing based on days paused?

---

## N. Vacation mode — coach-initiated

Same mechanism as M, but the coach pauses ALL their active trainees at
once, with one message shown to all of them. Likely shares most of its
implementation with M — a pause is a pause regardless of who triggered
it — with the coach's version being "apply this to every active
engagement" rather than one.

Worth building M and N as one underlying pause primitive (per-engagement,
who-triggered, message, start, end) rather than two separate mechanisms,
given how similar the requirements are.

---

## O. Admin: coach inactivity / missed-review monitoring

Carried over from item B's interview. Admin-visible signal for coaches
routinely missing their review deadline, so the FormTrace team can contact
them — this is the moderation lever behind "a coach who does this
routinely will probably get cancelled and/or removed."

The payment ledger (`payment_cycles`, once populated with real cycles) is
the natural data source: a rising count of cycles where `reviewed_count`
is low relative to `agreed_count` is exactly the inactivity signal needed.
Not designed yet — needs an admin screen and probably a threshold/alerting
rule, which doesn't exist for anything else in the app yet either.

---

## P. "The Journey" — goal-completion recap

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

Coach offers three time slots on a single day; trainee accepts one. At that
time both join a call in the app to review the week.

Largest item, and the only one needing infrastructure we don't have.
Build-vs-buy decision required — see open questions.

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

Risk register fully closed: storage lockdown, account deletion,
consent + age gate, private profile fields, server-enforced scheduling and
status, streak redefinition, error reporting, query batching.

Features: postpone requests + notifications, streak celebration +
milestones + shareable story, workout-vs-previous comparison, macro/weight
dashboard rework, landscape recording + post-hoc video rotation, single
rep-correction button, one-high-priority-notification rule.
