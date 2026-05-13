# Fix: DHCP Offer no llega a macOS en estado APIPA

**Fecha:** 2026-05-12
**Estado:** Aplicado ✅

---

## Síntoma

Al desconectar y reconectar el cable Ethernet en la MacBook (`en8`), la interfaz no obtenía IP del servidor DHCP y quedaba con dirección APIPA (`169.254.80.5`). Los logs de Kea mostraban actividad continua (`DHCP4_LEASE_ADVERT`) pero nunca un `DHCP4_LEASE_ALLOC`.

---

## Diagnóstico: captura coordinada de paquetes

Se realizó un `tcpdump -e` simultáneo en el Mini PC (`enp171s0.30`) mientras se forzaba DHCP en el Mac. Esto reveló el comportamiento exacto a nivel Ethernet:

```
Mac   → Discover: 3c:ab:72:4a:b9:cd > ff:ff:ff:ff:ff:ff   0.0.0.0     > 255.255.255.255  (broadcast ✓)
Kea   → Offer:    78:55:36:09:07:0a > 3c:ab:72:4a:b9:cd   192.168.30.1 > 192.168.30.100   (unicast ✗)
```

El Mac enviaba el Discover en broadcast. Kea respondía correctamente, pero el Offer llegaba como **unicast** con:
- `dst MAC = 3c:ab:72:4a:b9:cd` (MAC del Mac)
- `dst IP = 192.168.30.100` (IP ofrecida, que el Mac aún no tiene)

El Mac recibía el frame físicamente (dirección MAC correcta), pero el stack de red lo descartaba.

---

## Causa raíz 1 — macOS BPF filter en estado APIPA

El cliente DHCP de macOS (`configd` / `IPConfiguration`) usa un socket **BPF** (Berkeley Packet Filter) para capturar paquetes DHCP a nivel Ethernet, antes del filtrado IP. El filtro BPF del cliente en estado APIPA acepta únicamente:

```
udp dst port 68 AND (dst IP == 255.255.255.255 OR dst IP == 169.254.80.5)
```

El Offer venía con `dst IP = 192.168.30.100`, que no coincide con ninguna de las dos condiciones → **paquete descartado silenciosamente**.

El Discover de macOS tiene `Flags [none] (0x0000)` — **el BROADCAST bit está apagado**. Según RFC 2131, cuando el BROADCAST bit = 0 y CIADDR = 0, el servidor puede responder en unicast. Kea lo hace correctamente por especificación, pero macOS en APIPA no acepta esa respuesta.

---

## Causa raíz 2 — Kea usa raw sockets que bypasean netfilter

Al analizar los sockets del proceso Kea:

```bash
sudo cat /proc/$(pgrep kea-dhcp4)/net/packet
# proto 0x0003 (ETH_P_ALL) → Kea usa AF_PACKET sockets
```

Kea con `dhcp-socket-type: raw` abre sockets `AF_PACKET` (raw Ethernet) para enviar Offers directamente al MAC del cliente. Estos sockets **bypasean completamente el stack IP y netfilter**, incluyendo los hooks `OUTPUT` y `PREROUTING` de nftables. Por esta razón, reglas `DNAT` en la tabla `ip nat` (hook output) tenían `counter packets 0` — los paquetes nunca pasaban por esas cadenas.

---

## Intentos fallidos (documentados para referencia)

### Intento 1 — `dhcp-socket-type: raw` en Kea
```json
"interfaces-config": {
    "interfaces": ["enp171s0.10", "enp171s0.20", "enp171s0.30"],
    "dhcp-socket-type": "raw"
}
```
Kea sí activó raw sockets (verificado en `/proc/.../net/packet`), pero el formato del Offer no cambió: seguía siendo unicast a `192.168.30.100`. Kea construye el frame usando la `chaddr` del cliente pero mantiene el unicast al IP ofrecido.

### Intento 2 — nftables OUTPUT DNAT
```nft
table ip nat {
    chain output {
        type nat hook output priority dstnat; policy accept;
        oif "enp171s0.30" udp sport 67 ip daddr 192.168.30.0/24 dnat to 255.255.255.255
    }
}
```
Counter = 0 paquetes. Los raw sockets de Kea bypasean el hook `output` de netfilter por completo. Esta regla nunca se ejecutó.

---

## Fix aplicado — nftables `netdev egress`

La tabla `netdev` con hook `egress` opera **por debajo de la capa IP**, directamente sobre los frames Ethernet antes de que salgan por la interfaz. A diferencia de los hooks `input`/`output`/`forward`, el hook `egress` captura **todos** los frames que salen del dispositivo, incluyendo los enviados via raw sockets `AF_PACKET`.

### Regla aplicada en vivo

```bash
sudo nft add table netdev dhcp_fix
sudo nft add chain netdev dhcp_fix out_vlan30 \
    '{ type filter hook egress device "enp171s0.30" priority 0; }'
sudo nft add rule netdev dhcp_fix out_vlan30 \
    udp sport 67 udp dport 68 ip daddr != 255.255.255.255 \
    ip daddr set 255.255.255.255 ether daddr set ff:ff:ff:ff:ff:ff
```

### Resultado verificado con tcpdump

