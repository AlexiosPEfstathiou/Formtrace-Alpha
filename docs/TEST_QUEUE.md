# Formtrace — test queue for the next workout (owner)

Everything built and waiting for the owner's check. Tick each line; tell Claude the results (or "all pass") and it
updates PRODUCT_LOG. Grouped by where you will be in the app. Created 2026-11-05.
**How results are collected:** after the workout, tell Claude "I tested" - Claude interviews you through every pending line, group by group (pass / fail / not tried), with follow-up questions on anything that failed.
Tip: allow ~10 minutes after a change for the phone to pick up the new version (close and reopen the app).

## First — after the security lock (GD, 2026-11-10)
- [ ] **GD-T1** Everything still works after the internal functions were locked. As a **trainee** and as a **coach**: sign out and in; open every tab (Home, Goal / Trainees, Training / Library, Social, Profile, Notifications; Review as admin); open a workout and mark a set; submit; as the coach open a review; open the payment tracker on a goal; pause / end pause; Social: congratulate. **If any screen says "permission denied for function …", note the function name** - it is a one-line fix.

- [x] **GE-T1** PASSED 2026-11-10 - (after the webhook secret is set) a real notification still arrives - e.g. congratulate someone in Social, or have the coach review a session - and tapping it opens the right tab.

- [ ] **GF-T2** Change your display name to `Alex <b>bold</b> "x"` (and name an exercise the same way): in every message it appears exactly as typed - no bold text, nothing odd. Change it back afterwards.
- [ ] **GF-T3** Profile -> Social settings: type a full link into Instagram and leave the field - red border and a hint, nothing saved; type a plain username - it saves (green flash).
- [ ] **GF-T4** A handle someone shared with you: **Open** goes to the right profile.

## Offers and goals after the write lock (GG, 2026-11-10) - two accounts (a trainee and a coach)
- [ ] **GG-T1** Trainee posts a goal; coach sends an offer on it (with a pitch video if you like) - "Offer sent".
- [ ] **GG-T2** Trainee proposes a change (counter); coach accepts or keeps the terms; the offer shows the right price and length.
- [ ] **GG-T3** Trainee **accepts** the offer: the goal is created and (test mode) the payment page opens; the other pending offers on that goal are declined automatically.
- [ ] **GG-T4** Trainee **declines** a different offer: "Declined". Opening an offer marks it viewed (no error).
- [ ] **GG-T5** On the active goal: the coach changes the **level**; **mark complete**, then **reopen**; the trainee **cancels** a goal. Each works without an error message.
- [ ] **GG-T6** A **renewal**: the coach sends a direct offer to an existing trainee, the trainee accepts - a new goal starts.
If anything says "permission denied for table / column ..." or one of the new guard sentences ("Only the trainee can accept an offer", "A goal starts from an accepted offer"...), note what you were doing.
## Credit at checkout (GH, 2026-11-10) - sandbox (?stripetest=1), a trainee who has credit
- [ ] **GH-T2** Part credit: accept a goal that costs more than your credit. Before paying, Profile -> Credit shows "credit reserved while you pay for this goal". Pay with a test card -> the line reads "credit used for this goal" and the balance is right.
- [ ] **GH-T3** Start a part-credit checkout and **close it without paying**. After about 40-50 minutes the reservation line is gone and the credit is back.
- [ ] **GH-T4** Full credit: a goal that costs no more than your credit is paid at once ("paid with your credit"); the ledger shows one line for it.
- [ ] **GH-T5** With credit that covers only one goal: start the checkout for goal A (do not pay), then accept goal B. Goal B must **not** get the same credit (card for the full price, or only what is left).
## As the trainee - the Training tab as a control panel (GK, 2026-11-10)
- [ ] **GN-T1** (2026-11-10 evening) Finish a set: the rest timer is a small pill in the top-right corner (where the 🔥 badge was), nothing under it is covered; tapping it shows the "Take a break" message **in front**; when the rest ends the 🔥 badge is back.
- [ ] **GM-T1** (2026-11-10 evening) With the camera blocked, open a session: the steps say Chrome -> ⋮ -> Settings -> Site settings -> Camera -> formtrace.ie -> Allow; following them and tapping **Try again** (button fully visible) brings up the camera.
- [ ] **GL-T1** (fix 2026-11-10 evening) On the phone: open **Calendar**, then **Weight** - the tab bar stays at the bottom and nothing slides up. Then **Start a session** -> pick one -> the session screen opens normally (a double tap starts it once).
- [ ] **GK-T1** The tab opens with a large **Start a session** button at the top and this week's progress under it; below, a grid of buttons; nothing else is open. No long scroll.
- [ ] **GK-T2** **Start a session** opens this week's sessions as before. With nothing assigned it reads "No session to start yet".
- [ ] **GK-T3** Each button opens its section under the grid and is highlighted; tapping it again closes it; opening another closes the first: Calendar, Weight, Macros, Check-ins, Personal bests, Measurements, Calls.
- [ ] **GK-T4** Inside **Calendar**: change the month, tap a day, log something - the calendar stays open. Inside **Weight** / **Macros**: Goal / Week / Day switches and the section stays open.
- [ ] **GK-T5** **Take a vacation** (last button) opens the same panel as before; while on a break it reads **Resume training**.
## Sessions, reviews and ratings after the tighter write rules (GI-1, 2026-11-11) - a trainee and a coach
- [ ] **GI1-T1** Coach: **assign** a session to a trainee; **remove** one that has not been started; move one to another date. Each works.
- [ ] **GI1-T2** Trainee: open the session, mark sets (the draft saves), **submit** it. Coach: it appears in the review queue; **send a review**.
- [ ] **GI1-T3** After a goal is **completed** (or ended): each side can **rate** the other, once.
- [ ] **GI1-T4** The streak number on the badge still updates after a completed session (it is now maintained only by the database).
## After the library pin (GI-3, 2026-11-11)
- [ ] **GI3-T1** The app opens and signs in as usual (if the library were refused you would see "Formtrace could not load a file it needs"). Profile -> your **QR code** still appears.

