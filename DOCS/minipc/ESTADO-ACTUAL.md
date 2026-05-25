# Estado actual del Mini PC — Router de red comunitaria

> ⚠️ Este documento refleja el estado al **2026-05-08** (solo rol `router` desplegado, VLANs sin cable). El estado completo y actualizado está en `DOCS/red/ESTADO_ACTUAL_RED.md`. El playbook actual despliega 6 roles: `router`, `dns`, `dhcp`, `captive_portal`, `ntp`, `monitoring`.

**Fecha de configuración:** 2026-05-08  
**Host:** `100.90.95.134` (Netbird/Tailscale VPN)  
**SO:** Ubuntu Server 24.04.4 LTS  
**Usuario Ansible:** `user` (sudo sin contraseña configurado)

---

## Qué hace el playbook

El playbook `playbook.yml` configura el Mini PC como router interno de una red comunitaria en dos plays:

### Play 1 — Configuración del router (`roles/router`)

| Paso | Qué hace | Módulo Ansible |
|------|----------|---------------|
| 1 | Valida que las interfaces WAN y LAN existen en el host | `assert` |
| 2 | Instala `nftables`, `netplan.io`, `linux-headers` | `apt` |
| 3 | Habilita el repositorio `universe` de Ubuntu e instala `jool-dkms` + `jool-tools` | `apt_repository`, `apt` |
| 4 | Activa `net.ipv4.ip_forward` y `net.ipv6.conf.all.forwarding` de forma persistente | `sysctl` |
| 5 | Hace backup de todos los archivos netplan existentes en `/etc/netplan/backups/` | `shell` |
| 6 | Elimina el config por defecto de cloud-init (`50-cloud-init.yaml`) | `file` |
| 7 | Despliega `/etc/netplan/00-router.yaml` desde template Jinja2 y aplica netplan | `template` + handler |
| 8 | Despliega `/etc/nftables.conf` desde template Jinja2 con validación `nft -c` | `template` + handler |
| 9 | Habilita y arranca el servicio `nftables` | `service` |
| 10 | Carga el módulo del kernel `jool` | `command` |
| 11 | Despliega el unit systemd `/etc/systemd/system/jool-nat64.service` | `template` |
| 12 | Habilita y arranca el servicio `jool-nat64` | `systemd` |
| 13 | Crea `/etc/modules-load.d/jool.conf` para cargar el módulo en cada boot | `copy` |
| 14 | Assertions finales: ip_forward=1, VLAN20 existe, nftables tiene reglas | `assert`, `slurp`, `command` |

### Play 2 — Verificación (`--tags verify`)

Corre pruebas automáticas y reporta el estado:
- Ping al router externo y a internet (8.8.8.8)
- Ping inter-VLAN (VLAN30 → VLAN20)
- Verificación de ip_forward
- Verificación de rutas VLAN en tabla de routing
- Verificación de reglas nftables en chain `forward`
- Verificación de módulo Jool cargado
- Verificación de instancia NAT64 y prefijo `64:ff9b::/96`

---

## Estado actual del Mini PC

### Interfaces de red

| Interfaz | IP IPv4 | IP IPv6 | Estado | Rol |
|----------|---------|---------|--------|-----|
| `enp170s0` | `172.16.0.11/16` (DHCP) | fe80::... | UP | WAN — hacia router Starlink |
| `enp171s0` | — | — | DOWN (sin cable) | LAN — trunk 802.1Q hacia switch |
| `enp171s0.10` | `192.168.10.1/24` | `fd00:0:0:10::1/64` | LOWERLAYERDOWN | VLAN10 — Gestión |
| `enp171s0.20` | `192.168.20.1/24` | `fd00:0:0:20::1/64` | LOWERLAYERDOWN | VLAN20 — Servidores / RPi |
| `enp171s0.30` | `192.168.30.1/24` | `fd00:0:0:30::1/64` | LOWERLAYERDOWN | VLAN30 — Clientes WiFi |
| `wt0` | `100.90.95.134/16` | — | UP | Netbird VPN (gestión remota) |

> Las interfaces VLAN están en `LOWERLAYERDOWN` porque `enp171s0` aún no tiene cable conectado al switch L2. Las IPs ya están asignadas y los servicios configurados — se activarán al conectar el cable.

