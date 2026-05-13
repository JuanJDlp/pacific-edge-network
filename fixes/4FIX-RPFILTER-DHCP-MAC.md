# Fix: rp_filter all=2, DHCP bloqueado en Mac (APIPA), routing métrica

**Fecha:** 2026-05-12
**Estado:** Aplicado ✅

---

## Problema 1 — Portal cautivo lento y falla en segunda URL HTTP

### Síntoma
- La primera vez que un cliente conecta, el portal cautivo tarda mucho en aparecer.
- Después de aceptar el portal, la primera URL HTTP funciona pero URLs posteriores fallan.
- El DNS resuelve inconsistentemente.

### Causa raíz — `rp_filter all=2` anula los fixes por interfaz

El FIX-3 anterior configuró `rp_filter=1` (loose) en cada interfaz VLAN:
```ini
net.ipv4.conf.enp171s0.rp_filter = 1
net.ipv4.conf.enp171s0/10.rp_filter = 1
net.ipv4.conf.enp171s0/20.rp_filter = 1
net.ipv4.conf.enp171s0/30.rp_filter = 1
```

Pero **no se configuró `net.ipv4.conf.all`**. El kernel Linux calcula el valor efectivo de `rp_filter` para cada interfaz como:

```
efectivo = max(net.ipv4.conf.all.rp_filter, net.ipv4.conf.IFACE.rp_filter)
```

Con `all=2` (strict) y `enp171s0.30=1` (loose):
```
max(2, 1) = 2  ← strict en todas las interfaces, aunque la config de cada una diga 1
```

### Por qué esto rompe el DNS del portal cautivo

El flujo DNS del cliente VLAN 30 con DNAT activo:

```
Cliente (192.168.30.100) → consulta DNS a 192.168.30.1:53
    │
    │  DNAT (nat prerouting): dst 192.168.30.1 → 192.168.10.1:53
    ▼
systemd-resolved en 192.168.10.1 resuelve y responde:
    src=192.168.10.1, dst=192.168.30.100
    │
    │  rp_filter strict (modo 2) verifica en enp171s0.30:
    │  "¿La mejor ruta hacia 192.168.10.1 pasa por enp171s0.30?"
    │  Respuesta: NO — 192.168.10.0/24 está en enp171s0.10
    ▼
Paquete descartado ← DNS falla → HTTP falla
```

Sin respuesta DNS estable el portal aparecía solo cuando conntrack lograba manejar la sesión antes del drop, de forma intermitente.

### Fix aplicado en el Mini PC

```bash
sudo sysctl -w net.ipv4.conf.all.rp_filter=1
sudo sysctl -w net.ipv4.conf.default.rp_filter=1
```

Persistido en `/etc/sysctl.d/10-vlan-routing.conf`:

```ini
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.enp171s0.rp_filter = 1
net.ipv4.conf.enp171s0/10.rp_filter = 1
net.ipv4.conf.enp171s0/20.rp_filter = 1
net.ipv4.conf.enp171s0/30.rp_filter = 1
```

| Parámetro | Antes | Después |
|-----------|-------|---------|
| `all` | `2` (strict) | `1` (loose) |
| `default` | `2` (strict) | `1` (loose) |
| `enp171s0/30` (efectivo) | `max(2,1)=2` ❌ | `max(1,1)=1` ✅ |

---

## Problema 2 — DHCP no reasigna IP al reconectar el cable (Mac queda en APIPA)

### Síntoma
Al desconectar y reconectar el cable Ethernet en el Mac (`en8`), la interfaz queda con dirección APIPA (`169.254.x.x`) y nunca obtiene IP del servidor DHCP aunque éste funciona correctamente.

### Diagnóstico

Los logs de Kea mostraron el comportamiento real:

```
DHCP4_LEASE_ADVERT [hwtype=1 3c:ab:72:4a:b9:cd] ... lease 192.168.30.100 will be advertised
DHCP4_LEASE_ADVERT [hwtype=1 3c:ab:72:4a:b9:cd] ... lease 192.168.30.100 will be advertised
... (decenas de veces, nunca DHCP4_LEASE_ALLOC)
```

