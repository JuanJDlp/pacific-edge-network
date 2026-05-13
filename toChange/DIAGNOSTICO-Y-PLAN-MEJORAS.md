# Diagnóstico actual y Plan de Mejoras — Pacific Edge Network
**Fecha:** 2026-05-12

---

## 1. Estado actual de la red

### Topología

```
Internet (Starlink)
      │
      │ 172.16.0.11/16 (WAN DHCP)
┌─────▼──────────────────────────────────────────────────────────┐
│                   MINI PC — Ubuntu Server 24.04                │
│                                                                │
│  enp170s0  →  172.16.0.11   (WAN)                             │
│  enp171s0.10 → 192.168.10.1 (VLAN 10 — Gestión)              │
│  enp171s0.20 → 192.168.20.1 (VLAN 20 — Servidores)           │
│  enp171s0.30 → 192.168.30.1 (VLAN 30 — Clientes WiFi)        │
│  wt0         → 100.90.95.134 (Netbird VPN)                   │
└─────────────────────────────┬──────────────────────────────────┘
                              │ trunk 802.1Q
                    ┌─────────▼──────────┐
                    │  Switch Catalyst   │
                    │  2960 (L2)         │
                    │  SW-CORE-BONGO     │
                    └──┬──────────────┬──┘
                       │ Fa0/1        │ Fa0/4
              VLAN 20  │              │  VLAN 30 (native)
           ┌───────────▼───┐   ┌──────▼────────────────┐
           │ Raspberry Pi 5│   │ AP / PC de prueba      │
           │ 192.168.20.10 │   │ 192.168.30.100–200     │
           └───────────────┘   └────────────────────────┘
```

---

### 1.1 Mini PC — Servicios expuestos

| Servicio | Protocolo | Puerto / Interfaz | Estado |
|----------|-----------|-------------------|--------|
| Kea DHCPv4 | UDP | `192.168.10.1:67` `192.168.20.1:67` `192.168.30.1:67` | ✅ activo |
| systemd-resolved (DNS) | UDP/TCP | `192.168.10.1:53` `192.168.20.1:53` `192.168.30.1:53` | ✅ activo |
| captive-portal.py | HTTP | `0.0.0.0:2050` | ✅ activo |
| nftables | — | firewall + NAT | ✅ activo |
| Netbird VPN | WireGuard | `wt0 :51820` | ✅ activo |
| SSH | TCP | `22` (VLANs + wt0) | ✅ activo |

#### DNS upstream configurado

systemd-resolved usa los DNS de Starlink vía `enp170s0`:

```
Current DNS Server: 192.168.215.30
DNS Servers:        192.168.215.20  192.168.215.30
```

Los VLAN sub-interfaces tienen `Current Scopes: none` — no tienen DNS propio asignado. Todas las consultas de clientes llegan vía DNAT a `192.168.10.1:53` y salen a internet por los DNS de Starlink.

#### nftables — Reglas activas resumidas

```
PREROUTING (DNAT):
  • VLAN 10/20/30 UDP/TCP :53  → 192.168.10.1:53      (DNS forzado)
  • VLAN 30, mark≠0x1, TCP :80 → 192.168.30.1:2050    (portal cautivo)

FORWARD:
  • VLAN 10/20             → WAN: permitido siempre
  • VLAN 30 @captive_allowed → WAN: permitido
  • VLAN 30 @captive_allowed → VLAN 20: permitido
  • Todo lo demás: DROP

POSTROUTING:
  • oif WAN: MASQUERADE

NETDEV EGRESS (enp171s0.30):
  • UDP sport 67 dport 68: dst IP→255.255.255.255, dst MAC→ff:ff:ff:ff:ff:ff
    (DHCP Offer broadcast fix para macOS en estado APIPA)
```

---

### 1.2 Raspberry Pi 5 — Servicios expuestos

| Servicio | Puerto | Acceso | Estado |
|----------|--------|--------|--------|
| nginx (proxy reverso) | `80/tcp` | LAN (`0.0.0.0`) | ✅ activo |
| Squid (proxy cache) | `3128/tcp` | LAN + Netbird | ✅ activo (offline_mode) |
| Kiwix (Wikipedia, etc.) | `8080/tcp` | localhost | ✅ activo |
| Kolibri (educación) | `8090/tcp` | localhost | ✅ activo |
| Jellyfin (multimedia) | `8096/tcp` | LAN | ✅ activo |
| SSH | `22/tcp` | LAN + Netbird | ✅ activo |

#### Squid — Modo actual

```
offline_mode on      ← solo sirve contenido cacheado
never_direct allow all ← nunca va a internet
cache_dir aufs /var/lib/biblioteca/squid-cache 10240 MB
cache_mem 512 MB
maximum_object_size 128 MB
```

