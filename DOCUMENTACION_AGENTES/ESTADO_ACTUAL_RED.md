# Diagnóstico y Estado Actual — Pacific Edge Network v2
**Fecha:** 2026-05-13
**Referencia:** Versión anterior en `DIAGNOSTICO-Y-PLAN-MEJORAS.md` (2026-05-12)

---

## Resumen de cambios aplicados desde v1

| # | Mejora | Estado | Archivos modificados |
|---|--------|--------|----------------------|
| 4.1 | TCP RST en puerto 443 para no autenticados | ✅ Aplicado | `/etc/nftables.conf` |
| 4.2 | Reemplazar captive-portal.py con nginx | ✅ Aplicado | `/etc/nginx/sites-available/captive-portal`, `/etc/systemd/system/captive-portal.service`, `/etc/systemd/system/captive-accept.service`, `/usr/local/bin/captive-accept.py` |
| 4.3 | Squid transparente para autenticados | ✅ Aplicado | `/etc/squid/squid.conf`, `/etc/nftables.conf` |
| 4.5 | Probes OS en captive portal (iOS/Android/Windows) | ✅ Aplicado | `/etc/nginx/sites-available/captive-portal` |
| 4.4 | Pi-hole como DNS primario | ⬜ Pendiente | — |

---

## 1. Estado actual de la red

### Topología (sin cambios)

```
Internet (Starlink)
      │
      │ 172.16.0.11/16 (WAN DHCP)
┌─────▼──────────────────────────────────────────────────────────┐
│                   MINI PC — Ubuntu Server 24.04                │
│                                                                │
│  enp170s0    →  172.16.0.11   (WAN)                           │
│  enp171s0.10 → 192.168.10.1  (VLAN 10 — Gestión)             │
│  enp171s0.20 → 192.168.20.1  (VLAN 20 — Servidores)          │
│  enp171s0.30 → 192.168.30.1  (VLAN 30 — Clientes)            │
│  wt0         → 100.90.95.134 (Netbird VPN)                   │
└─────────────────────────────┬──────────────────────────────────┘
                              │ trunk 802.1Q
                    ┌─────────▼──────────┐
                    │  Switch Catalyst   │
                    │  2960 (L2)         │
                    └──┬──────────────┬──┘
                       │ Fa0/1        │ Fa0/4
              VLAN 20  │              │  VLAN 30 (native)
           ┌───────────▼───┐   ┌──────▼────────────────┐
           │ Raspberry Pi 5│   │ AP / PC de prueba      │
           │ 192.168.20.10 │   │ 192.168.30.100–200     │
           └───────────────┘   └────────────────────────┘
```

---

## 2. Mini PC — Estado actual de servicios

| Servicio | Protocolo/Puerto | Estado | Cambio desde v1 |
|----------|-----------------|--------|-----------------|
| nginx (captive portal) | TCP `:2050` | ✅ activo | **Nuevo** — reemplaza captive-portal.py |
| captive-accept | TCP `127.0.0.1:2051` | ✅ activo | **Nuevo** — handler Python mínimo para `nft` |
| Kea DHCPv4 | UDP `192.168.{10,20,30}.1:67` | ✅ activo | Sin cambios |
| systemd-resolved (DNS) | UDP/TCP `192.168.{10,20,30}.1:53` | ✅ activo | Sin cambios |
| nftables | — | ✅ activo | **Modificado** — RST en 443 + DNAT a Squid |
| Netbird VPN | WireGuard `wt0` | ✅ activo | Sin cambios |
| SSH | TCP `22` | ✅ activo | Sin cambios |

### 2.1 Arquitectura del captive portal (nueva)

**Antes:**

```
Puerto 2050
└── captive-portal.py (HTTPServer, single-threaded, root)
    ├── GET /          → lee splash.html del disco en cada request
    └── GET /accept    → nft add element + 302 a RPi
```

**Ahora:**

```
Puerto 2050
└── nginx (multi-proceso, caché en memoria)
    ├── GET /                       → splash.html (no-cache headers)
    ├── GET /generate_204           → 302 /  (probe Android)
    ├── GET /hotspot-detect.html    → 302 /  (probe macOS/iOS)
    ├── GET /connecttest.txt        → 302 /  (probe Windows)
    ├── GET /ncsi.txt               → 302 /  (probe Windows alt)
    └── GET /accept                 → proxy_pass → 127.0.0.1:2051
                                              │
                                    captive-accept.py (ThreadingHTTPServer)
                                    ├── extrae X-Real-IP del header
                                    └── nft add element captive_allowed { IP }
```

