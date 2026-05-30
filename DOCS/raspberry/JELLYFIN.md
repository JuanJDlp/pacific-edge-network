# Jellyfin — Servidor de video educativo

> **Ultima actualizacion:** 2026-05-30

## Rol Ansible

`raspberry/rpi-setup/roles/jellyfin/`

## Descripción

Jellyfin sirve videos educativos almacenados en la RPi. Corre en el puerto 8096 del loopback y es accesible vía nginx en `/videos/`. Los clientes pueden ver videos sin necesidad de internet.

## Detalles del servicio

```
# /usr/lib/systemd/system/jellyfin.service
# Instalado vía paquete apt
Type=simple
User=jellyfin
ExecStart=/usr/bin/jellyfin ...
```

Ansible solo asegura que el servicio esté `enabled` y `started`. La configuración (bibliotecas, usuarios, metadatos) se gestiona vía la interfaz web.

## Acceso vía nginx

```nginx
location /videos/ {
    proxy_pass http://jellyfin_backend/;   # trailing slash: strip /videos/
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 6h;    # streaming de video largo
    proxy_send_timeout 6h;
}
```

El trailing slash en `proxy_pass` hace que nginx reemplace `/videos/` antes de enviar a Jellyfin — Jellyfin no sabe que está montado en `/videos/`.

Los timeouts de 6 horas permiten reproducir videos sin interrupciones.

## Bibliotecas configuradas

Jellyfin tiene 3 bibliotecas configuradas:

| Biblioteca | Directorio | Contenido |
|------------|-----------|-----------|
| Comunitarios | `/var/lib/biblioteca/videos/comunitarios` | Videos de la comunidad |
| Educativos | `/var/lib/biblioteca/videos/educativos` | Material educativo |
| Culturales | `/var/lib/biblioteca/videos/culturales` | Contenido cultural |

## Videos actuales

| Video | Tamano |
|-------|--------|
| test.mp4 | 1.1 MB |
| Tiburones-Discovery | 133 MB |
| Tierra Fragil | 293 MB |
| WOW-Discovery | 290 MB |
| Cueva de los Tallos | 107 MB |
| **Total** | **~823 MB** |

## Almacenamiento

```
/etc/jellyfin/           # configuracion del servidor
/var/lib/jellyfin/       # base de datos, metadatos, miniaturas
/var/lib/biblioteca/videos/
├── comunitarios/    # Videos de la comunidad
├── educativos/      # Material educativo
└── culturales/      # Contenido cultural
```

## Credenciales

| Usuario | Password | Visible en login | Rol |
|---------|----------|-------------------|-----|
| admin | admin2026 | No (oculto) | Administrador |
| Invitado | (sin password) | Si | Acceso a todo el contenido |

Documentacion completa en [`jellyfin-config/`](jellyfin-config/).

## API Key

API key para automatizacion: `1e2ba6b4e3ca45aa95627eddc7f46bf2`

Generada desde el dashboard de Jellyfin (`Dashboard > API Keys`). Almacenada tambien en `group_vars/all.yml` como `jellyfin_api_key`.

## Escaneo automatico de biblioteca

Cron diario a las 04:30 re-escanea la biblioteca para indexar archivos nuevos. El script dispara `POST /Library/Refresh` via la API con el API key. Documentacion en [`jellyfin-config/`](jellyfin-config/).

## Agregar contenido

```bash
# 1. Copiar videos a un directorio de media
sudo cp video.mp4 /var/lib/biblioteca/videos/educativos/
sudo chown jellyfin:jellyfin /var/lib/biblioteca/videos/educativos/video.mp4

# 2. Forzar re-escaneo (o esperar al cron diario)
sudo /usr/local/sbin/scan-jellyfin-library
```

## Verificación

```bash
# Servicio activo
systemctl status jellyfin

# Puerto 8096 escuchando
ss -tlnp | grep 8096

# Acceso vía nginx
curl -I http://192.168.20.10/videos/

# Logs
journalctl -u jellyfin -f
```
