# DNS — Bind9 (`biblioteca.local`)

## Rol Ansible

`minipc/router-setup/roles/dns/`

## Descripción

Bind9 actúa como servidor DNS autoritativo para el dominio `biblioteca.local` y como resolver recursivo con forwarding para dominios externos. Reemplaza la resolución DNS en las VLANs internas (el stub de systemd-resolved sigue activo en `127.0.0.53` solo para uso local del Mini PC).

## Por qué Bind9 y no systemd-resolved

systemd-resolved no soporta zonas locales autoritativas con múltiples registros A/CNAME. Bind9 permite:
- Definir `biblioteca.local` con A records por servicio
- Responder en múltiples interfaces (una IP por VLAN)
- Forwarding condicional a DNS externos

## Interfaces donde escucha

| Interfaz | IP | VLANs que lo usan |
|---|---|---|
| loopback | 127.0.0.1 | Mini PC local |
| enp171s0.10 | 192.168.10.1 | VLAN10 gestión |
| enp171s0.20 | 192.168.20.1 | VLAN20 servidores |
| enp171s0.30 | 192.168.30.1 | VLAN30 clientes |

El nftables ya redirige UDP/TCP 53 desde las VLANs hacia `192.168.10.1:53` (Bind9).

## Registros del dominio `biblioteca.local`

### A records

| Nombre | IP | Descripción |
|---|---|---|
| minipc | 192.168.10.1 | Mini PC — gateway |
| ns1 | 192.168.10.1 | Nameserver primario |
| switch | 192.168.10.2 | Switch Catalyst 2960 |
| biblioteca | 192.168.20.10 | RPi — servidor de servicios |
| rpi | 192.168.20.10 | RPi (alias técnico) |

### CNAME (alias → biblioteca)

| Alias | Destino | Servicio |
|---|---|---|
| wikipedia | biblioteca | Kiwix Wikipedia |
| educacion | biblioteca | Kolibri |
| videos | biblioteca | Jellyfin |
| kolibri | biblioteca | Kolibri |
| jellyfin | biblioteca | Jellyfin |
| squid | biblioteca | Squid proxy |
| wiki | biblioteca | Kiwix (alias corto) |
| media | biblioteca | Jellyfin (alias) |

Todos los servicios educativos resuelven a `192.168.20.10` (RPi). El nginx de la RPi los enruta al puerto correcto según el `Host` header.

## Zonas inversas (PTR)

- `10.168.192.in-addr.arpa` → VLAN10
- `20.168.192.in-addr.arpa` → VLAN20
- `30.168.192.in-addr.arpa` → VLAN30

## Forwarding externo

Cuando un cliente pide `google.com` u otro dominio externo, Bind9 hace forwarding a:
1. `8.8.8.8` (Google)
2. `8.8.4.4` (Google)
3. `1.1.1.1` (Cloudflare)

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible |
|---|---|
| `/etc/bind/named.conf.options` | `templates/named.conf.options.j2` |
| `/etc/bind/named.conf.local` | `templates/named.conf.local.j2` |
| `/var/cache/bind/db.biblioteca.local` | `templates/db.forward.j2` |
| `/var/cache/bind/db.10.168.192` | `templates/db.reverse.j2` (VLAN10) |
| `/var/cache/bind/db.20.168.192` | `templates/db.reverse.j2` (VLAN20) |
| `/var/cache/bind/db.30.168.192` | `templates/db.reverse.j2` (VLAN30) |

## Variables (`roles/dns/vars/main.yml`)

```yaml
dns_domain: "biblioteca.local"
dns_primary_ip: "192.168.10.1"
dns_listen_ips: [127.0.0.1, 192.168.10.1, 192.168.20.1, 192.168.30.1]
dns_forwarders: [8.8.8.8, 8.8.4.4, 1.1.1.1]
```

## Verificación

```bash
# Desde cualquier cliente en VLAN30
dig @192.168.10.1 biblioteca.local +short
# → 192.168.20.10

dig @192.168.10.1 wikipedia.biblioteca.local +short
# → biblioteca.biblioteca.local. (CNAME) → 192.168.20.10

# Estado del servicio en Mini PC
systemctl status named
named-checkconf /etc/bind/named.conf
named-checkzone biblioteca.local /var/cache/bind/db.biblioteca.local
```

## Coexistencia con systemd-resolved

systemd-resolved sigue activo en `127.0.0.53` para resolver consultas locales del Mini PC (ej. actualizaciones apt). No interfiere con Bind9 porque escuchan en IPs distintas. Los clientes DHCP reciben `192.168.10.1` como DNS, apuntando directamente a Bind9.
