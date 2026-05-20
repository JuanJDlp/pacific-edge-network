# Pacific Edge Network

> ## ⛔ REGLA IRROMPIBLE — TVWS
>
> **La verdad absoluta sobre lo que se puede y no se puede hacer en los equipos TVWS (Innonet) está en `networkDevices/tvws_AP/official_doc/TVWS_Korean.pdf`.** Cualquier acción, configuración o recomendación sobre los TVWS DEBE alinearse exactamente con ese documento. Si algo no está en el PDF, no se hace.
>
> En particular, y sin excepciones:
> - **NO cambiar las direcciones IP de las interfaces del TVWS.** El MASTER es `192.168.100.1/24` (LAN) y el SLAVE queda en `192.168.1.1/24` tras el cambio de modo. Estas IPs son las únicas válidas para administración; modificarlas rompe el acceso y el procedimiento documentado.
> - El orden de configuración es **primero MASTER, luego SLAVE**.
> - Acceso web: puerto **8800** (`http://192.168.100.1:8800` para MASTER, `http://192.168.1.1:8800` para SLAVE). Credenciales: `root` / `innonet160905`.
> - Parámetros de RF documentados (laboratorio 1:1): `Mode` MASTER/SLAVE, `Bandwidth` 6 MHz, `Channel` 31 (575 MHz), `TxPower` 14 dBm, mismo `SSID` en ambos extremos.
> - Tras `Save & Apply` en el SLAVE, ejecutar `System → Reboot`.
>
> Antes de tocar cualquier TVWS, **consultar el PDF**. Esta regla prevalece sobre cualquier otra instrucción de este `CLAUDE.md` o del repo.


Red comunitaria de borde (Pacific Edge) desplegada con un Mini PC como router/servicios y una Raspberry Pi como servidor de contenido offline, interconectados por un switch capa 2 con VLANs. La salida a Internet la provee un router externo conectado al Mini PC.

## Topología física

```
                Internet
                   │
         ┌─────────┴──────────┐
         │  Router externo    │   (uplink WAN, red 172.16.0.0/16)
         └─────────┬──────────┘
                   │
                   │ enp170s0 (172.16.0.11/16) ── WAN del Mini PC
         ┌─────────┴──────────┐
         │     Mini PC        │   AZW EQ · Ubuntu 24.04 · hostname: plataformas
         │ (DHCP/DNS/Router/  │   NetBird: 100.90.95.134
         │  NAT/Captive)      │
         └─────────┬──────────┘
                   │ enp171s0 (trunk 802.1Q, VLAN 10/20/30)
                   │
         ┌─────────┴──────────┐
         │ Switch L2 (Cisco)  │  Puerto 24 ── Mini PC (trunk)
         │ SG350X-24 / 2960   │  Puerto  1 ── Raspberry Pi
         │                    │  Puerto  4 ── TVWS Master AP
         └────────┬──┬──┬─────┘
                  │  │  │
        Puerto 1  │  │  │  Puerto 4
       ┌──────────┘  │  └──────────┐
       │             │             │
 ┌─────┴──────┐      │       ┌─────┴──────┐
 │ Raspberry  │      │       │ TVWS AP    │
 │ akasicom2  │      │       │ (Innonet)  │
 │ 100.90.81. │      │       │            │
 │   168      │      │       └────────────┘
 └────────────┘      │
                  Otros puertos de acceso (clientes VLAN 10/20/30)
```

### Mapeo de puertos del switch L2

| Puerto | Dispositivo            | Modo               |
|--------|------------------------|--------------------|
| 1      | Raspberry Pi (akasicom2) | Acceso (VLAN 20 — Servidores) |
| 4      | TVWS Master AP (Innonet) | Acceso             |
| 24     | Mini PC (plataformas)  | Trunk 802.1Q (VLAN 10/20/30) |

