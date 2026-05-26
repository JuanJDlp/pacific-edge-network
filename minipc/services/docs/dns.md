# DNS — Bind9 primario + DNS64

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/dns/`
**Servicio systemd:** `named`
**Dominio:** `biblioteca.tel`

---

## Qué hace

Bind9 actúa como servidor DNS autoritativo y recursivo para toda la red. Resuelve el dominio interno `biblioteca.tel` y reenvía queries externas a los forwarders del ISP. Incluye **DNS64** para que clientes IPv6 puedan alcanzar destinos IPv4 a través del NAT64 (Jool).

---

## Dónde escucha

| Interfaz | IPv4 | IPv6 |
|---|---|---|
| Loopback | `127.0.0.1:53` | `::1:53` |
| VLAN10 Gestión | `192.168.10.1:53` | `fd00:0:0:10::1:53` |
| VLAN20 Servidores | `192.168.20.1:53` | `fd00:0:0:20::1:53` |
| VLAN30 Clientes | `192.168.30.1:53` | `fd00:0:0:30::1:53` |

Los clientes nunca llegan directamente a Bind9 — nftables hace DNAT de cualquier query DNS (puerto 53) hacia `192.168.10.1:53`, forzando el uso del DNS interno aunque el dispositivo tenga configurado un DNS externo (8.8.8.8, etc.).

---

## Zonas configuradas

### Zona directa — `biblioteca.tel` (master)

Registros publicados:

| Nombre | Tipo | Valor |
|---|---|---|
| `minipc` | A + AAAA | `192.168.10.1` / `fd00:0:0:10::1` |
| `ns1` | A + AAAA | `192.168.10.1` / `fd00:0:0:10::1` |
| `switch` | A | `192.168.10.2` |
| `biblioteca` | A + AAAA | `192.168.20.10` / `fd00:0:0:20::10` |
| `rpi` | A + AAAA | `192.168.20.10` / `fd00:0:0:20::10` |
| `wikipedia` | CNAME | `biblioteca` |
| `educacion` | CNAME | `biblioteca` |
| `videos` | CNAME | `biblioteca` |
| `kolibri` | CNAME | `biblioteca` |
| `jellyfin` | CNAME | `biblioteca` |
| `wiki` | CNAME | `biblioteca` |
| `media` | CNAME | `biblioteca` |
| `squid` | CNAME | `biblioteca` |

### Zonas inversas (master)

- `10.168.192.in-addr.arpa` — VLAN10
- `20.168.192.in-addr.arpa` — VLAN20
- `30.168.192.in-addr.arpa` — VLAN30

### Zone transfer al secundario

Bind9 permite AXFR hacia la RPi (`192.168.20.10`) para que el DNS secundario mantenga copias sincronizadas de todas las zonas.

---

## Forwarders externos

Queries para dominios no locales se reenvían a:
- `8.8.8.8` (Google DNS)
- `8.8.4.4` (Google DNS secundario)
- `1.1.1.1` (Cloudflare)

Modo `forward only` — Bind9 nunca hace resolución iterativa propia, delega todo a los forwarders.

DNSSEC está deshabilitado porque `forward only` + validación rompe cadenas de certificados de Apple/iCloud.

---

## DNS64

DNS64 permite la coexistencia de clientes IPv6-only con internet IPv4. Funciona junto al NAT64 (Jool).

**Cómo funciona:**

1. Cliente IPv6 pide `AAAA` para `google.com`
2. Si `google.com` tiene registro `A` pero no `AAAA`, Bind9 sintetiza: `64:ff9b::<IP_de_google>`
3. El cliente envía paquetes a esa dirección sintética
4. Jool (kernel) intercepta y traduce IPv6 → IPv4
5. El paquete sale por WAN como IPv4 normal

**Exclusiones configuradas:**
- No sintetiza AAAA para rangos RFC1918 (`10/8`, `172.16/12`, `192.168/16`) — los hosts internos IPv4 siguen siendo alcanzables directamente
- Preserva AAAA reales de la red ULA (`fd00::/8`) — los hosts internos dual-stack conservan sus direcciones IPv6 reales

---

## Coexistencia con systemd-resolved

Ubuntu tiene `systemd-resolved` que por defecto crea un `DNSStubListenerExtra` en las interfaces LAN, ocupando TCP 53 y bloqueando Bind9. El rol elimina el drop-in conflictivo y deja `resolved` solo en `127.0.0.53`.

---

## Flujo de una query DNS desde VLAN30

```
[Cliente 192.168.30.X]
    │ query UDP 53 → 8.8.8.8 (su DNS configurado, cualquiera)
    ▼
[nftables prerouting DNAT]
    │ iif enp171s0.30, udp dport 53 → DNAT a 192.168.10.1:53
    ▼
[Bind9 en Mini PC]
    │ ¿dominio local biblioteca.tel? → responde con zona local
    │ ¿dominio externo? → reenvía a 8.8.8.8
    ▼
[Respuesta al cliente]
```

---

## Comandos útiles

```bash
# Verificar que Bind9 está activo
sudo systemctl status named

# Probar resolución local
dig @192.168.10.1 biblioteca.tel
dig @192.168.10.1 wikipedia.biblioteca.tel

# Probar DNS64 (debe devolver AAAA sintético 64:ff9b::...)
dig @192.168.10.1 AAAA google.com

# Ver zona completa
sudo named-checkzone biblioteca.tel /etc/bind/zones/db.biblioteca.tel

# Logs de Bind9
sudo journalctl -u named -f
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags dns
# o:
ansible-playbook services/dns.yml -i router-setup/inventory.ini
```
