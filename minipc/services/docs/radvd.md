# radvd — Router Advertisement (IPv6 SLAAC)

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/radvd/`
**Servicio systemd:** `radvd`
**Config en servidor:** `/etc/radvd.conf`

---

## Qué hace

radvd (Router Advertisement Daemon) emite mensajes ICMPv6 Router Advertisement (RA) en cada VLAN, permitiendo que los clientes configuren su dirección IPv6 automáticamente mediante SLAAC (Stateless Address Autoconfiguration), sin necesidad de DHCPv6.

---

## Prerequisito

radvd requiere que `net.ipv6.conf.all.forwarding = 1` esté habilitado en el kernel. El rol `router` lo configura. El rol `radvd` verifica este requisito y falla si no está activo.

---

## Cómo funciona SLAAC

Cuando un dispositivo se conecta a una VLAN:

1. radvd emite periódicamente un Router Advertisement (RA) en la VLAN
2. El RA contiene el prefijo de la red (ej: `fd00:0:0:30::/64`)
3. El cliente combina ese prefijo con su identificador EUI-64 (derivado de la MAC) para generar su dirección IPv6 completa: `fd00:0:0:30::<eui64>`
4. El RA también incluye el servidor DNS (RDNSS) para que el cliente configure DNS sin DHCPv6

---

## VLANs con RA habilitado

| VLAN | Interfaz | Prefijo IPv6 | RDNSS (DNS) |
|---|---|---|---|
| VLAN10 Gestión | `enp171s0.10` | `fd00:0:0:10::/64` | `fd00:0:0:10::1` |
| VLAN20 Servidores | `enp171s0.20` | `fd00:0:0:20::/64` | `fd00:0:0:20::1` |
| VLAN30 Clientes | `enp171s0.30` | `fd00:0:0:30::/64` | `fd00:0:0:30::1` |

El RDNSS apunta al gateway IPv6 de cada VLAN (el Mini PC), donde Bind9 escucha en IPv6.

---

## Parámetros del RA

```
AdvManagedFlag off    # No hay DHCPv6, el cliente se auto-configura (SLAAC)
AdvOtherConfigFlag off # No hay DHCPv6 para opciones adicionales
AdvAutonomous on      # Cliente genera su propia dirección con el prefijo
```

Con `AdvManagedFlag off`, los clientes usan SLAAC puro — no consultan DHCPv6. La dirección IPv6 se genera combinando el prefijo del RA con el EUI-64 de la interfaz de red.

---

## Flujo IPv6 completo de un cliente

```
[Cliente VLAN30 (ej: laptop)]
    │
    │ 1. radvd emite RA: prefijo fd00:0:0:30::/64 + RDNSS fd00:0:0:30::1
    │
    │ 2. Cliente genera: fd00:0:0:30::<eui64_de_su_MAC>
    │
    │ 3. Cliente envía query DNS AAAA a fd00:0:0:30::1
    │    → Bind9 DNS64 en Mini PC
    │    → Si destino no tiene AAAA real → sintetiza 64:ff9b::<IPv4>
    │
    │ 4. Cliente envía paquete IPv6 a 64:ff9b::<IPv4_destino>
    │
    │ 5. Jool NAT64 en kernel → traduce a IPv4
    │
    │ 6. Sale por enp170s0 (WAN) como IPv4 con masquerade
    ▼
[Internet]
```

---

## Integración con DNS64 y NAT64

radvd, DNS64 (Bind9) y NAT64 (Jool) forman el trio que habilita IPv6 completo en la red:

- **radvd** → da dirección IPv6 y DNS al cliente
- **DNS64** → sintetiza AAAA para destinos IPv4-only
- **NAT64** → traduce el tráfico IPv6 → IPv4 en el kernel

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status radvd

# Verificar que se están enviando RA
sudo tcpdump -i enp171s0.30 icmp6 and 'ip6[40] == 134'
# 134 = Router Advertisement

# Ver configuración activa
cat /etc/radvd.conf

# Logs
sudo journalctl -u radvd -f

# Verificar que un cliente recibió IPv6 (desde el cliente)
ip -6 addr show
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags radvd
# o:
ansible-playbook services/radvd.yml -i router-setup/inventory.ini
```
