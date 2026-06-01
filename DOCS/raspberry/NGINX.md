# nginx — Portal educativo en RPi

> **Ultima actualizacion:** 2026-05-30
> nginx 1.24.0

## Rol Ansible

`raspberry/rpi-setup/roles/nginx/`

## Descripcion

nginx actua como la puerta de entrada unica a todos los servicios educativos de la RPi. Escucha en el puerto 80 y enruta el trafico hacia Kiwix, Kolibri y Jellyfin mediante reverse proxy. Tambien corrige los OS captive-portal probes para redirigirlos al portal cautivo del Mini PC.

## Flujo de trafico

```
Clientes VLAN30 → biblioteca.tel (192.168.20.10:80)
    ├── /                → Kiwix  :8080  (pagina principal, rewrite)
    ├── /wikipedia/      → Kiwix  :8080  (rewrite: strip /wikipedia/)
    ├── /content/        → Kiwix  :8080  (transparente)
    ├── /skin/           → Kiwix  :8080
    ├── /search          → Kiwix  :8080
    ├── /catalog/        → Kiwix  :8080
    ├── /kolibri/        → Kolibri :8090
    ├── /videos/         → Jellyfin :8096
    └── CNA probes       → 302 redirect a portal cautivo (192.168.30.1:2050)
```

## Fix critico: captive-portal probes (CNA)

Los dispositivos (Android, macOS, iOS, Windows) envian requests a URLs fijas para detectar captive portals. Sin este fix, los dispositivos ven la RPi como internet libre (o nada). Con el fix, el sistema operativo muestra el popup de "Conectar a red WiFi".

```nginx
# Managed by Ansible — do not edit manually
location = /generate_204         { return 302 http://192.168.30.1:2050/; }
location = /gen_204              { return 302 http://192.168.30.1:2050/; }
location = /hotspot-detect.html  { return 302 http://192.168.30.1:2050/; }
location = /library/test/success.html { return 302 http://192.168.30.1:2050/; }
location = /ncsi.txt             { return 302 http://192.168.30.1:2050/; }
location = /connecttest.txt      { return 302 http://192.168.30.1:2050/; }
location = /success.txt          { return 302 http://192.168.30.1:2050/; }
location = /canonical.html       { return 302 http://192.168.30.1:2050/; }
```

## Fix critico: HTML del panel con `Cache-Control: no-cache` (cache rancia de Squid)

**Sintoma (incidente 2026-06-01):** al hacer click en "Wikipedia" desde el panel,
los clientes veian *"Oops. Page not found — /content/wikipedia_es_all_mini_2026-02/"*
aunque el ZIM en disco ya era `2026-05`.

**Causa raiz:** el `index.html` del panel referencia el ZIM activo **por fecha**
(`wikipedia_es_all_mini_AAAA-MM`). El auto-update de Kiwix reescribe ese link cuando
cambia la version (ver `KIWIX.md`), y nginx lo sirve correcto. **Pero los clientes
pasan por Squid** (cache reverse-proxy en `:443`, ver `SQUID.md`). Como nginx no
enviaba `Cache-Control` en el HTML, Squid aplicaba freshness heuristica y servia la
copia **vieja** del `index.html` por dias (`Cache-Status: hit`, `Age` de dias) — con
el link al ZIM viejo, ya inexistente → 404 para **todos** los clientes.

**Fix:** las locations del HTML del panel envian `Cache-Control: no-cache`, forzando
a Squid (y al navegador) a **revalidar** el HTML siempre (304 si no cambio). El
contenido pesado (`/content/`, ZIMs) sigue cacheado normalmente.

```nginx
location = / {
    add_header Cache-Control "no-cache" always;
    try_files /index.html =404;
}
location ~* \.html$ {
    add_header Cache-Control "no-cache" always;
    try_files $uri =404;
}
```

> **Al cambiar un ZIM manualmente** y necesitar que los clientes vean el link nuevo
> de inmediato, purgar la cache de Squid: `sudo /usr/local/sbin/clear-squid-cache`
> (ver `SQUID.md` — ojo con la trampa del glob `rm -rf .../*`).

## Por que proxy transparente en Kiwix

Cuando `proxy_pass` tiene un path (e.g. `http://upstream/skin/`), nginx reemplaza el prefijo de la location antes de enviar upstream. Con Kiwix esto causaba 404 en assets CSS/JS. La solucion es `proxy_pass http://kiwix_backend;` (sin path) — el URI completo se reenvia verbatim.

## Snippet kiwix-proxy.conf

Centraliza los headers comunes a todos los bloques Kiwix. Se despliega en `/etc/nginx/snippets/kiwix-proxy.conf` y se incluye con `include /etc/nginx/snippets/kiwix-proxy.conf;`.

### Fix critico: `proxy_set_header Accept-Encoding ""` (variante gzip en cache de Squid)

**Sintoma (incidente 2026-06-01):** paginas de Kiwix (p.ej.
`/content/wikinews_es_all_nopic_2026-04/Portada`) cargaban **en blanco** con
HTTP 200 pero ~0.7 kB y 0 sub-recursos en el navegador.

**Causa raiz:** Kiwix sirve el contenido con `Content-Encoding: gzip` +
`Vary: Accept-Encoding`. Squid (reverse-proxy cache enfrente) manejaba mal las
**variantes** de compresion: cacheaba el objeto gzip y a veces lo servia con
cabeceras inconsistentes, dejando al navegador con bytes comprimidos que
interpretaba como HTML plano → pagina en blanco. (Se disparo al limpiar la cache
de Squid, que forzo a re-cachear y aterrizar en la variante gzip.)

**Fix:** el snippet `kiwix-proxy.conf` y los bloques `/wikipedia/` envian
`proxy_set_header Accept-Encoding "";`. Asi nginx le pide a Kiwix contenido **sin
comprimir**: la respuesta no lleva `Content-Encoding` ni `Vary`, y Squid cachea
una **sola** representacion (plano). En LAN el costo de no comprimir es irrelevante.

> nginx `gzip on` global no afecta el trafico hacia Squid porque Squid manda header
> `Via` y `gzip_proxied` esta en su default (`off`) → nginx no recomprime para Squid.

## Archivos desplegados

| Template Ansible | Destino en RPi |
|---|---|
| `templates/biblioteca.nginx.j2` | `/etc/nginx/sites-available/biblioteca` |
| `templates/kiwix-proxy.conf.j2` | `/etc/nginx/snippets/kiwix-proxy.conf` |

## Verificacion

```bash
# nginx escuchando
ss -tlnp | grep :80

# Servicios responden
curl -s http://192.168.20.10/ | head -5
curl -I http://192.168.20.10/wikipedia/
curl -I http://192.168.20.10/kolibri/
curl -I http://192.168.20.10/videos/

# Probe redirect (debe retornar 302 a 192.168.30.1:2050)
curl -I http://192.168.20.10/generate_204

# Logs
tail -f /var/log/nginx/biblioteca-access.log
tail -f /var/log/nginx/biblioteca-error.log
```
