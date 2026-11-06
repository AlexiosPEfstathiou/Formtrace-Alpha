# Formtrace — openart style brief and L1 prompts (PRODUCT_LOG EW)

Ready-to-use brief for the paid openart month. Read with `docs/DESIGN_ASSETS.md` (the full list, tiers and specs).
Drafted 2026-11-05 (C). The owner adjusts the words and picks; nothing here is final until chosen.

## 1. The brief (paste as the project description / first message)
**Formtrace** is an online fitness-coaching app: a trainee posts a goal, coaches pitch a plan, the trainee records each set on
their phone, the app **traces their form** (pose tracking — joints and movement paths), and the coach reviews every session.
North star: people grow their **fitness and their social life**; Formtrace becomes a **community brand that brings people
together**. Audience: adults of all body types and levels, and the coaches who train them; Ireland first, English (en-GB).

**Personality:** precise · encouraging · athletic · warm · community. Confident, never aggressive.
**The idea to carry everywhere: "traced form"** — thin motion-trace lines that follow joints through a movement (hips, knees,
hands), with small dots at the joints. The landing page already shows it: a bodyweight squat, arms held forward, gold dashed
traces for the hips and knees, lime joint dots.
**Colours:** background `#0B0E11`, cards `#151B21`, signature **gold `#F0D231`** (main accent — traces, buttons),
**lime `#C8FF3D`** (joints, attention — sparingly), white text `#EEF3F6`, muted `#8593A0`. Light theme gold `#B8960A`.
**Shapes:** rounded rectangles (14–28 px radius), circles, thin round-capped lines; generous dark space.
**Type:** display face **Big Shoulders Display** (tall, condensed, athletic) with a clean system sans for text. The wordmark is
"FORM**TRACE**" (TRACE in gold).
**Avoid:** stock-gym clichés (dumbbells everywhere, flexing muscles, sweat, chains), aggressive bodybuilding imagery, one body
type only, neon cyberpunk, glossy 3D, heavy gradients, clutter, any real brand or character, **any text inside generated
images** (text is added afterwards in vector — AI lettering is unreliable).
**Must work:** tiny (16–24 px) and on phones; on dark first, then checked on light; calm enough for a reduced-motion version.

