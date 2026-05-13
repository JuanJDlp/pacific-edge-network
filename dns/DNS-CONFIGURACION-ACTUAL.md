# DNS — Configuración Actual
**Fecha:** 2026-05-13
**Equipo:** Mini PC (`100.90.95.134`)

---

## 1. Resumen

El DNS de la red funciona con un único componente: **systemd-resolved** en el Mini PC actuando como stub resolver para todas las VLANs. No hay resolver recursivo dedicado, ni DNSSEC, ni Pi-hole. Las consultas de los clientes llegan interceptadas por nftables y salen a internet a través de los DNS de Starlink.

```
Cliente VLAN 30/20/10
    │  consulta a 192.168.30.1:53 (lo que le dió DHCP)
    │
    │  nftables PREROUTING DNAT:
    │  udp/tcp dport 53 → 192.168.10.1:53
    ▼
systemd-resolved (Mini PC)
    │  escucha en 192.168.10.1:53 via DNSStubListenerExtra
    │  upstream configurado por DHCP de Starlink (enp170s0)
    ▼
DNS Starlink
    192.168.215.20
    192.168.215.30
    │
    ▼
Respuesta → resolved → cliente
```

---

## 2. systemd-resolved — Configuración detallada

### 2.1 Puertos en escucha

```
127.0.0.53:53       ← stub por defecto (loopback, solo para procesos del Mini PC)
127.0.0.54:53       ← stub sin caché (resolve directo, loopback)
192.168.10.1:53     ← stub extra VLAN 10 (gestión)
192.168.20.1:53     ← stub extra VLAN 20 (servidores)
192.168.30.1:53     ← stub extra VLAN 30 (clientes WiFi)
100.90.95.134:53    ← stub extra Netbird VPN
```

Los stubs extra están configurados en `/etc/systemd/resolved.conf.d/lan-stub.conf`:

```ini
[Resolve]
DNSStubListenerExtra=192.168.10.1
DNSStubListenerExtra=192.168.20.1
DNSStubListenerExtra=192.168.30.1
```

### 2.2 DNS upstream (automático vía DHCP de Starlink)

| Interfaz | Upstream DNS | Origen |
|----------|-------------|--------|
| `enp170s0` (WAN) | `192.168.215.20`, `192.168.215.30` | DHCP Starlink |
| `wt0` (Netbird) | `100.90.95.134` | Netbird |

> Los servidores DNS de Starlink son IPs privadas (RFC1918 `192.168.215.x`) dentro de la red del módem Starlink.

### 2.3 Estado de características avanzadas

| Característica | Estado |
|---------------|--------|
| DNSSEC | ❌ Desactivado (`DNSSEC=no/unsupported`) |
| DNS-over-TLS | ❌ Desactivado |
| LLMNR | ❌ Desactivado |
| mDNS | ❌ Desactivado |
| Caché negativo | Activado por defecto (`Cache=no-negative` no aplica) |
| Caché | ✅ Activo (caché interno de resolved) |

### 2.4 Flujo de una consulta desde resolved

```
resolved recibe consulta para wikipedia.org
    │
    ├─ ¿Está en caché?  → responde inmediato
    │
    └─ Cache miss
         │
         └─ forwarding via enp170s0
              → 192.168.215.30:53 (DNS Starlink)
              ← respuesta A/AAAA
              → cachea y responde al cliente
```

No hay resolución recursiva propia — resolved solo hace forwarding.

---

## 3. Interceptación DNS via nftables

Todos los clientes de VLAN 10/20/30 tienen el DNS de su interfaz de gateway como servidor DNS (entregado por DHCP). Sin embargo, cualquier consulta DNS — incluso si el cliente configurase manualmente otro servidor (8.8.8.8, 1.1.1.1) — es interceptada y redirigida a `192.168.10.1:53`:

```nft
# En table ip nat, chain prerouting (prioridad dstnat = -100):

iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } udp dport 53 \
    dnat to 192.168.10.1:53

iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } tcp dport 53 \
    dnat to 192.168.10.1:53
```

Esto garantiza que ningún cliente pueda evitar el DNS interno usando un resolver alternativo.

---

## 4. DNS entregado por DHCP (Kea)

Kea entrega el servidor DNS por subnet. Hay una inconsistencia entre VLANs:

| VLAN | Subnet | DNS entregado por DHCP | ¿Coincide con el DNAT? |
|------|--------|------------------------|------------------------|
| 10 (gestión) | `192.168.10.0/24` | `192.168.10.1` | ✅ Sí — es directamente resolved |
| 20 (servidores) | `192.168.20.0/24` | `192.168.10.1` | ✅ Sí — directo a resolved (DNAT no necesario) |
| 30 (clientes) | `192.168.30.0/24` | `192.168.30.1` | ⚠️ DNAT redirige a 192.168.10.1 igualmente |

