# Kolibri — Plataforma educativa offline

> **Ultima actualizacion:** 2026-06-01

## Rol Ansible

`raspberry/rpi-setup/roles/kolibri/`

## Descripcion

Kolibri es una plataforma de aprendizaje offline que incluye contenidos de Khan Academy, EiE Familias, Proyecto Biosfera y Biblioteca Elejandria. Corre en el puerto 8090 del loopback y es accesible via nginx en `/kolibri/`.

## Estado actual

- **Usuario del sistema:** `akasicom`
- **KOLIBRI_HOME:** `/home/akasicom/.kolibri`
- **Contenido total:** ~38 GB
- **Disco RPi:** 59G total (~62.4 GB), 81% usado, ~12 GB libre (tras quitar NASA y bajar reserva ext4 al 1%)

## Canales instalados

| Canal | Tamano aprox. |
|-------|---------------|
| Khan Academy Espanol | ~36.6 GB |
| EiE Familias | 0.1 GB |
| Proyecto Biosfera | 0.2 GB |
| Biblioteca Elejandria | 0.9 GB |

> **Ciencia NASA (3.1 GB) removido el 2026-06-01.** En la SD de 59G no caben Khan
> Academy (36.6G, el canal mas valioso) + el resto + ZIMs de Kiwix sin cruzar el
> umbral de alarma del disco (85%). Se priorizo Khan Academy y se removio NASA.
> Para re-agregarlo hace falta liberar espacio o agregar almacenamiento USB.

## Presupuesto de disco y umbral de alarma (CRITICO)

El panel de estado (ver [`HEALTH-CHECK.md`](HEALTH-CHECK.md)) muestra
**"Sistema sobrecargado · avisar al encargado"** cuando el disco supera el **85%**.
El auto-update de Kolibri puede llenar el disco, asi que su guard debe parar
**antes** de ese umbral:

- `MIN_FREE_MB=10000` en `update-kolibri-content.sh.j2` — el script deja de
  descargar cuando quedan <10 GB libres (~84% usado), por debajo del 85% de alarma.
  (Antes era 4000 ≈ 93%, lo que permitia llenar el disco y disparar la alarma.)
- **ext4 reserved blocks** bajados de 4% a 1% (`tune2fs -m 1 /dev/mmcblk0p2`) para
  recuperar ~2 GB de espacio util en la particion de datos.

> **Incidente 2026-06-01:** el auto-update lleno `/home/akasicom/.kolibri/content`
> a 41 GB (disco 91%) y disparo la alarma roja. Causa raiz: el guard (4 GB) era mas
> permisivo que el umbral de alarma (85%). Solucion: remover NASA, subir el guard a
> 10 GB y bajar la reserva ext4.

## Limpieza de canales huerfanos (idempotencia)

`update-kolibri-content.sh` borra al inicio el contenido de cualquier canal
**instalado que ya no este en `kolibri_channels`** (`kolibri manage deletecontent <id> -f`).
Invariante: *nada en disco que no se este sirviendo*. Por eso, para dejar de servir
un canal basta con quitarlo de `group_vars/all.yml` — el siguiente cron lo borra.

`importcontent` ya es idempotente: salta los archivos ya descargados, no re-baja
todo en cada corrida (solo deltas cuando el canal publica version nueva).

## Detalles del servicio systemd

```
# /usr/lib/systemd/system/kolibri.service
# Instalado vía paquete apt (modo compatibilidad init.d)
Type=forking
ExecStart=/etc/init.d/kolibri start
ExecStop=/etc/init.d/kolibri stop
```

El unit de Kolibri usa el script init.d legacy para compatibilidad hacia atrás. Ansible simplemente asegura que esté `enabled` y `started` sin modificar la configuración interna de la app.

## Acceso vía nginx

```nginx
location /kolibri/ {
    proxy_pass http://127.0.0.1:8090;
    proxy_set_header X-Forwarded-Host  $host;
    proxy_buffer_size       16k;
    proxy_buffers           8 16k;
    client_max_body_size    1G;  # para uploads de canales
}
```

Los buffers grandes son necesarios porque Kolibri carga muchos metadatos de canales en los headers de respuesta.

## Configuracion de Kolibri

Kolibri almacena su configuracion y base de datos en:
```
/home/akasicom/.kolibri/
├── kolibri.sqlite3     # base de datos principal
├── content/            # canales descargados
└── logs/
```

Para gestionar Kolibri (descargar canales, crear usuarios, etc.) acceder a `http://biblioteca.tel/kolibri/` como admin.

## Auto-actualizacion de canales

Los canales se actualizan automaticamente via cron (martes y viernes a las 03:00). Documentacion completa en [`kolibri-auto-update/`](kolibri-auto-update/).

## Acceso sin credenciales

Configurado con `landing_page=learn` y `allow_guest_access=True`. Los usuarios ven el contenido directamente en `http://biblioteca.tel/kolibri/` sin necesidad de login.

## Agregar canales educativos

```bash
# Desde la interfaz web de Kolibri (recomendado)
# http://biblioteca.tel/kolibri/ → Gestionar → Canales

# O desde linea de comandos en RPi (usuario akasicom)
KOLIBRI_HOME=/home/akasicom/.kolibri sudo -u akasicom kolibri manage importchannel network <ID>
KOLIBRI_HOME=/home/akasicom/.kolibri sudo -u akasicom kolibri manage importcontent network <ID>
```

**Nota:** La sintaxis correcta es `importchannel network <id>` y `importcontent network <id>` (sin `--channel-id`).

## Troubleshooting: 500 Server Error / "database disk image is malformed"

Sintoma: `/kolibri/` devuelve **500** y el log (`/home/akasicom/.kolibri/logs/kolibri.txt`)
muestra `sqlite3.DatabaseError: database disk image is malformed` con un traceback
que pasa por `diskcache` (`fanout.py` / `core.py`).

**Causa:** corrupcion del *diskcache* de Kolibri (`/home/akasicom/.kolibri/process_cache/`),
tipicamente porque **el disco se lleno** (ver presupuesto de disco arriba) y un write
del cache quedo truncado. La DB principal `db.sqlite3` suele estar intacta
(`PRAGMA integrity_check` = ok); el problema es el cache, que es **desechable**.

**Recuperacion (orden de menos a mas agresivo):**

```bash
# 1. Reiniciar Kolibri (suele bastar: reconecta a shards ya auto-recuperadas)
sudo systemctl restart kolibri

# 2. Si persiste: verificar integridad de los shards del cache
for f in /home/akasicom/.kolibri/process_cache/*/cache.db; do
    echo "$f"; sudo -u akasicom sqlite3 "$f" "PRAGMA integrity_check;" | head -1
done

# 3. Si algun shard esta malformed: borrar el cache entero y reiniciar
#    (Kolibri lo reconstruye solo; no se pierde contenido)
sudo systemctl stop kolibri
sudo -u akasicom rm -rf /home/akasicom/.kolibri/process_cache/*
sudo systemctl start kolibri
```

> **Incidente 2026-06-01:** el disco lleno (91%) corrompio el diskcache; Kolibri
> daba 500. `systemctl restart kolibri` lo resolvio. Prevencion: mantener disco
> bajo el umbral de alarma (guard del auto-update = 10 GB libres).

## Verificacion

```bash
# Servicio activo
systemctl status kolibri

# Puerto 8090 escuchando
ss -tlnp | grep 8090

# Listar canales instalados
KOLIBRI_HOME=/home/akasicom/.kolibri sudo -u akasicom kolibri manage listchannels

# Acceso via nginx
curl -I http://192.168.20.10/kolibri/
```
