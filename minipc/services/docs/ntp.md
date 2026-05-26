# NTP — Chrony

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/ntp/`
**Servicio systemd:** `chrony`
**Config en servidor:** `/etc/chrony/chrony.conf`

---

## Qué hace

Chrony actúa como servidor NTP para todos los dispositivos de las VLANs internas. Se sincroniza con pools NTP colombianos/sudamericanos y redistribuye la hora a los clientes. Si pierde conectividad WAN, continúa sirviendo la hora con stratum local.

---

## Fuentes de tiempo (upstream)

Se usan tres pools regionales en orden de preferencia:

```
pool 0.south-america.pool.ntp.org iburst maxsources 2
pool 1.south-america.pool.ntp.org iburst maxsources 2
pool 2.co.pool.ntp.org iburst maxsources 2  ← pool colombiano
```

`iburst` envía una ráfaga de 8 paquetes al iniciar para sincronizarse rápidamente. `maxsources 2` limita a 2 fuentes por pool para no sobrecargar los servidores.

---

## Clientes permitidos

```
allow 192.168.0.0/16
```

Todos los dispositivos de las tres VLANs (`192.168.10.0/24`, `192.168.20.0/24`, `192.168.30.0/24`) pueden consultar NTP en el Mini PC.

---

## Stratum local (fallback sin WAN)

```
local stratum 10
```

Si el Mini PC pierde conectividad con los servidores NTP externos, sigue sirviendo la hora desde su reloj local con stratum 10 (suficientemente alto para que los clientes lo usen como fallback pero sepan que no es una fuente autoritativa).

---

## Otros parámetros

| Parámetro | Valor | Propósito |
|---|---|---|
| `makestep 1 3` | Ajuste en los primeros 3 arranques | Permite ajuste de reloj mayor a 1s al iniciar |
| `rtcsync` | — | Sincroniza el reloj hardware (RTC) del Mini PC |
| `maxupdateskew 100.0` | — | Tolerancia de deriva máxima antes de considerar la fuente inválida |
| `leapsectz right/UTC` | — | Manejo correcto de segundos bisiesto |

---

## Flujo de sincronización

```
[Pool NTP sudamericano] ← internet
    │ UDP 123
    ▼
[Chrony en Mini PC]
    │ sincroniza reloj interno
    ▼
[Clientes VLAN10/20/30]
    │ UDP 123 hacia 192.168.X.1
    ▼ (responde Chrony)
```

Los clientes pueden apuntar NTP a su gateway de VLAN (`.1`) ya que Chrony escucha en todas las interfaces del Mini PC.

---

## Comandos útiles

```bash
# Estado y fuentes activas
sudo chronyc tracking
sudo chronyc sources -v

# Ver clientes que están consultando
sudo chronyc clients

# Logs
sudo journalctl -u chrony -f
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags ntp
# o:
ansible-playbook services/ntp.yml -i router-setup/inventory.ini
```
