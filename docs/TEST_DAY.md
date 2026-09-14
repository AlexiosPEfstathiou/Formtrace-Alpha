# FormTrace Coach — Alpha test day pack

*Items BU (test day) and BP (seed goals). Print, or open on a second screen.*

---

## 1. The plan

**Who plays whom.** Two testers, two phones. One is the **coach** for the whole day, the other the **trainee**. Do not swap mid-way — half the bugs live in the hand-off between roles, and swapping hides them. The project owner runs a third device as **admin** (approvals, badges, certifications).

**Before the day (owner, ~20 min).**
- Run every pending SQL from the product log (badges, top1, platform_rates, referral trainees-only, cert seen, call meeting url, video trim, offer start date, committed length, recurring calls, propose any time).
- Confirm both phones open the live URL and can grant camera + microphone.
- Post the **five seed goals** from section 4 from the trainee phone (or a second trainee account) so the coach's first Open goals tab is not empty. Time how long each takes — that is a finding too.
- Decide the two accounts' names; the trainee should sign up through the coach's **referral link** as the very first step so BN gets exercised.

**Rules of the day.**
- Follow the lists top to bottom. The order is the real order of a goal's life.
- Tick each line as **✓ worked**, **~ worked but odd**, or **✗ failed**, and write one line in Notes in your own words. Do not diagnose — describe what you saw and expected.
- Read the "not yet testable" list out loud at the start so nobody reports payments or automatic Meet links as bugs.
- Every ✗ and every ~ becomes one product-log item, with the tester's words.

**Not yet testable — say it out loud:** payments and any money moving (BI), automatic Google Meet creation (the link is pasted), push reminders, iOS install, the Android app (AD), NFC (AE), and background blur on a phone you have not tried it on before (BT — try it, but treat frame-rate as the thing to observe, not a pass/fail).

**Timing.** Trainee list ≈ 2.5 h with a real workout in it; coach list ≈ 2 h; they interleave (the coach cannot review before the trainee submits). Plan a half day.

---

## 2. Trainee checklist

