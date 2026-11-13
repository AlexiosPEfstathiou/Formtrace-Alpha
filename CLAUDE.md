# CLAUDE.md — working rules for Formtrace Coach

Read this first, then `docs/HANDOVER.md` (where things stand) and `PRODUCT_LOG.md`
(every item, decision and finding, newest items at the top of the index).

## Session routine - two Claude accounts, one repository (owner rule, 2026-10-29)
The owner works from **two Claude accounts** (Lilly and personal). Neither can see the
other's chats or memory - **this repository is the shared memory.**
1. **Start of every session:** `git pull`, then read **this file**,
   **`docs/HANDOVER.md`** and **`supabase/SQL_JOURNAL.md`** before doing anything else.
2. **Every 5 owner prompts** in a session: update `docs/HANDOVER.md` (state, plan,
   decisions, blockers) and this file (any new rule or convention), commit
   "Handover refresh", push. Also do it before the session ends. (Last refresh: 2026-11-13, personal account - GP voice-over drawings, GQ / GR / GS review push link, send confirmation, withdraw; see top of HANDOVER.)
3. **Every SQL command handed to the owner** gets a row in `supabase/SQL_JOURNAL.md`
   (status `given`); when the owner confirms, mark it `run ✓` with the result. Never
   assume SQL was run - check the journal, or run its verification query.
4. **Every decision** goes into `PRODUCT_LOG.md`, not only into a chat.
5. **One machine active at a time:** pull before starting, push before stopping;
   allocate the next item code only after pulling.
6. **If a push is rejected, the other account has pushed.** Fetch, read its commits
   (`git log HEAD..origin/main`, `git show`), treat its decisions as current, and
   re-apply only what is new on top - never force-push.

## What this is
A coaching PWA: trainees post goals, coaches pitch, trainees record sets, coaches
review with tags, voice-over and drawing. **Single file app** — `index.html` holds
all HTML, CSS and the ES module; `store.supabase.js` is the data layer; `sw.js` the
service worker. No build step. Hosted on GitHub Pages from `main`; backend Supabase.

## The rules that prevent breakage (all learned the hard way — see PRODUCT_LOG)
1. **Verify before building.** Read the actual code before assuming a feature is or
   is not there. Several "missing" features already existed.
2. **Every edit is anchored and verified.** Replace by a unique, exact anchor; check
   the anchor occurred exactly once; report each anchor's result. **Never push if any
   anchor missed** — the gate cannot see a skipped edit. **Assert the expected number
   of anchors** (an empty result must fail, not pass), and never name a PowerShell helper
   after a built-in alias (`R`, `h`, `r`, `ls`, `cd`…) - it silently runs the alias.
3. **The gate must pass before every push** — all four checks:
   ```
   node tools/check.mjs                                        # parse + ids smoke test → must print PASSED
   node tools/toplevel-check.mjs index.html /tmp/ft_mod.mjs    # module evaluates at top level → TOP-LEVEL OK
   node tools/render-check.mjs index.html /tmp/ft_render.mjs   # runs every render* for trainee and coach → RENDER CHECK OK
   node tools/store-check.mjs index.html store.supabase.js     # every store.x() the app calls exists → STORE CHECK OK
   ```
   (`tools/gate.ps1` runs all three on the original Windows machine; its paths are
   hard-coded there.) Push only when **anchors all landed AND the gate passed**.
4. **No `//` comments inserted mid-line** in a one-line JS statement — it comments out
   the rest of the line and broke the live module once. Use `/* … */`.
5. **Supabase `rpc()` / query builders are thenable but have NO `.catch`.** Use
   `.then(...)` or wrap in `Promise.resolve(...)`. (This hid the coach homepage for a
   week; render-check now catches it.)
6. **`profiles` has column-level grants.** A new column the client writes needs
   `grant update (col)` — or, better, write through a `security definer` function, as
   every recent feature does.
7. **Every trigger that is a side effect (push, achievements, badges, anything not the action itself) catches its own errors** - DQ: an achievement trigger without this blocked goal completion for five weeks. Read NEW fields of a trigger shared across tables via `to_jsonb(new)->>'field'`. Originally: **every push trigger catches its own errors** (`begin … exception when others`), so
   a notification can never block the write it describes. Keep it that way.
8. **Migrations must be safe to run before their dependencies:** guard references to
   optional tables (`to_regclass('public.push_outbox') is not null`).
9. **Give the owner the SQL in the reply** — always, in full — and say what the final
   `select` should show.