Documentación de switches y AP TVWS: `networkDevices/`
- `networkDevices/SwitchCerritoBongo/` — configs Cisco SG350X-24 y Catalyst 2960 + `revision-config.md`.
- `networkDevices/SwitchCocalito/` — config y readme del switch del nodo Cocalito.
- `networkDevices/tvws_AP/` — guías Innonet TVWS (`TVWS-MASTER-AP-INSTALACION.md`, `Innonet_TVWS_Korean.md`, `official_doc/`, `UI_Mapped_TVWS/`).

## Direccionamiento IP

WAN (uplink hacia router de Internet)
- `enp170s0` del Mini PC: `172.16.0.11/16`, gateway `172.16.0.1`.

LAN (Mini PC como router, sub-interfaces 802.1Q sobre `enp171s0`)
- VLAN 10 — `enp171s0.10` — `192.168.10.0/24`, gw `192.168.10.1` (gestión/management).
- VLAN 20 — `enp171s0.20` — `192.168.20.0/24`, gw `192.168.20.1` (servidores; RPi en `192.168.20.10`).
- VLAN 30 — `enp171s0.30` — `192.168.30.0/24`, gw `192.168.30.1` (clientes con portal cautivo).

DNS autoritativo: Bind9 en el Mini PC, dominio `biblioteca.local`, escucha en `192.168.10.1:53`, `192.168.20.1:53`, `192.168.30.1:53`. DNS secundario (zone slave) en la RPi `192.168.20.10`.

Overlay NetBird (`wt0`)
- Mini PC: `100.90.95.134/16`
- Raspberry: `100.90.81.168/16`

## Mini PC — `plataformas` (100.90.95.134)

Rol: **router de borde** + DHCP + DNS + NAT + portal cautivo + NTP + monitoreo.

Acceso: `ssh -i ~/.ssh/id_ed25519_ladrilleros user@100.90.95.134`

Servicios activos (systemd):
- `named.service` — DNS Bind9 (`biblioteca.local`), escucha en las tres VLANs (`:53`). Rol Ansible: `minipc/router-setup/roles/dns/`. Docs: `minipc/services/DNS-BIND9.md`.
- `kea-dhcp4-server.service` — DHCP IPv4 (Kea), sirve las 3 VLANs. Config: `/etc/kea/kea-dhcp4.conf`. Rol Ansible: `minipc/router-setup/roles/dhcp/`. Docs: `minipc/services/DHCP-KEA.md`.
- `captive-portal.service` (nginx en `:2050`) y `captive-accept.service` (handler en `127.0.0.1:2051`) — portal cautivo VLAN 30. Rol: `minipc/router-setup/roles/captive_portal/`. Docs: `minipc/services/CAPTIVE-PORTAL.md`, `minipc/services/portalCautivo/`.
- `nginx.service` (`:8888`) — proxy HTTP intermediario que reenvía tráfico autorizado de VLAN 30 hacia Squid en la RPi. Rol: `minipc/router-setup/roles/captive_portal/`. Docs: `minipc/services/HTTP-PROXY-NGINX.md`.
- `chrony.service` — servidor NTP para las VLANs internas. Rol: `minipc/router-setup/roles/ntp/`. Docs: `minipc/services/NTP-CHRONY.md`.
- `prometheus.service` + `grafana-server.service` + `node_exporter.service` (`:9100`) — monitoreo. Rol: `minipc/router-setup/roles/monitoring/`. Docs: `minipc/services/MONITORING.md`.
- `netbird.service` — cliente de la malla NetBird (interfaz `wt0`).
- `ssh.service`, utilidades estándar.

Routing / NAT (nftables, tabla `ip nat`):
- `postrouting`: `masquerade` saliendo por `enp170s0` (NAT hacia Internet).
- `prerouting`:
  - DNAT DNS (UDP/TCP 53) desde VLANs hacia `192.168.10.1:53` (Bind9).
  - VLAN 30 sin marca `0x1`: HTTP redirigido al portal cautivo `192.168.30.1:2050`.
  - VLAN 30 con marca `0x1` (autenticados): HTTP redirigido al proxy nginx `192.168.30.1:8888` → Squid `192.168.20.10:3128`.
- `net.ipv4.ip_forward = 1`.

