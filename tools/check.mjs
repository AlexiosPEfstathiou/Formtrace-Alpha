// FormTrace smoke test — run:  node tools/check.mjs
// Catches the classes of bug that actually bit us: parse errors, JS
// referencing elements that no longer exist, router targets with no screen,
// and render functions the router calls but nobody defined.
import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(root, "index.html"), "utf8");
let fails = 0, warns = 0;
const fail = m => { console.log("  FAIL  " + m); fails++; };
const warn = m => { console.log("  warn  " + m); warns++; };
const ok   = m => console.log("  ok    " + m);

const mod = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!mod) { console.log("FAIL: no module script found"); process.exit(1); }
const js = mod[1];

// 1. parse
const tmp = join(root, "_smoke.mjs");
try {
  writeFileSync(tmp, js, "utf8");
  execFileSync(process.execPath, ["--check", tmp], { stdio: "pipe" });
  ok("module parses");
} catch (e) {
  fail("module does NOT parse:\n" + (e.stderr?.toString() || e.message));
} finally { try { unlinkSync(tmp); } catch {} }

// 2. every element the JS reaches for exists somewhere in the markup
const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map(m => m[1]));
// elements can also be built in JS and given an id by assignment, e.g.
// `ta.id="rev-overall"` — those are just as real, so collect them too.
for (const m of js.matchAll(/\.id\s*=\s*"([A-Za-z0-9_-]+)"/g)) ids.add(m[1]);
for (const m of js.matchAll(/\.setAttribute\("id",\s*"([A-Za-z0-9_-]+)"\)/g)) ids.add(m[1]);
const refs = new Set();
for (const m of js.matchAll(/\$\("#([A-Za-z0-9_-]+)"\)/g)) refs.add(m[1]);
for (const m of js.matchAll(/getElementById\("([A-Za-z0-9_-]+)"\)/g)) refs.add(m[1]);
const missing = [...refs].filter(r => !ids.has(r)).sort();
if (missing.length) fail(`JS references ${missing.length} id(s) with no element: ${missing.join(", ")}`);
else ok(`all ${refs.size} referenced ids exist`);

// 3. every navigation target has a screen
const goTargets = new Set([...html.matchAll(/data-go="([A-Za-z0-9_-]+)"/g)].map(m => m[1]));
for (const m of js.matchAll(/\bgo\("([A-Za-z0-9_-]+)"\)/g)) goTargets.add(m[1]);
const synthetic = new Set(["ex-edit-new", "wo-build-new"]);
const noScreen = [...goTargets].filter(t => !synthetic.has(t) && !ids.has("s-" + t)).sort();
if (noScreen.length) fail(`navigation targets with no screen: ${noScreen.join(", ")}`);
else ok(`all ${goTargets.size} navigation targets resolve to a screen`);

// 4. router render functions are defined
const called = [...js.matchAll(/\bR\((render[A-Za-z0-9_]+)\)/g)].map(m => m[1]);
const undef = [...new Set(called)].filter(fn =>
  !new RegExp(`(async\\s+)?function\\s+${fn}\\s*\\(`).test(js));
if (undef.length) fail(`router calls undefined function(s): ${undef.join(", ")}`);
else ok(`all ${new Set(called).size} router render functions defined`);

// 5. store accessors used by the client are exposed
let storeJs = "";
try { storeJs = readFileSync(join(root, "store.supabase.js"), "utf8"); } catch {}
if (storeJs) {
  const exposed = new Set([...storeJs.matchAll(/(\w+)\s*:\s*table\("/g)].map(m => m[1]));
  // store members are also written as plain or async methods, e.g.
  // `async videoRotations(paths) {` — those are exposed just the same
  for (const m of storeJs.matchAll(/^\s*(?:async\s+)?([A-Za-z_]\w*)\s*\([^)]*\)\s*\{/gm)) exposed.add(m[1]);
  for (const m of storeJs.matchAll(/(\w+)\s*:\s*(?:async\s*)?\(/g)) exposed.add(m[1]);
  ["auth","video","coachApps","coaches","_sb","subscribe","from"].forEach(k => exposed.add(k));
  const used = new Set([...js.matchAll(/\bstore\.([A-Za-z_][A-Za-z0-9_]*)/g)].map(m => m[1]));
  const notExposed = [...used].filter(u => !exposed.has(u)).sort();
  if (notExposed.length) fail(`store.<x> used but not exposed: ${notExposed.join(", ")}`);
  else ok(`all ${used.size} store accessors exposed`);
} else warn("store.supabase.js not readable — skipped store check");

// 6. style blocks balanced
const styles = [...html.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m => m[1]);
let styleBad = false;
styles.forEach((s, i) => {
  const d = (s.match(/{/g) || []).length - (s.match(/}/g) || []).length;
  if (d !== 0) { fail(`style block ${i} brace imbalance: ${d}`); styleBad = true; }
});
if (!styleBad) ok(`${styles.length} style block(s) balanced`);

// 7. RPCs need a matching DB function — cannot verify from here
const rpcs = [...new Set([...js.matchAll(/\.rpc\("([A-Za-z0-9_]+)"/g)].map(m => m[1]))];
if (rpcs.length) warn(`confirm these RPCs exist in the DB: ${rpcs.join(", ")}`);

console.log(`\n${fails ? "FAILED" : "PASSED"}  (${fails} failure${fails === 1 ? "" : "s"}, ${warns} warning${warns === 1 ? "" : "s"})`);
process.exit(fails ? 1 : 0);
