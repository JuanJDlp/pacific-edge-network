# 01 — Arquitectura

## Componentes y dónde corre cada cosa

```
┌──────────────────────────────────────────────────────────────────┐
│  Mini PC (192.168.30.1 en VLAN30, 192.168.20.1 en VLAN20, ...)  │
│ ─────────────────────────────────────────────────────────────── │
│  • nftables (DNAT del tráfico de clientes hacia Squid en RPi)    │
│  • nginx :8888 (HTTP intermediario → Squid 3129 en RPi)          │
│  • Portal cautivo :2050                                          │
│  • Bind9 :53, Kea DHCP, Chrony NTP                               │
└────────────────────────────┬─────────────────────────────────────┘
                             │ trunk 802.1Q (VLAN 10/20/30)
                             ▼
              ┌─────────────────────────────┐
              │  Switch L2 (Cisco SG350X)   │
              └────┬───────────┬────────────┘
   Puerto 1 (acc)  │           │  Puertos varios (acc VLAN30)
                   ▼           ▼
┌──────────────────────────────────┐    ┌──────────────────┐
│  Raspberry Pi  192.168.20.10     │    │  Clientes VLAN30 │
│ ────────────────────────────────── │    │  (laptops, móvil)│
│  • nginx :80     (HTTP público)  │    └──────────────────┘
│  • nginx 127.0.0.1:8443 (interno) │
│  • Squid :3128   (intercept HTTP) │
│  • Squid :3129   (accel HTTP — forward proxy) │
│  • Squid :3130   (intercept HTTPS — peek+splice / filtro) │
│  • Squid :443    (accel HTTPS — reverse proxy biblioteca.tel) │
│  • Kiwix 127.0.0.1:8080, Kolibri 127.0.0.1:8090, Jellyfin 127.0.0.1:8096 │
└──────────────────────────────────┘
```

## Los 4 flujos finales

### Flujo A — Cliente VLAN30 autenticado → internet **HTTPS**

```
[Cliente VLAN30]  (mark 0x1 si autenticado)
    │
    │  conecta a   https://www.google.com
    │  paquete:    SrcIP=192.168.30.X  DstIP=<IP-google>  TCP/443
    ▼
[Mini PC: nftables ip nat prerouting]
    │  match: iif vlan30 + mark 0x1 + daddr != 192.168.20.10 + dport 443
    │  acción: DNAT to 192.168.20.10:3130
    ▼
[RPi: Squid puerto 3130]   (intercept ssl-bump)
    │
    │  Lee SO_ORIGINAL_DST = <IP-google>:443  (era el destino original)
    │  Recibe ClientHello con SNI = "www.google.com"
    │
    │  ssl_bump peek step1   ← lee el SNI sin descifrar
    │
    │  ¿SNI ∈ /etc/squid/blocklists/blocked_domains.txt ?
    │      SÍ  → ssl_bump terminate    → cierra el socket TLS
    │             (cliente ve: connection reset / closed)
    │      NO  → ssl_bump splice       → "pipea" los bytes TLS
    │             entre cliente y servidor original
    ▼
[Internet — Google, cifrado E2E]
    │
    │ Squid NUNCA descifra; solo vio el SNI.
    │ La cache es N/A para HTTPS spliced.
```

### Flujo B — Cliente VLAN30 autenticado → internet **HTTP**

```
[Cliente VLAN30]
    │  http://example.com
    │  paquete: dport 80
    ▼
[Mini PC: nftables ip nat prerouting]
    │  match: iif vlan30 + mark 0x1 + daddr != RPi + dport 80
    │  acción: DNAT to 192.168.30.1:8888  (nginx en Mini PC)
    ▼
[Mini PC: nginx :8888]
    │  proxy_pass http://192.168.20.10:3129
    │  preserva Host header del cliente
    ▼
[RPi: Squid puerto 3129]   (accel vhost allow-direct = forward proxy)
    │
    │  ACL: http_access deny blocked_domains
    │       si dominio en blocklist → 403 (HTML de Squid)
    │
    │  always_direct allow all → conecta directo al origen
    │  cache deny !cache_allowed → NO guarda nada en cache
    ▼
[Internet — example.com, HTTP plano]
```

### Flujo C — Cliente VLAN30 → **biblioteca.tel HTTPS** (con cache)

