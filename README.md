# Pacific Edge Network

Red comunitaria de borde (*edge*) que ofrece acceso a contenido educativo y multimedia
**funcionando sin Internet**. Está construida sobre dos nodos —un **Mini PC** que actúa
como router y proveedor de servicios de red, y una **Raspberry Pi** que sirve el contenido
offline— interconectados por un **switch de capa 2 con VLANs**. La salida a Internet la
provee un router externo conectado al Mini PC, y un **Linksys E2500 en modo bridge** da
WiFi a los clientes.

El proyecto integra los requisitos de las asignaturas *Plataformas* e *Infraestructura*:
dual stack IPv4/IPv6, DHCP, DNS autoritativo con DNSSEC/TSIG/DNS64, proxy-cache, portal
cautivo, CDN de contenido offline, mensajería privada, NTP, monitoreo y un panel web con
buscador.

---

## Topología física

```
                Internet
                   │
         ┌─────────┴──────────┐
         │  Router externo    │   (uplink WAN, red 172.16.0.0/16)
         └─────────┬──────────┘
                   │ enp170s0 (172.16.0.11/16) ── WAN del Mini PC
         ┌─────────┴──────────┐
         │     Mini PC        │   AZW EQ · Ubuntu 24.04 · hostname: plataformas
         │ (Router · DHCP ·   │
         │  DNS · NAT ·       │
         │  Portal cautivo)   │
         └─────────┬──────────┘
                   │ enp171s0 (trunk 802.1Q, VLAN 10/20/30)
         ┌─────────┴──────────┐
         │ Switch L2 (Cisco)  │  Puerto 24 ── Mini PC (trunk)
         │ SG350X-24 / 2960   │  Puerto  1 ── Raspberry Pi (VLAN 20)
         │                    │  Puerto  4 ── Linksys E2500 (VLAN 30)
         └────────┬──┬──┬─────┘
                  │  │  │
        ┌─────────┘  │  └──────────┐
        │            │             │
 ┌──────┴─────┐      │      ┌──────┴──────┐
 │ Raspberry  │      │      │ Linksys     │
 │ Pi         │      │      │ E2500 (AP   │
 │ (contenido │      │      │ bridge)     │
 │  offline)  │      │      └──────┬──────┘
 └────────────┘      │             │
                  Otros        Clientes WiFi
                  puertos       (VLAN 30)
```

| Puerto switch | Dispositivo            | Modo                          |
|---------------|------------------------|-------------------------------|
| 1             | Raspberry Pi           | Acceso (VLAN 20 — Servidores) |
| 4             | Linksys E2500 (AP)     | Acceso (VLAN 30 — Clientes)   |
| 24            | Mini PC                | Trunk 802.1Q (VLAN 10/20/30)  |

---

## Direccionamiento

**WAN** (uplink hacia Internet): `enp170s0` → `172.16.0.11/16`, gateway `172.16.0.1`.

**LAN** (sub-interfaces 802.1Q sobre `enp171s0` del Mini PC):

| VLAN | Interfaz        | Red               | Gateway        | Uso                          |
|------|-----------------|-------------------|----------------|------------------------------|
| 10   | `enp171s0.10`   | `192.168.10.0/24` | `192.168.10.1` | Gestión / management         |
| 20   | `enp171s0.20`   | `192.168.20.0/24` | `192.168.20.1` | Servidores (RPi `.10`)       |
| 30   | `enp171s0.30`   | `192.168.30.0/24` | `192.168.30.1` | Clientes WiFi + portal cautivo |

La red opera en **dual stack**: además de IPv4 hay IPv6 con SLAAC/RDNSS (radvd) y NAT64 +
DNS64 (Jool) para alcanzar destinos IPv4 desde clientes IPv6. Detalle en
[`DOCS/red/DUAL-STACK.md`](DOCS/red/DUAL-STACK.md).

---

## Nodos y servicios

### Mini PC — router de borde

Router + DHCP + DNS + NAT + portal cautivo + NTP + monitoreo. Todo se despliega con
Ansible desde [`minipc/router-setup/`](minipc/router-setup/).

| Servicio                | Rol Ansible        | Función |
|-------------------------|--------------------|---------|
| Router / VLANs / NAT    | `router`, `firewall` | Sub-interfaces 802.1Q, `ip_forward`, NAT (nftables), routing |
| DNS (Bind9)             | `dns`              | Autoritativo de `biblioteca.tel` con DNSSEC, TSIG y DNS64 |
| Pi-hole                 | `pihole`           | Filtrado DNS (ad/track-blocking) |
| DHCPv4 (Kea)            | `dhcp`             | Leases para las 3 VLANs |
| IPv6 (radvd / NAT64)    | `radvd`, `router`  | SLAAC/RDNSS + Jool NAT64 |
| Portal cautivo          | `captive_portal`   | Splash + autenticación por MAC; proxy HTTP hacia Squid |
| NTP (Chrony)            | `ntp`              | Servidor de tiempo para las VLANs internas |
| Monitoreo               | `monitoring`       | Prometheus + Grafana + node_exporter |

