// Service worker: network-first for the app's own files (so updates arrive fast),
// cached copy as an offline fallback. API calls and CDN scripts are never touched.
const CACHE = "melech-v9";
const SHELL = [
  "./",
  "index.html",
  "config.js",
  "teams.js",
  "manifest.webmanifest",
  "icon.svg",
  "icon-192.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches
      .open(CACHE)
      .then((c) => c.addAll(SHELL))
      .then(() => self.skipWaiting()),
  );
});
self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});
self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  if (
    e.request.headers.has("range") ||
    /\.(mp3|m4a|ogg|wav|aac)$/i.test(u.pathname)
  )
    return; // let audio stream directly
  e.respondWith(
    fetch(e.request)
      .then((r) => {
        const copy = r.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return r;
      })
      .catch(() =>
        caches.match(e.request).then((r) => r || caches.match("index.html")),
      ),
  );
});

// ---- Push notifications ----
self.addEventListener("push", (e) => {
  let d = {};
  try {
    d = e.data.json();
  } catch {
    /* ignore */
  }
  e.waitUntil(
    self.registration
      .showNotification(d.title || "מלך התחזיות", {
        body: d.body || "",
        icon: "icon-192.png",
        badge: "icon-192.png",
        tag: d.tag,
        dir: "rtl",
        lang: "he",
        data: { url: d.url || "./" },
      })
      .then(() => clients.matchAll({ type: "window" }))
      .then((list) => list.forEach((c) => c.postMessage({ type: "push" }))),
  );
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  e.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((list) => {
        const url = e.notification.data.url;
        for (const c of list)
          if ("focus" in c) {
            c.postMessage({ type: "open", url });
            return c.focus();
          }
        return clients.openWindow(url);
      }),
  );
});