> Squid actualmente NO hace proxy de internet. Solo sirve su caché pre-poblada.

#### nginx — Endpoints configurados

```
/             → index.html estático (portal de bienvenida)
/wikipedia/   → proxy → Kiwix :8080
/videos/      → proxy → Jellyfin :8096
/kolibri/     → proxy → Kolibri :8090
/status       → health-check
/splash       → splash.html (página del portal cautivo)
/accept       → proxy → :8088/accept (captive portal viejo)
```

---

## 2. Flujo de una request HTTP no autenticada

### Escenario: cliente conecta a FA0/4, escribe `http://neverssl.com`

```
CLIENTE (192.168.30.100, NO autenticado)
│
│  1. DHCP: obtiene IP 192.168.30.100/24, GW 192.168.30.1, DNS 192.168.30.1
│
│  2. DNS Query: neverssl.com A ?
│     → UDP 192.168.30.100:XXXXX → 192.168.30.1:53
│                                           │
│     nftables PREROUTING DNAT:             │
│     dst 192.168.30.1:53 → 192.168.10.1:53│
│                                           ▼
│                               systemd-resolved
│                               upstream: 192.168.215.x (Starlink)
│                               ← responde con A 34.223.124.45  (~134ms)
│
│  3. [BROWSER INTENTA HTTPS PRIMERO — AQUÍ ESTÁ EL DELAY]
│     TCP SYN → 34.223.124.45:443
│     nftables FORWARD: sin regla para VLAN30 no autenticado a WAN
│     Resultado: DROP silencioso (no hay RST)
│     Browser espera TCP timeout: ~30 segundos ← CAUSA PRINCIPAL DEL DELAY
│
│  4. Browser re-intenta con HTTP (tras timeout de 443):
│     TCP SYN → 34.223.124.45:80
│     nftables PREROUTING DNAT:
│     iif enp171s0.30, mark≠0x1, tcp dport 80 → 192.168.30.1:2050
│
│  5. captive-portal.py (Python HTTPServer, single-threaded) responde:
│     GET / → lee splash.html del disco → envía 200 OK
│     (puede demorar si el browser abre conexiones concurrentes)
│
│  6. Browser renderiza splash.html (Biblioteca Digital Ladrilleros)
│     Click "Entrar a la biblioteca" → GET /accept
│     captive-portal.py: nft add element captive_allowed { 192.168.30.100 }
│     → 302 redirect → http://192.168.20.10
│
│  7. POST AUTENTICACIÓN:
│     nftables mangle: paquetes de .100 → mark 0x1 (no interceptados)
│     FORWARD: iif enp171s0.30 oif enp170s0 @captive_allowed accept
│     NAT POSTROUTING: MASQUERADE
│     → cliente navega libremente durante 8 horas
```

---

## 3. Diagnóstico del delay de 30 segundos

### Medición desde el Mini PC

```
curl -w '%{time_namelookup} dns | %{time_connect} connect | %{time_total} total' http://neverssl.com

→  0.134s  dns
→  0.001s  connect  (DNAT al portal es inmediato)
→  10.2s   total    (exit 56: receive error)
```

### Causa raíz identificada: HTTPS drop silencioso

| Paso | Componente | Tiempo | ¿Problema? |
|------|-----------|--------|------------|
| DNS query | systemd-resolved → Starlink | ~134 ms | ✓ aceptable |
| TCP SYN :443 | nftables FORWARD → DROP | **30 s timeout** | ❌ **causa principal** |
| TCP SYN :80 | nftables DNAT → portal:2050 | < 1 ms | ✓ correcto |
| HTTP GET / | captive-portal.py (single-thread) | ~1–3 s | ⚠️ mejorable |
| Assets adicionales | captive-portal.py (cola FIFO) | +1–2 s por asset | ⚠️ mejorable |

**Problema 1 — DROP silencioso en puerto 443:**
La regla de FORWARD dropea el tráfico de clientes no autenticados, incluyendo HTTPS. El browser moderno (Chrome/Safari/Firefox) intenta HTTPS antes que HTTP (HSTS preload, upgrade-insecure-requests). El SYN a puerto 443 entra al switch, llega al Mini PC y es dropeado sin RST. El browser espera el TCP timeout completo (~30s) antes de reintentar con HTTP.

**Problema 2 — captive-portal.py single-threaded:**
`http.server.HTTPServer.serve_forever()` es blocking single-threaded. Cuando el browser abre múltiples conexiones simultáneas (típicamente 6), se encolan. Cada request espera que termine la anterior. Leer `splash.html` del disco en cada request agrega latencia adicional. Esto explica los 10+ segundos de tiempo total en curl.

