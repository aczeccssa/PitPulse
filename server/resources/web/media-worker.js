const cacheName = "pitpulse-media-v1";

self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));

self.addEventListener("fetch", event => {
    const url = new URL(event.request.url);
    if (event.request.method !== "GET" || url.origin !== self.location.origin ||
        !/^\/media\/blob\/[0-9a-f]{64}$/.test(url.pathname)) return;

    event.respondWith((async () => {
        const cache = await caches.open(cacheName).catch(() => null);
        const cached = await cache?.match(url.pathname).catch(() => null);
        if (cached) return cached;
        const response = await fetch(event.request);
        if (response.ok && cache) await cache.put(url.pathname, response.clone()).catch(() => {});
        return response;
    })());
});
