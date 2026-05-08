# Resumen de sesión — Configuración Mini PC como Router + DHCP

**Fecha:** 2026-05-08  
**Host objetivo:** Mini PC en `100.90.95.134` (acceso vía Netbird VPN, interfaz `wt0`)  
**SO del Mini PC:** Ubuntu Server 24.04.4 LTS  
**Usuario:** `user` (sudo sin contraseña configurado durante la sesión)

---

## 1. Descubrimiento del entorno

Antes de crear cualquier archivo se hizo reconocimiento del Mini PC vía SSH:

| Dato | Valor real encontrado |
|------|----------------------|
| Interfaz WAN | `enp170s0` — IP `172.16.0.11/16` por DHCP (hacia Starlink/router externo) |
| Interfaz LAN | `enp171s0` — sin carrier (sin cable al switch aún) |
| Interfaz VPN | `wt0` — `100.90.95.134` (Netbird, canal de gestión remota) |
| Netplan existente | Solo `dhcp4: true` en `enp170s0`, nada más |
| Kea disponible | Paquete `kea-dhcp4-server` v2.4.1 en repo `universe` de Ubuntu 24.04 |

> Las interfaces **no son `eth0`/`eth1`** como asumía el prompt original — son `enp170s0` y `enp171s0`.

---

## 2. Parte 1 — Router (Ansible en `minipc/router-setup/`)

### Qué se construyó

Estructura completa desde cero siguiendo el plan en `prompt-nat-router.md`:

```
minipc/router-setup/
├── inventory.ini
├── playbook.yml
├── README.md
├── ESTADO-ACTUAL.md
└── roles/router/
    ├── handlers/main.yml
    ├── tasks/main.yml
    ├── templates/
    │   ├── netplan.yaml.j2
    │   ├── nftables.conf.j2
    │   └── jool-nat64.service.j2
    └── vars/main.yml
```

### Decisiones de diseño

- **Interfaz WAN** (`enp170s0`): configurada con `dhcp4: true` — ya recibe `172.16.x.x` del router externo.
- **Interfaz LAN** (`enp171s0`): trunk 802.1Q sin IP propia.
- **VLAN interfaces** creadas por Netplan con IPs estáticas IPv4 + IPv6 (ULA):

| Interfaz | IPv4 | IPv6 |
|----------|------|------|
| `enp171s0.10` | `192.168.10.1/24` | `fd00:0:0:10::1/64` |
| `enp171s0.20` | `192.168.20.1/24` | `fd00:0:0:20::1/64` |
| `enp171s0.30` | `192.168.30.1/24` | `fd00:0:0:30::1/64` |

- **`wt0` (Netbird)** protegido explícitamente en nftables con `iif wt0 accept` — para no perder acceso remoto.
- Se añadió `meta: flush_handlers` + tarea de verificación de VLAN antes de desplegar nftables (el validador `nft -c` requiere que las interfaces existan).
- Backup automático de netplan antes de cualquier cambio (`/etc/netplan/backups/`).

### Problemas encontrados y resueltos

| Problema | Causa | Solución |
|----------|-------|----------|
| `Missing sudo password` | Usuario `user` requería contraseña para sudo | Se configuró `/etc/sudoers.d/99-user-nopasswd` vía SSH una sola vez |
| PPA de Jool no existe para Ubuntu 24.04 | El PPA `ppa:ydahj/jool` solo cubre versiones anteriores | Se habilitó el repositorio `universe` de Ubuntu donde `jool-dkms` ya está disponible |
| nftables falla validación (`nft -c`) | Las interfaces VLAN no existían cuando se validaba (netplan no había aplicado aún) | Se añadió `meta: flush_handlers` + tarea explícita: "si VLAN no existe, aplicar netplan ahora" |

### Resultado del playbook

```
PLAY RECAP
minipc : ok=43   changed=6   failed=0
```

| Verificación | Resultado |
|---|---|
| `ip_forward = 1` (IPv4 e IPv6) | ✓ |
| VLAN interfaces creadas con IPs correctas | ✓ |
| Rutas de las 3 VLANs en tabla de routing | ✓ |
| nftables cargado con reglas en `forward` | ✓ |
| Módulo kernel `jool` cargado | ✓ |
| Instancia Jool NAT64 activa (`default`, netfilter) | ✓ |
| Prefijo NAT64 `64:ff9b::/96` configurado | ✓ |
| Internet alcanzable (`ping 8.8.8.8`) | ✓ |

### Reglas de firewall activas (nftables)

- `policy drop` en `input` y `forward`
- `wt0` (Netbird) siempre permitido
- Desde VLANs: SSH, DNS, DHCP, NTP, HTTP/HTTPS permitidos
- Forward VLAN → WAN: permitido (con NAT44 masquerade)
- Forward VLAN30 → VLAN20: permitido
- Forward VLAN20 → VLAN30: **bloqueado** (policy drop)
- DNS redirect: todo puerto 53 de clientes → `192.168.10.1:53` (preparado para Pi-hole)

