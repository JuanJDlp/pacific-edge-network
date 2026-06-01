# Squid — Cache web offline + forward proxy + filtrado HTTPS

> **Ultima actualizacion:** 2026-05-30
> Squid 6.14 — filtra HTTPS por SNI (porn + gambling) y cachea biblioteca.tel como reverse proxy.
> Documentacion completa del filtrado/cache en **[`squid-filter-cache/`](squid-filter-cache/README.md)**:
> arquitectura, decisiones tecnicas, implementacion, consideraciones, testing, blocklists y troubleshooting.

## Rol Ansible

`raspberry/rpi-setup/roles/squid/`

## Descripcion

Squid en la RPi cumple cuatro roles segun el puerto:

| Puerto | Modo | Proposito |
|--------|------|-----------|
| 3128 | `intercept` | Captura trafico HTTP local de la RPi |
| 3129 | `accel vhost allow-direct` | Recibe requests del Mini PC nginx (HTTP) y los sirve con cache |
| 3130 | `intercept ssl-bump` (peek+splice) | **NO usado en produccion** — cross-host DNAT pierde `SO_ORIGINAL_DST` y Squid termina con `TCP_DENIED CONNECT 192.168.20.10:3130`. Filtrado HTTPS porn/gambling se hace ahora a nivel DNS via Bind9 RPZ (`rpz.blocklist`). El puerto queda en la config historicamente; el DNAT que apuntaba a el fue removido. |
| 443  | `accel` (reverse proxy) | Termina TLS de biblioteca.tel y cachea con backend → nginx 127.0.0.1:80 |

## Flujo para clientes autenticados (VLAN30)

```
Cliente VLAN30 (mark=0x1) → tcp dport 80
    │  nftables DNAT → 192.168.30.1:8888 (nginx intermediario Mini PC)
    ▼
nginx Mini PC :8888
    │  proxy_pass + Host header → 192.168.20.10:3129
    ▼
Squid RPi :3129 (accel vhost allow-direct)
    │  Lee Host header para el destino (no necesita SO_ORIGINAL_DST)
    ▼
Internet / cache local
```

## Por que `accel vhost allow-direct` en puerto 3129

nginx (Mini PC) reenvia requests con URI relativa (`GET / HTTP/1.0`) y `Host: example.com`. Un forward proxy estandar espera URI absoluta (`GET http://example.com/ HTTP/1.0`). El modo `accel vhost` hace que Squid extraiga el destino del header `Host`, aceptando URIs relativas. `allow-direct` le permite conectarse directamente al origen.

### El problema original (SO_ORIGINAL_DST)

Sin el intermediario nginx, el flujo era `Cliente → DNAT → 192.168.20.10:3128 (intercept)`. Squid intercept en RPi llama `SO_ORIGINAL_DST` al kernel de la RPi, pero el DNAT ocurrio en el Mini PC — el kernel de la RPi devuelve `192.168.20.10:3128` (el propio Squid). Squid detecta un loop → **403 Access Denied**.

La solucion fue usar el puerto 3129 en modo `accel vhost` + nginx intermediario en el Mini PC que construye el `Host` header correctamente.

## Configuracion de cache

```
cache_dir aufs /var/lib/biblioteca/squid-cache 10240 16 256
cache_mem 512 MB
maximum_object_size 128 MB
```

- **10 GB** en disco para contenido cacheado
- **512 MB** en RAM para objetos frecuentes
- `refresh_pattern . 43200 90% 525600` — retencion muy larga (offline-first)

> **Cuidado con contenido que cambia (HTML del panel).** Con esa `refresh_pattern`,
> un objeto sin `Cache-Control` se considera fresco hasta ~30 dias (freshness
> heuristica). El `index.html` del panel cambia cuando el auto-update de Kiwix
> rota la fecha del ZIM; sin header, Squid servia el HTML viejo (link al ZIM
> inexistente) durante dias → 404 para todos los clientes (incidente 2026-06-01).
> **Fix:** nginx sirve el HTML del panel con `Cache-Control: no-cache` (ver
> [`NGINX.md`](NGINX.md)). El contenido pesado (ZIMs) si se sigue cacheando.

## Variantes de compresion (Vary: Accept-Encoding) — paginas en blanco

Squid maneja mal las variantes `gzip`/identidad del contenido de Kiwix (que envia
`Content-Encoding: gzip` + `Vary: Accept-Encoding`): cacheaba la variante gzip y la
servia mal etiquetada → el navegador veia bytes comprimidos como HTML plano y la
**pagina quedaba en blanco** (HTTP 200, ~0.7 kB). Aparecio al limpiar la cache.

**Fix (lado nginx):** nginx pide a Kiwix contenido **sin comprimir**
(`proxy_set_header Accept-Encoding ""` en `kiwix-proxy.conf` y `/wikipedia/`), de modo
que Squid solo ve/cachea **una** representacion plana. Ver [`NGINX.md`](NGINX.md).
Tras aplicar el fix, **limpiar la cache de Squid** (abajo) para descartar variantes gzip
ya envenenadas.

## Purga de cache — usar `clear-squid-cache`

Esta instancia **no** tiene `squidclient` ni ACL de PURGE. Para invalidar objetos
cacheados (tras cambiar un ZIM, o si una pagina sale rancia / en blanco / con bytes
raros) usar el script desplegado por Ansible:

```bash
sudo /usr/local/sbin/clear-squid-cache
```

Hace: `stop` → borra y recrea `/var/lib/biblioteca/squid-cache` como root → `start`
(squid recrea los swap dirs solo). Es seguro: solo se pierde cache, se repuebla
desde nginx.

> ### ⚠️ Dos trampas que costaron horas (incidente 2026-06-01) — por eso existe el script
>
> 1. **`sudo rm -rf /var/lib/biblioteca/squid-cache/*` NO borra nada** si lo corres
>    como usuario sin privilegios: el glob `*` lo expande tu shell, que no puede
>    listar el dir de `proxy` (modo 0750) → el `*` queda **literal** y `rm` no borra
>    nada, **en silencio**. Resultado: crees que limpiaste la cache pero los objetos
>    viejos/envenenados siguen ahi y el problema "vuelve". Borrar el **directorio
>    completo** (sin glob), como hace el script.
> 2. **`squid -z` a mano choca con systemd** (PID/puertos en uso) y deja el servicio
>    caido. NO hace falta: squid crea los swap dirs faltantes al arrancar.
> 3. `systemctl restart squid` por si solo **no** purga: la cache en disco persiste.

Rol Ansible: `roles/squid/templates/clear-squid-cache.sh.j2`.

## ACLs

```squid
acl localnet src 192.168.0.0/16  # Todos los VLANs
acl localnet src 100.64.0.0/10   # Netbird CGNAT
```

## Archivos desplegados

| Template Ansible | Destino en RPi |
|---|---|
| `templates/squid.conf.j2` | `/etc/squid/squid.conf` |

## Verificacion

```bash
# Squid escuchando en los 4 puertos
ss -tlnp | grep squid
# Esperado: 3128, 3129, 3130, 443

# Test forward proxy desde Mini PC
curl --proxy http://192.168.20.10:3129 http://example.com
# Primera vez: TCP_MISS; segunda vez: TCP_HIT

# Logs
tail -f /var/log/squid/access.log
tail -f /var/log/squid/cache.log
```
