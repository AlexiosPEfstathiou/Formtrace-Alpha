# Formtrace — design assets for an openart theme (living list)

**Purpose:** every visual element of Formtrace that could be replaced by a designed asset.
When it is time, take this whole list to openart.ai (PRODUCT_LOG **EW**) and ask for **one
consistent theme across all of it** — not one-off pieces.
**Keep it current:** whoever builds or changes a visual element adds or updates its row
(rule in CLAUDE.md). Status: **placeholder** = stand-in today · **current** = acceptable but
generic · **future** = not built yet, design needed when it is.

**Theme constraints to give openart:** dark UI first (light theme exists); signature accent
**gold `#F0D231`** (light theme `#B8960A`); attention lime `#C8FF3D`; status red `#FF5A5A`,
amber `#FFC24A`, blue `#5AB0FF`, violet `#B79CFF`; backgrounds `#0B0E11` / cards `#151B21`.
Name: **Formtrace** (owner, 2026-11-04 - not FormTrace; wordmark today: "FORM**TRACE**" with TRACE in gold). Audience: trainees and
coaches, fitness, form and progress. Must work small (16–24 px) and on phones; animations need
a calm reduced-motion version.

## 1. Brand core
| Asset | Where | Status | Notes |
|---|---|---|---|
| Logo / wordmark "FORMTRACE · COACH" | Home hero (`.logo`), sign-in | current (text only) | Needs a real mark + wordmark lock-up |
| App icon 192 / 512 / maskable 512 | `icon-192.png`, `icon-512.png`, `icon-512-maskable.png` | placeholder | Home-screen icon; maskable needs a safe zone |
| Apple touch icon | `apple-touch-icon.png` | placeholder | iPhone home screen |
| Notification bar icon | `badge-96.png` (white "FT" on transparent) | placeholder (DJ) | Must be a single-colour silhouette |
| Browser tab icon (favicon) | manifest / page | placeholder | 32 px and 16 px versions |
| Colour palette and type | CSS variables in `index.html` | current | The theme may refine, not replace, the gold |

## 2. Navigation icons (today: Unicode symbols / emoji)
| Tab | Today | Who |
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
Also: settings gear, back arrow, the header avatar — one icon family for all.

## 3. Badges, marks and status pills
| Asset | Where | Status | Notes |
|---|---|---|---|
| Achievement icons — 27 achievements in 6 families (Start, Discipline, Effort, Body, Journey, Social) | Profile achievements grid, unlock animation (CY) | placeholder (family colours) | One icon per achievement, family-coded |
| Consistency badge tiers Bronze → Silver → Gold → Platinum → Diamond | streak badge row (BW) | placeholder | Five tiers, every 13 weeks |
| Streak flame chip ("🔥 1d") | top-right header | current (emoji) | Also has an amber "at risk" state |
| Founding coach badge | coach cards (BQ) | placeholder | Permanent, prestigious |
| Top 1% coach gold frame + label | pitch rows (BY) | current (animated gold frame) | |
| Verified / certification badges | coach cards (`badgeSpans`) | current (text pills) | |
| "⚡ Reviews within a day" mark | coach card (EL) | current (text + emoji) | |
| Referral reward tiers | Profile referral card (BN/BW) | placeholder | |
| "Offer accepted" pill, red "to assign" / green "to review" counts | Trainees list (FD) | current | |
| Tab badge dots | tab bar | current (red dot) | |

## 4. Celebrations, motion and progress
| Asset | Where | Status | Notes |
|---|---|---|---|
| Achievement unlock animation (drop-squash, ring sweep, particles) | `playUnlock` (DA) | current | Family colours are placeholders |
| Streak level-up confetti | `sbConfetti` | current | |
| "Day complete" celebration (check pop + confetti) | Home checklist (ES / FH) | current | |
| Goal celebration screen | `s-celebrate` | current | |
| "Your journey" recap screen | `s-journey` | current | Candidate for an illustrated recap |
| Payment tracker steps map | goal payment card (DL) | current | Accepted → Deposit → Training → Complete |
| Rest timer stopwatch (ring, green → red) | workout screen (EU) | current | Crown, side button, ring |
| Analysis progress ring | after a set (`#analyze`) | current | |
| Glisten / guide pulse effects | calendar, cards, call walkthrough | current | |
| Loading spinner / app loading | everywhere | current | |

## 5. Shareable images (drawn by the app)
| Asset | Where | Status | Notes |
|---|---|---|---|
| Referral invite image 720×960 | `referralShareImage` (DG) | current | Shared to WhatsApp / Instagram |
| Referral QR card (lime frame, FT mark) | `renderQrInto` (DG) | current | |
| Check-in photo timelapse | `s-timelapse` | current | Frame, title card, watermark |
| Check-in photo guide (head and feet outline) | camera (CS) | current | |

## 6. Empty states, placeholders and illustrations
| Asset | Where | Status | Notes |
|---|---|---|---|
| Empty-state icons ("No goals posted yet", "No pending applications", …) | `.empty .ic` on many screens | placeholder (symbols) | One illustration style for all |
| Avatar fallback (initials) | everywhere | current | |
| Video thumbnail placeholder | exercise and goal cards (`.ex-thumb .ph`) | placeholder | |
| Sign-in / consent screen artwork | `s-auth`, `s-consent` | current (plain) | First impression |
| Home hero background | `s-home .hero` | current (plain) | |
| Coach application screen | `s-coach-apply` | current (plain) | |

## 7. Camera and recorder
| Asset | Where | Status | Notes |
|---|---|---|---|
| Pose overlay skeleton (joints, lines) | recorder | current | Colours and line style |
| Record button, countdown, take review | recorder (`#rec`) | current | |

## 8. Outside the app
| Asset | Where | Status | Notes |
|---|---|---|---|
| Stripe Checkout and Connect branding (icon, colour) | Stripe settings (EC) | current (gold + placeholder icon) | |
| Sign-in / password-reset emails | Supabase Auth templates | current (default) | |
| Email signature and templates | Zoho, @formtrace.ie (EH) | future | |
| **Landing page - the whole page** (layout, hero, section art, typography, button) | formtrace.ie for signed-out visitors (EX, 2026-11-04) | current (built in code) | Owner 2026-11-04: an openart item - keep the copy and structure, redesign the look within the theme |
| Landing page hero: pose-traced squat (SVG, animated) | `#landing` in index.html (EX, 2026-11-04) | current | Bodyweight squat, arms held forward (owner, 2026-11-04); joints lime, hip and knee paths gold; a designed version should keep the "traced form" idea |
| Share preview (Open Graph) image 1200x630 | `og:image` (EX) | placeholder (icon-512) | Shown on WhatsApp / Instagram / Facebook links |
| Landing display typeface: Big Shoulders Display | landing headlines (EX) | current | Candidate for the brand face across the app |
| Onboarding walkthrough art | first-run tours (EV) | future | |
| Encouragement-video frame / card | EY | future | |
| Points and cosmetic add-ons (avatar frames, themes, celebration styles) | FL | future | The add-ons themselves are design work |
| App-store screenshots and listing art | native app (deferred) | future | |
| Social media profile and cover images | Instagram etc. | future | |