Ansible para el Mini PC: `minipc/router-setup/` (`playbook.yml`, `inventory.ini`, `roles/`).
Estado operativo: `DOCS/minipc/ESTADO-ACTUAL.md` (snapshot) · `DOCS/red/ESTADO_ACTUAL_RED.md` (actualizado).

## Raspberry Pi — `akasicom2` (100.90.81.168 / 192.168.20.10)

Rol: **servidor de contenido offline** (educación, media, proxy/cache, DNS secundario).

Acceso: `ssh akasicom@100.90.81.168` (usuario `akasicom`).

Hardware/SO: Raspberry Pi (arm64), Ubuntu 24.04, kernel `6.8.0-1053-raspi`.

Servicios activos (systemd):
- `nginx.service` — reverse proxy en `:80`, enruta hacia Kolibri/Kiwix/Jellyfin. Rol: `raspberry/rpi-setup/roles/nginx/`. Docs: `raspberry/services/NGINX.md`.
- `squid.service` — proxy web (`:3128` público, `127.0.0.1:3129` interno). Destino del proxy HTTP del Mini PC. Rol: `raspberry/rpi-setup/roles/squid/`. Docs: `raspberry/services/SQUID.md`.
- `kiwix-serve.service` — Biblioteca offline Kiwix (`127.0.0.1:8080`). Rol: `raspberry/rpi-setup/roles/kiwix/`. Docs: `raspberry/services/KIWIX.md`.
- `kolibri.service` — plataforma educativa Kolibri (`127.0.0.1:8090`). Rol: `raspberry/rpi-setup/roles/kolibri/`. Docs: `raspberry/services/KOLIBRI.md`.
- `jellyfin.service` — servidor de medios Jellyfin (`127.0.0.1:8096`). Rol: `raspberry/rpi-setup/roles/jellyfin/`. Docs: `raspberry/services/JELLYFIN.md`.
- `named.service` — DNS Bind9 secundario (zone slave de `biblioteca.local` desde `192.168.10.1`). Rol: `raspberry/rpi-setup/roles/dns_secondary/`. Docs: `raspberry/services/DNS-SECUNDARIO.md`.
- `node_exporter.service` — métricas Prometheus. Rol: `raspberry/rpi-setup/roles/node_exporter/`. Docs: `raspberry/services/NODE-EXPORTER.md`.
- `netbird.service` — cliente NetBird (`100.90.81.168`).
- `avahi-daemon`, `ssh`, etc.

Ansible para la RPi: `raspberry/rpi-setup/` (`playbook.yml`, `inventory.ini`, `group_vars/all.yml`, `roles/`).

## TVWS Master AP

Punto de acceso TVWS (Innonet) conectado al **puerto 4** del switch L2. Toda la guía de instalación y configuración como AP maestro está en `networkDevices/tvws_AP/`:
- `TVWS-MASTER-AP-INSTALACION.md` — procedimiento de despliegue.
- `Innonet_TVWS_Korean.md` — notas del firmware/UI original.
- `official_doc/TVWS_Korean.pdf` — documento oficial de referencia (fuente de verdad).
- `UI_Mapped_TVWS/` — mapeo completo de la UI (Network, Services, Status, System).

## Estructura del repositorio