## Notifications open the right tab (GO, 2026-11-11)
- [ ] **GO-T1** (owner 2026-11-11: a tapped alert opened Review - confirm which case) With the app **open on another tab** (e.g. Home), send the test alert (SQL journal: `select public._admin_alert(...)`), tap it: the app comes forward on **Review**.
- [ ] **GO-T2** With the app **fully closed** (swiped away), send it again, tap it: the app opens on **Review**.

## Anywhere — pull-to-refresh (GC)
- [ ] **GC-T1** On **Goal** or **Notifications**, at the top, pull down: the gold arrow follows your finger, flips past the threshold with a tiny buzz, and spins on release; the list updates; the refresh sound plays (Sounds on).
- [ ] **GC-T2** Release before the arrow flips: it slides away, nothing refreshes.
- [ ] **GC-T3** In the workout builder, the workout player, Settings, or with a panel open: pulling down does nothing.
- [ ] **GC-T4** A sideways swipe, or a pull inside a list that is itself scrolled down, does not refresh. After a refresh, the back button still works as before.

## As the coach — building a workout (EZ, Library → a workout)
- [x] **EZ-T1** Unsaved changes + back button → "Discard your changes?" — **passed 2026-11-05**. Still worth a quick look: the back arrow at the top and a tab tap ask the same; an untouched workout leaves without asking.
- [ ] **EZ-T2** 🗑 Delete asks first; **Keep it** keeps the workout.
- [ ] **EZ-T3** Hold **+** on Target kg: it climbs quickly. Tap a number and type it — e.g. **82.5** for weight, **2:30** (or 150, or 2.5) for rest; Enter or tapping away saves it; an emptied weight shows "—".
- [ ] **EZ-T4** Tap **Save** twice quickly: only one workout is created; the button shows "Saving…".
- [ ] **EZ-T5** Remove an exercise (✕ or drag it out): "Removed … Undo" appears; **Undo** puts it back in the same place with its sets, reps, weight and rest.
- [ ] **EZ-T6** The estimate in the header ("~N min") changes when you change a rest or a number of sets.
- [ ] Also check: the second button reads **"+ Add several…"**; the label reads **"Target kg (level 1)"**.

## As the coach — reviewing a session (EZ-6 / EZ-6b)
- [ ] **GP-T1** (2026-11-13) Record a **new** voice-over on a portrait clip and draw near a joint (e.g. the knee); in the preview and later as the trainee, the drawing appears on the same spot of the body. (Old voice-overs may still be off.)
Needs a trainee with **two or more reviewed sessions** of the same exercise.
- [ ] **EZ6-T4** While reviewing that exercise, **"Your notes on this exercise (N)"** shows every earlier note, dated, newest first, above the sets. Write a new comment in a set's box and send the review.
- [ ] **EZ6b-T2** Tap **Edit** on one of your notes, change it, **Save**: it shows "edited" under its date.
- [ ] **EZ6b-T3** **Edit → Delete** on a note: it asks, then the note is gone. That set's tags and voice-over are unchanged.
- [ ] **EZ6b-T4** Notes written by another coach (if any) show **no** Edit.

## Recording a set — the camera (GA)
Front camera, filming yourself, on your Android phone. Then once with the back camera.
- [ ] **GA-T1** The preview is **mirrored** (raise your right hand: it moves on the right of the screen, like a mirror). The **⇄ Mirror** button flips it; your choice is remembered next time.
- [ ] **GA-T2** The **saved** video (Replay, and later the coach's review) is mirrored the same way you saw it.
- [ ] **GA-T3** The preview shows the **whole** recorded frame (dark bars instead of a crop); the pose lines sit on the body; Replay shows the same framing.
- [ ] **GA-T4** Turn the phone **sideways, top to the LEFT**: the countdown, timer and icons turn to face you; there is no Portrait/Landscape button any more. Record a set → it is saved **upright in landscape**. Then **top to the RIGHT** → also upright. **If one is upside down, note which side.**
- [ ] **GA-T5** Start recording, then turn the phone: the recording's orientation does not change mid-set.
- [ ] **GA-T6** **Back camera**: not mirrored, and the Mirror button is hidden.
## As the trainee — the workout (EZ-6)
- [ ] **EZ6-T2** Each exercise shows **"Your coach's notes (N)"**: all the comments from earlier reviews of that exercise, dated, newest first; 3 shown, then **Show all**. The note written in EZ6-T4 is at the top; an edited one shows "edited"; a deleted one is gone.
- [ ] **EZ6-T3** **▶ Replay the latest voice-over (date)** plays the coach's voice-over with its drawings; **Close** stops it.

## Done already (for reference)
- FZ sounds and their Settings switches — **pass** ("the sounds work", 2026-11-05).
- EJ part 3 (a card dispute cancels the goal) — being tested from the **personal account**.
