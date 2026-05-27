# Squid — Proxy Web y Caché HTTP

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/squid/`
**Servicio systemd:** `squid`
**Puertos:** `:3129` (forward proxy desde Mini PC), `:3128` (intercept local)

---

## Qué hace

Squid actúa como proxy web con caché HTTP para los clientes de VLAN30. Cachea respuestas de sitios web para que las visitas repetidas sirvan desde disco en lugar de ir a internet. Recibe el tráfico desde el nginx intermediario del Mini PC (no directamente de los clientes).

---

## Puertos

| Puerto | Modo | Quién conecta |
|---|---|---|
| `3129` | `accel vhost allow-direct` | nginx intermediario del Mini PC |
| `3128` | `intercept` | Tráfico local de la RPi |

### Por qué dos puertos

- **`:3129 accel vhost`** — Recibe requests del nginx intermediario. En este modo Squid usa el `Host` header para conocer el destino real, sin depender de `SO_ORIGINAL_DST`. El flag `allow-direct` permite que Squid conecte al origen directamente.
- **`:3128 intercept`** — Para tráfico local de la RPi que pase por iptables/nftables. No es el flujo principal de los clientes.

---

## Por qué nginx como intermediario (no DNAT directo a Squid)

El Mini PC hace DNAT del HTTP de clientes autenticados hacia el nginx intermediario en `:8888`, que luego reenvía a `Squid:3129`. No se hace DNAT directo porque:

Squid en modo `intercept` usa la syscall `SO_ORIGINAL_DST` para obtener el destino original del paquete. Cuando el DNAT cruza máquinas (Mini PC → RPi), `SO_ORIGINAL_DST` en la RPi devuelve la IP de la propia RPi (el DNAT ya fue procesado en el Mini PC), causando que Squid detecte un loop y responda `403 Forwarding Loop`.

El nginx intermediario reconstruye el request con el `Host` header correcto y se lo envía a Squid como **forward proxy** (puerto 3129), evitando completamente el problema.

---

## Timeout de conexión

```
connect_timeout 15 seconds
```

Squid espera un máximo de 15 segundos para conectarse al destino antes de devolver error al cliente. El valor por defecto es 60 segundos. El timeout reducido permite que el nginx intermediario del Mini PC intercepte el error y muestre `offline.html` más rápidamente cuando el WAN está caído.

---

## Caché configurada

| Parámetro | Valor |
|---|---|
| Directorio | `/var/lib/biblioteca/squid-cache` |
| Tamaño en disco | **10 GB** (formato aufs) |
| Tamaño en RAM | **512 MB** |
| Tamaño máximo de objeto | 128 MB |
| Tamaño máximo en memoria | 4 MB |

### Política de refresco (refresh patterns)

Muy agresiva, optimizada para red offline:

```
refresh_pattern . 43200 90% 525600
```

- Tiempo mínimo en caché: **30 días** (43200 minutos)
- Porcentaje de "edad": 90% del tiempo desde la última modificación
- Tiempo máximo: **~1 año** (525600 minutos)

Esto significa que casi todo lo que pase por Squid queda cacheado por meses, ideal para una red comunitaria donde los recursos se repiten frecuentemente.

---

## ACLs de acceso

```
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src 100.64.0.0/10   # NetBird CGNAT
```

Solo redes privadas y el overlay NetBird pueden usar el proxy.

`always_direct allow all` — Squid siempre conecta directamente al destino (sin proxy padre).

---

## Logs

```
/var/log/squid/access.log    # log de acceso (formato squid)
/var/log/squid/cache.log     # log del proceso de caché
```

### Interpretar el access.log

```
1234567890.123 45 192.168.30.101 TCP_MISS/200 1234 GET http://...
```

- `TCP_HIT` — Sirvió desde caché (sin ir a internet)
- `TCP_MISS` — No estaba en caché, fue a internet
- `TCP_MEM_HIT` — Sirvió desde caché en RAM

---

## Flujo de una petición cacheada

```
[Primera visita — TCP_MISS]
Cliente → Mini PC nginx:8888 → Squid:3129 → Internet → respuesta guardada en caché

[Segunda visita — TCP_HIT]
Cliente → Mini PC nginx:8888 → Squid:3129 → Caché en disco → respuesta directa
                                              (sin salir a internet)
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status squid

# Ver hits/misses en tiempo real
sudo tail -f /var/log/squid/access.log | grep -E "TCP_HIT|TCP_MISS|TCP_MEM_HIT"

# Estadísticas del caché
sudo squidclient -h 127.0.0.1 -p 3129 mgr:info 2>/dev/null

# Tamaño actual del caché en disco
sudo du -sh /var/lib/biblioteca/squid-cache

# Limpiar caché completamente (requiere reinicio)
sudo systemctl stop squid
sudo squid -z  # reinicializa caché
sudo systemctl start squid

# Logs en tiempo real
sudo journalctl -u squid -f
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags squid
# o:
ansible-playbook services/squid.yml -i rpi-setup/inventory.ini
```