10. **Never put secrets in the repo or the chat** (including Stripe `sk_…` keys and webhook signing secrets). The Supabase anon key in
    `config.js` is public by design; the service role key and the VAPID private key
    are not (Edge Function secrets only).
11. **Log honestly.** Every change gets a PRODUCT_LOG entry: what, why, what was not
    done, and any mistake made on the way.

## Conventions
- New product items take the next two-letter code (last used: **GS**; next **GT**) - **always check the log for the highest code before allocating: both accounts write items**,
  with an entry under its own `## XX.` heading and a row in the index table.
- Copy: British English, sentence case, no exclamation-mark spam; buttons say what
  happens ("I've paid", "Received ✓").
- Lime (`--lime`) means tappable. Dark theme first; both themes must work.
- Achievements and the Consistency badge are **friends-only**, never public.
- The owner prefers concise, formal replies; screenshots identify UI problems fastest —
  ask for one on the first "doesn't work" report, and read Review → Client errors.

## Design assets list (owner, 2026-11-02)
Whenever you build or change a visual element (icon, badge, animation, illustration, shareable image, empty state, branded email or page) **or a sound**, add or update its row in `docs/DESIGN_ASSETS.md`, with its tier (L1 / L2 / Later / Code) and spec. It is the brief for the openart theme (PRODUCT_LOG EW).

## Last session (2026-11-05 to 2026-11-10, work account)
Read the top of docs/HANDOVER.md ("Session 2026-11-05 to 2026-11-10"). **Whole-repo security review: items GD-GJ; GD, GE, GF, GG,
GH built and all their SQL run** (details in the git-ignored `docs/private/` on the work laptop). **Open: `refund-send` is not
deployed under that name (404)**; owner tests in `docs/TEST_QUEUE.md` (security ones first); GD step 4; GI; GJ. Product: **GK
trainee Training tab as a control panel**, GA camera first pass, EZ builder fixes + EZ-6 / 6b cumulative notes, FZ sounds (passed),
GC pull-to-refresh, EW openart brief. No SQL pending. Next item code: **GP** (GO = notification-tap fix, 2026-11-11; GL, GM, GN were used by the personal account on 2026-11-10 evening: Training-tab scroll fix, camera-denied steps, rest-timer pill).

## Session before (2026-11-04 night, personal account)
FU verified; FP refund push passed on the phone; EJ dispute tests 1-2; EJ part 3 (a card dispute cancels the goal and its payouts);
GA camera logged; GB weekly report logged. EJ part 3 test (fresh 0259 payment) still to do from the personal account.
## Brand name (owner, 2026-11-04)
Write **Formtrace** (not FormTrace) in all new text. Older text is swept under PRODUCT_LOG FV when the owner says go.

## Expense log (owner, 2026-11-04)
Whenever a cost starts, changes or stops (a subscription, a plan change, a domain, a fee), add or update its row in `docs/EXPENSES.md` (PRODUCT_LOG FW).

## Test queue (owner, 2026-11-05)
Every owner test that is built and waiting goes into `docs/TEST_QUEUE.md` (grouped by where the owner will be in the app). Tick or remove lines when the owner reports results, and mirror the result in PRODUCT_LOG.
**Test interview (owner, 2026-11-05):** when the owner says he has tested the app (e.g. after a workout), **interview him through every pending line of `docs/TEST_QUEUE.md`**, one group at a time in the file's order - ask what he saw for each test (pass / fail / not tried), ask a follow-up on any failure (device, screen, what happened, which side for GA-T4), then tick passes, log failures as findings in PRODUCT_LOG, and keep "not tried" lines in the queue.

## Security rules (review 2026-11-10)
- **Every `revoke execute on function` names `public, anon, authenticated`** - on Supabase `from public` alone locks nothing. Internal functions get no grant; functions the app calls get `grant execute ... to authenticated`.
- User-written text is inserted with `escapeHtml` / `textContent`, never raw; URLs built from user text use `encodeURIComponent`.
- New tables: row-level security on, and write access by column (like `profiles`), not `for all`.
- **While the repo is public, exploit detail goes in `docs/private/` (git-ignored), not in committed files.**
- **Edge Functions (2026-11-11):** redeploying means updating the EXISTING function - never create a second one (an old copy, `smooth-service`, kept running unprotected code for a day). A function's URL is fixed at creation and may differ from its name (`refund-send` = `/functions/v1/super-api`); test at the URL shown in the Edge Functions list. The deployed set must equal the six folders in `supabase/functions/`.
