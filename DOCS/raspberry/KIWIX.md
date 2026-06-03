# Kiwix — Servidor de contenido offline (Wikipedia y ZIM)

> **Ultima actualizacion:** 2026-05-30

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

## ZIMs actuales (snapshot 2026-06-01)

| Archivo ZIM | Tamano |
|-------------|--------|
| wikipedia_es_all_mini_2026-05.zim | ~3.4 GB |
| wikibooks_es_all_nopic_2025-10.zim | 107 MB |
| wikivoyage_es_all_nopic_2026-03.zim | 37 MB |
| wikinews_es_all_nopic_2026-04.zim | 34 MB |
| wikiversity_es_all_nopic_2026-04.zim | 18 MB |

> **El nombre del ZIM incluye la fecha**, y la URL de contenido tambien
> (`/content/wikipedia_es_all_mini_2026-05/`). Cuando el auto-update cambia la
> version, los links viejos (`.../2026-02/`) dan **404** en Kiwix.
>
> **Cambio 2026-06-02:** el `index.html` del portal YA NO embebe las versiones
> de los ZIMs y el cron de auto-update YA NO lo muta con `sed`. Las tarjetas
> llevan `data-zim-category` y `/js/library.js` consulta `/catalog/v2/entries`
> para resolver el href al nombre versionado actual (ver [`NGINX.md`](NGINX.md)).
> El HTML del panel sigue saliendo con `Cache-Control: no-cache` para que Squid
> no sirva una version vieja del propio HTML.

## Paths accesibles via nginx

| URL cliente | Comportamiento |
|------------|----------------|
| `http://biblioteca.tel/wikipedia/` | Rewrite a `/` y proxea a Kiwix — URL amigable para usuarios |
| `http://biblioteca.tel/content/` | Proxy transparente (archivos ZIM internos) |
| `http://biblioteca.tel/skin/` | Assets CSS/JS de la interfaz Kiwix |
| `http://biblioteca.tel/search` | Búsqueda global multi-ZIM — destino del buscador del homepage |
| `http://biblioteca.tel/suggest` | Sugerencias para autocomplete (no usado aun) |
| `http://biblioteca.tel/random` | Articulo al azar — alimenta la fila "Descubre" del homepage |
| `http://biblioteca.tel/catalog/` | Catalogo OPDS — leido por `/js/library.js` para resolver versiones |

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

## Auto-actualizacion de contenido

Los ZIMs se actualizan automaticamente via cron (lunes y jueves a las 02:00). Documentacion completa en [`kiwix-auto-update/`](kiwix-auto-update/).

## Agregar nuevo contenido ZIM

```bash
# 1. Descargar un ZIM (en RPi)
wget -P /var/lib/biblioteca/zim/ https://download.kiwix.org/zim/...

# 2. Agregar al catálogo
sudo -u kiwix kiwix-manage /var/lib/biblioteca/zim/library.xml add /var/lib/biblioteca/zim/archivo.zim

# 3. Reiniciar kiwix
sudo systemctl restart kiwix-serve

# 4. Agregar a kiwix_zim_sources en group_vars/all.yml para auto-update
```

## Archivos desplegados por Ansible

| Template | Destino |
|----------|---------|
| `templates/kiwix-serve.service.j2` | `/etc/systemd/system/kiwix-serve.service` |
| `templates/update-kiwix-content.sh.j2` | `/usr/local/sbin/update-kiwix-content` |

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
