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

## Por que proxy transparente en Kiwix

Cuando `proxy_pass` tiene un path (e.g. `http://upstream/skin/`), nginx reemplaza el prefijo de la location antes de enviar upstream. Con Kiwix esto causaba 404 en assets CSS/JS. La solucion es `proxy_pass http://kiwix_backend;` (sin path) — el URI completo se reenvia verbatim.

## Snippet kiwix-proxy.conf

Centraliza los headers comunes a todos los bloques Kiwix. Se despliega en `/etc/nginx/snippets/kiwix-proxy.conf` y se incluye con `include /etc/nginx/snippets/kiwix-proxy.conf;`.

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
