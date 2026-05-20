# DHCP — Kea DHCPv4

## Rol Ansible

`minipc/router-setup/roles/dhcp/`

## Descripción

Kea DHCPv4 asigna IPs a los dispositivos en las tres VLANs. Kea usa raw sockets (en lugar de sockets UDP del sistema) para enviar DHCP Offers, lo que le permite llegar a clientes sin IP previa. Esto requiere el fix de broadcast en nftables (ver más abajo).

## Subnets

| VLAN | Red | Pool dinámico | Gateway | DNS |
|---|---|---|---|---|
| VLAN10 (gestión) | 192.168.10.0/24 | .50 — .99 | 192.168.10.1 | 192.168.10.1 |
| VLAN20 (servidores) | 192.168.20.0/24 | .50 — .99 | 192.168.20.1 | 192.168.10.1 |
| VLAN30 (clientes) | 192.168.30.0/24 | .100 — .200 | 192.168.30.1 | 192.168.10.1 |

El servidor DNS entregado a todos los clientes es `192.168.10.1` (Bind9), no el ISP.

## Reservas estáticas

| MAC | IP reservada | Hostname | Motivo |
|---|---|---|---|
| `2c:cf:67:d2:f0:98` | 192.168.20.10 | rpi5-servicios | RPi necesita IP fija para nftables y nginx |

## Timers

```
valid-lifetime:  4000 s (~66 min)
renew-timer:     1000 s (~16 min)   — T1
rebind-timer:    2000 s (~33 min)   — T2
```

## Fix de DHCP broadcast (nftables netdev)

Kea envía DHCP Offers con `dst = IP del cliente` (unicast a nivel IP) antes de que el cliente tenga IP asignada. Los switches/interfaces descartan estos paquetes porque el cliente no puede recibirlos por unicast.

El fix en nftables convierte los Offers a broadcast en egress:

```nft
table netdev dhcp_fix {
    chain out_vlan30 {
        type filter hook egress device "enp171s0.30" priority filter;
        udp sport 67 udp dport 68 ip daddr != 255.255.255.255 \
            ip daddr set 255.255.255.255 ether daddr set ff:ff:ff:ff:ff:ff
    }
}
```

Este hook está definido en `roles/router/templates/nftables.conf.j2` y aplica solo a la interfaz VLAN30 (clientes). Se necesita uno por cada interfaz donde haya clientes DHCP.

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible |
|---|---|
| `/etc/kea/kea-dhcp4.conf` | `templates/kea-dhcp4.conf.j2` |

## Variables (`roles/dhcp/vars/main.yml`)

```yaml
dhcp_dns_server: "192.168.10.1"      # Bind9
dhcp_domain_search: "biblioteca.tel"
dhcp_valid_lifetime: 4000
```

## Comandos útiles

```bash
# Estado del servicio
systemctl status kea-dhcp4-server

# Ver leases actuales
cat /var/lib/kea/kea-leases4.csv

# Ver logs en tiempo real
journalctl -u kea-dhcp4-server -f

# Reiniciar si se modificó la config
systemctl restart kea-dhcp4-server
```

## Verificación

```bash
# Desde cliente en VLAN30 — verificar IP obtenida
ip addr show
# → debe mostrar 192.168.30.x/24 con gateway 192.168.30.1

# Verificar DNS recibido vía DHCP
resolvectl status   # en Linux
ipconfig getpacket en0   # en macOS
# → domain_name_server: 192.168.10.1
```
