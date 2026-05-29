# Jellyfin — Configuracion y escaneo automatico de biblioteca

> **Implementado:** 2026-05-29
> **Estado:** En produccion
> **Componente:** `raspberry/rpi-setup/roles/jellyfin/`

Configuracion de acceso sin credenciales y escaneo automatico de la biblioteca de medios de Jellyfin.

## Diferencia fundamental con Kiwix/Kolibri

Jellyfin es un **servidor de media** que indexa archivos del disco. **No existe un repositorio central** de videos como download.kiwix.org o studio.learningequality.org. El contenido (videos comunitarios, educativos, culturales) se agrega manualmente al filesystem y Jellyfin lo indexa.

Lo que se automatiza es el **re-escaneo** de la biblioteca, no la descarga de contenido.

## Acceso sin credenciales

Se configuro un usuario **"Invitado"** sin password y visible en la pantalla de login. El usuario ve la lista de perfiles al entrar a `http://biblioteca.tel/videos/` y hace clic en "Invitado" para acceder.

El admin (`admin`) tiene password y esta oculto de la pantalla publica.

## Directorios de media

| Directorio | Proposito |
|------------|-----------|
| `/var/lib/biblioteca/videos/comunitarios` | Videos de la comunidad |
| `/var/lib/biblioteca/videos/educativos` | Material educativo |
| `/var/lib/biblioteca/videos/culturales` | Contenido cultural |

Todos propiedad de `jellyfin:jellyfin` (mode 0755).

### Agregar contenido

```bash
# Copiar un video
scp video.mp4 raspberry:/tmp/
ssh raspberry "sudo mv /tmp/video.mp4 /var/lib/biblioteca/videos/educativos/ && sudo chown jellyfin:jellyfin /var/lib/biblioteca/videos/educativos/video.mp4"

# Forzar re-escaneo inmediato
ssh raspberry "sudo /usr/local/sbin/scan-jellyfin-library"
```

El cron diario tambien detectara archivos nuevos automaticamente.

## Escaneo automatico

Cron: **diario a las 04:30** (`30 4 * * *`)

El script dispara `POST /Library/Refresh` via la API de Jellyfin con un API key dedicado.

## Archivos

| Archivo | Descripcion |
|---------|-------------|
| `roles/jellyfin/templates/scan-jellyfin-library.sh.j2` | Script de escaneo |
| `roles/jellyfin/tasks/main.yml` | Tasks (dirs, script, cron, logrotate) |
| `rpi-setup/group_vars/all.yml` | Variables `jellyfin_api_key`, `jellyfin_media_dirs` |

## API Key

API key para automatizacion: almacenada en `group_vars/all.yml` como `jellyfin_api_key`. Generada desde el dashboard de Jellyfin (`Dashboard > API Keys`).

## Deploy

```bash
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/jellyfin.yml
```

## Verificacion

```bash
# Escaneo manual
ssh raspberry "sudo /usr/local/sbin/scan-jellyfin-library"

# Usuario publico visible
curl -s http://biblioteca.tel/videos/Users/Public | python3 -m json.tool
# Esperado: usuario "Invitado" con HasPassword: false

# Logs
ssh raspberry "cat /var/log/biblioteca/jellyfin-scan.log"

# Acceso web
# Abrir http://biblioteca.tel/videos/ → ver "Invitado" → clic → acceso directo
```

## Credenciales Jellyfin

| Usuario | Password | Visible | Rol |
|---------|----------|---------|-----|
| admin | admin2026 | No (oculto) | Administrador |
| Invitado | (sin password) | Si | Acceso a todo el contenido |

## Schedule de cron completo en la RPi

| Dia | Hora | Script |
|-----|------|--------|
| Domingo | 03:30 | `update-squid-blocklist` |
| Lun/Jue | 02:00 | `update-kiwix-content` |
| Mar/Vie | 03:00 | `update-kolibri-content` |
| Diario | 04:30 | `scan-jellyfin-library` |
