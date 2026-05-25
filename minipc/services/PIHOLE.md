# Pi-hole — DNS con bloqueo de contenido

Pi-hole actúa como servidor DNS para toda la red (Cerrito Bongo y Cocalito). Bloquea publicidad, rastreadores y dominios maliciosos antes de que lleguen a los dispositivos.

## Arquitectura DNS

```
Clientes (VLAN10/20/30)
    │
    │ consulta DNS (puerto 53)
    ▼
nftables DNAT → 192.168.10.1:53
    │
    ▼
Pi-hole (Docker en Mini PC)
    │
    ├─ Dominio bloqueado → NXDOMAIN (no sale a internet)
    │
    ├─ biblioteca.local → Bind9 en 127.0.0.1:5353
    │                      (zonas locales: RPi, switches, etc.)
    │
    └─ Resto → Quad9 (9.9.9.9) — filtra malware adicional
```

El DNAT en nftables fuerza **todo** el tráfico DNS de las VLANs hacia Pi-hole, incluso si un cliente configura manualmente otro DNS (8.8.8.8, 1.1.1.1, etc.).

## Acceso al panel web

- **URL:** `http://192.168.10.1:8080/admin`
- **Acceso:** Solo desde VLAN10 (gestión)
- **Contraseña:** definida en `roles/pihole/vars/main.yml` → `pihole_web_password`

> ⚠️ Cambiar la contraseña antes del primer despliegue.

## Listas de bloqueo activas

| Lista | Descripción |
|-------|-------------|
| StevenBlack/hosts | Lista consolidada de ads, malware, fake news |
| AdAway | Publicidad en apps móviles |
| AdGuard DNS | Rastreadores y publicidad |
| EasyList | Publicidad web general |
| KADhosts | Dominios maliciosos polacos (amplia cobertura) |

Las listas se actualizan automáticamente cada semana (cron interno de Pi-hole).

## Dominios siempre permitidos (whitelist)

- `biblioteca.local` y subdominios
- `kolibri.biblioteca.local`
- `kiwix.biblioteca.local`
- `jellyfin.biblioteca.local`

## Gestión del contenedor

```bash
# Ver estado
sudo systemctl status pihole
sudo docker ps | grep pihole

# Ver logs
sudo docker logs pihole -f

# Reiniciar
sudo systemctl restart pihole

# Actualizar imagen
sudo docker pull pihole/pihole:latest
sudo systemctl restart pihole

# Entrar al contenedor
sudo docker exec -it pihole bash

# Actualizar listas de bloqueo manualmente
sudo docker exec pihole pihole -g

# Ver estadísticas desde CLI
sudo docker exec pihole pihole -c
```

## Agregar dominios a whitelist/blacklist

```bash
# Whitelist (permitir siempre)
sudo docker exec pihole pihole --white-list dominio.com

# Blacklist (bloquear siempre)
sudo docker exec pihole pihole --black-list dominio.com

# Ver lista actual
sudo docker exec pihole pihole --white-list --list
sudo docker exec pihole pihole --black-list --list
```

## Coexistencia con Bind9

Bind9 sigue corriendo pero en **puerto 5353** (no en el 53 estándar). Pi-hole le delega las consultas del dominio `biblioteca.local` y las zonas inversas `192.168.x.x`.

```bash
# Verificar que Bind9 escucha en 5353
sudo ss -ulnp | grep 5353

# Probar resolución local directamente a Bind9
dig @127.0.0.1 -p 5353 biblioteca.local

# Probar que Pi-hole resuelve biblioteca.local (debe delegar a Bind9)
dig @192.168.10.1 biblioteca.local
```

## Datos persistentes

Los datos de Pi-hole se guardan en el host en:

```
/opt/pihole/
├── etc-pihole/       # Configuración, listas, base de datos FTL
└── etc-dnsmasq.d/    # Configuración dnsmasq adicional
    └── 02-local-dns.conf  # Delegación a Bind9 para biblioteca.local
```

## Despliegue con Ansible

```bash
# Solo Pi-hole
ansible-playbook -i inventory.ini playbook.yml --tags pihole

# Pi-hole + firewall
ansible-playbook -i inventory.ini playbook.yml --tags pihole,firewall
```