> **Nota:** VLAN 30 entrega `192.168.30.1` como DNS. Esa IP llega al Mini PC por la interfaz `enp171s0.30`, y el DNAT la redirige a `192.168.10.1:53`. El resultado final es el mismo, pero el cliente ve `192.168.30.1` como su DNS en lugar de `192.168.10.1`. Esto es intencional: si se instalara Pi-hole en `192.168.30.1` o similar, la IP ya estaría configurada en los clientes.

Dominio de búsqueda entregado en todas las VLANs: `comunitaria.local`

---

## 5. Resolución desde el propio Mini PC

El Mini PC usa `127.0.0.53` como resolver (modo stub, `/etc/resolv.conf` apunta ahí). Las consultas del propio Mini PC van a systemd-resolved → upstream Starlink.

```
/etc/resolv.conf  →  nameserver 127.0.0.53
                      options edns0 trust-ad
                      search netbird.cloud
```

---

## 6. Limitaciones actuales

| Limitación | Impacto | Fix planificado |
|-----------|---------|-----------------|
| Sin DNSSEC | Consultas no validadas — vulnerable a spoofing | Pi-hole + Unbound con DNSSEC |
| Sin caché dedicado con prefetch | Primera consulta tarda ~100ms (Starlink) | Pi-hole tiene caché con prefetching activo |
| DNS upstream depende de Starlink | Si el módem cambia IP, se pierde el upstream | Configurar fallback explícito (1.1.1.1, 9.9.9.9) |
| Sin filtrado de publicidad/malware | Clientes ven ads y tienen riesgo de malware DNS | Pi-hole + listas de bloqueo |
| Sin DNS autoritativo local | `comunitaria.local` no resuelve a nada | BIND9 o Unbound con zona local |
| Sin DNS64 | IPv6-only devices no pueden usar IPv4 internet | Requiere DNS64 + NAT64 (Jool activo pero DNS64 no) |

---

## 7. Plan de mejora — Pi-hole (próximo paso)

### 7.1 Arquitectura propuesta

```
Cliente VLAN 30
    │  DNS: 192.168.30.1 (entregado por DHCP — sin cambio para el cliente)
    │
    │  nftables DNAT actualizado:
    │  udp/tcp dport 53 → 192.168.10.100:53   (IP de Pi-hole)
    ▼
Pi-hole (192.168.10.100, Mini PC o RPi)
    │  - Caché local con prefetching
    │  - Filtrado de publicidad y malware
    │  - Dashboard web de consultas
    │
    └─ upstream: Unbound (127.0.0.1:5335)
         │  - Resolver recursivo local (sin forwarding)
         │  - DNSSEC validado
         └─ consulta directamente a root servers
```

### 7.2 Cambios necesarios

#### nftables (Mini PC) — actualizar DNAT
```nft
# Reemplazar en ip nat prerouting:
iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } udp dport 53 \
    dnat to 192.168.10.100:53

iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } tcp dport 53 \
    dnat to 192.168.10.100:53
```

#### Kea DHCP (Mini PC) — actualizar DNS por VLAN
```json
{
  "name": "domain-name-servers",
  "data": "192.168.10.100"
}
```
> Aplicar en las 3 subnets. Los clientes con lease activo recibirán el cambio al renovar (máximo 12h).

#### Pi-hole — instalación
```bash
# En el Mini PC (recomendado — ya tiene IP fija en VLAN 10)
curl -sSL https://install.pi-hole.net | bash
# Configurar: interface enp171s0.10, IP 192.168.10.100, listen on all interfaces

# Deshabilitar DNSStubListenerExtra en la IP que usará Pi-hole para evitar conflicto de puerto:
# Eliminar de /etc/systemd/resolved.conf.d/lan-stub.conf:
#   DNSStubListenerExtra=192.168.10.1   ← si Pi-hole va en 192.168.10.100, no hay conflicto
```

#### Unbound como upstream de Pi-hole (DNSSEC)
```bash
sudo apt install unbound

# /etc/unbound/unbound.conf.d/pi-hole.conf:
server:
    interface: 127.0.0.1
    port: 5335
    do-daemonize: no
    prefetch: yes
    dnssec: yes
    root-hints: "/var/lib/unbound/root.hints"
```

### 7.3 Estado esperado tras la mejora

| Característica | Ahora | Con Pi-hole + Unbound |
|---------------|-------|-----------------------|
| Latencia DNS (caché hit) | ~100ms (Starlink) | < 1ms |
| Latencia DNS (caché miss) | ~100ms | ~20-50ms (recursión directa) |
| DNSSEC | ❌ No | ✅ Validado |
| Filtrado publicidad | ❌ No | ✅ Sí (listas Firebog) |
| DNS autoritativo `comunitaria.local` | ❌ No | ✅ Configurable en Pi-hole |
| Dashboard / observabilidad | ❌ No | ✅ Web UI Pi-hole |
