# Kolibri — Auto-actualizacion de canales educativos

> **Implementado:** 2026-05-29
> **Estado:** En produccion
> **Componente:** `raspberry/rpi-setup/roles/kolibri/`

Sistema automatico que mantiene actualizados los canales educativos de Kolibri (Khan Academy, etc.) descargando contenido nuevo desde Kolibri Studio.

## Problema que resuelve

Kolibri sirve canales educativos que se publican con actualizaciones periodicas en studio.learningequality.org. Sin auto-update, el contenido se desactualiza y los estudiantes no acceden a lecciones nuevas.

## Que hace

1. Verifica conectividad a Kolibri Studio
2. Para cada canal configurado:
   - `importchannel network <id>` — descarga metadata (rapido)
   - `importcontent network <id>` — descarga contenido nuevo (resumable, skip existente)
3. Kolibri detecta automaticamente el contenido nuevo sin reinicio

## Diferencias con Kiwix auto-update

| Aspecto | Kiwix | Kolibri |
|---------|-------|---------|
| Fuente | download.kiwix.org (archivos ZIM) | studio.learningequality.org (canales) |
| Mecanismo | curl + atomic swap | `kolibri manage` CLI (nativo) |
| Restart | Si (kiwix-serve) | No (Kolibri detecta cambios) |
| Resume | curl `--continue-at -` | Nativo (skip contenido existente) |
| Cleanup | Elimina ZIM viejo | No necesario (Kolibri maneja DB) |

## Archivos

| Archivo | Descripcion |
|---------|-------------|
| `roles/kolibri/templates/update-kolibri-content.sh.j2` | Script principal |
| `roles/kolibri/tasks/main.yml` | Tasks de deploy (script + cron + logrotate) |
| `rpi-setup/group_vars/all.yml` | Variables `kolibri_channels`, `kolibri_user`, `kolibri_home` |

## Configuracion

### Canales (`group_vars/all.yml`)

```yaml
kolibri_channels:
  - { id: "c1f2b7e6ac9f56a2bb44fa7a48b66dce", name: "Khan Academy (Español)" }
```

Para agregar un canal: buscar el ID en studio.learningequality.org, importarlo manualmente la primera vez, y agregarlo a la lista.

### Schedule

Cron: **martes y viernes 03:00** (`0 3 * * 2,5`)

### Acceso sin credenciales

Kolibri esta configurado con:
- `landing_page = learn` — muestra contenido directamente
- `allow_guest_access = True` — navegacion anonima
- `allow_other_browsers_to_connect = True`

URL: `http://biblioteca.tel/kolibri/`

## Deploy

```bash
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/kolibri.yml
```

## Verificacion

```bash
# Script manual
ssh raspberry "sudo /usr/local/sbin/update-kolibri-content"

# Canales importados
ssh raspberry "KOLIBRI_HOME=/home/akasicom/.kolibri sudo -u akasicom kolibri manage listchannels"

# Acceso sin login
curl -sIL http://biblioteca.tel/kolibri/ | grep -E 'HTTP|Location'
# Esperado: 302 → /kolibri/es-419/ → 302 → /kolibri/es-419/learn/ → 200

# Logs
ssh raspberry "cat /var/log/biblioteca/kolibri-update.log"
```
