# Formtrace — test queue for the next workout (owner)

Everything built and waiting for the owner's check. Tick each line; tell Claude the results (or "all pass") and it
updates PRODUCT_LOG. Grouped by where you will be in the app. Created 2026-11-05.
**How results are collected:** after the workout, tell Claude "I tested" - Claude interviews you through every pending line, group by group (pass / fail / not tried), with follow-up questions on anything that failed.
Tip: allow ~10 minutes after a change for the phone to pick up the new version (close and reopen the app).

## First — after the security lock (GD, 2026-11-10)
- [ ] **GD-T1** Everything still works after the internal functions were locked. As a **trainee** and as a **coach**: sign out and in; open every tab (Home, Goal / Trainees, Training / Library, Social, Profile, Notifications; Review as admin); open a workout and mark a set; submit; as the coach open a review; open the payment tracker on a goal; pause / end pause; Social: congratulate. **If any screen says "permission denied for function …", note the function name** - it is a one-line fix.

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
