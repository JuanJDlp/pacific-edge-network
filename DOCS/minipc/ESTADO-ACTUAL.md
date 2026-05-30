# Estado actual del Mini PC — Router de red comunitaria

> Snapshot al **2026-05-30**. Estado operativo general de la red en `DOCS/red/ESTADO_ACTUAL_RED.md`.

**Host:** `plataformas` / `100.90.95.134` (NetBird VPN)
**SO:** Ubuntu Server 24.04.4 LTS, kernel `6.8.0-111-generic`
**Usuario Ansible:** `user` (sudo sin contrasena configurado)

---

## Servicios activos

| Servicio | Puerto | Version | Estado systemd | Notas |
|----------|--------|---------|----------------|-------|
| Bind9 (DNS) | 53 (VLANs 10/20/30) | 9.18.39 | `active` (enabled) | Autoritativo `biblioteca.tel` + forwarding |
| Kea DHCPv4 | 67/68 | 2.4.1 | `active` (enabled) | Sirve VLANs 10/20/30 |
| nginx | 80, 2050 (SSL), 8888 | — | `active` (enabled) | Portal cautivo (splash) + HTTP proxy a Squid |
| captive-accept.py | 2051 | — | `active` (enabled) | Handler POST del portal cautivo |
| ~~captive-portal.service~~ | ~~2050~~ | — | **disabled** | Deshabilitado por conflicto de puerto; nginx.service maneja todo |
| Chrony (NTP) | 123 | — | `active` (enabled) | Sincronizado a `0.co.ntp.edgeuno.com`, stratum 3 |
| Prometheus | 9090 | — | `active` (enabled) | Scraping minipc, rpi, switch |
| Grafana | 3000 | 13.0.1 | `active` (enabled) | `monitoreo.biblioteca.tel` |
| node_exporter | 9100 | — | `active` (enabled) | Metricas del Mini PC |
| snmp_exporter | 9116 | — | `active` (enabled) | Scraping SNMP del switch 192.168.10.2 |
| radvd | — | — | `active` (enabled) | SLAAC IPv6 fd00:0:0:{10,20,30}::/64 |
| nftables | — | — | `active` (enabled) | inet filter + ip nat |
| NetBird | wt0 | — | `active` (enabled) | Overlay VPN, 100.90.95.134 |
| Docker | — | — | instalado (idle) | Instalado pero sin contenedores activos |
| ssh | 22 | — | `active` (enabled) | — |

---

## Interfaces de red

| Interfaz | IP IPv4 | IP IPv6 | Estado | Rol |
|----------|---------|---------|--------|-----|
| `enp170s0` | `172.16.0.11/16` | fe80::... | UP | WAN — hacia router externo |
| `enp171s0` | — | — | UP | LAN — trunk 802.1Q hacia switch |
| `enp171s0.10` | `192.168.10.1/24` | `fd00:0:0:10::1/64` | UP | VLAN10 — Gestion |
| `enp171s0.20` | `192.168.20.1/24` | `fd00:0:0:20::1/64` | UP | VLAN20 — Servidores / RPi |
| `enp171s0.30` | `192.168.30.1/24` | `fd00:0:0:30::1/64` | UP | VLAN30 — Clientes WiFi |
| `wt0` | `100.90.95.134/16` | — | UP | NetBird VPN (gestion remota) |

---

## IP Forwarding

| Parametro | Valor |
|-----------|-------|
| `net.ipv4.ip_forward` | `1` |
| `net.ipv6.conf.all.forwarding` | `1` |

## IPv6 — radvd

radvd esta activo y anuncia prefijos SLAAC en las tres VLANs:

- VLAN10: `fd00:0:0:10::/64`
- VLAN20: `fd00:0:0:20::/64`
- VLAN30: `fd00:0:0:30::/64`

---

## Firewall — nftables

Reglas activas en `/etc/nftables.conf`:

```
table inet filter
  chain input      -> policy DROP
  chain forward    -> policy DROP
  chain output     -> policy ACCEPT
  set captive_allowed_mac { type ether_addr; flags dynamic,timeout; timeout 8h }

table ip nat
  chain prerouting  -> DNAT DNS -> 192.168.10.1:53
                    -> Captive redirect (VLAN30 sin marca) -> 192.168.30.1:2050 (HTTP+HTTPS)
                    -> HTTP proxy (VLAN30 con marca 0x1) -> 192.168.30.1:8888 -> Squid RPi
                    -> HTTPS autenticado: SIN DNAT (pasa directo a WAN);
                       filtrado porn/gambling via Bind9 RPZ (rpz.blocklist)
  chain postrouting -> MASQUERADE en enp170s0 (NAT44)
```

**Reglas de forwarding:**
- VLAN10/20/30 -> WAN (`enp170s0`): **PERMITIDO**
- VLAN30 (clientes) -> VLAN20 (servidores): **PERMITIDO**
- VLAN20 -> VLAN30: **BLOQUEADO** (policy drop)
- NetBird (`wt0`): **SIEMPRE PERMITIDO** (gestion segura)

**DNS forzado:** Todo trafico al puerto 53 desde las VLANs es redirigido a `192.168.10.1:53` (Bind9).

---

## Persistencia tras reboot

| Componente | Mecanismo de persistencia |
|------------|--------------------------|
| IP Forwarding | `/etc/sysctl.d/` |
| Netplan / interfaces VLAN | `/etc/netplan/00-router.yaml` |
| nftables | Servicio systemd `nftables` enabled |
| radvd | Servicio systemd `radvd` enabled |

---

## Ansible

Playbook: `minipc/router-setup/playbook.yml`
Inventario: `minipc/router-setup/inventory.ini`
Roles: `router`, `dns`, `dhcp`, `captive_portal`, `ntp`, `monitoring`

```bash
# Conectarse al Mini PC
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134

# Re-ejecutar playbook completo
cd minipc/ && ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml

# Solo verificaciones
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags verify
```

---

## Comandos utiles para verificar estado

```bash
# Ver interfaces
ip addr show

# Ver reglas nftables activas
sudo nft list ruleset

# Estado de todos los servicios clave
systemctl status named kea-dhcp4-server nginx captive-accept chrony prometheus grafana-server radvd

# Ver clientes DHCP activos
cat /var/lib/kea/kea-leases4.csv

# Ver clientes autorizados en portal cautivo
sudo nft list set inet filter captive_allowed_mac
```
