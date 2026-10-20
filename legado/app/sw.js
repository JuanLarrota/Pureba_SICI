// Primero la red, para que cada ajuste llegue de inmediato; si no hay señal,
// lo último que se guardó. Los datos nunca se guardan aquí: solo la aplicación.
const CACHE = "sici-v10";
const PROPIOS = ["./", "index.html", "estilos.css", "app.js", "config.js", "manifest.webmanifest", "icono-192.png", "logo.png", "logo-blanco.png"];
self.addEventListener("install", e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(PROPIOS)).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => {
    const copia = r.clone();
    caches.open(CACHE).then(c => c.put(e.request, copia));
    return r;
  }).catch(() => caches.match(e.request).then(r => r || caches.match("index.html"))));
});