```
[Cliente VLAN30]
    │  https://biblioteca.tel/wikipedia/
    │  DNS (forzado a Bind9) resuelve biblioteca.tel → 192.168.20.10
    │  paquete: DstIP=192.168.20.10  dport 443
    ▼
[Mini PC: nftables]
    │  match condición incluye `daddr != 192.168.20.10`
    │  → NO entra en DNAT (la regla del filtro lo excluye explícitamente)
    │
    │  ¿Por qué excluido? Porque enviar el tráfico de biblioteca.tel al filtro
    │  haría que Squid intentara "peek" un dominio que Squid mismo sirve,
    │  generando un loop. Además queremos que biblioteca.tel use el accel
    │  con cache, no el intercept que filtra.
    ▼
[Routing IP normal] → 192.168.20.10:443
    ▼
[RPi: Squid puerto 443]   (https_port 443 accel)
    │
    │  Termina TLS con biblioteca-segura.crt + .key
    │  (mismo cert que antes tenía nginx)
    │
    │  ACL biblioteca_dom = dstdomain biblioteca.tel
    │  http_access allow biblioteca_dom
    │  never_direct allow biblioteca_dom   ← obliga ir vía cache_peer
    │  always_direct deny biblioteca_dom   ← (refuerza, mismo efecto)
    │
    │  ¿Hit en cache?
    │      SÍ → TCP_MEM_HIT/200 o TCP_HIT/200  (sirve desde RAM o disco)
    │      NO → consulta cache_peer
    ▼
[Cache miss] → cache_peer biblioteca_backend (127.0.0.1:80)
    ▼
[RPi: nginx :80]   (loopback HTTP)
    │
    │  location /wikipedia/  → upstream kiwix_backend (127.0.0.1:8080)
    │  location /kolibri/    → upstream kolibri_backend (127.0.0.1:8090)
    │  location /videos/     → upstream jellyfin_backend (127.0.0.1:8096)
    │  location /            → /var/www/html (portal estático)
    ▼
[Backend específico] → respuesta
    ▼
[Squid] cachea según refresh_pattern (43200 min = 30 días)
    │   y re-cifra para el cliente
    ▼
[Cliente] recibe el contenido
```

### Flujo D — Cliente VLAN30 → **biblioteca.tel HTTP** (sin cache, directo)

```
[Cliente VLAN30]
    │  http://biblioteca.tel/
    │  DstIP=192.168.20.10  dport 80
    ▼
[Mini PC: nftables]
    │  daddr == RPi ⇒ NO entra en DNAT (excepción)
    ▼
[Routing] → 192.168.20.10:80
    ▼
[RPi: nginx :80]   (sin pasar por Squid)
    │
    │ Sirve directo. Mismas locations que HTTPS.
    │ No hay cache porque no hay Squid en el medio para HTTP de biblioteca.tel.
```

> **¿Por qué HTTP de biblioteca.tel no pasa por Squid?**
> Históricamente el HTTP intermediary del Mini PC excluyó explícitamente la RPi
> (`daddr != rpi_ip`) para evitar loops. Mantenemos esa exclusión por simplicidad.
> Si en el futuro queremos cachear HTTP de biblioteca.tel, basta con quitar la
> exclusión y añadir un `http_port 80 accel` en Squid apuntando a otro puerto local.

## Puertos resumen

| Host       | Puerto       | Quién escucha | Para qué |
|------------|--------------|---------------|---|
| Mini PC    | 53/udp+tcp   | Bind9         | DNS interno + forwarding |
| Mini PC    | 67/udp       | Kea DHCPv4    | DHCP |
| Mini PC    | 123/udp      | chrony        | NTP |
| Mini PC    | 2050         | nginx         | Portal cautivo (splash + accept) |
| Mini PC    | 2051         | captive-accept| Handler interno del portal |
| Mini PC    | 8888         | nginx         | Intermediario HTTP → Squid RPi |
| RPi        | 80           | nginx         | biblioteca.tel HTTP público + backend HTTP de Squid accel |
| RPi        | **127.0.0.1:8443**| nginx     | Backup HTTPS interno (no usado en flujo normal) |
| RPi        | **443**      | **Squid (accel)** | biblioteca.tel HTTPS con cache |
| RPi        | 3128         | Squid         | Intercept HTTP (tráfico local de la RPi) |
| RPi        | 3129         | Squid         | Forward proxy HTTP (forwardproxy desde Mini PC nginx) |
| RPi        | **3130**     | **Squid (ssl-bump)** | **Filtro HTTPS por SNI (peek+splice)** |
| RPi        | 8080/8090/8096 | Kiwix/Kolibri/Jellyfin | Backends (loopback) |

## Por qué nginx perdió el listen 443 público

