# Firewall — nftables avanzado

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/router/` (integrado en el rol router)
**Servicio systemd:** `nftables`
**Ultima verificacion:** 2026-05-30

---

## Que hace

El firewall nftables provee proteccion completa del router de borde:

- Rate limiting para SSH, DNS e ICMP
- Bloqueo explicito de puertos peligrosos desde WAN
- Aislamiento estricto entre VLANs
- Proteccion anti-spoofing en WAN
- Auto-ban temporal por fuerza bruta SSH
- Logging configurable de paquetes dropeados

---

## Protecciones

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

### Rate limiting DNS (anti-amplificacion)

```
udp dport 53 limit rate 30/second burst 50 packets accept
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

Cada drop incluye prefix `"NFT DROP: "` con rate limit de 5/minuto para no saturar syslog.

```bash
# Ver drops en tiempo real
sudo journalctl -f | grep "NFT DROP:"
```

---

## Sets nftables

| Set | Tipo | Timeout | Proposito |
|-----|------|---------|-----------|
| `captive_allowed_mac` | `ether_addr` | 8h | MACs VLAN30 autenticadas en portal cautivo |
| `ssh_bruteforce` | `ipv4_addr` | 1h | IPs baneadas por exceso de conexiones SSH |

## Portal cautivo — DNAT HTTP y HTTPS

El firewall intercepta tanto HTTP como HTTPS de clientes no autenticados y los redirige al splash del portal:

```nft
# HTTP no autenticado → portal (puerto 2050 SSL)
iif "enp171s0.30" meta mark != 0x1 tcp dport 80
    dnat to 192.168.30.1:2050

# HTTPS no autenticado → portal (mismo puerto 2050 SSL)
iif "enp171s0.30" meta mark != 0x1 tcp dport 443
    dnat to 192.168.30.1:2050
```

Para clientes autenticados:
```nft
# HTTP autenticado → proxy nginx (:8888) → Squid RPi
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80
    dnat to 192.168.30.1:8888

# HTTPS autenticado → Squid SNI filter (:3130)
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 443
    dnat to 192.168.20.10:3130
```

---

## Servicios de gestion (solo VLAN10)

```
iif "enp171s0.10" tcp dport { 9090, 3000, 8080 } accept
```

- `:9090` — Prometheus
- `:3000` — Grafana
- `:8080` — reservado (antes Pi-hole)

Solo accesibles desde la VLAN de gestion. No son alcanzables desde VLAN30 (clientes).

---

## Comandos utiles

```bash
# Ver ruleset completo
sudo nft list ruleset

# Ver solo sets
sudo nft list set inet filter captive_allowed_mac
sudo nft list set inet filter ssh_bruteforce

# Vaciar MACs del portal cautivo
sudo nft flush set inet filter captive_allowed_mac

# Recargar reglas
sudo systemctl restart nftables
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags router
```