```
Antes:  78:55:36:09:07:0a > 3c:ab:72:4a:b9:cd   192.168.30.1.67 > 192.168.30.100.68   (unicast ✗)
Después: 78:55:36:09:07:0a > ff:ff:ff:ff:ff:ff   192.168.30.1.67 > 255.255.255.255.68  (broadcast ✓)
```

Los Offers ahora salen como broadcast completo (MAC + IP), que macOS acepta incluso en estado APIPA.

### Persistido en `/etc/nftables.conf`

```nft
# ─── DHCP Broadcast Fix ───────────────────────────────────────────────────────
# macOS en estado APIPA solo acepta DHCP Offers con dst=255.255.255.255.
# Kea usa raw sockets (bypass netfilter) y envía Offers en unicast.
# Esta regla los convierte a broadcast en la capa Ethernet antes de salir.

table netdev dhcp_fix {
    chain out_vlan30 {
        type filter hook egress device "enp171s0.30" priority 0;
        udp sport 67 udp dport 68 ip daddr != 255.255.255.255 \
            ip daddr set 255.255.255.255 ether daddr set ff:ff:ff:ff:ff:ff
    }
}
```

Verificado con: `sudo nft -c -f /etc/nftables.conf` → config válida.

---

## Fix adicional — ARP estático para 192.168.30.100

Durante el diagnóstico se añadió una entrada ARP permanente en el Mini PC para garantizar que la resolución MAC sea inmediata cuando Kea intenta enviar el Offer unicast:

```bash
sudo ip neigh replace 192.168.30.100 lladdr 3c:ab:72:4a:b9:cd dev enp171s0.30 nud permanent
```

Esta entrada es transitoria (se pierde al reiniciar). No es necesaria con el fix de broadcast, pero evita delays de ARP en caso de que el fix se desactive temporalmente.

---

## Escape del estado APIPA actual

Una vez que macOS entra en APIPA, su state machine (`configd` / `IPConfiguration`) queda atascada incluso recibiendo Offers en broadcast. La única forma de escapar sin reiniciar es:

```bash
sudo ipconfig set en8 DHCP
```

Este comando reinicia completamente el cliente DHCP para `en8`, sale del estado APIPA y ejecuta un nuevo ciclo DORA desde cero.

---

## Flujo DHCP correcto post-fix

```
Cable conectado a FA0/4
    │  portfast trunk → Forwarding inmediato
    ▼
macOS envía DHCPDISCOVER
    src MAC: 3c:ab:72:4a:b9:cd
    dst MAC: ff:ff:ff:ff:ff:ff
    src IP:  0.0.0.0
    dst IP:  255.255.255.255
    BROADCAST flag: 0 (macOS no lo setea)
    │
    ▼
Kea recibe por raw socket (enp171s0.30)
    │  Decide responder con OFFER unicast a 192.168.30.100
    ▼
AF_PACKET raw socket envía frame
    dst MAC: 3c:ab:72:4a:b9:cd (unicast)
    dst IP:  192.168.30.100 (unicast)
    │
    │  ← nftables netdev egress hook (ANTES de salir del NIC)
    ▼
ip daddr set 255.255.255.255
ether daddr set ff:ff:ff:ff:ff:ff
    │
    ▼
Frame sale como broadcast:
    dst MAC: ff:ff:ff:ff:ff:ff
    dst IP:  255.255.255.255
    │
    ▼
Switch → FA0/4 (native VLAN 30) → Mac recibe en en8
    │
    │  BPF filter: udp port 68 AND dst IP 255.255.255.255 → ACEPTA ✓
    ▼
configd procesa OFFER → envía DHCPREQUEST → Kea responde ACK
    │
    ▼
en8 obtiene 192.168.30.100/24
```

---

## Estado final

| Componente | Antes | Después |
|------------|-------|---------|
| DHCP Offer dst MAC | Unicast `3c:ab:72:4a:b9:cd` | Broadcast `ff:ff:ff:ff:ff:ff` |
| DHCP Offer dst IP | Unicast `192.168.30.100` | Broadcast `255.255.255.255` |
| macOS BPF acepta Offer | No (IP no coincide) | Sí ✓ |
| DHCP al reconectar | APIPA permanente | IP asignada en < 5s |
| Persistencia | — | `/etc/nftables.conf` (sobrevive reboot) |

---

## Archivos modificados

| Dispositivo | Archivo / Componente | Cambio |
|-------------|----------------------|--------|
| Mini PC | `/etc/nftables.conf` | Tabla `netdev dhcp_fix` agregada al final |
| Mini PC | `/etc/kea/kea-dhcp4.conf` | `"dhcp-socket-type": "raw"` en `interfaces-config` |
| Mini PC | ARP table (volátil) | `ip neigh permanent` para 192.168.30.100 |

---

## Notas técnicas

- **Requiere kernel ≥ 5.16** para soporte de `mangle` en hook `egress` de tabla `netdev`. Mini PC usa kernel `6.8.0-111-generic` ✓
- **Compatibilidad con múltiples clientes**: al broadcast el Offer, todos los clientes en VLAN 30 lo ven. Esto es RFC 2131 compliant — cada cliente descarta Offers cuyo `xid` no coincida con su Discover pendiente.
- **El fix de `dhcp-socket-type: raw` se mantiene** en Kea aunque no resuelva el broadcast por sí solo — mejora la compatibilidad general con clientes DHCP que sí soportan el modo raw.
