# Jellyfin — Servidor de video educativo

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

## Almacenamiento de video

Jellyfin lee bibliotecas de medios definidas en su configuración:
```
/etc/jellyfin/           # configuración del servidor
/var/lib/jellyfin/       # base de datos, metadatos, miniaturas
```

Las bibliotecas de video deben apuntar a directorios con los archivos `.mp4`, `.mkv`, etc.

## Agregar contenido

```bash
# 1. Copiar videos a un directorio accesible por jellyfin
sudo cp video.mp4 /media/videos/
sudo chown jellyfin:jellyfin /media/videos/video.mp4

# 2. Desde la interfaz web, agregar la carpeta como nueva biblioteca
# http://biblioteca.local/videos/ → Dashboard → Bibliotecas → Agregar
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
