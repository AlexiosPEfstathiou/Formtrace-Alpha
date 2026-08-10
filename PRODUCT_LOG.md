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

## B. Make the payment cadence visible (lower first commitment)

Accepting an offer is not a lump sum. Payment is periodic — weekly, per
workout reviewed — so a trainee can stop at any point without owing the
remainder of the goal. This must be prominent at the moment of accepting,
because that is where perceived risk is highest.

**Needs an interview before building.** Open questions in the section below.

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

**Blocked on a decision, not effort.** Date of birth was deliberately moved to
`profile_private` (owner-only RLS) because `profiles` is readable by every
signed-in user for any coach, and RLS cannot hide a column.

So age cannot simply be added to the profile row. Two options:

1. `coach_public_profile()` computes age from `profile_private` and returns
   only the integer. Works today — the function is SECURITY DEFINER — and
   never exposes the date itself.
2. Store a coarse public band (`30s`, `40s`) instead of an exact age.

Either way it needs **explicit consent**: the consent notice currently says
this data is visible only to the coach. Publishing age to strangers changes
that promise, so the notice needs updating and existing users re-prompted
(bump `CONSENT_VERSION`, which already triggers a re-prompt).

Recommend option 1 with an opt-in toggle, defaulting off. Age is a plausible
experience signal for a coach and irrelevant for a trainee, so it may be
worth showing on coach profiles only.

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
