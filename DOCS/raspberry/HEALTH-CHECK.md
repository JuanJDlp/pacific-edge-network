# Health-check & Panel de estado (RPi)

> **Ultima actualizacion:** 2026-06-01
> **Rol Ansible:** `raspberry/rpi-setup/roles/health_check/`
> **Playbook:** `raspberry/services/health_check.yml`

Sistema de monitoreo ligero que alimenta el indicador de estado del panel de la
biblioteca (`http://biblioteca.tel/`).

> **Nota historica:** este sistema fue agregado en vivo en la RPi y NO estaba en
> Ansible ni documentado hasta el 2026-06-01. El backend (script + units + tune2fs)
> ya esta capturado en el rol `health_check`. El **frontend** (`index.html`,
> `js/status.js`, `css/`) sigue mantenido manualmente en `/var/www/html` de la RPi
> (ver "Pendientes").

## Arquitectura

```
systemd timer (cada 30s)
   └─ biblioteca-health.service (oneshot)
        └─ /opt/biblioteca/scripts/health-check.sh
             └─ escribe /var/www/html/status.json
                  └─ nginx lo sirve en /status (Cache-Control: no-store)
                       └─ js/status.js (navegador) hace fetch cada 30s
                            └─ enciende el indicador del panel (dot + texto)
```

## Que mide `health-check.sh`

| Campo | Fuente |
|-------|--------|
| `services.{nginx,kiwix,squid,jellyfin,kolibri}` | `systemctl is-active` (nginx) / TCP probe a puertos 8080/3128/8096/8090 |
| `system.cpu_temp_c` | `/sys/class/thermal/thermal_zone*/temp` (mayor lectura) |
| `system.disk_used_pct` | `df --output=pcent /var/lib/biblioteca` (fallback `/`) |
| `system.memory_used_pct` | `free -m` |
| `system.active_http_conns` | `ss` conexiones establecidas a `:80` |
| `content.zim_count`, `zim_size_mb` | `find` / `du` en `/var/lib/biblioteca/zim` |
| `thresholds` | parametrizados en `group_vars/all.yml` |

Jellyfin se reporta `N/A` si su unit no existe (status.js no lo cuenta como fallo).

## Logica del indicador (`js/status.js`)

El frontend lee `/status` y decide el color/texto:

| Condicion | Nivel | Texto |
|-----------|-------|-------|
| Algun servicio != OK y != N/A | **fail** (rojo) | `Servicios con problema: ...` |
| `zim_count == 0` | warn | `Sin contenido cargado · ejecutar download-zims.sh` |
| `cpu_temp_c >= 75` **o** `disk_used_pct >= 85` | **fail** (rojo) | **`Sistema sobrecargado · avisar al encargado`** |
| `cpu_temp_c >= 70` **o** `disk_used_pct >= 80` | warn (amarillo) | `Sistema funcionando · revisar pronto` |
| en otro caso | ok (verde) | `Funcionando · N fuentes cargadas` |

> **IMPORTANTE — umbrales duplicados.** `status.js` tiene su PROPIA copia hardcodeada
> de los umbrales (`TEMP_WARN=70`, `TEMP_FAIL=75`, `DISK_WARN=80`, `DISK_FAIL=85`),
> independiente de los `thresholds` que publica `status.json`. Si cambias los
> umbrales en `group_vars/all.yml`, **actualiza tambien** `/var/www/html/js/status.js`.

## Relacion con el disco (incidente 2026-06-01)

El mensaje rojo **"Sistema sobrecargado · avisar al encargado"** se disparo porque el
disco supero el **85%** (el auto-update de Kolibri lo lleno al 91%). Ver
[`KOLIBRI.md`](KOLIBRI.md) (presupuesto de disco) y
[`kolibri-auto-update/README.md`](kolibri-auto-update/README.md). El auto-update
ahora se detiene antes del 85% (guard `MIN_FREE_MB=10000`).

El rol `health_check` tambien baja los **reserved blocks de ext4 al 1%**
(`tune2fs -m {{ rpi_reserved_pct }}`) para recuperar ~2 GB de espacio util.

## Archivos

| Componente | Ruta en RPi | Gestionado por |
|-----------|-------------|----------------|
| Script | `/opt/biblioteca/scripts/health-check.sh` | Ansible (`health_check`) |
| Service | `/etc/systemd/system/biblioteca-health.service` | Ansible |
| Timer | `/etc/systemd/system/biblioteca-health.timer` | Ansible |
| JSON de salida | `/var/www/html/status.json` | generado en runtime |
| Frontend | `/var/www/html/index.html`, `js/status.js`, `css/` | **manual** (pendiente) |

## Verificacion

```bash
# Timer activo
systemctl status biblioteca-health.timer

# Forzar una corrida y ver el JSON
sudo systemctl start biblioteca-health.service
curl -s http://biblioteca.tel/status | jq .

# Disco
df -h /
```

## Pendientes

- El frontend del panel (`index.html`, `js/status.js`, `css/`) aun no esta en
  Ansible. `index.html` es mutado en runtime por el auto-update de Kiwix (reescribe
  la fecha del ZIM), por lo que no puede ser un template estatico tal cual; requiere
  una estrategia aparte si se quiere versionar.