- **Kea SÍ recibe** los DHCPDISCOVER del Mac.
- **Kea SÍ envía** DHCPOFFER con 192.168.30.100.
- El Mac **nunca responde** con DHCPREQUEST → nunca se completa el handshake DORA.

El switch fue descartado como causa:
- DHCP snooping: **desactivado** → no dropea Offers
- FA0/4: `spanning-tree portfast trunk` ✓ → forwarding inmediato
- FA0/4: `switchport trunk native vlan 30` ✓ → frames sin tag van a VLAN 30

### Causa raíz — Estado APIPA bloquea el cliente DHCP de macOS

Cuando macOS entra en estado APIPA tras un fallo DHCP inicial, el stack de red (configd/IPConfiguration) entra en un ciclo de backoff. Al reconectar el cable, el cliente DHCP de `en8` **no reinicia limpiamente**: envía DISCOVERs pero ignora las OFFERs recibidas porque el estado interno no está limpio. El ciclo continúa hasta que se fuerza el reinicio del cliente DHCP.

### Fix — Reiniciar el cliente DHCP en macOS

Ejecutar en Terminal en el Mac:

```bash
sudo ipconfig set en8 DHCP
```

Este comando reinicia el stack DHCP de la interfaz `en8` desde cero. En el contexto del proyecto, `en8` es la interfaz Ethernet del Mac conectada al switch via FA0/4.

Tras ejecutarlo, Kea asigna la IP en menos de 5 segundos y el log muestra:
```
DHCP4_LEASE_ALLOC [hwtype=1 3c:ab:72:4a:b9:cd] ... lease 192.168.30.100 has been allocated
```

---

## Problema 3 — Mac pierde internet cuando en8 obtiene IP

### Síntoma
Al obtener una IP en `en8` (192.168.30.x), macOS prefiere esa interfaz sobre WiFi para el tráfico de internet. Como `en8` da acceso solo a la red local (VLAN 30 + portal cautivo), el Mac queda sin internet mientras `en8` está activa.

### Causa raíz — Métrica de routing: wired < WiFi en macOS

macOS asigna automáticamente métricas más bajas a interfaces cableadas que a WiFi. Al tener ambas activas con un default gateway, el Mac prefiere la ruta via `en8` (192.168.30.1) sobre WiFi.

### Fix — Cambiar el orden de servicios de red en macOS

**Método permanente (recomendado):**

1. Abrir **Preferencias del Sistema → Red**
2. Clic en `⋮` o el ícono de engranaje → **Set Service Order**
3. Arrastrar **Wi-Fi encima de Ethernet** (`en8`)
4. OK → Apply

Esto hace que macOS siempre use WiFi como ruta principal, incluso si `en8` tiene IP asignada.

**Método temporal (solo para pruebas, se pierde al reiniciar):**

```bash
# Eliminar la ruta default via en8
sudo route delete default 192.168.30.1
```

---

## Estado final

| Componente | Antes | Después |
|------------|-------|---------|
| `rp_filter all` | `2` (strict, anulaba los fixes) | `1` (loose) |
| `rp_filter default` | `2` (strict) | `1` (loose) |
| `rp_filter efectivo enp171s0.30` | `2` ❌ | `1` ✅ |
| DNS con DNAT a 192.168.10.1 | Intermitente / falla | Estable |
| Portal cautivo primera URL | Lento (30-60s) | < 5s |
| Portal cautivo URLs posteriores | Fallan | Funcionan |
| DHCP al reconectar cable | APIPA bloqueado | `sudo ipconfig set en8 DHCP` |
| Mac prefiere en8 sobre WiFi | Pierde internet | Fix en Service Order |

---

## Archivos modificados

| Dispositivo | Archivo / Componente | Cambio |
|-------------|----------------------|--------|
| Mini PC | `/etc/sysctl.d/10-vlan-routing.conf` | Agregados `all=1` y `default=1` |
| Mac (cliente) | Network Service Order | WiFi sobre Ethernet en el orden |
