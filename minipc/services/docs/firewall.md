# Firewall — nftables avanzado

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/firewall/`
**Servicio systemd:** `nftables`

---

## Qué hace

El rol `firewall` reemplaza el `nftables.conf` base del rol `router` con una versión más robusta que agrega:

- Rate limiting para SSH, DNS e ICMP
- Bloqueo explícito de puertos peligrosos desde WAN
- Aislamiento estricto entre VLANs
- Protección anti-spoofing en WAN
- Auto-ban temporal por fuerza bruta SSH
- Logging configurable de paquetes dropeados

> **Nota:** El rol `firewall` debe correr **después** del rol `router`, ya que este último configura las VLANs e ip_forward que firewall presupone.

---

## Protecciones adicionales sobre el rol `router`

### Anti-spoofing WAN

```
iif "enp170s0" ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
```

Descarta paquetes que llegan por WAN con IP de origen privada — indicio de spoofing o routing incorrecto del ISP.

### Rate limiting SSH + auto-ban

```
# Si una IP supera 5 conexiones/minuto, se agrega al set ssh_bruteforce por 1h
set ssh_bruteforce {
    type ipv4_addr; flags dynamic, timeout; timeout 1h;
}
tcp dport 22 ct state new limit rate over 5/minute burst 10 packets
    add @ssh_bruteforce { ip saddr timeout 1h } drop
```

### Rate limiting DNS (anti-amplificación)

```
udp dport 53 limit rate 30/second burst 50 packets accept
# Rechaza si supera el límite — evita que la red sea usada para ataques de amplificación
```

### Rate limiting ICMP

```
ip protocol icmp limit rate 10/second burst 20 packets accept
ip protocol icmp drop
```

### Puertos bloqueados desde WAN

| Puerto | Protocolo |
|--------|-----------|
| 23 | Telnet |
| 135, 137, 138, 139 | RPC/NetBIOS |
| 445 | SMB |
| 1433 | MSSQL |
| 3306 | MySQL |
| 3389 | RDP |
| 5900 | VNC |

### Aislamiento entre VLANs

```
# VLAN20 NO puede iniciar conexiones a VLAN30
iif "enp171s0.20" oif "enp171s0.30" drop

# VLAN10 NO puede llegar a VLAN30 directamente
iif "enp171s0.10" oif "enp171s0.30" drop
```

Los servidores (VLAN20) no pueden iniciar conexiones hacia los clientes (VLAN30). Solo se permiten respuestas a conexiones iniciadas por los clientes (`ct state established,related`).

### Logging de drops

Controlado por `enable_drop_logging: true` en `vars/main.yml`. Cada drop incluye prefix `"NFT DROP: "` con rate limit de 5/minuto para no saturar syslog.

```bash
# Ver drops en tiempo real
sudo journalctl -f | grep "NFT DROP:"
```

---

## Sets nftables

| Set | Tipo | Timeout | Propósito |
|-----|------|---------|-----------|
| `captive_allowed` | `ipv4_addr` | 8h | IPs VLAN30 autenticadas en portal cautivo |
| `ssh_bruteforce` | `ipv4_addr` | 1h | IPs baneadas por exceso de conexiones SSH |

> **Nota:** El set `captive_allowed` usa IP (versión legada). El rol `router` usa `captive_allowed_mac` (por MAC). Si ambos roles están activos, el de `router` tiene precedencia por ser el último en escribir `/etc/nftables.conf`.

---

## Servicios de gestión (solo VLAN10)

```
iif "enp171s0.10" tcp dport { 9090, 3000, 8080 } accept
```

- `:9090` — Prometheus
- `:3000` — Grafana
- `:8080` — Pi-hole web admin

Solo accesibles desde la VLAN de gestión. No son alcanzables desde VLAN30 (clientes).

---

## Variables de configuración

Archivo: `roles/firewall/vars/main.yml`

| Variable | Valor | Descripción |
|---|---|---|
| `ssh_rate_limit` | `5/minute` | Umbral de conexiones SSH |
| `ssh_rate_burst` | 10 | Burst permitido |
| `dns_rate_limit` | `30/second` | Umbral UDP DNS |
| `icmp_rate_limit` | `10/second` | Umbral ICMP |
| `enable_drop_logging` | `true` | Activa logs de drops |
| `drop_log_limit` | `5/minute` | Rate de log entries |

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
```
