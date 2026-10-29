# FormTrace — Test day (v2, pilot readiness)

Two phones: **C** = a coach account, **T** = a trainee account (Android, app installed
from Chrome). Optional third phone **F** = a second trainee, for Social.
Work top to bottom; each step depends on the ones before it.
For every failure: take a **screenshot** first, then open **Review → Client errors**
(admin) - the message there now includes the database's own error text.

**Before you start (once):** all migrations run (see the list at the end); push is on
for both phones (**Settings → Notifications → Push notifications**); during the pilot
the platform fee is 0 (`platform_rates`, see DK).

---

## 1. First run and navigation
| # | Who | Do | Expect |
|---|---|---|---|
| 1.1 | T | Sign up fresh | Lands on Home. Header: avatar left, gear + streak right. Tabs: Home · Training · Goal · Notifications · Social |
| 1.2 | C | Sign in | Tabs: Home · Library · Open goals · Trainees · Social (+ Review if admin) |
| 1.3 | T | Swipe left/right on the content | Moves between tabs |
| 1.4 | T | Open **Training** with no coach | "No coach yet" card + Post a goal; **Your days** calendar; macros, weight, check-in, measurements cards |
| 1.5 | T | Sign out → **Forgot password?** | Reset card; "If … has an account, a link is on its way"; the email link opens **Set a new password** |
| 1.6 | T | Profile | "Signed in as … - this is your login"; Achievements is one collapsed row; Consistency badge row (grey) |

## 2. Coach setup
| # | Who | Do | Expect |
|---|---|---|---|
| 2.1 | C | Library → new exercise; tap a muscle-group chip; **Save & add another** | Saves, blank editor reopens with the name focused |
| 2.2 | C | Library chips | "Unlabelled N", amber "No reference N"; second tap on a chip returns to All |
| 2.3 | C | New workout | Library panel inside the builder (sticky): Exercises/Workouts switch, group chips, search |
| 2.4 | C | Search "shoulders" | Every Shoulders exercise, whatever its name |
| 2.5 | C | Drag a card into the workout (hold on touch); drag ☰ to reorder; drag a row out | Lime insertion line; order changes; row removed. Header "N exercises · N sets · ~N min" |
| 2.6 | C | **+** on a card; on PC scroll the rows with the mouse wheel | Card added; rows scroll sideways |
| 2.7 | C | Workouts tab → **+** a saved workout | All its exercises copied in; name "<source> (copy)" |
| 2.8 | C | Profile → **Invite a friend** | QR (dark on white, lime frame, FT mark) scans with another phone; matrix shows commission tiers; Share sends an image |

## 3. Goal, offers, acceptance
| # | Who | Do | Expect |
|---|---|---|---|
| 3.1 | T | Post a goal **without** a video | First tap: "Posting without a video… tap Post again"; second tap posts. Achievement "The first step is the hardest" plays |
| 3.2 | C | Open goals → the new goal | "No video - text only" marker; pitch it with the agreed pilot price |
| 3.3 | T | Push arrives (status-bar icon = **FT**, not a white box) → Goal tab | The offer; a Top 1% coach's pitch is first and gold-framed |
| 3.4 | T | **Propose a change** | C gets the amber box + push; C answers; T gets the result |
| 3.5 | T | Accept | Goal Accepted; C gets a push |

## 4. Payment (pilot - direct to the coach)
| # | Who | Do | Expect |
|---|---|---|---|
| 4.1 | T | Accepted goal → Payment card | Map: Accepted ✓ · Deposit (dashed, struck, "pilot") · Paid · Training · Complete. No coach details yet → **I've paid** disabled, **Ask for details**, **Cancel goal** |
| 4.2 | T | **Ask for details** | C gets "is ready to pay you" push |
| 4.3 | C | Trainee screen → Payment → "Add how trainees pay you" → Save | Details saved |
| 4.4 | T | Refresh | Details shown; **I've paid** enabled → tap it | 
| 4.5 | C | Notifications 💶 Payments → **Received ✓** | Both maps: Paid ✓, Training "wk 1/N"; T gets a push |

## 5. Training week
| # | Who | Do | Expect |
|---|---|---|---|
| 5.1 | C | Trainee screen (tab bar visible, no back arrow) → assign a workout at Level 2 | T sees resolved reps/kg, not "level 2" |
| 5.2 | C | Set this week's diet plan | T's Home shows it |
| 5.3 | T | Log macros + weight; Saturday check-in photo (guide: head + feet only) | Saved photo is cropped to the body; "Keeping tabs" / "Initiate transformation" play once |
| 5.4 | T | Do the session (record sets) | Submitted |
| 5.5 | C | Review: tags, voice-over with **drawing** (red/green, erase, pause) | Voice-over sheet: Start recording visible below the video |
| 5.6 | T | Open the review | Push "Your coach reviewed a workout"; drawings replay in sync |
| 5.7 | T | Streak badge across all tabs | Same colour everywhere (no red flash on Training) |
| 5.8 | T/C | Next morning ~08:00 | Morning summary push (trainee: session/rest, kcal/protein, log reminders; coach: reviews waiting) |

## 6. Social
| # | Who | Do | Expect |
|---|---|---|---|
| 6.1 | T + F | Social → Add friends → knock phones (or code) | Both confirm faces; "Knock Knock" plays |
| 6.2 | T | Friend's page | Wins; Consistency badge / achievements if earned; **Connect** → handles (grey if not set in Profile) |
| 6.3 | F | Congratulate / Congratulate all | T: clap overlay + push |

## 7. Ending
| # | Who | Do | Expect |
|---|---|---|---|
| 7.1 | T | Goal → **Goal achieved** (or **Cancel goal**) with a reason | C homepage card with reason + push; rate the coach; survey card on Notifications |
| 7.2 | T/C | Payment map after a cancel for "coach not responding" after paying | Refund due → **Refund sent** (C) → **Refund received ✓** (T). Cancel before paying → no refund |

---

## Migrations to have run (newest last)
All earlier ones (see PRODUCT_LOG), then: `migrations_connect_handles.sql` ·
`migrations_end_goal_early.sql` · `migrations_achievements.sql` ·
`migrations_achievements_v2.sql` · `migrations_achievements_backfill.sql` ·
`migrations_dismissals.sql` · `migrations_push.sql` · `migrations_daily_digest.sql` ·
`migrations_streak_badge.sql` · `migrations_payment_tracker.sql` ·
`migrations_payment_way_out.sql` · and `update public.achievements set approved = true where code = 'level_up';`

## What to send back after the day
Screenshots of anything that failed, with the step number. Anything that felt slow or
confusing, even if it worked - that is the pilot's real output.