```
ANTES:                              DESPUÉS:
─────                              ────────
                                  
Cliente → nginx :443  (TLS)         Cliente → Squid :443  (TLS termina aquí)
            │                                     │
            └─ sirve directo                      ▼
               (backends)                  ¿hit cache? sí → sirve
                                          no → cache_peer
                                                 │
                                                 ▼
                                          nginx :80  (HTTP loopback)
                                                 │
                                                 └─ sirve (backends)
```

**Por qué se eligió mover nginx en lugar de quitarle el listener:** ver [`02-DECISIONES.md § Decisión 7`](02-DECISIONES.md).

## Diagrama de capas en Squid

```
                           Squid 6.14 (squid-openssl)
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                  │
   │  http_port 3128 intercept                                        │
   │    (HTTP intercepted desde la propia RPi)                        │
   │                                                                  │
   │  http_port 3129 accel vhost allow-direct                         │
   │    (forward proxy HTTP — usado por nginx Mini PC :8888)          │
   │     → http_access deny blocked_domains (filtra HTTP)             │
   │     → cache deny !cache_allowed (no cachea internet)             │
   │                                                                  │
   │  https_port 3130 intercept ssl-bump                              │
   │    (filtro HTTPS por SNI)                                        │
   │     ssl_bump peek step1                                          │
   │     ssl_bump terminate blocked_sni                               │
   │     ssl_bump splice all                                          │
   │                                                                  │
   │  https_port 443 accel cert=biblioteca.crt key=biblioteca.key     │
   │    (reverse proxy biblioteca.tel)                                │
   │     never_direct allow biblioteca_dom                            │
   │     cache_peer 127.0.0.1 parent 80 originserver                  │
   │     cache se rige por refresh_pattern                            │
   │                                                                  │
   └──────────────────────────────────────────────────────────────────┘
```

## Cómo se compone una request bloqueada (cronología detallada)

Cliente intenta `https://www.pornhub.com`:

1. **t=0ms** — Cliente DNS query → Bind9 → 1.2.3.4 (IP de Pornhub vía Cloudflare/CDN).
2. **t=5ms** — Cliente envía TCP SYN a 1.2.3.4:443.
3. **t=5ms** — Paquete cruza Mini PC. nftables prerouting NAT matchea:
   `iif vlan30 + mark 0x1 + daddr != 192.168.20.10 + dport 443`.
4. **t=6ms** — DNAT a 192.168.20.10:3130. Conntrack guarda la mapping.
5. **t=8ms** — Squid en :3130 acepta TCP. `SO_ORIGINAL_DST(socket) → 1.2.3.4:443` (eso era el destino original antes del DNAT).
6. **t=20ms** — Cliente envía TLS ClientHello con SNI = `www.pornhub.com`.
7. **t=21ms** — Squid lee el ClientHello (peek step1). El SNI queda disponible para ACLs.
8. **t=21ms** — Squid evalúa `ssl_bump terminate blocked_sni`. La ACL `blocked_sni` busca `www.pornhub.com` en el archivo blocklist (~82k entries, búsqueda O(log n) en Squid). Match.
9. **t=22ms** — Squid llama `ssl_bump terminate`. Cierra el socket TCP del cliente (sin enviar TLS Alert — el cliente ve un connection-reset / EOF).
10. **t=22ms** — Squid loguea: `TCP_DENIED/000 0 NONE ... ssl::server_name=www.pornhub.com`.
11. **t=23ms** — Curl/navegador del cliente reporta error (SSL_ERROR_SYSCALL, HTTP=000, "Connection refused", etc.).

## Cómo se compone una request a biblioteca.tel (cronología detallada)

Cliente intenta `https://biblioteca.tel/index.html` por segunda vez (cache hit):

1. **t=0ms** — DNS → biblioteca.tel = 192.168.20.10.
2. **t=2ms** — TCP SYN a 192.168.20.10:443. nftables NO matchea (excepción).
3. **t=3ms** — Routing IP entrega a RPi:443. Squid accepta.
4. **t=10ms** — TLS handshake completo. Squid presenta `biblioteca-segura.crt`.
5. **t=15ms** — Cliente envía: `GET /index.html HTTP/1.1\r\nHost: biblioteca.tel`.
6. **t=15ms** — Squid evalúa http_access → allow (biblioteca_dom).
7. **t=15ms** — Squid busca en cache `https://biblioteca.tel/index.html`. Hit en `cache_mem`.
8. **t=15ms** — Squid sirve directamente desde RAM. Loguea `TCP_MEM_HIT/200`.
9. **t=16ms** — Cliente recibe la respuesta. Total ~16ms (vs ~50ms si pasara por nginx + backend).