**Problema 3 — DNS dependiente de Starlink:**
Si Starlink tiene latencia alta o pérdida de paquetes, el DNS puede tardarse 2–20 segundos. No hay DNS local cacheante dedicado con prefetching ni TTL mínimo configurable.

---

## 4. Plan de mejoras

### 4.1 Fix inmediato — TCP RST para HTTPS no autenticado ⚡

**Impacto:** elimina el delay de 30s → portal aparece en < 2s
**Esfuerzo:** 5 minutos, una línea de nftables

En vez de dropear silenciosamente el puerto 443, enviar TCP RST inmediato. El browser recibe "connection refused" al instante y redirige al HTTP que cae en el portal cautivo.

```nft
# Agregar en chain forward (ANTES del DROP general):
iif "enp171s0.30" meta mark != 0x00000001 tcp dport 443 reject with tcp reset
```

```bash
# Aplicar en vivo:
sudo nft insert rule inet filter forward position 0 \
  iif "enp171s0.30" meta mark != 0x00000001 tcp dport 443 reject with tcp reset

# Persistir en /etc/nftables.conf en el bloque forward
```

---

### 4.2 Reemplazar captive-portal.py con nginx en el Mini PC 🔄

**Impacto:** portal responde en < 100ms, soporta conexiones concurrentes
**Esfuerzo:** ~30 minutos

El servidor Python `http.server.HTTPServer` es single-threaded y sin caching de disco. Reemplazarlo por nginx (ya instalable en Mini PC) que:
- Sirve `splash.html` con cache en memoria
- Maneja cientos de conexiones concurrentes sin bloqueo
- Soporta keepalive HTTP

La lógica del `/accept` (ejecutar `nft`) se mantiene en un script Python mínimo como FastCGI o se integra directamente en nginx con `ngx_http_lua_module` o similar.

**Esquema propuesto:**

```
Mini PC — nginx :2050
  location / {
      root /etc/captive-portal;
      try_files /splash.html =404;
  }
  location /accept {
      proxy_pass http://127.0.0.1:2051;  # script Python mínimo solo para nft
  }
```

---

### 4.3 Squid como proxy transparente para clientes autenticados 🌐

**Impacto:** caché HTTP local, acelera acceso a contenido repetido, cumple requisito del enunciado
**Esfuerzo:** ~2 horas (config Squid + nftables)

**Estado actual del problema:**
- Squid en RPi: `offline_mode on` + `never_direct allow all` → solo sirve caché sin internet
- No hay redirección desde Mini PC hacia Squid para tráfico de clientes

**Cambios necesarios:**

#### a) Squid en RPi — modo intercept con internet

```squid
# /etc/squid/squid.conf — cambios mínimos
http_port 3128 intercept          # modo transparente
offline_mode off                  # habilitar internet
never_direct deny all             # ← eliminar esta línea
always_direct allow all           # ir a internet cuando no hay caché

# Mantener la caché grande para contenido educativo
cache_dir aufs /var/lib/biblioteca/squid-cache 10240 16 256
cache_mem 512 MB

# ACLs ya configuradas aceptan localnet ✓
```

#### b) nftables en Mini PC — redirigir HTTP autenticado a Squid

Clientes que ya aceptaron el portal → su tráfico HTTP va a Squid (RPi:3128) en vez de directo a internet:

```nft
# En table ip nat, chain prerouting — ANTES de la regla de masquerade:
iif "enp171s0.30" ip saddr @captive_allowed tcp dport 80 \
    dnat to 192.168.20.10:3128
```

**Flujo con Squid activo:**

```
Cliente autenticado → HTTP :80 → Mini PC DNAT → Squid RPi:3128
    │
    ├─ Squid tiene caché del recurso → responde local (< 10ms)
    └─ Squid no tiene caché → va a internet → cachea → responde
```

**Beneficios concretos en la red comunitaria:**
- Wikipedia, recursos de Kolibri/Kiwix accedidos vía HTTP se cachean en Squid
- Segunda visita al mismo recurso: sin latencia de internet
- Reduce consumo de ancho de banda de Starlink

---

### 4.4 DNS local dedicado — Pi-hole (requisito del enunciado) 📋

**Impacto:** DNS en < 5ms para dominios cacheados, filtrado de publicidad, requisito del proyecto
**Esfuerzo:** ~3 horas

El enunciado requiere:
- DNS primario y secundario con DNSSEC y TSIG
- Servidor DNS autoritativo
- DNS64