**Por qué mejora:**
- nginx sirve `splash.html` desde memoria sin leer el disco en cada request
- Múltiples conexiones concurrentes (el browser abre 6 simultáneamente) no se encolan
- Los probes de OS (iOS, Android, Windows) son respondidos automáticamente → el sistema operativo muestra el popup de "Conectar a red" sin que el usuario abra el browser manualmente

### 2.2 nftables — Ruleset completo actual

```nft
table inet filter {

    # IPs autenticadas via portal (timeout 8h)
    set captive_allowed {
        type ipv4_addr
        flags dynamic, timeout
        timeout 8h
    }

    # Mangle prerouting: marca paquetes autenticados con 0x1
    # Prioridad mangle (-150) corre ANTES que el DNAT (-100)
    chain captive_mangle {
        type filter hook prerouting priority mangle; policy accept;
        iif "enp171s0.30" ip saddr @captive_allowed meta mark set 0x1
    }

    chain input {
        type filter hook input priority filter; policy drop;
        iif "lo" accept
        iif "wt0" accept
        ct state established,related accept
        ct state invalid drop
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } tcp dport { 22, 53, 80, 443 } accept
        iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } udp dport { 53, 67, 68, 123 } accept
        iif "enp171s0.30" tcp dport 2050 accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        # VLAN 10/20 → WAN: siempre libre
        iif { "enp171s0.10", "enp171s0.20" } oif "enp170s0" accept
        # VLAN 30 autenticados → WAN / RPi
        iif "enp171s0.30" oif "enp170s0"    ip saddr @captive_allowed accept
        iif "enp171s0.30" oif "enp171s0.20" ip saddr @captive_allowed accept
        iif "enp171s0.30" oif "enp171s0"    ip saddr @captive_allowed accept
        # ★ NUEVO: HTTPS no autenticado → RST inmediato (era DROP silencioso → 30s timeout)
        iif "enp171s0.30" meta mark != 0x1 tcp dport 443 reject with tcp reset
    }

    chain output { type filter hook output priority filter; policy accept; }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        # DNS forzado a resolver interno
        iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } udp dport 53 dnat to 192.168.10.1:53
        iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } tcp dport 53 dnat to 192.168.10.1:53
        # Portal cautivo: HTTP no autenticado → nginx :2050
        iif "enp171s0.30" meta mark != 0x1 tcp dport 80 dnat to 192.168.30.1:2050
        # ★ NUEVO: Proxy transparente: HTTP autenticado → Squid en RPi :3128
        iif "enp171s0.30" meta mark  0x1 tcp dport 80 dnat to 192.168.20.10:3128
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oif "enp170s0" masquerade
    }
}

# DHCP Broadcast Fix: Kea usa AF_PACKET (bypass netfilter), envía Offers en unicast.
# macOS en APIPA solo acepta dst=255.255.255.255 — esta regla lo convierte antes de salir del NIC.
table netdev dhcp_fix {
    chain out_vlan30 {
        type filter hook egress device "enp171s0.30" priority 0;
        udp sport 67 udp dport 68 ip daddr != 255.255.255.255
            ip daddr set 255.255.255.255 ether daddr set ff:ff:ff:ff:ff:ff
    }
}
```

---

## 3. Raspberry Pi — Estado actual de servicios

| Servicio | Puerto | Estado | Cambio desde v1 |
|----------|--------|--------|-----------------|
| nginx (portal + servicios) | TCP `80` | ✅ activo | Sin cambios |
| Squid (proxy cache) | TCP `3128` (intercept) | ✅ activo | **Modificado** — ahora va a internet |
| Squid (forward local) | TCP `127.0.0.1:3129` | ✅ activo | **Nuevo** — requerido por Squid para intercept |
| Kiwix (Wikipedia, etc.) | TCP `8080` (localhost) | ✅ activo | Sin cambios |
| Kolibri (educación) | TCP `8090` (localhost) | ✅ activo | Sin cambios |
| Jellyfin (multimedia) | TCP `8096` | ✅ activo | Sin cambios |
| SSH | TCP `22` | ✅ activo | Sin cambios |

### 3.1 Squid — cambios de configuración

**Antes:**
```squid
http_port 3128
offline_mode on       ← solo caché, nunca internet
never_direct allow all
```

