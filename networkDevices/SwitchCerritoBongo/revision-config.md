# Revisión de configuración — SW-CORE-BONGO

**Revisado contra:** configuración del Mini PC (router + DHCP + firewall)  
**Fecha:** 2026-05-08

---

## Resumen de problemas

| # | Severidad | Problema |
|---|-----------|---------|
| 1 | 🔴 CRÍTICO | VLAN20 SVI `192.168.20.1` = misma IP que Mini PC |
| 2 | 🔴 CRÍTICO | VLAN30 SVI `192.168.30.1` = misma IP que Mini PC |
| 3 | 🔴 CRÍTICO | `ip routing` activo — el switch enruta entre VLANs sin pasar por el firewall del Mini PC |
| 4 | 🟡 MEDIO | Puerto 24 trunk usa `vlan add` en vez de definir la lista exacta |
| 5 | 🟡 MEDIO | Puerto 1 etiquetado "MiniPC" en VLAN20 access — el Mini PC conecta como router vía trunk en puerto 24 |

---

## Problema 1 y 2 — Conflicto de IPs en SVIs

El switch tiene asignadas las mismas IPs que el Mini PC en VLAN20 y VLAN30:

| Interfaz | IP Switch | IP Mini PC | Estado |
|----------|-----------|-----------|--------|
| VLAN 10 | `192.168.10.2/24` | `192.168.10.1/24` | ✅ Sin conflicto |
| VLAN 20 | `192.168.20.1/24` | `192.168.20.1/24` | ❌ Conflicto — misma IP |
| VLAN 30 | `192.168.30.1/24` | `192.168.30.1/24` | ❌ Conflicto — misma IP |
| VLAN 40 | `192.168.40.1/24` | no configurada | ⚠️ Huérfana |

Con dos dispositivos respondiendo a la misma IP:
- Los clientes en VLAN30 reciben `192.168.30.1` como gateway vía DHCP pero no saben si responde el Mini PC o el switch
- ARP genera conflictos intermitentes
- El tráfico puede tomar rutas inesperadas

---

## Problema 3 — `ip routing` bypasea el firewall

Con `ip routing` habilitado en el switch, el tráfico entre VLANs se enruta **localmente en el switch** sin pasar por el Mini PC. Esto rompe:

| Regla configurada en Mini PC | Efecto real con `ip routing` en el switch |
|------------------------------|------------------------------------------|
| VLAN30 → VLAN20: permitido | El switch lo enruta directamente ✓ pero sin pasar por nftables |
| VLAN20 → VLAN30: **bloqueado** | El switch lo enruta directamente ❌ el bloqueo no aplica |
| DNS forzado a `192.168.10.1:53` | No aplica para tráfico inter-VLAN ❌ |
| NAT64 | No aplica para tráfico inter-VLAN ❌ |
| Logs y contadores de nftables | No reflejan tráfico inter-VLAN ❌ |

El switch debe ser **L2 puro**. Todo el routing debe pasar por el Mini PC.

---

## Correcciones a aplicar

Conectarse al switch (Telnet o consola, user: `cisco`, pass: `cisco`) y ejecutar:

```
configure terminal

! Eliminar SVIs que conflictúan con el Mini PC
no interface vlan 20
no interface vlan 30
no interface vlan 40

! Desactivar routing L3 — el switch queda como L2 puro
no ip routing
no ip route 0.0.0.0 0.0.0.0 192.168.10.1

! Gateway de gestión para acceder al switch vía Telnet/ICMP
! (solo se usa cuando ip routing está desactivado)
ip default-gateway 192.168.10.1

! Corregir trunk del puerto 24 (uplink al Mini PC)
! Usar sin "add" para definir la lista exacta de VLANs permitidas
interface gi1/0/24
 switchport trunk allowed vlan 10,20,30,40
exit

end
write memory
```

---

## Cómo queda la arquitectura tras el fix

```
                   Internet
                       │
            [Router Starlink — 172.16.0.1]
                       │
     ┌─────────────────────────────────────┐
     │  MINI PC — Router + Firewall + DHCP │
     │  enp170s0  WAN  172.16.0.11/16      │
     │  enp171s0.10    192.168.10.1/24     │
     │  enp171s0.20    192.168.20.1/24     │
     │  enp171s0.30    192.168.30.1/24     │
     └─────────────┬───────────────────────┘
                   │ trunk 802.1Q (puerto 24)
                   │ VLANs 10, 20, 30, 40
     ┌─────────────┴───────────────────────┐
     │  SW-CORE-BONGO — L2 puro            │
     │  SVI VLAN10: 192.168.10.2/24        │
     │  (solo para gestión del switch)     │
     ├─────────────────────────────────────┤
     │  gi1/0/1   access VLAN20  (libre)   │
     │  gi1/0/2   access VLAN20  (RPi)     │
     │  gi1/0/3   access VLAN10  (radio)   │
     │  gi1/0/4   trunk VLAN20,30  (AP)    │
     │  gi1/0/24  trunk VLANs 10-40 (uplink Mini PC) │
     └─────────────────────────────────────┘
```

El switch solo mueve tramas Ethernet. Todo el routing, firewall, NAT y DHCP pasa siempre por el Mini PC.

---

## Configuración correcta completa (referencia)

```
configure terminal

hostname SW-CORE-BONGO

username admin password Cisco123! privilege 15
enable password Cisco123!

no ip http server
no ip http secure-server

ip telnet server
line telnet
 exec-timeout 30
exit

! VLANs
vlan 10,20,30,40
exit

! SVI solo para gestión del switch
interface vlan 10
 ip address 192.168.10.2 255.255.255.0
 no shutdown
exit

! Sin routing L3 — switch L2 puro
no ip routing
ip default-gateway 192.168.10.1

! Spanning Tree
spanning-tree mode rstp

! Puerto 1: libre (era MiniPC, ahora Mini PC conecta por puerto 24)
interface gi1/0/1
 switchport mode access
 switchport access vlan 20
 spanning-tree portfast
exit

! Puerto 2: Raspberry Pi
interface gi1/0/2
 switchport mode access
 switchport access vlan 20
 spanning-tree portfast
exit

! Puerto 3: Radio enlace 900MHz
interface gi1/0/3
 switchport mode access
 switchport access vlan 10
exit

! Puerto 4: Access Point (trunk VLAN30 para clientes WiFi)
interface gi1/0/4
 switchport mode trunk
 switchport trunk allowed vlan 20,30
exit

! Puerto 24: Uplink al Mini PC (router)
interface gi1/0/24
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30,40
exit

clock timezone "COT" -5
end

write memory
```

---

## Cómo acceder al switch para aplicar los cambios

```bash
# Desde cualquier equipo en la misma red, vía Telnet
telnet 192.168.10.2

# Credenciales
Usuario:    cisco
Contraseña: cisco
Enable:     Cisco123!
```
