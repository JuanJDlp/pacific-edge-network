# Estado actual de la red — Pacific Edge Network

**Fecha:** 2026-05-08  
**Proyecto:** Red Comunitaria Cerrito Bongo & Cocalito — Universidad ICESI

---

## Diagrama de la red

```
Internet
    │
[Router externo / Starlink]
    │  172.16.0.1  (gateway WAN actual)
    │
┌───────────────────────────────────────────────────────┐
│  MINI PC — Ubuntu Server 24.04  (router + DHCP + NAT) │
│                                                       │
│  enp170s0  (WAN)  →  172.16.0.11/16  (DHCP dinámico) │
│  enp171s0  (LAN)  →  trunk 802.1Q   [sin cable aún]  │
│    ├── enp171s0.10  →  192.168.10.1/24  (VLAN 10)    │
│    ├── enp171s0.20  →  192.168.20.1/24  (VLAN 20)    │
│    └── enp171s0.30  →  192.168.30.1/24  (VLAN 30)    │
│  wt0  (Netbird VPN)  →  100.90.95.134/16             │
└───────────────────────────────────────────────────────┘
         │ (pendiente: cable físico al switch L2)
    [Switch L2 802.1Q]
         ├── VLAN 10 — Gestión
         ├── VLAN 20 — Servidores / Raspberry Pi
         └── VLAN 30 — Clientes WiFi / Access Point

[Raspberry Pi]  →  192.168.20.10/24  (IP estática — VLAN 20, por configurar)
[Access Point]  →  clientes en 192.168.30.0/24  (por configurar)
```

---

## Mini PC — Direccionamiento completo

| Interfaz | Rol | IP / Prefijo | Estado |
|----------|-----|-------------|--------|
| `enp170s0` | WAN (hacia Starlink) | `172.16.0.11/16` (DHCP) | **UP** |
| `enp171s0` | LAN trunk 802.1Q | sin IP | DOWN — sin cable al switch |
| `enp171s0.10` | Gateway VLAN 10 | `192.168.10.1/24` | LOWERLAYERDOWN* |
| `enp171s0.20` | Gateway VLAN 20 | `192.168.20.1/24` | LOWERLAYERDOWN* |
| `enp171s0.30` | Gateway VLAN 30 | `192.168.30.1/24` | LOWERLAYERDOWN* |
| `wt0` | Netbird VPN (gestión) | `100.90.95.134/16` | **UP** |

> *LOWERLAYERDOWN = la interfaz está configurada con su IP pero sin carrier porque `enp171s0` no tiene cable físico al switch. Las IPs se activarán automáticamente al conectar el cable.

### IPv6 (ULA — configurado, esperando carrier)

| Interfaz | Prefijo IPv6 |
|----------|-------------|
| `enp171s0.10` | `fd00:0:0:10::1/64` |
| `enp171s0.20` | `fd00:0:0:20::1/64` |
| `enp171s0.30` | `fd00:0:0:30::1/64` |

---

## Tabla de routing actual

| Destino | Gateway | Interfaz | Origen |
|---------|---------|----------|--------|
| `0.0.0.0/0` (default) | `172.16.0.1` | `enp170s0` | DHCP |
| `172.16.0.0/16` | — | `enp170s0` | kernel |
| `100.90.0.0/16` | — | `wt0` | kernel |
| `192.168.10.0/24` | — | `enp171s0.10` | kernel (linkdown) |
| `192.168.20.0/24` | — | `enp171s0.20` | kernel (linkdown) |
| `192.168.30.0/24` | — | `enp171s0.30` | kernel (linkdown) |

---

## Servidor DHCP — Kea DHCPv4 v2.4.1

**Servicio:** `kea-dhcp4-server` — `active (running)` — habilitado en boot  
**Puerto:** UDP 67 — escuchando en todas las interfaces activas  
**Config:** `/etc/kea/kea-dhcp4.conf`  
**Leases:** `/var/lib/kea/kea-leases4.csv`  
**Logs:** `/var/log/kea/kea-dhcp4.log`

### Subredes configuradas

| VLAN | Subred | Pool de IPs | Gateway | DNS |
|------|--------|-------------|---------|-----|
| VLAN 10 — Gestión | `192.168.10.0/24` | `.50` → `.99` | `192.168.10.1` | `192.168.10.1` |
| VLAN 20 — Servidores | `192.168.20.0/24` | `.50` → `.99` | `192.168.20.1` | `192.168.10.1` |
| VLAN 30 — Clientes WiFi | `192.168.30.0/24` | `.100` → `.200` | `192.168.30.1` | `192.168.10.1` |

**Dominio de búsqueda:** `comunitaria.local`  
**Tiempos de lease:** válido 4000 s · T1 1000 s · T2 2000 s

> El DNS `192.168.10.1` es la IP futura de Pi-hole. El servidor DHCP entrega esa IP a todos los clientes desde ahora.

---

## Router — Servicios activos

| Servicio | Estado | Habilitado boot | Función |
|----------|--------|----------------|---------|
| `nftables` | **active** | sí | Firewall + NAT44 + DNS redirect |
| `jool-nat64` | **active** | sí | NAT64 con prefijo `64:ff9b::/96` |
| `kea-dhcp4-server` | **active** | sí | DHCP para VLANs 10/20/30 |

### Resumen de reglas nftables

| Origen | Destino | Acción |
|--------|---------|--------|
| Cualquier VLAN | WAN (`enp170s0`) | **FORWARD + NAT44** |
| VLAN 30 (clientes) | VLAN 20 (servidores) | **FORWARD permitido** |
| VLAN 20 (servidores) | VLAN 30 (clientes) | **BLOQUEADO** |
| LAN → puerto 53 | cualquier IP | **DNAT → `192.168.10.1:53`** (DNS forzado) |
| `wt0` (Netbird) | Mini PC | Siempre permitido |

**IP Forwarding:** IPv4 = 1 · IPv6 = 1 (persistente vía sysctl)

---

## Dispositivos planificados (pendiente de conectar)

| Dispositivo | IP | VLAN | Estado |
|-------------|-----|------|--------|
| Raspberry Pi | `192.168.20.10` (estática) | VLAN 20 | Por configurar |
| Access Point | DHCP → `192.168.30.x` | VLAN 30 | Por conectar |
| Pi-hole (DNS) | `192.168.10.1` | VLAN 10 | Por instalar |

---

## Cómo conectarse al Mini PC

```bash
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134
```

## Cómo re-ejecutar los playbooks

```bash
# Router + NAT + Firewall + Jool
cd minipc/router-setup/
ansible-playbook -i inventory.ini playbook.yml

# Servidor DHCP (Kea)
cd dhcp/dhcp4_role/provision/
ansible-playbook -i ../inventory.yml dhcp4.yml
```
