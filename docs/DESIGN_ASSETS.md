# Formtrace — design assets for an openart theme (living list)

**Purpose:** every visual element **and sound** of Formtrace that could be replaced by a designed asset.
When it is time, take this list to openart.ai (PRODUCT_LOG **EW**) and ask for **one consistent theme across
all of it** — not one-off pieces.
**Keep it current:** whoever builds or changes a visual element or a sound adds or updates its row (rule in CLAUDE.md).
**Finalised for launch 2026-11-04** — every row has a tier and a deliverable spec.

## How to read this list
**Tier** — **L1** = needed before the pilot coaches are invited (the openart month's must-do) ·
**L2** = launch nice-to-have, same month if time allows · **Later** = waits for a feature that is not built yet ·
**Code** = drawn by the app's code; no openart asset needed, only the theme's colours and motion applied after the theme exists.
**Status** — placeholder = stand-in today · current = acceptable but generic · future = not built yet.

**Theme constraints to give openart:** dark UI first (a light theme exists); signature accent **gold `#F0D231`**
(light theme `#B8960A`); attention lime `#C8FF3D`; status red `#FF5A5A`, amber `#FFC24A`, blue `#5AB0FF`,
violet `#B79CFF`; backgrounds `#0B0E11` / cards `#151B21`. Name: **Formtrace** (owner, 2026-11-04 - not FormTrace;
wordmark today: "FORM**TRACE**" with TRACE in gold). Display face in use on the landing page: Big Shoulders Display.
Audience: trainees and coaches; fitness, form and progress; community. Must work small (16–24 px) and on phones;
animations need a calm reduced-motion version. North star: fitness + social life + a community brand (PRODUCT_LOG FS).

**Delivery rules (all images):** master files at 2x the largest use; PNG with a transparent background unless stated;
**icons, logo and badges also as SVG** (openart produces images — trace them to vector, or have a designer finish them);
one icon family on a 24 px grid with the same stroke weight; check every item on the dark and the light theme.
AI-only art may not be copyrightable — a designer should refine the final logo (trademark still possible; check with the
Terms lawyer, DX).

## L1 summary — the must-do list for the openart month
Logo + wordmark · app icons (4 files) · notification icon · favicon · Stripe icon + logo · share image 1200x630 ·
landing page look · tab and header icon family (13) · the core workout sounds and the achievement-unlock sound.

## 1. Brand core
| Asset | Where | Tier | Status | Deliverable spec |
|---|---|---|---|---|
| Logo mark + wordmark lock-up ("Formtrace", FORM / TRACE) | Home hero (`.logo`), sign-in, landing, emails, Stripe | **L1** | current (text only) | SVG + PNG; horizontal lock-up, stacked lock-up, mark alone; dark and light versions; legible at 24 px tall |
| App icons | `icon-192.png`, `icon-512.png`, `icon-512-maskable.png` | **L1** | placeholder | PNG 192 and 512; maskable 512 with the mark inside the central 80% safe zone; no transparency on the maskable one |
| Apple touch icon | `apple-touch-icon.png` | **L1** | placeholder | PNG 180 x 180, no transparency (iOS adds the corners) |
| Notification bar icon | `badge-96.png` | **L1** | placeholder (DJ) | PNG 96 x 96, **white silhouette on transparent** only (Android tints it) |
| Browser tab icon (favicon) | page head | **L1** | placeholder | SVG favicon + PNG 32 and 16 |
| Colour palette and type | CSS variables in `index.html` | L1 | current | The theme may refine, not replace, the gold; name the display and text faces |

## 2. Navigation and header icons (today: Unicode symbols / emoji)
One family, 24 px grid, same stroke weight, **SVG**, an outline and a filled (active tab) state. **Tier L1** for all. **Source (recommended 2026-11-05):** an open-source family - **Lucide** or **Phosphor** (MIT licence, commercial use) - styled in the theme colours, rather than generated (consistent at 24 px, no credits). Prompts for everything else: `docs/OPENART_BRIEF.md`.
| Icon | Today | Who |
|---|---|---|
| Home | ⌂ | both |
| Library | ✎ | coach |
| Open goals | ◎ | coach |
| Trainees | ◉ | coach |
| Training | ◉ | trainee |
| Goal | ◎ | trainee |
| Notifications | 🔔 | trainee |
| Social | 🤝 | both |
| Review | ★ | admin |
| Settings gear, back arrow, close, more (⋯) | symbols | both |

## 3. Badges, marks and status pills
| Asset | Where | Tier | Status | Deliverable spec |
|---|---|---|---|---|
| Achievement icons — 27 achievements in 6 families (Start, Discipline, Effort, Body, Journey, Social) | Profile grid, unlock animation (CY) | **L2** | placeholder (family colours) | SVG + PNG 256; one shape per family, one symbol per achievement; readable at 40 px |
| Consistency badge tiers Bronze → Silver → Gold → Platinum → Diamond | streak badge row (BW) | **L2** | placeholder | SVG + PNG 256, five tiers of one design |
| Founding coach badge | coach cards (BQ) | **L2** | placeholder | SVG, works at 18 px inline |
| Referral reward tiers | Profile referral card (BN/BW) | L2 | placeholder | SVG, same family as the consistency tiers |
| Streak flame chip ("🔥 1d") | top-right header | L2 | current (emoji) | SVG flame, normal + amber "at risk" state |
| "⚡ Reviews within a day" mark | coach card (EL) | L2 | current (text + emoji) | SVG, 16 px inline |
| Verified / certification badges | coach cards (`badgeSpans`) | Code | current (text pills) | Theme colours only |
| Top 1% coach gold frame + label | pitch rows (BY) | Code | current (animated gold frame) | Theme colours only |
| "Offer accepted" pill, red "to assign" / green "to review" counts, tab badge dots | Trainees list (FD), tab bar | Code | current | Theme colours only |

## 4. Celebrations, motion and progress — drawn by code
All **Code**: keep the animation, apply the theme's colours and motion style; no openart files needed.
| Asset | Where | Notes |
|---|---|---|
| Achievement unlock animation (drop-squash, ring sweep, particles) | `playUnlock` (DA) | Family colours from the achievement icons (L2) |
| Streak level-up confetti | `sbConfetti` | |
| "Day complete" celebration (check pop + confetti) | Home checklist (ES / FH) | |
| Goal celebration screen | `s-celebrate` | Optional L2 illustration behind it |
| "Your journey" recap screen | `s-journey` | Later: an illustrated recap |
| Payment tracker steps map | goal payment card (DL) | Accepted → Deposit → Training → Complete |
| Rest timer stopwatch (ring, green → red) | workout screen (EU) | Crown, side button, ring |
| Analysis progress ring | after a set (`#analyze`) | |
| Glisten / guide pulse effects | calendar, cards, call walkthrough | |
| Loading spinner / app loading | everywhere | Could use the logo mark (L2) |
| Undo bar ("Removed ... Undo", 5 s) | workout builder (EZ-5, 2026-11-05) | Theme colours |
| Pull-to-refresh indicator (round, gold arrow, flips, spins) | top of the main screens (GC, 2026-11-05) | Theme colours; the arrow could become the logo mark (L2) |

## 5. Shareable images (drawn by the app)
| Asset | Where | Tier | Status | Deliverable spec |
|---|---|---|---|---|
| **Share preview (Open Graph) image** | `og:image` (EX) | **L1** | placeholder (icon-512) | PNG/JPG **1200 x 630**, logo + one line ("A real coach for every rep you record"), readable as a small WhatsApp thumbnail |
| Referral invite image 720 x 960 | `referralShareImage` (DG) | L2 | current | A background/frame PNG 720 x 960 the app draws text onto |
| Referral QR card (lime frame, FT mark) | `renderQrInto` (DG) | L2 | current | The centre mark = the logo mark (SVG) |
| Check-in photo timelapse | `s-timelapse` | Code | current | Title card and watermark use the logo |
| Check-in photo guide (head and feet outline) | camera (CS) | Code | current | |

## 6. Empty states, placeholders and illustrations
| Asset | Where | Tier | Status | Deliverable spec |
|---|---|---|---|---|
| Empty-state illustrations (no goals, no offers, no trainees, no workouts, no friends, no notifications, no applications, no achievements yet) | `.empty .ic` on many screens | **L2** | placeholder (symbols) | 8 spot illustrations in one style, SVG or PNG 400 x 300, transparent, calm |
| Sign-in / consent screen artwork | `s-auth`, `s-consent` | **L2** | current (plain) | One hero image, PNG 1200 x 800, must not fight the form |
| Video thumbnail placeholder | exercise and goal cards (`.ex-thumb .ph`) | L2 | placeholder | SVG, 16:9 and 9:16 |
| Home hero background | `s-home .hero` | L2 | current (plain) | Subtle texture/PNG, works behind text |
| Coach application screen | `s-coach-apply` | L2 | current (plain) | Reuse the sign-in artwork style |
| Avatar fallback (initials) | everywhere | Code | current | |

## 7. Camera and recorder — drawn by code
| Asset | Where | Tier | Notes |
|---|---|---|---|
| Pose overlay skeleton (joints, lines) | recorder | Code | Colours and line style follow the theme (lime joints, gold traces as on the landing page) |
| Record button, countdown, take review | recorder (`#rec`) | Code | |

## 8. Outside the app
| Asset | Where | Tier | Status | Deliverable spec |
|---|---|---|---|---|
| **Landing page — the whole look** (layout, hero, section art, typography, button) | formtrace.ie for signed-out visitors (EX) | **L1** | current (built in code) | Owner 2026-11-04: keep the copy and structure, redesign the look within the theme; hero keeps the "traced form" idea (bodyweight squat, arms forward, hip and knee traces) |
| **Stripe branding: icon, logo, brand and accent colours** | Stripe → Settings → Business → Branding (EC, FY) | **L1** | placeholder (interim: icon-512, #F0D231 / #0B0E11) | Square icon PNG ≥ 128 x 128 (works on white), horizontal logo PNG; live account too |
| **Sign-in / password-reset emails** | Supabase Auth templates (FX) | **L1** | placeholder (Supabase default, no branding) | Logo PNG 2x (max 600 px wide), gold button, footer; must work in every mail client |
| Landing display typeface: Big Shoulders Display | landing headlines (EX) | L1 | current | Confirm or replace as the brand face across the app |
| Email signature | contact@formtrace.ie (Titan, EH) | L2 | future | Logo PNG, small |
| Social media profile and cover images | Instagram etc. | L2 | future | Profile 1080 x 1080 (round-safe), cover per platform |
| Onboarding walkthrough art | first-run tours (EV) | Later | future | |
| Encouragement-video frame / card | EY | Later | future | |
| Points, shop, Events, leaderboard art; cosmetic add-ons (avatar frames, themes, celebration styles) | FL / FS | Later | future | Second openart month |
| App-store screenshots and listing art | native app (deferred) | Later | future | |

## 9. Sounds (SFX) — owner, 2026-11-04 (PRODUCT_LOG FZ)
**Placeholders built 2026-11-05 (FZ):** every **L1** sound already plays as a synthesised tone (no files yet); designed files replace them one by one, same names. Before that the app had no sounds (vibration and spoken interval announcements only, both kept).
**Behaviour rules (build, FZ):** a **Sounds** switch in Settings (on by default) plus **Workout sounds** (on by default) so
people can keep the timers and silence the rest; **never play while a video is recording** (it would end up in the coach's
review video) — the countdown before recording is the exception; quiet by default; vibration stays as well; sounds
unlock on the first tap (browsers require it). A web app cannot detect the phone's silent switch reliably — hence the switch.
**Delivery spec (all sounds):** MP3 (or AAC .m4a), mono, 44.1 kHz; UI sounds ≤ 150 ms and ≤ 15 KB; celebration sounds ≤ 2 s
and ≤ 60 KB; loudness matched across the set (UI quiet, timers clear, celebrations a little fuller); no hard clicks at the
start or end; one sonic family (same instrument palette as the theme's mood). **Licence:** commercial use. openart's audio
tools focus on voice — if they cannot make sound effects, options are ElevenLabs Sound Effects (paid plans include commercial
use) or CC0 libraries (e.g. Kenney UI Audio, Freesound CC0). Until then the app can **synthesise placeholder sounds** in code.
| Sound | When it plays | Tier |
|---|---|---|
| Button tap (soft click) | primary buttons, toggles | **L1** |
| Success | saved, submitted, offer sent, workout submitted | **L1** |
| Error / blocked | failed save, "Take a break to rest before the next set" | **L1** |
| Recording countdown 3-2-1 + go | before a set starts recording | **L1** |
| Recording start / stop | recorder | **L1** (stop plays after recording ends) |
| Rest timer — last 3 seconds ticks | rest timer (EU) | **L1** |
| Rest over (bell) | rest timer ends | **L1** |
| Interval change (walk ↔ run) | interval exercises | **L1** (with the spoken cue) |
| Workout complete | last set submitted | **L1** |
| Achievement unlock (rising sparkle, matches drop-squash) | `playUnlock` | **L1** |
| Refresh | pull-to-refresh (GC) - placeholder built 2026-11-05 | L2 |
| Sheet open / close (very soft) | bottom sheets and panels | L2 |
| Tab switch (very soft, optional) | tab bar | L2 |
| In-app notification arrived | card appears while the app is open | L2 |
| Day complete | Home checklist (ES / FH) | L2 |
| Streak level-up / consistency tier up | streak badge row | L2 |
| Goal complete | celebration screen | L2 |
| Personal best | a new best is recorded | L2 |
| Offer accepted (coach) | a trainee accepts | L2 |
| Deposit received / payout sent (coin) | payments | L2 |
| Friend request accepted / congratulations received | Social | L2 |
| Points earned / shop purchase / Event rank change | FS | Later |
