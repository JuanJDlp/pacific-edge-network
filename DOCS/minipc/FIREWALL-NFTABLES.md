# Firewall — nftables avanzado

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/firewall/` — **fuente de verdad** del ruleset desplegado.
**Servicio systemd:** `nftables` (`ExecStart=/usr/sbin/nft -f /etc/nftables.conf`)
**Ultima verificacion:** 2026-06-01

> **Importante (sincronización playbook ↔ máquina):** El `/etc/nftables.conf` que corre en
> el Mini PC lo genera **únicamente** el rol **`firewall`**
> (`roles/firewall/templates/nftables.conf.j2`). El rol `router` **ya no gestiona nftables**:
> antes desplegaba su propio `nftables.conf.j2` que el rol `firewall` luego sobreescribía
> (dos plantillas escribiendo el mismo archivo). Esa plantilla duplicada del rol `router` se
> eliminó; ahora hay una sola fuente de verdad. El rol `firewall` también deshabilita UFW
> (que entra en conflicto con nftables). Para editar el firewall, modifica el template del
> rol `firewall`.

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
# HTTP autenticado → proxy nginx (:8888) → Squid RPi (cache + blocklist HTTP)
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80
    dnat to 192.168.30.1:8888

# HTTPS autenticado → pasa directo a WAN (sin DNAT).
# El bloqueo de porn/gambling para HTTPS se hace a nivel DNS via Bind9 RPZ
# (zona rpz.blocklist). Squid intercept HTTPS cross-host NO funciona:
# pierde SO_ORIGINAL_DST y termina con TCP_DENIED contra si mismo.
```

### Portal cautivo — cierre del bypass IPv6/NAT64 (crítico)

> Añadido: 2026-06-01

**Síntoma:** un cliente VLAN30 nuevo podía navegar a Internet **sin** aceptar el splash.

**Causa raíz:** el portal cautivo solo controlaba **IPv4** (DNAT 80/443 + control de marca
en `forward`). Pero la red es **dual-stack**:

1. `radvd` entrega IPv6 global a VLAN30.
2. **DNS64** (Bind9) sintetiza registros AAAA hacia el prefijo NAT64 `64:ff9b::/96` para
   cualquier sitio, incluso solo-IPv4.
3. **Jool NAT64** traduce ese IPv6 → IPv4 y lo saca a Internet.

Como Jool **"roba" el paquete en `prerouting` ANTES de la cadena `forward`**, el control de
marca de `forward` **nunca** aplica al tráfico NAT64. Resultado: el cliente (que por Happy
Eyeballs / RFC 6724 prefiere IPv6) navega sin autenticarse — y la *probe* de detección de
portal cautivo del SO también sale por IPv6 y tiene éxito, así que el SO concluye "hay
Internet, no hay portal" y **nunca muestra el splash**.

**Fix:** bloquear el tráfico NAT64 de clientes VLAN30 no autenticados en la cadena
`captive_mangle` (prioridad mangle `-150`, que corre antes de Jool y después de marcar al
autenticado):

```nft
chain captive_mangle {
    type filter hook prerouting priority mangle; policy accept;
    iif "enp171s0.30" ether saddr @captive_allowed_mac meta mark set 0x1     # marca autenticado
    # log rate-limited (regla NO terminante: solo loguea, deja pasar al siguiente)
    iif "enp171s0.30" ip6 daddr 64:ff9b::/96 meta mark != 0x1 \
        limit rate 5/minute log prefix "NFT DROP: CAPTIVE-V6-NAT64: "
    # drop INCONDICIONAL (regla aparte)
    iif "enp171s0.30" ip6 daddr 64:ff9b::/96 meta mark != 0x1 drop
}
```

La marca se pone primero, así que **los autenticados no se ven afectados**. Al no-autenticado
se le cae la salida IPv6/NAT64 → su probe IPv6 falla → el SO cae a IPv4 → ahí el DNAT 80/443
al splash sí lo atrapa.

> ⚠️ **Gotcha de `limit` (importante):** `limit rate N` (sin `over`) es un **matcher** que
> solo matchea mientras se está **bajo** el límite. Si se escribe todo en una regla
> —`log ... limit rate 5/minute drop`— el `drop` solo se aplica a los primeros 5 paquetes/min
> y **el resto se fuga** (la regla deja de matchear). Por eso el `drop` va en su propia regla
> incondicional y el `log` (rate-limited) va aparte. Se detectó este bug probando en campo: el
> IPv6 seguía navegando pese a la regla. **Las demás reglas `log ... limit ... drop` del
> firewall (WAN-BLOCK, SPOOF-WAN, aislamiento VLAN20/10→30, SSH-BAN) tienen el mismo patrón y
> fugan igual** — pendiente de corregir con la misma estructura de dos reglas.

> El prefijo `64:ff9b::/96` debe coincidir con el `pool6` de Jool (rol `router`,
> `nat64_prefix`) y con la directiva `dns64` de Bind9. En el rol `firewall` está expuesto
> como la variable `nat64_prefix` en `roles/firewall/vars/main.yml`.

```bash
# Ver clientes no autenticados cayendo por este drop
sudo journalctl -kf | grep "CAPTIVE-V6-NAT64"
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
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
```

> El handler recarga `nftables` con `nft -f /etc/nftables.conf`, que hace `flush ruleset`.
> Esto **vacía el set `captive_allowed_mac`**: todos los clientes deberán volver a aceptar el
> portal (las conexiones ya establecidas siguen vivas por `ct state established,related`).
