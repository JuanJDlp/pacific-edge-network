# Network IPv6 — Direccion ULA estatica en la RPi

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/network_ipv6/`
**Configura:** Netplan drop-in `/etc/netplan/60-ipv6.yaml`
**Ultima verificacion:** 2026-05-30

---

## Que hace

Asigna una direccion IPv6 ULA (Unique Local Address) estatica a la interfaz `eth0` de la RPi. La IPv4 sigue siendo asignada por DHCP con reserva estatica en Kea.

---

## Direccion asignada

| Interfaz | IPv4 | IPv6 |
|---|---|---|
| `eth0` | `192.168.20.10` (reserva DHCP) | `fd00:0:0:20::10/64` |

El prefijo `fd00:0:0:20::/64` corresponde a la VLAN20 (Servidores). La RPi es el unico host con direccion IPv6 estatica explicita en VLAN20 — los demas dispositivos usan SLAAC (via radvd).

---

## Por que una direccion estatica

La RPi es un servidor que otros servicios referencian por IP:

- Bind9 primario (Mini PC) publica su AAAA como `fd00:0:0:20::10` en la zona `biblioteca.tel`
- DNS64 en Bind9 preserva este AAAA real (no sintetiza uno falso) porque esta en rango `fd00::/8`
- Prometheus scrape job apunta a `192.168.20.10:9100`
- Zone transfer DNS va a `fd00:0:0:20::10`

Si la IPv6 fuera dinamica (SLAAC con EUI-64), cambiaria si se reemplaza la RPi por otro hardware, rompiendo estos registros.

---

## Implementacion con Netplan drop-in

En lugar de reemplazar el config de cloud-init (`50-cloud-init.yaml`), el rol agrega un **drop-in** `60-ipv6.yaml`. Netplan aplica los archivos en orden numerico — el 60 sobreescribe solo la configuracion IPv6 de `eth0` sin tocar la IPv4.

---

## Relacion con el resto de la red IPv6

```
[Mini PC — radvd]
    | emite RA en VLAN20: prefijo fd00:0:0:20::/64
    v
[RPi eth0]
    | <- ignora el SLAAC (tiene estatica configurada)
    | usa fd00:0:0:20::10/64 (asignada manualmente en netplan)

[Mini PC — Bind9]
    | zona biblioteca.tel:
    |   biblioteca  A    192.168.20.10
    |   biblioteca  AAAA fd00:0:0:20::10  <- preservado por DNS64 exclude
    v
[Clientes IPv6 que consultan biblioteca.tel]
    | reciben fd00:0:0:20::10
    | se conectan directamente (red interna, sin NAT64)
```

---

## Comandos utiles

```bash
# Verificar que la IPv6 esta asignada
ip -6 addr show dev eth0

# Probar conectividad IPv6 desde la RPi al Mini PC
ping6 fd00:0:0:20::1

# Ver la configuracion netplan activa
sudo cat /etc/netplan/60-ipv6.yaml

# Aplicar cambios de netplan manualmente
sudo netplan apply
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags network_ipv6
```