## 2. Working method (to keep one consistent theme)
1. **Logo first** — it sets the style. Explore 3 directions (below), pick one, refine.
2. Use the chosen logo / hero as a **style reference image** for every later prompt (openart's style or image reference), and
   keep the same palette words in every prompt.
3. If openart's plan allows **training a style model**, train it once 10–20 images are approved, then generate the rest with it.
4. Download masters at the largest size; **vectorise** the logo, mark and badges (trace to SVG, or a designer's finishing pass).
5. Record every chosen file (name, prompt, seed if shown) in `DESIGN_ASSETS.md` so the theme can be extended later.
6. **Icons:** take the 13 tab / header icons from **Lucide** or **Phosphor** (MIT licence — free, commercial use, one consistent
   24 px family), styled in the theme's colours — instead of generating them. Saves credits; better at 24 px.
7. **Sounds:** openart's audio tools focus on voice; for sound effects use **ElevenLabs Sound Effects** (paid plans include
   commercial use) or CC0 libraries (Kenney UI Audio, Freesound CC0) — prompts in section 4.

## 3. L1 image prompts
Each prompt is followed by a **negative prompt** (what to avoid). Add `--` aspect ratio / size as openart asks.

### 3.1 Logo mark — three directions to explore
- **A. Traced F:** "Minimal geometric logo mark for a fitness coaching app called Formtrace: a single continuous thin gold line
  (#F0D231) that traces the path of a squat and resolves into an abstract letter F, with two small lime (#C8FF3D) dots marking
  joints, on a near-black background (#0B0E11), flat vector style, perfectly centred, bold silhouette that stays readable at
  16 pixels, generous negative space"
- **B. Joint constellation:** "Minimal logo mark: three to five small dots connected by thin round-capped gold lines forming a
  stylised human figure in mid-squat, abstract and geometric, gold #F0D231 lines and lime #C8FF3D dots on #0B0E11, flat vector,
  centred, simple enough for an app icon"
- **C. Motion arc:** "Minimal logo mark: one bold gold arc (#F0D231) sweeping like a movement path, ending in a single lime dot
  (#C8FF3D), suggesting motion being traced, flat vector, on #0B0E11, centred, strong at small sizes"
- **Negative (all):** text, letters other than F, words, photo, 3D, gradient, glow, shadow, dumbbell, muscles, flame, gym
  equipment, clutter, thin hairline details that vanish when small

### 3.2 Wordmark lock-up
Generated lettering is unreliable — **set the wordmark in vector** (Big Shoulders Display, "FORM" white + "TRACE" gold) next to
the chosen mark. Use openart only to explore spacing / layout ideas: "logo lock-up layout sketch: abstract mark on the left,
space for a tall condensed wordmark on the right, gold and white on near-black, flat, minimal" (negative: readable text).

### 3.3 App icon (from the chosen mark)
"App icon: the [chosen] Formtrace mark in gold (#F0D231) with lime (#C8FF3D) accents, centred on a near-black (#0B0E11) square
background, the mark filling about 60% of the square, flat, crisp edges, no text"
Negative: text, border, frame, gradient background, photo, 3D, shadow. **Then:** export 512 and 192; maskable 512 with the mark
inside the central 80%; Apple touch 180 x 180 without transparency. **Notification icon (96 px)** and **favicon (SVG + 32/16)**
are made from the **vector** mark (white silhouette for the notification icon) — not generated.

### 3.4 Share image 1200 x 630 (Open Graph)
"Wide banner, dark near-black background (#0B0E11), on the right an abstract athlete silhouette mid-squat with arms held
forward, drawn only with thin gold (#F0D231) motion-trace lines and small lime (#C8FF3D) joint dots, calm and precise, the left
half left empty for a headline, editorial minimal style, lots of negative space"
Negative: text, letters, logos, photo, realistic face, muscles, gym equipment, clutter, gradient sky.
**Then** add in vector: the logo and "A real coach for every rep you record". Check it as a small WhatsApp thumbnail.

### 3.5 Landing page hero (keeps the traced-form idea)
"Abstract illustration of a person doing a bodyweight squat with arms extended forward, side view, body drawn with clean white
round-capped lines, joints as small lime (#C8FF3D) dots, the paths of the hips and knees traced as gold (#F0D231) dashed curves,
on a near-black (#0B0E11) rounded panel, flat vector, minimal, precise, inclusive (no specific body type)"
Negative: text, photo, realistic face, muscles, gym, equipment, shadows, 3D, gradient, busy background.
Variants for **section art** (same style): "...two people side by side, one cheering the other" (Better with friends);
"...a phone showing the traced figure" (Your form, traced); "...a calendar of weeks with gold ticks" (Pay for progress).

### 3.6 Stripe branding
Icon = the app icon (square, ≥ 128 x 128, check it on white); logo = the horizontal lock-up (3.2) as PNG. No generation needed.

## 4. L1 sound prompts (for ElevenLabs Sound Effects, or to search a CC0 library)
One sonic family: soft, warm, precise; short; no harsh clicks; matched loudness. Keep each under the length given.
| Sound | Prompt | Max length |
|---|---|---|
| Button tap | "very soft short muted wooden tap, UI click, gentle, warm" | 0.1 s |
| Success | "short bright two-note rising chime, friendly confirmation, soft marimba" | 0.3 s |
| Error / blocked | "soft low muted thud, gentle error, not alarming" | 0.25 s |
| Countdown tick | "clean soft metronome tick, warm, single beat" | 0.12 s |
| Go | "short bright positive tone signalling start, slightly higher than a tick" | 0.3 s |
| Recording start / stop | "short soft rising chirp" / "short soft falling chirp" | 0.2 s |
| Rest timer — last 3 seconds | "quiet soft wooden tick" | 0.08 s |
| Rest over | "warm single bell, soft attack, gentle decay, gym-timer feel but calm" | 1.5 s |
| Interval change | "two-tone friendly chime, low then high, clear outdoors" | 0.4 s |
| Workout complete | "short uplifting four-note fanfare, soft marimba and bell, celebratory but brief" | 1 s |
| Achievement unlock | "magical rising sparkle arpeggio with a soft shimmer at the end, rewarding" | 1.2 s |
Files: MP3 or AAC, mono, 44.1 kHz, named as in the app (`tap`, `success`, `error`, `tick`, `go`, `recStart`, `recStop`,
`restTick`, `restOver`, `interval`, `complete`, `unlock`) so they replace the placeholders one by one.

## 5. L2 (same month if time allows) — prompt starters
- **Achievement icons (27 in 6 families):** "set of flat badge icons, one shape per family (Start, Discipline, Effort, Body,
  Journey, Social), each with one simple symbol, gold and lime on dark, consistent line weight, readable at 40 px, no text".
- **Consistency tiers (Bronze → Diamond):** "five versions of one round badge, bronze, silver, gold, platinum, diamond, same
  shape, flat, minimal, no text".
- **Empty-state illustrations (8):** "calm spot illustration in the Formtrace style (thin gold traces, lime dots, white lines on
  dark), [subject: an empty calendar / a waiting coach / a quiet inbox ...], minimal, lots of space, no text".
- **Sign-in artwork:** the hero style, wider, quieter, leaving room for the form.
