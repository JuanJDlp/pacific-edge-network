# Pi-hole — Bloqueo de publicidad DNS

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/pihole/`
**Servicio systemd:** `pihole` (wrapper sobre Docker Compose)
**Imagen Docker:** `pihole/pihole:2024.07.0`

---

## Qué hace

Pi-hole corre como contenedor Docker en el Mini PC y actúa como resolvedor DNS con bloqueo de publicidad, rastreadores y contenido no deseado para toda la red. Toma el puerto 53 en `192.168.10.1`, desplazando a Bind9 al puerto 5353.

---

## Arquitectura DNS con Pi-hole activo

```
[Clientes VLANs 10/20/30]
    │ cualquier DNS (nftables DNAT fuerza a 192.168.10.1:53)
    ▼
[Pi-hole :53 en 192.168.10.1]
    │ ¿dominio en blocklist? → NXDOMAIN (bloqueado)
    │ ¿biblioteca.tel o subdominio local?
    │         → reenvía a Bind9 en :5353 (mismo host)
    │ ¿dominio externo permitido?
    │         → reenvía a Quad9 (9.9.9.9)
    ▼
[Respuesta al cliente]
```

Bind9 se reconfigura para escuchar en puerto **5353** cuando Pi-hole está activo, para coexistir en la misma IP.

---

## Instalación

Pi-hole requiere Docker. El rol instala:
- `docker-ce`, `docker-ce-cli`, `containerd.io`
- `docker-buildx-plugin`, `docker-compose-plugin`

El contenedor se gestiona con un `docker-compose.yml` en `/opt/pihole/` y un systemd unit `pihole.service` que lo inicia/detiene.

---

## Configuración

| Parámetro | Valor |
|---|---|
| Puerto DNS | `53` (UDP/TCP) |
| Puerto web admin | `8080` (evita conflicto con nginx `:80`) |
| IP de escucha | `192.168.10.1` |
| Upstream DNS primario | `9.9.9.9` (Quad9 — filtra malware) |
| Upstream DNS secundario | `149.112.112.112` (Quad9 secundario) |
| Datos persistentes | `/opt/pihole/etc-pihole/` y `/opt/pihole/etc-dnsmasq.d/` |

---

## Listas de bloqueo (adlists)

| Lista | Fuente |
|---|---|
| StevenBlack unified hosts | GitHub |
| AdAway | adaway.org |
| AdGuard DNS | firebog.net |
| EasyList | firebog.net |
| KADhosts | PolishFiltersTeam |

---

## Whitelist de dominios locales

Estos dominios están siempre permitidos aunque aparezcan en alguna blocklist:

```
biblioteca.local
*.biblioteca.local
kolibri.biblioteca.local
kiwix.biblioteca.local
jellyfin.biblioteca.local
```

---

## Panel web de administración

```
http://192.168.10.1:8080/admin
```

Solo accesible desde VLAN10 (gestión). Permite ver estadísticas de bloqueo, añadir dominios a whitelist/blocklist, y ver el log de queries en tiempo real.

> Cambiar la contraseña antes de desplegar — está en `roles/pihole/vars/main.yml` como `pihole_web_password: "cambia_esta_password"`.

---

## Flujo de query con dominio local

```
[Cliente] → dig biblioteca.tel
    ▼
[Pi-hole :53] — dominio local, delega a Bind9
    ▼
[dnsmasq dentro de Pi-hole] — 02-local-dns.conf:
    server=/biblioteca.tel/127.0.0.1#5353
    ▼
[Bind9 :5353] — zona master biblioteca.tel
    ▼
[Respuesta: 192.168.20.10]
```

---

## Comandos útiles

```bash
# Estado del contenedor
sudo systemctl status pihole
sudo docker ps | grep pihole

# Ver estadísticas de bloqueo
sudo docker exec pihole pihole -c

# Ver log de queries en tiempo real
sudo docker exec pihole pihole -t

# Agregar dominio a whitelist
sudo docker exec pihole pihole --white-list ejemplo.com

# Agregar dominio a blacklist
sudo docker exec pihole pihole --black-list ads.ejemplo.com

# Actualizar listas de bloqueo
sudo docker exec pihole pihole -g

# Logs del contenedor
sudo docker logs pihole --follow
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags pihole
```
