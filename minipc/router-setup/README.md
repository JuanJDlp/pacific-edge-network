# Router Setup — Mini PC (Ubuntu Server 24.04)

Configura el Mini PC como router interno de la red comunitaria usando Ansible.

---

## Pre-requisitos

| Requisito | Detalle |
|-----------|---------|
| SO | Ubuntu Server 24.04 LTS |
| SSH habilitado | Puerto 22 abierto, usuario con sudo |
| Python 3 | Debe estar disponible en el host (`python3 --version`) |
| Acceso SSH | Llave `~/.ssh/plats_mini_pc` configurada en `inventory.ini` |
| Ansible en la máquina local | `ansible-playbook --version` ≥ 2.14 |
| ansible.posix collection | `ansible-galaxy collection install ansible.posix` |

---

## Verificar nombres de interfaces antes de ejecutar

En Ubuntu 24.04 las interfaces se llaman `enp<N>s<M>` en lugar de `eth0`/`eth1`. **Ejecutar en el Mini PC:**

```bash
ip link show
```

Ejemplo de salida en este host:
```
2: enp170s0   → WAN (conectado al router externo / Starlink)
3: enp171s0   → LAN (trunk 802.1Q hacia el switch L2)
4: wt0        → Tailscale VPN (no tocar)
```

Si los nombres son distintos, editar `roles/router/vars/main.yml`:

```yaml
wan_interface: enp170s0   # cambiar aquí
lan_interface: enp171s0   # cambiar aquí
```

El playbook fallará con un mensaje claro si las interfaces no existen.

---

## Instalar dependencias Ansible (una sola vez)

```bash
pip install ansible
ansible-galaxy collection install ansible.posix
```

---

## Ejecutar el playbook completo

```bash
cd minipc/router-setup/
ansible-playbook -i inventory.ini playbook.yml
```

> **Nota:** La aplicación de netplan puede interrumpir brevemente la conexión WAN. La conexión Tailscale (`wt0`) se recupera automáticamente.

---

## Ejecutar solo las verificaciones

```bash
ansible-playbook -i inventory.ini playbook.yml --tags verify
```

---

## Ejecutar por secciones

```bash
# Solo networking (netplan + ip forwarding)
ansible-playbook -i inventory.ini playbook.yml --tags networking

# Solo firewall (nftables)
ansible-playbook -i inventory.ini playbook.yml --tags firewall

# Solo NAT64 (Jool)
ansible-playbook -i inventory.ini playbook.yml --tags nat64
```

---

## Pruebas manuales desde un cliente en VLAN30 (AP)

```bash
# ¿Llega a la RPi en VLAN20?
ping 192.168.20.10

# ¿El salto intermedio es el Mini PC (192.168.30.1)?
traceroute 192.168.20.10

# ¿Responde Nginx de la RPi?
curl http://192.168.20.10
```

---

## Prueba de NAT64 desde cliente IPv6 puro

```bash
# Deshabilitar IPv4 temporalmente en el cliente para probar NAT64
ping6 64:ff9b::8.8.8.8        # 8.8.8.8 vía NAT64
curl -6 http://example.com    # debe funcionar vía NAT64
```

---

## Prueba de DNS forzado (Pi-hole)

Una vez instalado Pi-hole en 192.168.10.1:

```bash
# Intentar usar DNS externo — debe ser interceptado por nftables y respondido por Pi-hole
dig @8.8.8.8 google.com

# Resolver hostname local
nslookup kiwix.local.com   # debe devolver 192.168.20.10
```

---

## Arquitectura resultante

```
Internet
    │
[Router externo / Starlink]
    │
[Mini PC — Ubuntu 24.04]
    ├── enp170s0 (WAN)    → DHCP desde router externo
    └── enp171s0 (LAN)    → trunk 802.1Q hacia Switch L2
        ├── enp171s0.10   → 192.168.10.1/24  fd00:0:0:10::1/64  (VLAN10 — Gestión)
        ├── enp171s0.20   → 192.168.20.1/24  fd00:0:0:20::1/64  (VLAN20 — Servidores)
        └── enp171s0.30   → 192.168.30.1/24  fd00:0:0:30::1/64  (VLAN30 — Clientes WiFi)
```

### Reglas de firewall (nftables)

| Origen | Destino | Acción |
|--------|---------|--------|
| VLAN* | WAN | Forward permitido (NAT44) |
| VLAN30 | VLAN20 | Forward permitido |
| VLAN20 | VLAN30 | Bloqueado |
| LAN | Router | SSH, DNS, DHCP, NTP, HTTP/HTTPS permitidos |
| DNS a cualquier IP | Puerto 53 | DNAT → 192.168.10.1:53 |
