# Formtrace — test queue for the next workout (owner)

Everything built and waiting for the owner's check. Tick each line; tell Claude the results (or "all pass") and it
updates PRODUCT_LOG. Grouped by where you will be in the app. Created 2026-11-05.
**How results are collected:** after the workout, tell Claude "I tested" - Claude interviews you through every pending line, group by group (pass / fail / not tried), with follow-up questions on anything that failed.
Tip: allow ~10 minutes after a change for the phone to pick up the new version (close and reopen the app).

## Brand icons (EW, 2026-11-23)
- [ ] **EW-T1** New deep-gold F icon: the browser tab shows it; on the phone, remove and re-add the app to the home screen (icons are cached at install) and check the home-screen icon (outline F); a notification shows the white F in the status bar.

- [ ] **EW-T2** New wordmark: signed out, formtrace.ie shows the Formtrace logo + wordmark top left and the headlines in the new font; signed in, Home shows the wordmark above the heading; switch to the light theme - the wordmark stays readable.

- [ ] **IC-T1** New tab bar icons: grey, the active tab deep gold; the counters (Goal offers, Social, coach tabs) show as gold circles with black numbers; check dark and light, and the coach bar.

- [ ] **ID-T1** Training tab: gold Start a session; tiles with gold line icons, icon above the text, nothing cut off; Calls full width when it is the odd one; Take a vacation as a slim palm-tree row; check dark and light; tap a tile - it still opens its section.

- [ ] **IE-T1** Training -> Calendar: Weeks view by default - this week's sessions with ticks / Start / Any day, earlier weeks with rings (tap to expand), upcoming week; Start opens the session; switch to Month - the old grid, tap a past day -> Log weight and macros still works; the choice is kept after reopening. **IE-2:** Month view - plain grid with gold dots on training days, a ring per week on the right, today outlined; tap a week -> its sessions below with Start; tap a past day -> Log weight and macros. **IE-3:** Macros and Weight cards - a 7-day strip (ticks on logged days) and an Older day picker open the log form for that day; a reviewed session shows a solid gold tick / dot, one waiting for the coach a gold outline / hollow dot with "Awaiting review". **IE-4:** open a reviewed workout from the Weeks or Month view, press Back (or Close review) - you return to that view, not the old calendar.

- [ ] **IF-T1** Training -> Weight: Start -> Now journey bar with the runner, "-x kg in N weeks", the weekly pace gauge (needle, gold steady zone, caption), one bar per week with changes, this week's days (tick / dashed + / grey) and "You missed ..."; tap a + day -> log that day; Log an earlier day works; check dark and light. Is the steady zone right for your goal?

- [ ] **IG-T1** Training -> Macros: Week shows the week's average calories and protein in two gold rings against your coach's targets (On target / Under / Over); the daily bars have a dashed target line; a day you didn't log glows with "+ Log" and the gold banner lists missed days - tap to log; tap a bar -> Day shows that day; arrows step back through earlier weeks; dark and light.

- [ ] **IH-T1** Training -> Check-ins: "N weeks of progress"; before / after of week 1 and your latest photo - drag the gold divider; do the two halves line up as one person (same size and height)? Play the timelapse - does the body stay put? Photos are black and white; tap a thumbnail to compare that week; press and hold a thumbnail -> delete (asks first); "+ This week" opens the camera. Report any photo that does not line up (and whether your whole body is in it).

