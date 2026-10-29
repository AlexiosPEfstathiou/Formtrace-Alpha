# CLAUDE.md — working rules for FormTrace Coach

Read this first, then `docs/HANDOVER.md` (where things stand) and `PRODUCT_LOG.md`
(every item, decision and finding, newest items at the top of the index).

## Session routine - two Claude accounts, one repository (owner rule, 2026-10-29)
The owner works from **two Claude accounts** (Lilly and personal). Neither can see the
other's chats or memory - **this repository is the shared memory.**
1. **Start of every session:** `git pull`, then read **this file**,
   **`docs/HANDOVER.md`** and **`supabase/SQL_JOURNAL.md`** before doing anything else.
2. **Every 5 owner prompts** in a session: update `docs/HANDOVER.md` (state, plan,
   decisions, blockers) and this file (any new rule or convention), commit
   "Handover refresh", push. Also do it before the session ends.
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
   anchor missed** — the gate cannot see a skipped edit.
3. **The gate must pass before every push** — all three checks:
   ```
   node tools/check.mjs                                        # parse + ids smoke test → must print PASSED
   node tools/toplevel-check.mjs index.html /tmp/ft_mod.mjs    # module evaluates at top level → TOP-LEVEL OK
   node tools/render-check.mjs index.html /tmp/ft_render.mjs   # runs every render* for trainee and coach → RENDER CHECK OK
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
7. **Every push trigger catches its own errors** (`begin … exception when others`), so
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
- New product items take the next two-letter code (last used: **DL**; next **DM**),
  with an entry under its own `## XX.` heading and a row in the index table.
- Copy: British English, sentence case, no exclamation-mark spam; buttons say what
  happens ("I've paid", "Received ✓").
- Lime (`--lime`) means tappable. Dark theme first; both themes must work.
- Achievements and the Consistency badge are **friends-only**, never public.
- The owner prefers concise, formal replies; screenshots identify UI problems fastest —
  ask for one on the first "doesn't work" report, and read Review → Client errors.
