# Kolibri — Auto-actualizacion de canales educativos

> **Implementado:** 2026-05-29
> **Ultima actualizacion:** 2026-06-01
> **Estado:** En produccion
> **Componente:** `raspberry/rpi-setup/roles/kolibri/`

Sistema automatico que mantiene actualizados los canales educativos de Kolibri descargando contenido nuevo desde Kolibri Studio.

## Problema que resuelve

Kolibri sirve canales educativos que se publican con actualizaciones periodicas en studio.learningequality.org. Sin auto-update, el contenido se desactualiza y los estudiantes no acceden a lecciones nuevas.

## Que hace

1. Verifica conectividad a Kolibri Studio
2. **Orphan cleanup:** borra el contenido de cualquier canal instalado que ya no
   este en `kolibri_channels` (`deletecontent <id> -f`). Invariante: nada en disco
   que no se este sirviendo.
3. Para cada canal configurado:
   - Chequea espacio libre (guard `MIN_FREE_MB`, ver abajo) y se detiene si no hay margen
   - `importchannel network <id>` — descarga metadata (rapido)
   - `importcontent network <id>` — descarga contenido nuevo (resumable, **skip existente** = idempotente)
4. Kolibri detecta automaticamente el contenido nuevo sin reinicio

## Canales configurados (4 canales, ~38 GB total)

| Canal | ID | Tamano aprox. |
|-------|----|---------------|
| Khan Academy Espanol | `c1f2b7e6ac9f56a2bb44fa7a48b66dce` | ~36.6 GB |
| EiE Familias | `359e048230974c8f80db1a95dc80d544` | 0.1 GB |
| Proyecto Biosfera | `f446655247a95c0aa94ca9fa4d66783b` | 0.2 GB |
| Biblioteca Elejandria | `fed29d60e4d84a1e8dcfc781d920b40e` | 0.9 GB |

> **Ciencia NASA** (`da53f90b...`, 3.1 GB) removido el 2026-06-01 por falta de espacio.

**Disco RPi:** 59G total (~62.4 GB), 81% usado, ~12 GB libre.

## Guard de disco vs. alarma del panel (CRITICO)

El panel de estado marca **"Sistema sobrecargado"** al **85%** de disco (ver
[`../HEALTH-CHECK.md`](../HEALTH-CHECK.md)). El guard del script debe parar de
descargar **antes** de ese punto:

- `MIN_FREE_MB=10000` → se detiene con <10 GB libres (~84%), bajo el 85% de alarma.

> **Incidente 2026-06-01:** con el guard antiguo (4 GB ≈ 93%) el auto-update lleno
> el disco al 91%, disparo la alarma y corrompio el diskcache de Kolibri (500). Se
> subio el guard a 10 GB, se removio NASA y se bajo la reserva ext4 a 1%
> (`tune2fs -m 1`). Ver [`../KOLIBRI.md`](../KOLIBRI.md) (troubleshooting 500).

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
  # + EiE Familias, Proyecto Biosfera, Biblioteca Elejandria, Ciencia NASA
```

Para agregar un canal: buscar el ID en studio.learningequality.org, importarlo manualmente la primera vez, y agregarlo a la lista.

### Usuario y KOLIBRI_HOME

- **Usuario:** `akasicom`
- **KOLIBRI_HOME:** `/home/akasicom/.kolibri`

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