- [ ] **II-T1** Training -> Personal bests: "Your next PB is waiting", the PB quest pill, trophies on the weeks you set PBs (the selected exercise's in gold) and "N weeks since your last ... PB"; Oldest / Newest sort; tap a row to select it; targets read "+1 rep or more kg" (or N+1 reps); Try tonight opens Start a session. **II-2:** scroll down the list - the timeline stays pinned at the top; tap an exercise near the bottom - the pinned timeline switches to it.
- [ ] **IJ-T1** Training -> Body measurements: the gold figure with a % pill per body part (gold = right way for your goal), the Q switcher (‹ ›) between quarters, the comment under it, Log / Update this quarter opens the sheet. Tap **How to measure** (top right) - the tutorial sheet opens, scrolls, closes with × or Got it.
- [ ] **IK-T1** Training -> call card: My availability -> Edit - set days and times (toggle, + Add time, quick chips, Save). With the coach account set hours too; the trainee card then lists **Times that work for both of you** - pick one, Propose; the coach gets the notification; Accept or Propose a new time from the other side.
- [ ] **IL-T1** Training -> Take a vacation: the sunset postcard sheet; type a message, tap Back on and pick a date (the line shows it), Start my vacation - goals pause, toast "Enjoy your vacation"; the coach sees the message; Resume training brings it back.
- [ ] **IM-T1** Goal tab with an active goal: progress ring (week and sessions), week strip (pills for short goals, numbered grid for long ones), Your plan with the payment steps, Pitch video opens the player, Goal achieved / Cancel goal open the usual sheets; "Past goals" line opens Completed / Rejected.
- [ ] **IO-T1** Social tab (two phones): + Knock -> Start -> knock phones -> "Is this ...?" -> Yes; the friend appears in the ring. Their new PB shows a gold ring + count and a cheer card: Congratulate all (confetti), Pick one (single Congratulate), tap the avatar for the profile (share-handle toggle). Switch the meetup on (`formtrace_events.active`) -> I'm going, Add to calendar, Directions, can't make it.
- [ ] **IQ-T1** Settings: camera badge changes the photo; Full / Initial / First updates "Others will see"; pencil opens Country / Languages (names in English now) and Remove photo; feed switch; theme thumbnails switch the theme; three switches; Install (or the help line); See what's stored, Sign out, Delete account behave as before.

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
- [ ] **GT-T1** (2026-11-13) While recording a voice-over: pinch with two fingers to zoom in, drag with two fingers to move, pinch back to the full picture; one finger still draws, and a pinch never leaves a stray line.
- [ ] **GT-T2** Draw while zoomed in, then zoom out: the drawing stays on the same spot of the body.
- [ ] **GT-T3** Play it back (preview, then as the trainee): the video zooms and moves at the same moments, and the drawings sit where they were drawn.
- [ ] **GR-T1** (2026-11-13) Tap **Send review**: a "Send this review to <name>?" summary appears; **Keep editing** sends nothing; **Send review** sends it.
- [ ] **GS-T1** Open a review you sent less than an hour ago: **Withdraw this review** shows with the minutes left; withdraw -> the workout is back in your queue.
- [ ] **GS-T2** Open it again: tags, notes, voice-overs (with drawings) and overall feedback are all filled in; change one, send - the trainee sees the new version.
- [ ] **GS-T3** As the trainee, after a withdrawal: the review is gone from the workout until it is sent again.
- [ ] **GP-T1** (2026-11-13, re-fixed 16:05 - GP-2) Record a **new** voice-over on a portrait clip and draw near a joint (e.g. the knee); in the preview and later as the trainee, the drawing **appears** and sits on the same spot of the body; the whole clip is visible in the player. (Old voice-overs may still be off.)
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
- [ ] **GA-T7** (2026-11-22) The new lines: every joint (incl. thumbs, fingers, heels, toes), glow, ring joints, knee/elbow arcs; they glide rather than jitter, and fade rather than flicker when a limb leaves the frame. Same look in Replay and in the coach's review.
- [ ] **GA-T8** Phone sideways (each way): the lines stay on the body as well as in portrait; the saved landscape video is upright with the lines on it.
- [ ] **GA-T9** Turn the phone back and forth before recording: the countdown, timer and side icons turn smoothly in place; rep counting still works on a landscape set.
## As the trainee — a workout (GX, 2026-11-20)
- [ ] **HY-T1** (2026-11-22, coach) Send an offer on a demo goal: amber "Trainee requested … - try not to deviate" under Length and Sessions / week, fields prefilled; the bar then shows Pitched; a trainee's counter shows Counter.
- [ ] **HX-T1** (2026-11-22, coach Open goals; after the SQL) Bars newest first with first names, "x ago", emoji and "Total of Y sessions over Z weeks"; the newest have New; tapping a bar opens the goal; Your sent offers is its own card at the end. Post a goal (trainee) shows Weeks and Sessions per week.
- [ ] **GI-T1** (2026-11-22) Pay for a goal (sandbox card or promo code) and set up / open coach payouts: both still open Stripe as before (the payment functions now only answer formtrace.ie).
- [ ] **GI-T2** Open https://formtrace.ie/?csp=1 and use the app normally for a day (camera with lines, videos, voice-over, Shop, check-in photo); then Review -> Client errors: no "csp" rows. Then I make it the default.
- [ ] **GI-T3** Stripe -> Developers -> Webhooks -> endpoint -> add refund.failed, refund.updated, charge.refund.updated, transfer.reversed.
- [ ] **GK-T6** (2026-11-22, trainee Training tab) Each button shows a small value under its name (sessions left, latest weight, macros, last photo, records, last measurement, next call) and they match what opens.
- [ ] **HV-T1** (2026-11-22) A call proposed to you shows the date tile, weekday and time, a full-width Accept call, and Suggest another time / Decline side by side; all three work.
- [ ] **HU-T1** (2026-11-22, trainee, a reviewed workout) The review has a back arrow and "Close review" at the bottom; 💬 Reply -> Send reply shows your reply under Overall feedback.
- [ ] **HU-T2** (coach; after the SQL) The coach gets "💬 … replied to the review", sees the reply in the review and can answer; the trainee gets that push.
- [ ] **HT-T1** (2026-11-22, Home) Open the Home card's weekly side: "Weekly check-in photo" now shows ✓ with "Progress captured" +20 (your 19:47 photo counts). Next week: take the photo from the quest - it completes straight away.
- [ ] **HR-T1** (2026-11-22) Propose a coaching call: the start time is two 24-hour boxes (e.g. 18 : 30); the sent call shows 18:30. Coach weekly side shows "Assign next week's sessions".
- [ ] **HQ-T1** (2026-11-22) Open a workout (trainee) and a review (coach): the tab bar stays; the last set / Submit and "Send review" are not hidden behind it.
- [ ] **HP-T2** (trainee calendar) Tap a past day with a workout: Open workout / Log weight and macros (+ call for today or later).
- [ ] **HO-T1** (2026-11-22, Home weekly side) Tap Weekly check-in photo (camera opens), Attend a call (your coaching opens), Make a friend (In Touch opens), Log macros / Weigh in (the log opens), workouts (this week opens).
- [ ] **HN-T1** (2026-11-22, coach review; after the SQL) Write an exercise note and a set note, send: toast says the exercise note was saved; the trainee's next workout with that exercise shows the exercise note on the card and on the camera, not the set note.
- [ ] **HN-T2** (trainee) The set note appears in that workout's review only.
- [ ] **HN-T3** (trainee workout) Tap Skip on a set, then "↶ Undo skip": the set is back with ● Record.
- [ ] **HM-T1** (2026-11-22, phone) Open the app from a notification (e.g. macros), log the item, then go to Home: the "+N points" pops rise from the matching rows of the daily card, and nothing pops on other screens.
- [ ] **HL-T1** (2026-11-21, Home) The lime "⇄ Weekly" pill is top right of the Today card; "⇄ Today" top right on the back.
- [ ] **HL-T2** (Home) Complete a weekly quest (e.g. 5th weigh-in) while on another tab, then open Home: a "Weekly quest complete" card names it with +points; Share gives an image; Nice closes it (several show one after another).
- [ ] **HK-T2** (trainee) Finish all of today's tasks: after Day complete the card flips to the weekly quests by itself (once).
- [ ] **HK-T3** (trainee) Complete a quest (e.g. the 3rd personal best, or 5th weigh-in): "+30 points · weekly quest" pops; Profile points and level bar go up.
- [ ] **HK-T4** (coach) Review a session / assign one: next time Home opens, "+5 points · reviewed a session" (or +2) pops; the coach card flips to 4 coach quests.
- [ ] **HJ-T1** (2026-11-21, trainee Home; after the SQL) Complete a daily task (e.g. weigh in): "+3 points" rises from the row; Profile points go up; reopening Home pays nothing again.
- [ ] **HI-T1** (2026-11-20, Profile) Under the profile photo: "Level N", the bar and "x exp to level N+1" match your points earned (375 exp = level 2).
- [ ] **HI-T2** (2026-11-20, Profile; after the SQL) The Shop button on the right opens the Shop with your balance and "Nothing in the shop yet".
- [ ] **HH-T1** (2026-11-20, trainee Home) Tap "See today's calorie budget": a card with the coach's kcal and protein; Got it ticks the task and the numbers stay on the row.
- [ ] **HH-T2** (2026-11-20, trainee Home; after the SQL) Complete every daily task: Day complete shows "+10 points · daily bonus"; Profile points balance up by 10; doing it again the same day pays nothing.
- [ ] **HG-T1** (2026-11-20, coach then trainee; after the SQL) Leave two set notes, one with Retain unticked: next time the trainee does that exercise only the ticked one is in "Your coach's notes".
- [ ] **HG-T2** (2026-11-20, coach then trainee) Tap More weight on a set and type e.g. 25 kg (and More reps 12): the next time the trainee does that exercise, the set shows "12 reps target @ 25 kg (coach)", the card shows the targets and the weight field is 25.
- [ ] **HF-T1** (2026-11-20, as the coach) Record a voice-over: use ⏪ 2 s, 2 s ⏩ and the slider (playing and paused), draw after a jump; the preview and the trainee's replay jump to the same moments with the drawings in place.
- [ ] **HE-T1** (2026-11-20, phone) Training tab: scroll the macros dashboard charts sideways - the tab stays; swipe on an empty part of the screen - the tab changes.
- [ ] **HD-T1** (2026-11-20, phone) Open the camera in a workout, lock the phone for 5+ minutes, unlock: the lines come back within a few seconds. If not, toggle Lines off and on ("Restarting the pose lines…").
- [ ] **HC-T1** (2026-11-20) Record a set or two, leave the workout and restart the app: Home shows "Unfinished workout - N of M sets recorded and saved - Continue"; Continue opens it with the sets there and "Welcome back" message; in Start a session it is listed first and marked.
- [ ] **HB-T1** (2026-11-20) After a set, Set complete shows reps and target but no "Form match ..." line; the coach's review shows no "🤖 Form match" line either.
- [ ] **GZ-T1** (SQL run 2026-11-20) Make 3 personal bests in one week (a first record counts; correcting reps counts): after each, the quest card shows x -> x+1 of 3; at 3, "Quest complete +10 points"; Profile -> Points shows 10.
- [ ] **GY-T1** (2026-11-20) Finish a set of an exercise you did before with a weight: **Weight used** is already filled with last time's weight; change it and the new value is kept; a bodyweight exercise stays blank.
- [ ] **GX-T1** Finish a set, then tap **Record** on the next one straight away: the rest pill in the top-right corner flashes twice. Tap the pill: "Break ends in m:ss" counts down; **Add 30 seconds** adds 30 s; **Skip break** ends it and the next set can be recorded.

## Notifications (GW, 2026-11-20)
- [ ] **GW-T1** Tomorrow about 08:00: the morning summary arrives on the phone (e.g. "Rest day today") even with nothing new in the app.
- [ ] **GW-T2** On one phone, sign out of Alex Stinson and sign in as the coach (push allowed): pushes for the coach arrive, and none for Alex Stinson until you sign back in.

## As the trainee — the workout (EZ-6)
- [ ] **GQ-T1** (2026-11-13) Tap the "Your coach reviewed a workout" notification (app closed, then app open): the review of **that workout** opens; Back returns to Training.
- [ ] **EZ6-T2** Each exercise shows **"Your coach's notes (N)"**: all the comments from earlier reviews of that exercise, dated, newest first; 3 shown, then **Show all**. The note written in EZ6-T4 is at the top; an edited one shows "edited"; a deleted one is gone.
- [ ] **EZ6-T3** **▶ Replay the latest voice-over (date)** plays the coach's voice-over with its drawings; **Close** stops it.

## Done already (for reference)
- FZ sounds and their Settings switches — **pass** ("the sounds work", 2026-11-05).
- EJ part 3 (a card dispute cancels the goal) — being tested from the **personal account**.