| # | Step | Where | ✓ / ~ / ✗ | Notes |
|---|------|-------|-----------|-------|
| 1 | Sign up **through the coach's referral link**; see "You joined through …'s link"; age + consent gate; profile photo; theme, colourblind mode | Sign-in, Profile | | |
| 2 | Post a goal: title, focus, details, sessions/week, **video pitch** (required) | Open goals → Post | | |
| 3 | Receive an offer: pitch video plays; coach's **badges + rating** shown on the card; Length, Sessions "18 sessions (3 / week)", **Dates** on one line, **Price "$635.40 ($35.30 / session · includes the 5.9% service fee)"** | Offers tab | | |
| 4 | Accept it: confirmation states weeks and the maximum; other offers auto-declined; goal closes | Offers tab | | |
| 5 | Training tab (merged calendar): This week card — X of N, days to close; **Start a session** → week pool → pick a workout | Training | | |
| 6 | Record a set: 3-2-1 timer or open-palm trigger; skeleton overlay visible; **trim start/end** on the review; Use this trace | Recorder | | |
| 7 | Set result: reps counted; correct with +/−; weight; **form match line** when the exercise has a reference; last-time comparison | Set complete | | |
| 8 | Try **Blur bg** on one set: does the recording blur behind you? Does the phone get warm / stutter? Note the phone model | Recorder | | |
| 9 | Wildcard slot (pick from the coach's library); skip a workout with a reason; exit mid-workout and come back (draft restored?) | Workout | | |
| 10 | Interval running workout outdoors: cues spoken and vibrated; GPS distance; the running review card | Workout | | |
| 11 | Macros: log a day; see the coach's weekly goal and live %; dashboard bars and goal line | Training → day tap; Dashboard | | |
| 12 | Check-in photo (Saturday/Sunday window — if not that day, note that the prompt is correctly absent); calendar day glistens; lightbox on the photo; measurements | Home, Training, Profile | | |
| 13 | Personal bests and dashboard: streak squares, week streak badge, milestone celebration + share image ("weeks", not "days") | Dashboard | | |
| 14 | Video call: **Propose a call** (one-time AND recurring); accept / decline / suggest another; **Join call** from card, calendar day, homepage; Withdraw a proposal | Training → Video call card | | |
| 15 | Receive a review: tags per set; written feedback; **voice-over** plays with the clip; rate the coach | Review | | |
| 16 | Day notes with a video attachment; read the coach's day note | Training → day | | |
| 17 | Vacation: set a range; streak neutral; at-risk copy stays quiet | Profile / Training | | |
| 18 | Goal completion: outcome recorded; calendar and streak afterwards; goal in history; the referrer's Profile shows "1 trainee completed a goal" | Training, Profile | | |
| 19 | Profile: referral card — Copy and Share work; counts; the card says tiers unlock **vouchers and merch** | Profile | | |
| 20 | Install as an app; offline banner behaviour | Profile → Install | | |

---

## 3. Coach checklist

| # | Step | Where | ✓ / ~ / ✗ | Notes |
|---|------|-------|-----------|-------|
| 1 | Apply to coach → admin approves → **Verified** badge appears with a date on hover | Profile, Admin | | |
| 2 | Admin **Assign badges**: set Professional with an employer ("Works at …" on hover); Founding; see them on the public profile and on offer cards | Admin, public profile | | |
| 3 | Attach a **certification** (title, issuer, date, photo/PDF) → admin approves → Certified badge + summary on public profile → **homepage notice** to the coach | Profile, Admin, Home | | |
| 4 | Open goals: **who** posted (avatar, name, city, "posted N days ago"), days left, Hide / Unhide, hidden-goals toggle | Open goals | | |
| 5 | Send an offer: single **Length (weeks)**, sessions/week, price, no-show %; preview says "**The trainee pays … You receive … after your … rate**" (and the standard rate + saving if privileged); video pitch required | Open goals → Send an offer | | |
| 6 | Trainees list: "2/3 this week" per trainee; open one | Trainees | | |
| 7 | Exercise library: create, **record a reference** (trim it), reps detected; edit; delete; the "no reference recorded" hint on review for one without | Library, Review | | |
| 8 | Builder: build a workout (sets/reps, intervals, wildcard slots); save as template | Builder | | |
| 9 | Assign into a week: session slots per cap; + Assign; remove an unstarted one; carried-forward labels; weekly **macro goal** in the week header | Trainee calendar | | |
| 10 | Calendar as coach: week rows, done days gold, call days blue, **check-in badges**; tap a day → coaching-call choice | Trainee calendar | | |
| 11 | Review a submitted workout: each set video (rotation fix if sideways); **form match + pose-coverage warning**; tags per set; note per exercise; **voice-over** (mic check, meter, low-level warning); submit; review deadline | Review | | |
| 12 | Payment ledger: earned per reviewed workout, per-trainee totals — display only, no money moves | Payments | | |
| 13 | Video call: propose (day tap or card), accept the trainee's, **add the Meet link**, Join; recurring shows "next …" | Trainee calendar → Video call card | | |
| 14 | Weekly macro goal; carry-forward; the trainee's % visible to you | Trainee calendar | | |
| 15 | Vacation for a trainee (single and bulk); at-risk homepage card for a trainee; inactivity list in admin | Trainee calendar, Admin | | |
| 16 | Complete the goal with the trainee; outcome recorded; history | Trainee calendar | | |
| 17 | Profile: referral link card (coach copy says tiers **lower your commission**); "Your trainees' streaks" card — combined weeks, rank of N, **Top 1%** badge or "held by the top K" | Profile | | |
| 18 | Public profile as a trainee would see it: badges in order (Top 1% first), certification summary, ratings, pitch history | Public profile | | |
| 19 | Admin: applications, error log, inactivity, **Coach badges** list with "N to review" flags | Admin | | |

---

## 4. Seed goals (BP)

Five realistic trainee goals to post before the day. Each has a **20-second pitch script** — a goal cannot be posted without a video. Read the script to the camera in one take; imperfect is fine and more believable than polished.

| # | Title | Focus | Sessions / week | Details (paste) |
|---|-------|-------|-----------------|-----------------|
| 1 | Fix my squat depth and stop my knees caving | Strength | 3 | Been lifting on and off for two years. I can squat 80 kg but my knees track inward below parallel and my lower back rounds. Want a coach who will actually watch my sets and tell me what to change, not send a PDF. |
| 2 | First 10K without stopping | Running | 3 | I can run 5K in about 32 minutes but fall apart after that. Eight weeks until a local 10K. Need a run plan I can follow from my phone with interval sessions, and someone to keep me honest. |
| 3 | Lose 6 kg by Christmas, keep my strength | Fat loss | 4 | 34, desk job, 92 kg. I want to drop to 86 without losing what I've built in the gym. Need help with macros as much as training — I under-eat protein and then binge at the weekend. |
| 4 | Get back into training after a shoulder injury | Rehab / return | 2 | Rotator cuff strain six months ago, physio signed me off, but I'm scared of the bench. Want a careful return-to-lifting plan with form checks on pressing movements. Two sessions a week to start. |
| 5 | Build a proper pull-up from zero | Bodyweight | 3 | I can do zero pull-ups and I want to do five clean ones by the end of the goal. Have a door bar and a set of bands. Would love a coach who can watch my form and progress me week by week. |

**Pitch scripts (≈20 s each, first person, phone at chest height):**

1. *"Hi — I've been squatting for a couple of years and I'm stuck at eighty kilos because my knees cave and my back rounds when I go deep. I've watched every video there is. What I need is someone to look at my actual sets and tell me what to fix. Three sessions a week, six to eight weeks."*
2. *"Hey. I can run five K but around thirty-two minutes I just fall apart. There's a ten K in eight weeks and I want to finish it without walking. I need a plan I can run off my phone with the interval cues, and a coach who'll notice if I skip a Tuesday."*
3. *"Hi, I'm thirty-four, desk job, ninety-two kilos. I want to be eighty-six by Christmas without losing the strength I've built. My problem is food more than the gym — I under-eat protein all week and then blow it at the weekend. Four sessions a week, and help with my macros."*
4. *"Hello. I strained my rotator cuff six months ago. The physio's signed me off, but honestly I'm scared of the bench press. I want a careful plan to get back to lifting, with someone checking my form on anything pressing. Two sessions a week to begin with."*
5. *"Hi — I've never done a pull-up. Not one. I've got a door bar and some bands, and I'd like to do five clean ones by the end of this. I need a coach who'll watch my form and move me on week by week rather than leaving me to guess."*

**Log for each seed goal:** time to post (seconds), whether the video recorded first time, and — over the following days — time to first offer. Those three numbers are the honest measure of BM's "48-hour first response" promise.

---

## 5. After the day

Send the two tables back as they are (photos of the printout are fine). Each ✗ and ~ row becomes one product-log item titled in the tester's own words, tagged with the phone model. Nothing gets "fixed on the day" — write it down, keep going, so the day stays a test and not a repair session.