**Ahora:**
```squid
http_port 127.0.0.1:3129      # forward proxy local (requerido por Squid)
http_port 3128 intercept       # modo transparente — recibe tráfico DNAT del Mini PC
always_direct allow all        # si no hay caché → va a internet directamente
```

**Por qué funciona el intercept con DNAT desde otro equipo:**

El Mini PC hace DNAT del tráfico HTTP autenticado hacia `192.168.20.10:3128`. Cuando el paquete llega al RPi, `SO_ORIGINAL_DST` devuelve `192.168.20.10:3128` (la IP del propio RPi) porque el conntrack del RPi no tiene el destino original. Squid 6.x en modo intercept detecta esto y cae back al `Host:` header del HTTP request — que siempre contiene el dominio real en HTTP/1.1. El resultado es funcional para todo tráfico HTTP/1.1.

**Flujo con Squid activo (cliente autenticado):**

```
Cliente (192.168.30.100, autenticado, mark=0x1)
│
│  GET / HTTP/1.1
│  Host: wikipedia.org           ← HTTP/1.1: Host: es obligatorio
│  → TCP SYN a 93.46.8.90:80
│
│  Mini PC PREROUTING DNAT:
│  mark 0x1, dport 80 → 192.168.20.10:3128
│
▼
Squid RPi (192.168.20.10:3128)
│
├─ Caché HIT  → responde desde /var/lib/biblioteca/squid-cache (< 10ms)
└─ Caché MISS → GW 192.168.20.1 → Mini PC → Starlink → internet
                └─ cachea respuesta para siguiente request
```

---

## 4. Flujo completo de una request (estado actual)

### 4.1 Cliente NO autenticado — `http://neverssl.com`

```
CLIENTE (192.168.30.100, NO autenticado)

1. DHCP → obtiene IP 192.168.30.100, GW 192.168.30.1, DNS 192.168.30.1

2. Browser intenta HTTPS primero (HSTS / upgrade):
   TCP SYN → neverssl.com:443
   → nftables forward: iif enp171s0.30, mark≠0x1, dport 443
   → REJECT with tcp reset   ← ★ NUEVO: RST inmediato (antes: DROP 30s)
   → Browser falla en < 1ms, intenta HTTP sin esperar

3. DNS: neverssl.com A? → DNAT → systemd-resolved → Starlink (~134ms)

4. TCP SYN → neverssl.com:80
   → nftables PREROUTING DNAT: mark≠0x1, dport 80 → 192.168.30.1:2050

5. nginx :2050 responde:
   → GET / → splash.html (desde memoria, < 5ms)
   → múltiples conexiones concurrentes del browser: servidas en paralelo

6. Usuario hace click "Entrar a la biblioteca":
   → GET /accept → nginx proxy_pass → captive-accept.py :2051
   → nft add element captive_allowed { 192.168.30.100 }   (timeout 8h)
   → 302 → http://192.168.20.10

Tiempo total hasta ver el portal: < 1s (antes: ~30s)
```

### 4.2 Cliente NO autenticado — dispositivo móvil (probe automático)

```
CLIENTE iOS/Android/Windows conecta al switch
│
│  OS envía probe HTTP al conectarse:
│  - iOS:     GET /hotspot-detect.html   Host: captive.apple.com
│  - Android: GET /generate_204          Host: connectivitycheck.gstatic.com
│  - Windows: GET /connecttest.txt       Host: www.msftconnecttest.com
│
│  DNS: captive.apple.com → cualquier IP (resuelta por systemd-resolved)
│  TCP SYN a esa IP:80
│  → DNAT: mark≠0x1, dport 80 → 192.168.30.1:2050
│
▼
nginx :2050
│  location = /hotspot-detect.html { return 302 http://$host:$server_port/; }
│
▼
OS detecta redirección → muestra popup "Conectar a Biblioteca Digital Ladrilleros"
Usuario hace tap → browser abre splash.html → /accept → autenticado
```

### 4.3 Cliente autenticado — navegación normal

```
CLIENTE (192.168.30.100, autenticado, mark=0x1)

HTTP (puerto 80):
  → DNAT a 192.168.20.10:3128 (Squid intercept)
  → Squid: caché HIT → responde local / caché MISS → internet → cachea

HTTPS (puerto 443):
  → forward chain: @captive_allowed accept
  → MASQUERADE → Starlink → internet directamente
  (HTTPS no pasa por Squid — no es interceptable sin MITM)

DNS (puerto 53):
  → DNAT a 192.168.10.1:53 → systemd-resolved → Starlink
```