**Estado actual:**
- systemd-resolved actúa como DNS stub forwarding a Starlink (192.168.215.x)
- Sin caché dedicado ni filtrado
- Sin DNSSEC habilitado (`DNSSEC=no/unsupported`)
- Sin Pi-hole instalado

**Plan:**

| Componente | Dónde | Función |
|-----------|-------|---------|
| Pi-hole | Mini PC o RPi | DNS primario VLAN 30, caching, filtrado |
| BIND9 o Unbound | RPi | DNS secundario, DNSSEC, TSIG |
| Cambio DNAT | Mini PC nftables | redirigir :53 a Pi-hole en vez de systemd-resolved |

**Cambio en Kea DHCP tras instalar Pi-hole:**
```json
{
  "name": "domain-name-servers",
  "data": "192.168.10.100"   // IP de Pi-hole
}
```

**Cambio en nftables DNAT:**
```nft
# Reemplazar la regla actual de DNS:
iif "enp171s0.30" udp dport 53 dnat to 192.168.10.100:53
```

---

### 4.5 Integración de captive portal con probes del OS 📱

**Impacto:** portal aparece automáticamente en iOS/Android/Windows sin abrir browser
**Esfuerzo:** ~1 hora

Los sistemas operativos envían sondas HTTP específicas al conectarse a una red:

| OS | URL de sonda |
|----|-------------|
| macOS / iOS | `http://captive.apple.com/hotspot-detect.html` |
| Android | `http://connectivitycheck.gstatic.com/generate_204` |
| Windows | `http://www.msftconnecttest.com/connecttest.txt` |

La RPi ya tiene estas rutas configuradas en nginx (redirigen a `http://10.13.13.1/splash`). Sin embargo, la IP `10.13.13.1` corresponde a un AP en configuración anterior que ya no está activa.

**Fix**: actualizar las rutas de sonda en nginx de la RPi para que respondan `302` a `http://192.168.30.1:2050/` (portal actual en el Mini PC):

```nginx
location = /generate_204         { return 302 http://192.168.30.1:2050/; }
location = /hotspot-detect.html  { return 302 http://192.168.30.1:2050/; }
location = /connecttest.txt      { return 302 http://192.168.30.1:2050/; }
location = /ncsi.txt             { return 302 http://192.168.30.1:2050/; }
```

Pero esas rutas están en la RPi y los clientes no autenticados no llegan a la RPi. El fix correcto es que el **Mini PC** maneje estas sondas directamente en el servidor captive portal (nginx o captive-portal.py):

```nginx
# En nginx :2050 del Mini PC:
location = /generate_204         { return 302 /; }
location = /hotspot-detect.html  { return 302 /; }
location = /connecttest.txt      { return 302 /; }
```

Esto hace que iOS/Android muestren el portal nativo del sistema operativo sin que el usuario tenga que abrir un browser manualmente.

---

## 5. Resumen — Prioridad de implementación

| Prioridad | Fix | Tiempo estimado | Impacto en UX |
|-----------|-----|-----------------|---------------|
| 🔴 Crítico | TCP RST en puerto 443 para no autenticados | 5 min | Elimina delay de 30s |
| 🟠 Alto | Reemplazar captive-portal.py con nginx | 30 min | Portal < 100ms, concurrente |
| 🟡 Medio | Probes OS en captive portal | 1 hora | Portal aparece automático en móviles |
| 🟡 Medio | Squid transparente para autenticados | 2 horas | Caché HTTP, menor consumo WAN |
| 🟢 Planificado | Pi-hole como DNS primario | 3 horas | DNS rápido, DNSSEC, requisito enunciado |

---

## 6. Estado por requisito del enunciado

| Requisito | Estado | Notas |
|-----------|--------|-------|
| DHCPv4 | ✅ Implementado | Kea en Mini PC, VLANs 10/20/30 |
| DHCPv6 | ⬜ Pendiente evaluar | Kea soporta DHCPv6, interfaces tienen ULA |
| DNS primario + secundario (DNSSEC + TSIG) | ❌ Pendiente | Solo systemd-resolved forwarding |
| DNS autoritativo + DNS64 | ❌ Pendiente | Jool NAT64 activo, DNS64 sin configurar |
| Proxy-cache (Squid) | ⚠️ Parcial | Squid activo en RPi pero offline_mode |
| Portal cautivo | ✅ Implementado | Funcional, mejorable en latencia |
| CDN local | ⚠️ Parcial | Kiwix/Jellyfin/Kolibri activos en RPi |
| Servidor Matrix | ❌ Pendiente | No instalado |
| NTP | ⬜ Sin verificar | systemd-timesyncd por defecto |
| Monitoreo/observabilidad | ❌ Pendiente | Health-check básico en RPi (/status) |