### Raspberry Pi — servidor de contenido offline

Sirve el contenido educativo/multimedia y un DNS secundario. Se despliega desde
[`raspberry/rpi-setup/`](raspberry/rpi-setup/).

| Servicio        | Rol Ansible      | Función |
|-----------------|------------------|---------|
| nginx           | `nginx`          | Reverse proxy + panel web con buscador |
| Squid           | `squid`          | Proxy-cache (funciona también sin Internet) |
| Kiwix           | `kiwix`          | Biblioteca offline (Wikipedia, etc.) |
| Kolibri         | `kolibri`        | Plataforma educativa |
| Jellyfin        | `jellyfin`       | Servidor de medios / streaming |
| Matrix (Conduit)| `matrix`         | Mensajería privada |
| DNS secundario  | `dns_secondary`  | Bind9 slave de `biblioteca.tel` |
| Health-check    | `health_check`   | Indicador de estado del panel (`/status`) |
| Métricas        | `node_exporter`  | Exporter para Prometheus |
| IPv6            | `network_ipv6`   | Direccionamiento IPv6 estático |

### Switch L2 y Access Point

- **Switch Cisco** (SG350X-24 / Catalyst 2960): trunk hacia el Mini PC, accesos por VLAN.
  Configuraciones en [`networkDevices/`](networkDevices/).
- **Linksys E2500** en modo bridge: provee WiFi a los clientes de la VLAN 30. No hace
  routing ni DHCP; los clientes reciben IP del Kea DHCP del Mini PC.

---

## Estructura del repositorio

```
.
├── README.md                 Este archivo
├── DOCS/                      Documentación operativa por nodo
│   ├── minipc/                Router, DNS, DHCP, portal cautivo, NTP, monitoreo…
│   ├── raspberry/             nginx, Squid, Kiwix, Kolibri, Jellyfin, auto-update…
│   └── red/                   Estado de la red, dual stack, credenciales (interno)
├── minipc/
│   ├── router-setup/          Ansible: playbook + inventario + roles del Mini PC
│   └── services/              Playbooks individuales por servicio
├── raspberry/
│   ├── rpi-setup/             Ansible: playbook + inventario + roles de la RPi
│   └── services/              Playbooks individuales por servicio
├── networkDevices/            Configuraciones de switches Cisco y del AP
└── fixes/                     Bitácora de incidencias resueltas (postmortems)
```

---

## Despliegue

Cada nodo se configura de forma reproducible con **Ansible**. Los playbooks son
idempotentes y el del Mini PC incluye una fase de verificación que comprueba el estado
de los servicios al terminar.

```bash
# Mini PC — todos los servicios
cd minipc
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml

# Raspberry Pi — todos los servicios
cd raspberry
ansible-playbook -i rpi-setup/inventory.ini rpi-setup/playbook.yml
```

Para aplicar un solo servicio existen playbooks individuales en `minipc/services/` y
`raspberry/services/` (por ejemplo `ansible-playbook -i rpi-setup/inventory.ini services/squid.yml`).

---

## Documentación

La documentación operativa detallada vive en [`DOCS/`](DOCS/):

- **Red:** [estado actual](DOCS/red/ESTADO_ACTUAL_RED.md) · [dual stack IPv4/IPv6](DOCS/red/DUAL-STACK.md)
- **Mini PC:** [router/VLANs/NAT](DOCS/minipc/ROUTER-VLANS-NAT.md) · [DNS Bind9](DOCS/minipc/DNS-BIND9.md) · [DHCP Kea](DOCS/minipc/DHCP-KEA.md) · [portal cautivo](DOCS/minipc/CAPTIVE-PORTAL.md) · [firewall nftables](DOCS/minipc/FIREWALL-NFTABLES.md) · [NTP](DOCS/minipc/NTP-CHRONY.md) · [monitoreo](DOCS/minipc/MONITORING.md)
- **Raspberry Pi:** [nginx](DOCS/raspberry/NGINX.md) · [Squid (filtro + cache)](DOCS/raspberry/squid-filter-cache/README.md) · [Kiwix](DOCS/raspberry/KIWIX.md) · [Kolibri](DOCS/raspberry/KOLIBRI.md) · [Jellyfin](DOCS/raspberry/JELLYFIN.md) · [DNS secundario](DOCS/raspberry/DNS-SECUNDARIO.md) · [health-check](DOCS/raspberry/HEALTH-CHECK.md)

> Las credenciales de acceso se documentan en `DOCS/red/CREDENCIALES-SSH.md`. Es un
> documento interno del equipo: corresponde a un despliegue de laboratorio y las
> credenciales deben rotarse antes de cualquier uso en producción.
