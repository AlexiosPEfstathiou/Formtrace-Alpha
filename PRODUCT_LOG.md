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

## C. Streak protection on a missed workout

When a missed workout would break a streak, notify the trainee and offer:
- **Reschedule** — move the workout later in the calendar, streak intact
- **Break my streak** — accept it

Offered indefinitely, so a streak is always recoverable.

**DECIDED 2026-08-07:** no coach approval needed, but the new date must fall
**within the next 6 days**, and the trainee must be clearly notified of what
they're doing. This keeps streaks recoverable without letting a trainee push
a workout indefinitely or quietly rewrite the coach's programme.

Implementation note: needs its own SECURITY DEFINER function rather than
reusing `request_postpone` — that one sets status 'pending' and waits for a
coach. This one commits the move immediately, with the 6-day ceiling enforced
in SQL so the client cannot widen it.

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

## H. Profile pictures on profiles

Avatar upload already exists for the social profile (`profiles.avatar_path`,
`uploadAvatar`, shrunk to 256px on device before upload). What's missing:

- The public coach profile renders **initials only** — it should show the
  actual photo when one is set.
- Coaches have no obvious prompt to add one. A photo is a cheap trust signal
  on a marketplace profile and currently most coaches won't have set one.
- Storage policy already allows avatars to be read by anyone
  (`profiles.avatar_path` is in the storage read policy), so no policy work.

Small. Worth doing alongside anything else that touches the coach profile.

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

## K. Profile pictures in Find a coach

The public profile shows an avatar (item H); the coach BROWSE list itself
(the actual "Find a coach" tab, before opening a profile) still shows
whatever it showed before H — needs checking whether that's initials or
nothing, and wiring the same avatar there.

Small — same asset, same `avatar_path`, second render site.

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

# Done (this session)

Risk register fully closed: storage lockdown, account deletion,
consent + age gate, private profile fields, server-enforced scheduling and
status, streak redefinition, error reporting, query batching.

Features: postpone requests + notifications, streak celebration +
milestones + shareable story, workout-vs-previous comparison, macro/weight
dashboard rework, landscape recording + post-hoc video rotation, single
rep-correction button, one-high-priority-notification rule.
