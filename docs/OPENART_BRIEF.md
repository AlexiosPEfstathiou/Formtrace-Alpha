# Formtrace - OpenArt work plan (the art month, started 2026-11-23)

Working sheet for the OpenArt month (PRODUCT_LOG **EW**, item list in `docs/DESIGN_ASSETS.md`).
Order matters: **the logo mark is made first and becomes the style reference for everything after it**, so the theme
stays one family. Tick items here as they are done.

## How we work
1. You generate in OpenArt with the prompts below (4 variations each), pick one, upscale it.
2. Send me the chosen files (attach them in the chat) with their file names from the table.
3. I put them into the app / landing page / Stripe / emails list, check them on dark and light, push, and tick the row.
4. Anything that must be crisp at small sizes (logo, favicon, notification icon, badges) I trace to SVG or rebuild
   cleanly in code from your image - OpenArt makes pixels, not vectors.

**Every prompt starts with the style block** (paste it in front), and from step 2 on add the chosen logo as an
**image / style reference** in OpenArt.

> **Style block:** Formtrace, a fitness coaching app about movement, form and progress. Dark, premium, minimal.
> Background near-black #0B0E11. Signature accent deep gold #E8B923 (owner 2026-11-23; was #F0D231) - black and yellow only (owner 2026-11-23: no lime).
> Clean geometric shapes, smooth confident lines, subtle glow, no clutter, no text unless asked, no stock-photo look,
> no gym clichés (no dumbbell clip-art). Flat vector style, crisp edges.

Negative prompt (all): `text, letters, watermark, signature, photo, realistic skin, busy background, gradients mesh, 3d render, blurry`

## Step 1 - Logo mark (L1) - do first
Try the three directions; pick one direction, then iterate on it.
- **A. Traced motion:** "a single continuous gold line tracing the path of a moving body, abstract, forming a stylised
  F, on near-black, minimal vector logo mark, centred, generous padding"
- **B. Joint and line:** "logo mark: three gold dots joined by two lines like a joint angle (hip-knee-ankle), forming an
  abstract F, minimal vector, near-black background, centred"
- **C. Monogram shield:** "minimal monogram FT in a rounded square, gold strokes on near-black, geometric, modern
  fitness brand mark, vector, centred"
Output: square 2048 x 2048, mark only, lots of empty space. **Name:** `logo-mark.png`
Then the wordmark: "FORMTRACE wordmark, TRACE in gold #F0D231, FORM in off-white, condensed bold sports display type,
on near-black" - OpenArt is weak at letters; if the text comes out wrong, skip it - I set the wordmark in the app's
display face (Big Shoulders Display) next to your mark.

## Step 2 - Icons from the mark (L1) - I make these
From `logo-mark.png` I make: `icon-192.png`, `icon-512.png`, `icon-512-maskable.png` (mark in the central 80%),
`apple-touch-icon.png` (180, no transparency), `badge-96.png` (white silhouette), favicon SVG + 32/16, Stripe icon.
**Nothing to generate** unless the mark needs a filled background version: "the same logo mark on a solid #0B0E11
rounded square app icon background, subtle gold glow" -> `icon-base.png` 1024.

## Step 3 - Share image 1200 x 630 (L1)
"wide banner, near-black, the Formtrace logo mark on the left, abstract gold motion trail of a person training across
the right, plenty of dark space in the middle for a headline" (style reference: the mark). I add the headline text
("A real coach for every rep you record") and the wordmark in code. **Name:** `og-base.png` (1200 x 630 or larger, 1.9:1)

## Step 4 - Landing page hero (L1)
"hero illustration for a fitness coaching website, dark, an athlete mid-squat drawn as glowing gold joint lines and
dots over a faint silhouette, motion trail, premium and calm, lots of negative space on the left for text"
**Name:** `landing-hero.png` - 2400 x 1600 (or 3:2). Optional mobile crop `landing-hero-mobile.png` 1080 x 1350.

## Step 5 - Quest / points art (L1 for the quest celebration, L2 rest)
- Points coin: "a single gold coin icon with a small lightning or upward arrow emblem, flat vector, front view, on
  transparent background" -> `coin.png` 512
- Quest badge base: "round emblem badge, gold rim, dark centre, minimal, room for a small symbol inside" -> `quest-badge.png` 512

## Step 6 - Empty states (L2) - 8 spot illustrations, one style
Each: "small spot illustration, minimal, gold line art on transparent background, one simple scene: ___" with:
no goals (a flag on an empty track) · no offers (an empty envelope) · no trainees (an empty bench) · no workouts (a
blank calendar page) · no friends (two empty chairs) · no notifications (a quiet bell) · no applications (a clipboard)
· no achievements yet (an empty trophy shelf). **Names:** `empty-goals.png` ... 800 x 600, transparent.

## Step 7 - Badges (L2)
- Consistency tiers: "five versions of one badge: bronze, silver, gold, platinum, diamond; same shape, a flame-shaped
  centre, flat vector, transparent" -> `tier-bronze.png` ... 512 each.
- Achievement families (6 shapes): Start, Discipline, Effort, Body, Journey, Social - "badge shape set, six distinct
  silhouettes (circle, shield, hexagon, diamond, pentagon, star), gold outline, dark fill" -> `ach-shapes.png`
- Goal categories (8, owner HX): muscle gain, strength, fat loss, endurance, mobility, rehab, technique, other -
  "set of 8 minimal fitness icons, gold line, same stroke, transparent" -> `goal-icons.png` (a sheet is fine; I cut it).

## Not from OpenArt
- **Tab and header icons (13):** Lucide (free, MIT) styled in the theme - I do this in code, no credits needed.
- **Sounds:** not an image tool - separate (FZ).
- **Emails / Stripe:** reuse the mark and colours - I apply them once Step 1 is done.

## Progress
| Step | Files | Status |
|---|---|---|
| 1 | logo-mark.png (+ wordmark) | mark chosen 2026-11-23: traced-line F, deep gold #E8B923 - files in docs/brand/logo/; wordmark to do |
| 2 | app icons, favicon, badge, Stripe icon | waits for 1 |
| 3 | og-base.png | to do |
| 4 | landing-hero.png | to do |
| 5 | coin.png, quest-badge.png | to do |
| 6 | 8 empty states | to do |
| 7 | tiers, achievement shapes, goal icons | to do |
