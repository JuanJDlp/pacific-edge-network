# Kolibri — Plataforma educativa offline (Khan Academy)

## Rol Ansible

`raspberry/rpi-setup/roles/kolibri/`

## Descripción

Kolibri es una plataforma de aprendizaje offline que incluye contenidos de Khan Academy, CK-12, y otras fuentes educativas. Corre en el puerto 8090 del loopback y es accesible vía nginx en `/kolibri/`.

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

## Configuración de Kolibri

Kolibri almacena su configuración y base de datos en:
```
/home/kolibri/.kolibri/
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

# O desde línea de comandos en RPi
sudo kolibri manage importchannel --channel-id <ID>
sudo kolibri manage importcontent --channel-id <ID>
```

## Verificación

```bash
# Servicio activo
systemctl status kolibri

# Puerto 8090 escuchando
ss -tlnp | grep 8090

# Acceso vía nginx
curl -I http://192.168.20.10/kolibri/
```
