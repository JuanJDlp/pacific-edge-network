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
| 3130 | `intercept ssl-bump` (peek+splice) | Filtra HTTPS por SNI usando blocklist (porn + gambling) |
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
