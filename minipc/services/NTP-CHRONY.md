# NTP — Chrony

## Rol Ansible

`minipc/router-setup/roles/ntp/`

## Descripción

Chrony actúa como servidor NTP para todos los dispositivos de la red interna. Sincroniza el reloj del Mini PC con pools NTP de Colombia/Sudamérica y redistribuye tiempo a las VLANs internas. Si no hay conexión WAN, funciona como reloj local (stratum 10).

## Topología

```
[Internet — NTP pools Colombia/Sudamérica]
    │  upstream sync
    ▼
[Mini PC — chrony :123]
    │  serve to 192.168.0.0/16
    ├── VLAN10 — gestión
    ├── VLAN20 — RPi (servidores)
    └── VLAN30 — clientes
```

## Fuentes NTP upstream

```
pool 0.south-america.pool.ntp.org iburst maxsources 2
pool 1.south-america.pool.ntp.org iburst maxsources 2
pool 2.co.pool.ntp.org iburst maxsources 2
```

Prioriza servidores del pool colombiano y sudamericano para menor latencia.

## Configuración destacada

| Directiva | Valor | Efecto |
|---|---|---|
| `allow 192.168.0.0/16` | todas las VLANs internas | Permite queries NTP de clientes |
| `local stratum 10` | stratum 10 | Sirve tiempo local si no hay WAN |
| `makestep 1 3` | 1 seg en primeras 3 actualizaciones | Corrección de tiempo grande al inicio |
| `rtcsync` | — | Sincroniza RTC del hardware |
| `maxupdateskew 100.0` | 100 ppm | Límite de deriva antes de rechazar fuente |

`local stratum 10` es clave para redes sin internet estable: los clientes siguen sincronizando aunque el Mini PC no tenga acceso WAN.

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible |
|---|---|
| `/etc/chrony/chrony.conf` | `templates/chrony.conf.j2` |

## Variables

No hay variables específicas en este rol. La configuración completa está en el template.

## Verificación

```bash
# Estado de chrony y fuentes
chronyc sources -v
# → debe mostrar fuentes con * (sincronizado)

chronyc tracking
# → muestra stratum actual, offset, drift

# Verificar que escucha en UDP 123
ss -ulnp | grep 123

# Desde cliente en VLAN30 — verificar sync
ntpdate -q 192.168.30.1
# o
chronyc -h 192.168.30.1 tracking
```

## Comandos útiles

```bash
# Forzar sincronización inmediata
chronyc makestep

# Ver actividad en tiempo real
chronyc activity

# Reiniciar servicio
systemctl restart chrony
journalctl -u chrony -f
```