---

## 3. Parte 2 — DHCP (Ansible en `dhcp/dhcp4_role/`)

### Qué había

Un playbook incompleto y con varios errores, escrito por otro compañero, que usa **ISC Kea** como servidor DHCP.

### Errores encontrados y corregidos

| Archivo | Problema | Corrección |
|---------|----------|------------|
| `inventory.yml` | Llave SSH apuntaba a `/home/jjarias/.ssh/id_rsa.pub` (ruta del colega, además era la clave **pública** no la privada) | Cambiado a `~/.ssh/plats_mini_pc` |
| `provision/dhcp4.yml` | Rol referenciado como `kea_dhcp4` pero el directorio se llama `dhcp4_role` — Ansible no lo encontraba y corría silenciosamente sin tareas | Creado `ansible.cfg` con `roles_path = ../..` y cambiado a `role: dhcp4_role` |
| `vars/Debian.yml` | Paquete `isc-kea*` y servicio `isc-kea-dhcp4-server` — nombres de Ubuntu 18/20, no existen en 24.04 | Corregido a `kea-dhcp4-server` (nombre correcto en Ubuntu 24.04) |
| `vars/main.yml` | Interfaz `eth0` (no existe), DNS apuntaba a `192.168.20.1`, subnets con VLAN 40 (no configurada) | Interfaz `*`, DNS `192.168.10.1`, subnets VLAN 10/20/30 |
| `tasks/configure.yml` | `validate: "kea-dhcp4 -t %s"` fallaba — AppArmor impide que el binario lea archivos temporales de Ansible cuando corre como root | Cambiado a task separado con `sudo -u _kea kea-dhcp4 -t <archivo>` |
| `provision/setup_ssh.yml` | Misma llave del colega | Corregido a `plats_mini_pc.pub` |

### Nuevo archivo creado

`dhcp/dhcp4_role/provision/ansible.cfg`:
```ini
[defaults]
roles_path = ../..        # apunta a dhcp/ para encontrar dhcp4_role/
host_key_checking = False
```

### Configuración de Kea resultante

```
Subredes gestionadas:
  VLAN10 → 192.168.10.50 - 192.168.10.99   (gestión)
  VLAN20 → 192.168.20.50 - 192.168.20.99   (servidores/RPi)
  VLAN30 → 192.168.30.100 - 192.168.30.200 (clientes WiFi)

Gateway por subred:   192.168.X.1  (el propio Mini PC)
DNS entregado:        192.168.10.1 (futuro Pi-hole)
Dominio de búsqueda:  comunitaria.local
Leases:               /var/lib/kea/kea-leases4.csv
Logs:                 /var/log/kea/kea-dhcp4.log
```

### Resultado del playbook

```
PLAY RECAP
minipc-core : ok=14   changed=2   failed=0
```

| Verificación | Resultado |
|---|---|
| `kea-dhcp4-server` activo y habilitado | ✓ |
| Puerto 67 UDP escuchando | ✓ |
| Config validado con `kea-dhcp4 -t` | ✓ |

---

## 4. Estado actual del Mini PC

### Servicios activos y persistentes

| Servicio | Estado | Habilitado en boot |
|----------|--------|-------------------|
| `nftables` | running | sí |
| `jool-nat64` | running | sí |
| `kea-dhcp4-server` | running | sí |

### Nota sobre las interfaces VLAN

Las interfaces `enp171s0.10/20/30` están en estado `LOWERLAYERDOWN` porque `enp171s0` (LAN) **no tiene cable físico al switch todavía**. Las IPs ya están asignadas y los servicios ya escuchan en `*`. En cuanto se conecte el cable:

1. Las interfaces VLAN pasarán a estado `UP`
2. Kea empezará a entregar leases en las 3 subredes
3. nftables aplicará el firewall en esas interfaces automáticamente (ya están en las reglas)

### Cómo re-ejecutar los playbooks

```bash
# Router (desde la raíz del proyecto)
cd minipc/router-setup/
ansible-playbook -i inventory.ini playbook.yml

# DHCP
cd dhcp/dhcp4_role/provision/
ansible-playbook -i ../inventory.yml dhcp4.yml
```

---

## 5. Pendiente para próximas sesiones

| Tarea | Descripción |
|-------|-------------|
| Conectar cable switch | `enp171s0` → switch L2 para activar VLANs |
| Instalar Pi-hole | En `192.168.10.1` — el DNS forzado de nftables ya está preparado |
| Configurar RPi | IP estática `192.168.20.10` en VLAN20, instalar Nginx |
| Configurar AP | En VLAN30, verificar que clientes reciben DHCP y pueden llegar a VLAN20 |
| Agregar VLAN40 | Cuando se conecte el nodo Cocalito vía radioenlace |