### IP Forwarding

| Parámetro | Valor |
|-----------|-------|
| `net.ipv4.ip_forward` | `1` ✓ |
| `net.ipv6.conf.all.forwarding` | `1` ✓ |

### Firewall — nftables

Reglas activas en `/etc/nftables.conf`:

```
table inet filter
  chain input      → policy DROP
  chain forward    → policy DROP
  chain output     → policy ACCEPT

table ip nat
  chain prerouting  → DNAT DNS → 192.168.10.1:53
  chain postrouting → MASQUERADE en enp170s0 (NAT44)
```

**Reglas de forwarding:**
- VLAN10/20/30 → WAN (`enp170s0`): **PERMITIDO**
- VLAN30 (clientes) → VLAN20 (servidores): **PERMITIDO**
- VLAN20 → VLAN30: **BLOQUEADO** (policy drop)
- Tailscale (`wt0`): **SIEMPRE PERMITIDO** (gestión segura)

**DNS forzado:** Todo tráfico al puerto 53 desde las VLANs es redirigido a `192.168.10.1:53` (preparado para Pi-hole).

### NAT64 — Jool

| Item | Estado |
|------|--------|
| Módulo kernel `jool` | Cargado ✓ |
| Instancia NAT64 | `default` (netfilter) ✓ |
| Prefijo pool6 | `64:ff9b::/96` ✓ |
| Servicio systemd `jool-nat64` | `enabled` + `active` ✓ |
| Carga en boot | `/etc/modules-load.d/jool.conf` ✓ |

### Persistencia tras reboot

| Componente | Mecanismo de persistencia |
|------------|--------------------------|
| IP Forwarding | `/etc/sysctl.d/` (sysctl module) |
| Netplan / interfaces VLAN | `/etc/netplan/00-router.yaml` |
| nftables | Servicio systemd `nftables` enabled |
| Jool NAT64 | Servicio systemd `jool-nat64` enabled + `/etc/modules-load.d/jool.conf` |

---

## Pendiente

| Tarea | Descripción |
|-------|-------------|
| Conectar cable al switch | `enp171s0` necesita cable físico para que las VLANs pasen a estado UP |
| ~~Instalar Pi-hole~~ | ✅ Rol `pihole` creado — listo para desplegar con `--tags pihole` |
| ~~Firewall mejorado~~ | ✅ Rol `firewall` creado — reemplaza nftables básico con rate limiting y aislamiento VLAN |
| Cambiar contraseña Pi-hole | Editar `roles/pihole/vars/main.yml` → `pihole_web_password` antes del primer despliegue |
| Verificar conectividad WAN completa | El router externo parece estar en `172.16.0.1`, no `192.168.0.1` — ajustar si es necesario |

---

## Servicios configurados

| Servicio | Puerto | Rol | Estado |
|----------|--------|-----|--------|
| Bind9 (DNS local) | 5353 (tras Pi-hole) | Zonas biblioteca.local | Configurado |
| Pi-hole (DNS + bloqueo) | 53, 8080 (web) | DNS resolver con filtrado | **Listo para desplegar** |
| Kea DHCPv4 | 67/68 | Asignación IPs en 3 VLANs | Configurado |
| nginx (Portal Cautivo) | 2050 | Splash page autenticación | Configurado |
| captive-accept.py | 2051 | Backend portal cautivo | Configurado |
| nginx (HTTP Proxy) | 8888 | Intermediario → Squid RPi | Configurado |
| chrony (NTP) | 123 | Servidor de tiempo VLANs | Configurado |
| Prometheus | 9090 | Métricas (solo VLAN10) | Configurado |
| Grafana | 3000 | Dashboards (solo VLAN10) | Configurado |
| nftables (Firewall) | — | Firewall + NAT + rate limiting | **Listo para desplegar** |

---

## Comandos útiles para verificar estado

```bash
# Conectarse al Mini PC
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134

# Ver interfaces
ip addr show

# Ver reglas nftables activas
sudo nft list ruleset

# Ver instancia Jool
sudo jool instance display
sudo jool global display

# Re-ejecutar playbook completo
cd minipc/router-setup/
ansible-playbook -i inventory.ini playbook.yml

# Solo verificaciones
ansible-playbook -i inventory.ini playbook.yml --tags verify
```