---

## 5. Plan de mejoras — estado actualizado

| Prioridad | Mejora | Estado | Notas |
|-----------|--------|--------|-------|
| 🔴 Crítico | TCP RST en :443 para no autenticados | ✅ **Implementado** | Elimina delay de 30s |
| 🟠 Alto | nginx reemplaza captive-portal.py | ✅ **Implementado** | Portal < 100ms, concurrente |
| 🟡 Medio | Probes OS (iOS/Android/Windows) | ✅ **Implementado** | Popup automático en móviles |
| 🟡 Medio | Squid transparente para autenticados | ✅ **Implementado** | Caché HTTP, menor WAN |
| 🟢 Planificado | Pi-hole como DNS primario | ⬜ **Pendiente** | DNSSEC, filtrado, requisito enunciado |

---

## 6. Requisitos del enunciado — estado actualizado

| Requisito | Estado | Notas |
|-----------|--------|-------|
| DHCPv4 | ✅ Implementado | Kea en Mini PC, VLANs 10/20/30 |
| DHCPv6 | ⬜ Pendiente evaluar | Kea lo soporta |
| DNS primario + secundario (DNSSEC + TSIG) | ❌ Pendiente | Solo systemd-resolved forwarding; Pi-hole planificado |
| DNS autoritativo + DNS64 | ❌ Pendiente | Jool NAT64 activo, DNS64 sin configurar |
| Proxy-cache (Squid) | ✅ Implementado | Squid activo en RPi, intercept + internet |
| Portal cautivo | ✅ Implementado | nginx, probes OS, RST en 443 |
| CDN local | ⚠️ Parcial | Kiwix/Jellyfin/Kolibri activos en RPi |
| Servidor Matrix | ❌ Pendiente | No instalado |
| NTP | ⬜ Sin verificar | systemd-timesyncd por defecto |
| Monitoreo/observabilidad | ❌ Pendiente | Health-check básico en RPi (/status) |

---

## 7. Archivos modificados (acumulado desde v1)

### Mini PC (`100.90.95.134`)

| Archivo | Cambio |
|---------|--------|
| `/etc/nftables.conf` | + RST en 443 para no autenticados; + DNAT HTTP autenticado → Squid; - chain `ip nat output` (debugging, eliminada) |
| `/etc/nginx/sites-available/captive-portal` | **Nuevo** — config nginx :2050 con probes OS y proxy a captive-accept |
| `/etc/nginx/sites-enabled/captive-portal` | **Nuevo** — symlink a sites-available |
| `/usr/local/bin/captive-accept.py` | **Nuevo** — handler Python mínimo para `/accept` (ThreadingHTTPServer en 127.0.0.1:2051) |
| `/etc/systemd/system/captive-portal.service` | **Modificado** — ahora gestiona nginx en vez de Python |
| `/etc/systemd/system/captive-accept.service` | **Nuevo** — service para captive-accept.py |
| `/etc/kea/kea-dhcp4.conf` | `dhcp-socket-type: raw` (fix DHCP APIPA macOS) |
| `/etc/sysctl.d/10-vlan-routing.conf` | `rp_filter all=1, default=1` (fix DNS con DNAT) |

### Raspberry Pi (`100.90.81.168`)

| Archivo | Cambio |
|---------|--------|
| `/etc/squid/squid.conf` | `http_port 3128 intercept` + `http_port 127.0.0.1:3129`; eliminado `offline_mode on` y `never_direct allow all`; agregado `always_direct allow all` |

---

## 8. Próximo paso — Pi-hole (4.4)

El único ítem pendiente del plan de mejoras es Pi-hole. Pasos:

1. Instalar Pi-hole en el Mini PC (o RPi) — recibe consultas en `192.168.10.100:53`
2. Actualizar nftables DNAT de DNS:
   ```nft
   # Reemplazar:
   iif { ... } udp dport 53 dnat to 192.168.10.1:53
   # Por:
   iif { ... } udp dport 53 dnat to 192.168.10.100:53
   ```
3. Actualizar Kea DHCP para entregar `domain-name-servers = 192.168.10.100`
4. Configurar DNSSEC upstream en Pi-hole (Unbound como resolver recursivo)
5. Habilitar TSIG para transferencias de zona si se agrega BIND9 secundario
