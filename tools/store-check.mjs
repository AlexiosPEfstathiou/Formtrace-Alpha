// store-check: every store.<name>(…) and store.<ns>.<method>(…) the app calls must exist in
// store.supabase.js. The render check's stand-in store answers any name, so a misnamed call
// (store.journeySummary instead of store.auth.journeySummary) could never fail there.
// usage: node tools/store-check.mjs index.html store.supabase.js
import fs from "node:fs";
const [, , appPath = "index.html", storePath = "store.supabase.js"] = process.argv;
const app = fs.readFileSync(appPath, "utf8"), storeSrc = fs.readFileSync(storePath, "utf8");
// a stand-in Supabase client: any property, any call, chainable
const deep = () => new Proxy(function () {}, { get: (t, p) => (p === "then" ? undefined : deep()), apply: () => deep() });
const win = { FT_CONFIG: { SUPABASE_URL: "https://x.supabase.co", SUPABASE_ANON_KEY: "k" }, supabase: { createClient: () => deep() } };
win.window = win;
const quiet = { log() {}, warn() {}, error() {} };
new Function("window", "console", storeSrc)(win, quiet);
const store = win.store;
if (!store) { console.log("STORE CHECK: FAIL - store.supabase.js did not define window.store"); process.exit(1); }
const calls = new Map();
for (const m of app.matchAll(/(?<![\w.$])store\.(\w+)(?:\.(\w+))?\s*\(/g)) {
  const [ , a, b ] = m; if (a === "_sb") continue;              // the raw Supabase client: not ours to check
  const key = b ? `${a}.${b}` : a; if (!calls.has(key)) calls.set(key, app.slice(0, m.index).split("\n").length);
}
const missing = [];
for (const [key, line] of calls) {
  const [a, b] = key.split(".");
  const ok = b ? (store[a] && typeof store[a][b] === "function") : typeof store[a] === "function";
  if (!ok) missing.push(`store.${key}() - first used at line ${line}`);
}
if (missing.length) { for (const x of missing) console.log("  FAIL  " + x); console.log(`STORE CHECK: ${missing.length} missing of ${calls.size} store calls`); process.exit(1); }
console.log(`STORE CHECK OK: ${calls.size} distinct store calls all exist`);
