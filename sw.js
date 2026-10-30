/* FormTrace service worker — installability only, deliberately not a cache.
   Scoped this way on purpose: almost everything this app shows is live
   Supabase data (assigned workouts, review status, streaks, payment
   cycles) where a stale cached response could show something that's no
   longer true — has this been reviewed, is this goal still active, did
   the coach just decline. A service worker that caches aggressively would
   trade a real correctness risk for offline support nobody asked for.
   This one exists only to satisfy the install criteria some platforms
   check for; every request still goes straight to the network exactly as
   if this file didn't exist. */
self.addEventListener("install", () => {
  self.skipWaiting();
});
self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});

/* Item CE: Web Push. The server sends {title, body, url, kind, tag}. */
self.addEventListener("push", (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: "FormTrace", body: event.data ? event.data.text() : "" }; }
  const title = data.title || "FormTrace";
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || "",
    icon: "icon-192.png",
    badge: "badge-96.png",   // DJ: monochrome - Android draws the status-bar icon from alpha only
    tag: data.tag || undefined,
    renotify: !!data.tag,
    data: { url: data.url || "/" }
  }));
});
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  /* EP: push urls are written as "/#tab"; resolve them against the worker's scope (the app folder), not the origin root - on github.io the root is a 404. */
  const raw = (event.notification.data && event.notification.data.url) ? String(event.notification.data.url) : "/";
  const target = new URL(raw.replace(/^\//, ""), self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) { if (c.url.startsWith(self.location.origin)) { c.focus(); c.navigate(target).catch(() => {}); return; } }
    return self.clients.openWindow(target);
  }));
});