# DHCP — Kea DHCPv4

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/dhcp/`
**Servicio systemd:** `kea-dhcp4-server`
**Config en servidor:** `/etc/kea/kea-dhcp4.conf`

---

## Qué hace

Kea DHCPv4 asigna direcciones IP dinámicas a todos los dispositivos de las tres VLANs. Se eligió Kea en lugar de ISC DHCP por su soporte moderno, mejor manejo de raw sockets y formato de configuración en JSON.

---

## Subredes configuradas

| VLAN | Red | Pool dinámico | Gateway |
|------|-----|---------------|---------|
| VLAN10 Gestión | `192.168.10.0/24` | `.50` – `.99` | `192.168.10.1` |
| VLAN20 Servidores | `192.168.20.0/24` | `.50` – `.99` | `192.168.20.1` |
| VLAN30 Clientes | `192.168.30.0/24` | `.100` – `.200` | `192.168.30.1` |

Todos los clientes reciben:
- **DNS:** `192.168.10.1` (Bind9 en el Mini PC)
- **Domain search:** `biblioteca.tel`

---

## Reservas estáticas (MAC → IP)

| Dispositivo | MAC | IP fija | Hostname |
|---|---|---|---|
| Raspberry Pi | `2c:cf:67:d2:f0:98` | `192.168.20.10` | `rpi5-servicios` |

La RPi siempre recibe la misma IP, lo que permite que todos los demás servicios (Prometheus, Squid, DNS secundario) apunten a `192.168.20.10` de forma confiable.

---

## Tiempos de lease

| Parámetro | Valor |
|---|---|
| `valid-lifetime` | 4000 s (~66 min) |
| `renew-timer` | 1000 s (~16 min) |
| `rebind-timer` | 2000 s (~33 min) |

Leases cortos porque la VLAN30 tiene clientes transitorios (usuarios que se conectan y desconectan). Esto reduce la probabilidad de que una IP "liberada" quede ocupada por mucho tiempo.

---

## Raw sockets y fix macOS APIPA

Kea usa `dhcp-socket-type: raw` — envía los paquetes directamente con `AF_PACKET`, bypaseando la pila IP del kernel. Esto es necesario para responder correctamente a clientes en estado APIPA (sin IP asignada aún), ya que el kernel normalmente no routea paquetes a `0.0.0.0`.

El efecto secundario es que los DHCP Offers de Kea van en unicast a la MAC del cliente, pero macOS en APIPA solo acepta Offers con `dst=255.255.255.255`. El rol `router` incluye una regla en `table netdev` (egress) que reescribe el destino a broadcast antes de que el frame salga por `enp171s0.30`.

---

## Persistencia de leases

Los leases se guardan en:
```
/var/lib/kea/kea-leases4.csv
```

Con `lfc-interval: 3600` (Lease File Cleanup cada hora), que compacta el CSV eliminando entradas expiradas.

---

## Logs

```
/var/log/kea/kea-dhcp4.log
```
- Rotación automática: máximo 1 MB por archivo, 3 versiones.

---

## Flujo de asignación DHCP

```
[Cliente nuevo en VLAN30]
    │ DHCPDISCOVER (broadcast)
    ▼
[Kea en Mini PC]
    │ interfaz enp171s0.30, pool 192.168.30.100-200
    │ DHCPOFFER → IP + gw 192.168.30.1 + dns 192.168.10.1
    ▼
[nftables netdev egress]  ← solo si dst no es 255.255.255.255
    │ reescribe dst a 255.255.255.255 (fix macOS APIPA)
    ▼
[Cliente acepta → DHCPREQUEST → DHCPACK]
    │ lease guardado en kea-leases4.csv
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status kea-dhcp4-server

# Ver leases activos
sudo cat /var/lib/kea/kea-leases4.csv

# Logs en tiempo real
sudo journalctl -u kea-dhcp4-server -f

# Ver qué IP tiene asignada la RPi
grep "rpi5-servicios\|192.168.20.10" /var/lib/kea/kea-leases4.csv
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags dhcp
# o:
ansible-playbook services/dhcp.yml -i router-setup/inventory.ini
```
