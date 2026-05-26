# Jellyfin — Servidor de Medios

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/jellyfin/`
**Servicio systemd:** `jellyfin`
**Puerto interno:** `127.0.0.1:8096`
**Acceso de clientes:** `http://biblioteca.tel/videos/`

---

## Qué hace

Jellyfin es un servidor de medios de código abierto que organiza y sirve videos, música e imágenes almacenados en la RPi. Los clientes pueden explorar y reproducir contenido multimedia sin conexión a internet, directamente desde el browser o apps nativas de Jellyfin.

---

## Exposición al exterior

Jellyfin escucha en **loopback** (`127.0.0.1:8096`). Los clientes acceden a través de nginx:

```
http://biblioteca.tel/videos/
```

nginx proxea el path `/videos/` hacia `jellyfin_backend` con soporte completo para WebSockets (usados por el cliente web de Jellyfin para sincronización de estado y notificaciones) y timeouts muy largos para streams de video.

---

## Configuración nginx para Jellyfin

Jellyfin requiere:

- **WebSockets** — para sincronización del cliente web (`$http_upgrade`, `$connection_upgrade`)
- **Timeouts extremadamente largos** — `proxy_read_timeout 6h` y `proxy_send_timeout 6h` para streams de video de larga duración
- `proxy_buffering off` — entrega directa sin buffer (evita acumular videos en memoria de nginx)
- `X-Forwarded-Proto` — para que Jellyfin sepa que está detrás de un proxy

---

## Organización del contenido

Jellyfin organiza el contenido en **bibliotecas** (carpetas). Cada biblioteca tiene un tipo:

| Tipo | Contenido |
|---|---|
| Movies | Películas (uno o varios archivos de video) |
| Shows | Series de TV (carpetas por temporada/episodio) |
| Music | Música (organizada por artista/álbum) |
| Books | Libros/documentos |

El contenido se almacena en el sistema de archivos de la RPi, típicamente bajo `/media/` o `/var/lib/jellyfin/data/`.

---

## Transcodificación

Jellyfin puede transcodificar video en tiempo real si el formato del archivo no es compatible con el browser del cliente. En la RPi 5 esto funciona con aceleración de hardware (video core). En hardware más limitado, la transcodificación puede ser lenta — se recomienda usar formatos compatibles directamente (H.264/MP4).

---

## Gestión de usuarios

Jellyfin tiene su propio sistema de usuarios:
- **Admin** — gestiona el servidor, agrega bibliotecas, crea usuarios
- **Usuarios** — acceden al contenido según los permisos del admin

El primer acceso configura el admin y las bibliotecas.

---

## Flujo de reproducción de un video

```
[Cliente en VLAN30]
    │ GET http://biblioteca.tel/videos/
    ▼
[nginx RPi :80]
    │ proxy_pass jellyfin_backend :8096
    │ WebSocket upgrade para cliente web
    ▼
[Jellyfin :8096]
    │ sirve la interfaz web
    │ cliente selecciona película
    │ stream de video desde disco
    ▼
[nginx → cliente]
    │ proxy_buffering off → stream directo
    │ timeouts de 6h para no cortar streams largos
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status jellyfin

# Logs de Jellyfin
sudo journalctl -u jellyfin -f

# Ver espacio del contenido
sudo du -sh /var/lib/jellyfin/

# Reiniciar si hay problemas
sudo systemctl restart jellyfin

# Acceso admin (desde VLAN10 o NetBird, directo sin nginx)
# http://192.168.20.10:8096
```

---

## Deploy

El rol solo habilita e inicia el servicio (Jellyfin se instala por separado desde su repositorio oficial):

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags jellyfin
# o:
ansible-playbook services/jellyfin.yml -i rpi-setup/inventory.ini
```
