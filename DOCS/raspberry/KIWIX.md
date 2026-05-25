# Kiwix — Servidor de contenido offline (Wikipedia y ZIM)

## Rol Ansible

`raspberry/rpi-setup/roles/kiwix/`

## Descripción

Kiwix sirve archivos ZIM (Wikipedia, otras enciclopedias) en el puerto 8080 del loopback. Los clientes nunca acceden directamente — nginx proxea `/wikipedia/` y los demás paths de Kiwix.

## Configuración del servicio

```
ExecStart=/usr/local/bin/kiwix-serve \
    --address=127.0.0.1 \
    --port=8080 \
    --library /var/lib/biblioteca/zim/library.xml
```

- **Vinculado a loopback**: los clientes pasan siempre por nginx
- **library.xml**: catálogo de archivos ZIM disponibles
- **Usuario**: `kiwix` (sin shell, sin home)

## Paths accesibles vía nginx

| URL cliente | Comportamiento |
|------------|----------------|
| `http://biblioteca.tel/wikipedia/` | Rewrite a `/` y proxea a Kiwix — URL amigable para usuarios |
| `http://biblioteca.tel/content/` | Proxy transparente (archivos ZIM internos) |
| `http://biblioteca.tel/skin/` | Assets CSS/JS de la interfaz Kiwix |
| `http://biblioteca.tel/search` | Búsqueda de artículos |
| `http://biblioteca.tel/catalog/` | Catálogo de libros |

## Archivos importantes en RPi

| Ruta | Descripción |
|------|-------------|
| `/etc/systemd/system/kiwix-serve.service` | Systemd unit (desplegado por Ansible) |
| `/var/lib/biblioteca/zim/library.xml` | Catálogo de ZIMs |
| `/var/lib/biblioteca/zim/*.zim` | Archivos de contenido |
| `/var/log/biblioteca/` | Logs de kiwix-serve |

## Hardening del servicio

```systemd
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=/var/lib/biblioteca/zim
MemoryMax=1G
CPUQuota=200%
```

## Agregar nuevo contenido ZIM

```bash
# 1. Descargar un ZIM (en RPi)
wget -P /var/lib/biblioteca/zim/ https://download.kiwix.org/zim/...

# 2. Agregar al catálogo
sudo -u kiwix kiwix-manage /var/lib/biblioteca/zim/library.xml add /var/lib/biblioteca/zim/archivo.zim

# 3. Reiniciar kiwix
sudo systemctl restart kiwix-serve
```

## Archivos desplegados por Ansible

| Template | Destino |
|----------|---------|
| `templates/kiwix-serve.service.j2` | `/etc/systemd/system/kiwix-serve.service` |

## Verificación

```bash
# Servicio activo
systemctl status kiwix-serve

# Puerto 8080 escuchando
ss -tlnp | grep 8080

# Acceso directo (desde RPi)
curl -s http://127.0.0.1:8080/ | head -5

# Acceso vía nginx (desde cliente)
curl -I http://192.168.20.10/wikipedia/
```
