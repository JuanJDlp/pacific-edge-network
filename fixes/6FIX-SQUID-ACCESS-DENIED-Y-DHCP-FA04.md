# Fix 6 — Squid Access Denied en http://192.168.20.10 + DHCP FA0/4
**Fecha:** 2026-05-13
**Estado:** ✅ Resuelto

---

## Problema 1 — Squid devuelve 403 al redirigir al home de la RPi

### Síntoma
Después de autenticarse en el portal cautivo, el browser era redirigido a
`http://192.168.20.10/` y Squid respondía:

```
The requested URL could not be retrieved
Access Denied.
Access control configuration prevents your request from being allowed at this time.
```

Log de Squid (`/var/log/squid/access.log`):
```
192.168.20.10  TCP_MISS/403  GET http://192.168.20.10/ - HIER_NONE/- text/html
192.168.30.101 TCP_MISS/403  GET http://192.168.20.10/ - ORIGINAL_DST/192.168.20.10 text/html
```

### Causa raíz — Loop DNAT en nftables

La regla DNAT en el Mini PC redirigía **todo** el HTTP autenticado (mark=0x1)
al puerto 3128 de Squid, incluyendo el tráfico ya destinado a `192.168.20.10:80`:

```
Cliente autenticado → http://192.168.20.10:80
→ DNAT Mini PC: mark=0x1, dport 80 → 192.168.20.10:3128  (Squid)
→ Squid intercept: SO_ORIGINAL_DST = 192.168.20.10:3128   (su propio puerto)
→ Squid detecta loop → 403 Access Denied
```

Squid en modo intercept llama a `SO_ORIGINAL_DST` para saber el destino original.
Como el DNAT fue aplicado en el Mini PC (no en la RPi), el conntrack de la RPi
no tiene registro de la traducción y devuelve `192.168.20.10:3128` (su propio
puerto de intercept). Squid detecta que intentaría conectarse a sí mismo y deniega.

### Fix — Excluir tráfico destinado a la RPi del DNAT

**Archivo:** `/etc/nftables.conf` en el Mini PC

**Antes:**
```nft
iif "enp171s0.30" meta mark 0x1 tcp dport 80 dnat to 192.168.20.10:3128
```

**Después:**
```nft
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80 dnat to 192.168.20.10:3128
```

**Comando aplicado:**
```bash
sudo sed -i 's|iif "enp171s0.30" meta mark 0x1 tcp dport 80 dnat to 192.168.20.10:3128|iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80 dnat to 192.168.20.10:3128|' /etc/nftables.conf
sudo nft -f /etc/nftables.conf
```

### Comportamiento resultante

| Destino del cliente autenticado | Flujo |
|---------------------------------|-------|
| `http://192.168.20.10/` (RPi) | Directo → nginx RPi — **sin pasar por Squid** |
| `http://cualquier.otro.sitio/` | DNAT → Squid :3128 → caché → internet |
| `https://cualquier.sitio/` | Forward directo → WAN (Squid no puede interceptar HTTPS) |

---

## Problema 2 — DHCP no asigna IP al PC conectado en FA0/4

### Síntoma
PC conectado a FA0/4 del switch Catalyst 2960 obtenía dirección APIPA
(`169.254.x.x`) en lugar de `192.168.30.x`. Kea sí recibía y respondía a los
DISCOVER del cliente (MAC `3c:ab:72:4a:b9:cd`) pero el OFFER no llegaba.

```
# kea-dhcp4.log mostraba asignación exitosa:
DHCP4_LEASE_ADVERT  [hwtype=1 3c:ab:72:4a:b9:cd]: lease 192.168.30.101 will be advertised
DHCP4_LEASE_ALLOC   [hwtype=1 3c:ab:72:4a:b9:cd]: lease 192.168.30.101 has been allocated
```

### Causa raíz — Faltaba `switchport mode trunk` en FA0/4

`show interfaces status` mostraba FA0/4 en **VLAN 1** en lugar de trunk:

```
Fa0/4  AP_PacificEdge_WiF  connected    1     a-full  a-100
```

La config tenía los comandos de trunk (`native vlan 30`, `allowed vlan 20,30`)
pero faltaba `switchport mode trunk`. Sin ese comando, el puerto opera en modo
**dynamic auto** y negocia como access en VLAN 1. Los broadcasts DHCP del
cliente llegaban al switch en VLAN 1 y nunca eran enviados por el trunk al
Mini PC en `enp171s0.30` (VLAN 30).

### Fix — Agregar `switchport mode trunk` a FA0/4

**Config final de FA0/4:**
```
interface FastEthernet0/4
 description AP_PacificEdge_WiFi
 switchport trunk native vlan 30
 switchport trunk allowed vlan 20,30
 switchport mode trunk
 spanning-tree portfast trunk
```

**Comandos aplicados en el switch:**
```
configure terminal
 interface FastEthernet0/4
  switchport mode trunk
 end
write memory
```

**Verificación post-fix:**
```
Fa0/4  AP_PacificEdge_WiF  connected    trunk    a-full  a-100
```

**En el cliente (macOS):**
```bash
sudo ipconfig set en8 NONE && sudo ipconfig set en8 DHCP
# → Obtiene 192.168.30.101
```

### Nota sobre native VLAN 30

Con `native vlan 30`, el switch envía/recibe tráfico de VLAN 30 **sin etiqueta
802.1Q**. Esto permite que un PC convencional (sin soporte de VLANs) conectado
a FA0/4 opere correctamente en VLAN 30 sin configuración especial en el cliente.

---

## Archivos modificados

| Dispositivo | Archivo / Config | Cambio |
|-------------|-----------------|--------|
| Mini PC | `/etc/nftables.conf` | DNAT Squid: añadido `ip daddr != 192.168.20.10` para excluir tráfico directo a RPi |
| Switch Catalyst 2960 | `interface FastEthernet0/4` (NVRAM) | Añadido `switchport mode trunk`; guardado con `write memory` |