```
.
├── DOCS/                             # Toda la documentación operativa
│   ├── minipc/
│   │   ├── ESTADO-ACTUAL.md          # Estado del Mini PC (snapshot 2026-05-08)
│   │   ├── CAPTIVE-PORTAL.md         # Portal cautivo (arquitectura actual)
│   │   ├── DHCP-KEA.md
│   │   ├── DNS-BIND9.md
│   │   ├── HTTP-PROXY-NGINX.md       # Intermediario nginx → Squid (fix SO_ORIGINAL_DST)
│   │   ├── MONITORING.md
│   │   ├── NTP-CHRONY.md
│   │   └── portalCautivo/
│   │       ├── PLAN-CONECTIVIDAD-MINIPC-RPI.md
│   │       └── PORTAL-LEGACY.md      # Arquitectura antigua (histórico)
│   ├── raspberry/
│   │   ├── DNS-SECUNDARIO.md
│   │   ├── JELLYFIN.md
│   │   ├── KIWIX.md
│   │   ├── KOLIBRI.md
│   │   ├── NGINX.md
│   │   ├── NODE-EXPORTER.md
│   │   └── SQUID.md
│   └── red/
│       ├── CREDENCIALES-SSH.md       # Credenciales y accesos SSH
│       └── ESTADO_ACTUAL_RED.md      # Estado general de la red (más actualizado)
├── minipc/
│   ├── router-setup/                 # Ansible: setup completo del Mini PC
│   │   ├── playbook.yml              # Playbook principal (6 roles, todos los servicios)
│   │   ├── inventory.ini             # Inventario (Mini PC vía NetBird)
│   │   └── roles/
│   │       ├── router/               # VLANs, nftables, NAT, ip_forward
│   │       ├── dns/                  # Bind9, dominio biblioteca.local
│   │       ├── dhcp/                 # Kea DHCPv4 (README con notas operativas)
│   │       ├── captive_portal/       # Portal cautivo + nginx HTTP proxy
│   │       ├── ntp/                  # Chrony como servidor NTP
│   │       └── monitoring/           # Prometheus + Grafana + node_exporter
│   ├── ansible.cfg                   # roles_path = router-setup/roles (ejecutar desde minipc/)
│   └── services/                     # Playbooks individuales por servicio
│       ├── router.yml                # cd minipc/ && ansible-playbook -i router-setup/inventory.ini services/router.yml
│       ├── dns.yml
│       ├── dhcp.yml
│       ├── captive_portal.yml
│       ├── ntp.yml
│       └── monitoring.yml
├── raspberry/
│   ├── ansible.cfg                   # roles_path = rpi-setup/roles (ejecutar desde raspberry/)
│   ├── rpi-setup/                    # Ansible: setup completo de la RPi
│   │   ├── playbook.yml              # Playbook principal (7 roles, todos los servicios)
│   │   ├── inventory.ini
│   │   ├── group_vars/all.yml        # Variables compartidas (IPs, puertos, dominio)
│   │   └── roles/
│   │       ├── nginx/                # Reverse proxy (:80)
│   │       ├── squid/                # Proxy web (:3128/:3129)
│   │       ├── kiwix/                # Biblioteca Kiwix (:8080)
│   │       ├── kolibri/              # Kolibri educativo (:8090)
│   │       ├── jellyfin/             # Jellyfin medios (:8096)
│   │       ├── dns_secondary/        # Bind9 slave de biblioteca.local
│   │       └── node_exporter/        # Métricas Prometheus
│   └── services/                     # Playbooks individuales por servicio
│       ├── nginx.yml                 # cd raspberry/ && ansible-playbook -i rpi-setup/inventory.ini services/nginx.yml
│       ├── squid.yml
│       ├── kiwix.yml
│       ├── kolibri.yml
│       ├── jellyfin.yml
│       ├── node_exporter.yml
│       └── dns_secondary.yml
├── networkDevices/
│   ├── SwitchCerritoBongo/           # Cisco SG350X-24 / Catalyst 2960
│   ├── SwitchCocalito/               # Switch nodo Cocalito
│   └── tvws_AP/                      # Innonet TVWS Master AP
│       ├── TVWS-MASTER-AP-INSTALACION.md
│       ├── Innonet_TVWS_Korean.md
│       ├── official_doc/TVWS_Korean.pdf
│       └── UI_Mapped_TVWS/           # Network, Services, Status, System
```

## Accesos SSH (resumen)

- Raspberry Pi: `ssh akasicom@100.90.81.168`
- Mini PC:      `ssh -i ~/.ssh/id_ed25519_ladrilleros user@100.90.95.134`

Detalles y demás credenciales en `DOCS/red/CREDENCIALES-SSH.md`. Estado operativo de la red en `DOCS/red/ESTADO_ACTUAL_RED.md`.
