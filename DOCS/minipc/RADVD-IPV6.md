# radvd — Router Advertisement (IPv6 SLAAC)

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/router/` (integrado en el rol router)
**Servicio systemd:** `radvd`
**Config en servidor:** `/etc/radvd.conf`
**Ultima verificacion:** 2026-05-30 — servicio activo

---

## Que hace

radvd (Router Advertisement Daemon) emite mensajes ICMPv6 Router Advertisement (RA) en cada VLAN, permitiendo que los clientes configuren su direccion IPv6 automaticamente mediante SLAAC (Stateless Address Autoconfiguration), sin necesidad de DHCPv6.

---

## VLANs con RA habilitado

| VLAN | Interfaz | Prefijo IPv6 | RDNSS (DNS) |
|---|---|---|---|
| VLAN10 Gestion | `enp171s0.10` | `fd00:0:0:10::/64` | `fd00:0:0:10::1` |
| VLAN20 Servidores | `enp171s0.20` | `fd00:0:0:20::/64` | `fd00:0:0:20::1` |
| VLAN30 Clientes | `enp171s0.30` | `fd00:0:0:30::/64` | `fd00:0:0:30::1` |

El RDNSS apunta al gateway IPv6 de cada VLAN (el Mini PC), donde Bind9 escucha en IPv6.

---

## Parametros del RA

```
AdvManagedFlag off    # No hay DHCPv6, el cliente se auto-configura (SLAAC)
AdvOtherConfigFlag off # No hay DHCPv6 para opciones adicionales
AdvAutonomous on      # Cliente genera su propia direccion con el prefijo
MinRtrAdvInterval 30
MaxRtrAdvInterval 100
AdvDefaultLifetime 1800
```

---

## Flujo IPv6 completo de un cliente

```
[Cliente VLAN30 (ej: laptop)]
    |
    | 1. radvd emite RA: prefijo fd00:0:0:30::/64 + RDNSS fd00:0:0:30::1
    |
    | 2. Cliente genera: fd00:0:0:30::<eui64_de_su_MAC>
    |
    | 3. Cliente envia query DNS AAAA a fd00:0:0:30::1
    |    → Bind9 DNS64 en Mini PC
    |    → Si destino no tiene AAAA real → sintetiza 64:ff9b::<IPv4>
    |
    | 4. Cliente envia paquete IPv6 a 64:ff9b::<IPv4_destino>
    |
    | 5. Jool NAT64 en kernel → traduce a IPv4
    |
    | 6. Sale por enp170s0 (WAN) como IPv4 con masquerade
    v
[Internet]
```

---

## Integracion con DNS64 y NAT64

radvd, DNS64 (Bind9) y NAT64 (Jool) forman el trio que habilita IPv6 completo en la red:

- **radvd** → da direccion IPv6 y DNS al cliente
- **DNS64** → sintetiza AAAA para destinos IPv4-only
- **NAT64** → traduce el trafico IPv6 → IPv4 en el kernel

---

## Comandos utiles

```bash
# Estado del servicio
sudo systemctl status radvd

# Verificar que se estan enviando RA
sudo tcpdump -i enp171s0.30 icmp6 and 'ip6[40] == 134'

# Ver configuracion activa
cat /etc/radvd.conf

# Logs
sudo journalctl -u radvd -f

# Verificar que un cliente recibio IPv6 (desde el cliente)
ip -6 addr show
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags radvd
```
