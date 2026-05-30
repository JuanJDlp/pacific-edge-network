# Router — VLANs, NAT e IP Forwarding

**Dispositivo:** Mini PC (`plataformas`, 100.90.95.134)
**Rol Ansible:** `minipc/router-setup/roles/router/`
**Servicios systemd:** `nftables`, `jool-nat64`, `systemd-networkd` (via netplan)
**Ultima verificacion:** 2026-05-30

---

## Que hace

El Mini PC actua como router de borde de la red comunitaria. Este rol configura:

1. **Interfaces de red** via Netplan (VLANs 802.1Q sobre `enp171s0`)
2. **IP forwarding** IPv4 e IPv6
3. **nftables** — firewall, NAT, portal cautivo (ver `FIREWALL-NFTABLES.md` para detalles)
4. **Jool NAT64** — traduce trafico IPv6 a IPv4 para clientes duales

---

## Interfaces de red

| Interfaz | Funcion | Direccion |
|---|---|---|
| `enp170s0` | WAN (uplink al router externo) | DHCP → `172.16.0.11/16` |
| `enp171s0` | LAN trunk (sin IP propia) | — |
| `enp171s0.10` | VLAN 10 — Gestion | `192.168.10.1/24` + `fd00:0:0:10::1/64` |
| `enp171s0.20` | VLAN 20 — Servidores | `192.168.20.1/24` + `fd00:0:0:20::1/64` |
| `enp171s0.30` | VLAN 30 — Clientes (portal cautivo) | `192.168.30.1/24` + `fd00:0:0:30::1/64` |
| `wt0` | NetBird overlay VPN (gestion remota) | `100.90.95.134/16` |
| `docker0` | Docker bridge (sin uso activo) | `172.17.0.1/16` (DOWN) |

Netplan despliega `00-router.yaml` y elimina el config de cloud-init (`50-cloud-init.yaml`).

---

## IP Forwarding

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

Sin esto, el Mini PC no reenvia paquetes entre interfaces (dejaria de ser router).

---

## nftables (reglas base)

Tres tablas principales:

### `table inet filter`

- **`captive_mangle`** (prioridad mangle, corre ANTES del DNAT): marca con `0x1` los paquetes de clientes VLAN30 cuya MAC ya esta en el set `captive_allowed_mac`.
- **`input`**: politica DROP. Permite loopback, VPN, ICMP, SSH/DNS/DHCP/NTP desde VLANs, y puertos del portal cautivo.
- **`forward`**: politica DROP. Permite VLAN10/20 → WAN siempre; VLAN30 → WAN/VLAN20 solo con `mark=0x1`.

### `table ip nat`

- **`prerouting`**:
  - DNS de todas las VLANs → DNAT a `192.168.10.1:53` (Bind9)
  - HTTP/HTTPS de VLAN30 sin mark → DNAT al portal cautivo (`:2050`)
  - HTTP de VLAN30 con mark `0x1` → DNAT al proxy nginx (`:8888`) → Squid RPi
  - HTTPS de VLAN30 con mark `0x1` → DNAT a Squid RPi (`:3130`) para filtrado SNI
- **`postrouting`**: `masquerade` saliendo por `enp170s0` (NAT hacia internet)

### `table netdev dhcp_fix`

Fix especifico para macOS en estado APIPA: Kea usa `AF_PACKET` (bypasea netfilter) y envia DHCP Offers en unicast. macOS en APIPA solo acepta Offers con `dst=255.255.255.255`. Esta cadena `egress` en `enp171s0.30` reescribe la direccion destino a broadcast.

---

## Jool NAT64

Permite que clientes con direccion IPv6 ULA (`fd00::/8`) alcancen destinos IPv4 en internet, sin necesidad de asignar IPv4 a cada cliente.

**Flujo:**
```
Cliente IPv6 (fd00:0:0:30::X)
  → query DNS → Bind9 DNS64 sintetiza AAAA: 64:ff9b::<ipv4_destino>
  → cliente envia paquete a 64:ff9b::<ipv4>
  → Jool intercepta (modulo kernel) y traduce IPv6 → IPv4
  → sale por enp170s0 como trafico IPv4 normal (NAT masquerade)
```

- **Modulo kernel:** `jool-dkms` (instalado via Ubuntu universe)
- **Instancia:** `jool instance add default --netfilter --pool6 64:ff9b::/96`
- **Servicio:** `jool-nat64.service` (oneshot, `RemainAfterExit=yes`)
- El modulo se carga en boot via `/etc/modules-load.d/jool.conf`

---

## Flujo de paquetes (VLAN30 cliente autenticado, HTTP)

```
[Cliente 192.168.30.X]
    | HTTP GET ejemplo.com:80
    v
[nftables captive_mangle]  <- prioridad mangle
    | ether saddr en captive_allowed_mac? → mark=0x1
    v
[nftables prerouting DNAT]
    | mark=0x1, daddr != RPi, dport 80 → DNAT a 192.168.30.1:8888
    v
[nginx :8888 — http-proxy]
    | reenvia como forward proxy a RPi:3129
    v
[Squid RPi :3129]
    | conecta al destino real
    v
[nftables postrouting]
    | oif enp170s0 → masquerade
    v
[Internet]
```

---

## Comandos utiles

```bash
# Ver interfaces y VLANs
ip link show
ip addr show

# Ver ruleset nftables completo
sudo nft list ruleset

# Ver set de MACs autorizadas en portal cautivo
sudo nft list set inet filter captive_allowed_mac

# Vaciar MACs autorizadas (para re-probar portal)
sudo nft flush set inet filter captive_allowed_mac

# Estado de Jool NAT64
sudo jool instance show
sudo jool bib display

# Verificar ip_forward
cat /proc/sys/net/ipv4/ip_forward
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags networking,firewall,nat64
# o solo el rol completo:
ansible-playbook services/router.yml -i router-setup/inventory.ini
```
