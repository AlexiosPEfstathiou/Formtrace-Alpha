/* Formtrace service worker — installability only, deliberately not a cache.
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
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: "Formtrace", body: event.data ? event.data.text() : "" }; }
  const title = data.title || "Formtrace";
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
  /* GE (security review 2026-11-10): a notification may only open a page inside the app; anything else opens the app's home. */
  let target = self.registration.scope;
  try { const u = new URL(raw.replace(/^\//, ""), self.registration.scope); if (u.origin === self.location.origin) target = u.href; } catch (e) {}
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    /* GO (2026-11-11): the app is already open - tell it which tab to show, then bring it forward. Before, this asked the
       browser to navigate the page (client.navigate), which on the owner's phone left the app on the screen it was already
       on: an alert for Review opened on Goal. A message does not depend on the browser's navigation rules. */
    for (const c of list) { if (c.url.startsWith(self.location.origin)) {
      let tab = ""; try { tab = new URL(target).hash.replace("#", ""); } catch (e) {}
      try { c.postMessage({ type: "ft-nav", tab: tab, url: target }); } catch (e) {}
      return c.focus().catch(() => {});
    } }
    return self.clients.openWindow(target);
  }));
});