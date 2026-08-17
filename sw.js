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
