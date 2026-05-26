# Network IPv6 — Dirección ULA estática en la RPi

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/network_ipv6/`
**Configura:** Netplan drop-in `/etc/netplan/60-ipv6.yaml`

---

## Qué hace

Asigna una dirección IPv6 ULA (Unique Local Address) estática a la interfaz `eth0` de la RPi. La IPv4 sigue siendo asignada por DHCP con reserva estática en Kea.

---

## Dirección asignada

| Interfaz | IPv4 | IPv6 |
|---|---|---|
| `eth0` | `192.168.20.10` (reserva DHCP) | `fd00:0:0:20::10/64` |

El prefijo `fd00:0:0:20::/64` corresponde a la VLAN20 (Servidores). La RPi es el único host con dirección IPv6 estática explícita en VLAN20 — los demás dispositivos usan SLAAC (via radvd).

---

## Por qué una dirección estática

La RPi es un servidor que otros servicios referencian por IP:

- Bind9 primario (Mini PC) publica su AAAA como `fd00:0:0:20::10` en la zona `biblioteca.tel`
- DNS64 en Bind9 preserva este AAAA real (no sintetiza uno falso) porque está en rango `fd00::/8`
- Prometheus scrape job apunta a `192.168.20.10:9100`
- Zone transfer DNS va a `fd00:0:0:20::10`

Si la IPv6 fuera dinámica (SLAAC con EUI-64), cambiaría si se reemplaza la RPi por otro hardware, rompiendo estos registros.

---

## Implementación con Netplan drop-in

En lugar de reemplazar el config de cloud-init (`50-cloud-init.yaml`), el rol agrega un **drop-in** `60-ipv6.yaml`. Netplan aplica los archivos en orden numérico — el 60 sobreescribe solo la configuración IPv6 de `eth0` sin tocar la IPv4.

Esto es más seguro que reemplazar el config principal: si el rol falla a mitad, el netplan original sigue funcionando.

---

## Relación con el resto de la red IPv6

```
[Mini PC — radvd]
    │ emite RA en VLAN20: prefijo fd00:0:0:20::/64
    ▼
[RPi eth0]
    │ ← ignora el SLAAC (tiene estática configurada)
    │ usa fd00:0:0:20::10/64 (asignada manualmente en netplan)

[Mini PC — Bind9]
    │ zona biblioteca.tel:
    │   biblioteca  A    192.168.20.10
    │   biblioteca  AAAA fd00:0:0:20::10  ← preservado por DNS64 exclude
    ▼
[Clientes IPv6 que consultan biblioteca.tel]
    │ reciben fd00:0:0:20::10
    │ se conectan directamente (red interna, sin NAT64)
```

---

## Comandos útiles

```bash
# Verificar que la IPv6 está asignada
ip -6 addr show dev eth0

# Probar conectividad IPv6 desde la RPi al Mini PC
ping6 fd00:0:0:20::1

# Ver la configuración netplan activa
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
