# Auto-update del contenido de la biblioteca (RPi)

> Actualizado: 2026-05-30

La Raspberry Pi hospeda tres servicios de contenido offline: **Kiwix** (Wikipedia y proyectos hermanos en ZIM), **Kolibri** (canales educativos) y **Jellyfin** (videos comunitarios/educativos/culturales). Cuando el nodo tiene WAN, los tres se actualizan automaticamente sin intervencion: detectan versiones nuevas, descargan con resume y rate-limit, swappean atomicamente y reinician el servicio. Esta doc explica cada flujo, los scripts, los crons y como operarlos.

## 1. Resumen de scripts y schedule

| Servicio | Script | Cron (root) | Logs |
|---|---|---|---|
| Kiwix ZIM | `/usr/local/sbin/update-kiwix-content` | `0 2 * * 1,4` (Lun/Jue 02:00) | `/var/log/biblioteca/kiwix-update.log` |
| Kolibri | `/usr/local/sbin/update-kolibri-content` | `0 3 * * 2,5` (Mar/Vie 03:00) | `/var/log/biblioteca/kolibri-update.log` |
| Jellyfin scan | `/usr/local/sbin/scan-jellyfin-library` | `30 4 * * *` (diario 04:30) | `/var/log/biblioteca/jellyfin-scan.log` |
| Squid blocklist | `/usr/local/sbin/update-squid-blocklist` | `30 3 * * 0` (Dom 03:30) | `/var/log/squid-blocklist.log` |

Roles Ansible que despliegan los scripts y crons:
- `raspberry/rpi-setup/roles/kiwix/`
- `raspberry/rpi-setup/roles/kolibri/`
- `raspberry/rpi-setup/roles/jellyfin/`
- `raspberry/rpi-setup/roles/squid/`

Las listas de canales/ZIMs y la API key de Jellyfin viven en `raspberry/rpi-setup/group_vars/all.yml` — agregar contenido nuevo es editar esa lista y re-correr el role.

Todos los scripts comparten patrones:
- `set -euo pipefail` para fail-fast.
- `flock -n` para evitar dos instancias simultaneas (cron y operador manual).
- `wan_check()` antes de descargar — si no hay internet, exit limpio.
- `logger -t <tag>` ademas de stdout → tambien quedan en `journalctl SYSLOG_IDENTIFIER=<tag>`.
- Verificacion de disco minimo (`MIN_FREE_MB=4000`) antes de bajar nada grande.

---

## 2. Kiwix — `update-kiwix-content`

### 2.1. Que actualiza

La lista de ZIMs vive en `group_vars/all.yml`:

```yaml
kiwix_zim_sources:
  - { category: "wikipedia",   prefix: "wikipedia_es_all_mini" }
  - { category: "wikibooks",   prefix: "wikibooks_es_all_nopic" }
  - { category: "wikinews",    prefix: "wikinews_es_all_nopic" }
  - { category: "wikiversity", prefix: "wikiversity_es_all_nopic" }
  - { category: "wikivoyage",  prefix: "wikivoyage_es_all_nopic" }
```

Cada item es **el prefijo del nombre** del archivo en `https://download.kiwix.org/zim/<category>/`. Los ZIMs reales se nombran `<prefix>_YYYY-MM.zim` (e.g. `wikipedia_es_all_mini_2026-05.zim`). El prefijo permite seguir la "rama" del ZIM y solo bajar la version nueva.

### 2.2. Flujo

Para cada entry:

```
1. current  = ls ZIM_DIR/<prefix>_*.zim → tomar el ultimo (mayor fecha)
2. latest   = scrape HTML de download.kiwix.org/zim/<category>/
              y filtrar href="<prefix>_YYYY-MM.zim"
3. if current == latest  → log "up to date", continuar
4. remote_size = curl -I (Content-Length)
5. free_mb = df --output=avail
   if free_mb < remote_size + 500MB OR < MIN_FREE_MB  → skip
6. curl -fSL --limit-rate 2M --continue-at - -o ZIM_DIR/<latest>.tmp <url>
7. verificar size local == remote_size → si no coincide, borrar tmp
8. atomic swap:
   a. mv .tmp → final, chown kiwix:kiwix
   b. kiwix-manage library.xml add <latest>     # registra el nuevo antes
   c. kiwix-manage library.xml remove <old_id>  # quita el viejo
   d. sed -i homepage: reemplaza stem viejo → stem nuevo
   e. rm ZIM_DIR/<current>
9. RESTART_NEEDED = true
```

Al terminar todos los entries, si hubo cambios:
```
systemctl restart kiwix-serve
```

### 2.3. Detalles tecnicos importantes

- **Rate limit `--limit-rate 2M`** (≈ 7 GB/h). Evita saturar el enlace comunitario; los ZIMs pueden ser 20-40 GB. Una update de Wikipedia ES puede tardar 3-6 h con paciencia.
- **`--continue-at -`** habilita resume: si el cron muere o la WAN se cae a medio download, el siguiente run continua desde donde quedo. El `.tmp` se conserva.
- **Limpieza de `.tmp` stale**: al inicio del script, antes del loop, revisa todos los `.zim.tmp` en `ZIM_DIR` y borra los que no correspondan a un `latest` actual (e.g. quedo un `wikipedia_es_all_mini_2026-04.zim.tmp` cuando ya salio `2026-05`).
- **Atomic swap "add antes que remove"**: agrega el nuevo book a `library.xml`, luego elimina el viejo. Asi nunca hay una ventana donde `library.xml` no contenga ningun Wikipedia.
- **Reinicio agrupado**: `systemctl restart kiwix-serve` se hace **una sola vez** al final (variable `RESTART_NEEDED`). Si actualizo 5 ZIMs, no se reinicia 5 veces.
- **`get_book_id`** parsea `library.xml` con grep/regex para encontrar el id que tiene el `path="..."` matcheando el stem (ej. `wikipedia_es_all_mini_2026-04`). Es ligero (sin XML parser).

### 2.4. Cuando NO actualiza

- Si no hay `current` (es decir, el prefix nunca se instalo): `WARNING: no current ZIM for <prefix> — skipping (install manually first)`. La idea es que la primera instalacion es manual (decision de la operadora sobre cuanto disco gastar). Una vez instalado, las updates automaticas siguen el riel.
- Si `wan_check` falla (no llega a `download.kiwix.org/zim/`): `No internet — skipping`.
- Si no hay espacio: log de error y skip de ESE prefix (sigue con los demas).
- Si lockfile existente (`/run/lock/kiwix-update.lock`): `Another instance is running — exiting`.

### 2.5. Verificacion

```bash
# Forzar un run manual
sudo /usr/local/sbin/update-kiwix-content

# Ver libreria registrada en kiwix-serve
sudo cat /var/lib/biblioteca/zim/library.xml | grep -o 'path="[^"]*"'

# Ver ZIMs en disco vs library
ls -la /var/lib/biblioteca/zim/*.zim

# Ultimos eventos
tail -50 /var/log/biblioteca/kiwix-update.log
journalctl -t kiwix-update -n 50

# Status del servicio
systemctl status kiwix-serve
```

---

## 3. Kolibri — `update-kolibri-content`

### 3.1. Que actualiza

Lista de canales en `group_vars/all.yml`:

```yaml
kolibri_channels:
  - { id: "c1f2b7e6ac9f56a2bb44fa7a48b66dce", name: "Khan Academy (Español)" }
  - { id: "359e048230974c8f80db1a95dc80d544", name: "EiE Familias (español)" }
  - { id: "f446655247a95c0aa94ca9fa4d66783b", name: "Proyecto Biosfera" }
  - { id: "fed29d60e4d84a1e8dcfc781d920b40e", name: "Biblioteca Elejandria" }
  - { id: "da53f90b1be25752a04682bbc353659f", name: "Ciencia NASA" }
```

Cada `id` es el UUID del canal en `https://studio.learningequality.org` (catalogo publico).

### 3.2. Flujo

Para cada canal:

```
1. check disk: free_mb < MIN_FREE_MB → break (no seguir bajando)
2. kolibri manage importchannel network <channel_id>
   (baja solo el metadata DB del canal — rapido)
3. kolibri manage importcontent network <channel_id>
   (baja los recursos reales: videos, PDFs, ejercicios — resumable)
4. UPDATE_COUNT++
```

Ambos comandos corren con `sudo -u akasicom KOLIBRI_HOME=/home/akasicom/.kolibri kolibri manage ...`. Necesitamos el `KOLIBRI_HOME` correcto porque Kolibri tiene su DB SQLite ahi (`/home/akasicom/.kolibri/db.sqlite3`).

### 3.3. Detalles tecnicos

- **`importchannel` siempre primero**: actualiza el catalogo del canal (que recursos hay, sus hashes). Sin esto, `importcontent` no sabe que bajar.
- **`importcontent` es resumable** por design: usa hashes de archivos. Si un archivo ya esta y su hash coincide, lo salta. Si esta parcial, continua. Si la lista crece (canal agrego cosas), las cosas nuevas se bajan; las viejas no se vuelven a bajar.
- **No filtra por nodo**: baja TODOS los recursos del canal. Para canales muy grandes (Khan Academy crecio a ~37 GB) eso significa que la primera importacion es lenta y pesada. Updates incrementales son rapidas.
- **`logger -t kolibri-update` por linea** ademas del log file: cada linea de output de `kolibri manage` se replica a syslog en tiempo real (`while IFS= read -r line; do echo "$line"; logger -t kolibri-update "$line"; done`).
- **`systemctl is-active --quiet kolibri`** antes de empezar: si el servicio esta caido lo levanta + `sleep 5` para que termine de boot. Kolibri en Pi 4 tarda ~3-4 s en arrancar.
- **Salida temprana por disco**: en cuanto `free_mb < MIN_FREE_MB`, se rompe el loop (`break`). No se intentan los canales restantes — evita corromper otros canales por escritura interrumpida.

### 3.4. Caso especial: el servicio bloqueado

Si el script importa canales con `kolibri manage importcontent` mientras `kolibri.service` esta ACTIVO, hay un caso en el que el servicio se queda en 500: el script y el servicio comparten DB SQLite y, si la importacion modifica el schema interno (rara vez), el servicio queda con cache obsoleto. La solucion historica fue `sudo systemctl restart kolibri` al detectar 500. El script actual mitiga llamando `kolibri manage` siempre como el mismo usuario (`akasicom`) que corre el servicio. Aun asi, si despues de una update el `:8090` da 500, reiniciar es la primera accion.

### 3.5. Verificacion

```bash
# Run manual
sudo /usr/local/sbin/update-kolibri-content

# Listar canales registrados
sudo -u akasicom KOLIBRI_HOME=/home/akasicom/.kolibri \
    kolibri manage list_channels

# Status + logs
systemctl status kolibri
tail -50 /var/log/biblioteca/kolibri-update.log
journalctl -t kolibri-update -n 50

# Test que la API responde
curl -sI http://127.0.0.1:8090/
```

---

## 4. Jellyfin — `scan-jellyfin-library`

### 4.1. Que hace

Jellyfin **no descarga** contenido — los videos se copian manualmente (o via futuro pipeline, p.ej. desde Internet Archive). Lo que el script automatiza es disparar el **library scan** que indexa archivos nuevos en los tres directorios:

```yaml
jellyfin_media_dirs:
  - /var/lib/biblioteca/videos/comunitarios
  - /var/lib/biblioteca/videos/educativos
  - /var/lib/biblioteca/videos/culturales
```

Sin el scan, copiar un archivo .mp4 a uno de esos dirs no lo hace aparecer en la UI. El cron diario garantiza que cualquier video copiado durante el dia este indexado para la manana siguiente.

### 4.2. Flujo

```bash
JELLYFIN_URL="http://127.0.0.1:8096"
API_KEY="<configurada en group_vars/all.yml>"

if ! systemctl is-active --quiet jellyfin; then
    systemctl start jellyfin
    sleep 5
fi

curl -fsSL -X POST "${JELLYFIN_URL}/Library/Refresh?api_key=${API_KEY}"
```

`POST /Library/Refresh` retorna 204 inmediato y arranca el scan en background. Tipicamente termina en menos de 30 s para nuestra coleccion (~4 videos × 3 libraries). En logs de Jellyfin (`journalctl -u jellyfin`) se ve la actividad de cada library.

### 4.3. Por que via API y no FS watcher

Jellyfin tiene un FS watcher interno que detecta cambios en directorios. Pero en la Pi con SD card el watcher consume CPU constante y dispara muchos falsos positivos (touch de logs, locks). El cron + API es mas barato y predecible.

### 4.4. API key

La key se genero una vez via la UI de Jellyfin (`Dashboard → API Keys → New API Key`) y quedo en `group_vars/all.yml`. Como es un secreto compartido al repo, se rotara cuando se cambie el patron de hosting. Mientras tanto es aceptable porque Jellyfin solo escucha en `127.0.0.1:8096` (los clientes lo ven via reverse proxy nginx → ningun externo puede usar la key).

### 4.5. Verificacion

```bash
# Trigger manual
sudo /usr/local/sbin/scan-jellyfin-library

# Ver librerias actuales
curl -s "http://127.0.0.1:8096/Library/VirtualFolders?api_key=${API_KEY}" | jq '.[].Name'

# Ver items indexados por libreria
curl -s "http://127.0.0.1:8096/Items?api_key=${API_KEY}&Recursive=true&IncludeItemTypes=Movie,Video" \
    | jq '.Items[].Name'

# Logs
tail -50 /var/log/biblioteca/jellyfin-scan.log
journalctl -u jellyfin --since "10 minutes ago" | grep -i refresh
```

---

## 5. Squid blocklist — `update-squid-blocklist`

Aunque no es estrictamente "contenido", sigue el mismo patron de cron + script idempotente. Descarga las listas `porn-only` y `gambling-only` de StevenBlack/hosts y arma `/etc/squid/blocklists/blocked_domains.txt`.

```bash
SOURCES=(
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
)
```

Flujo:
1. `curl -fsSL` cada source a un `/tmp/srcN.txt`.
2. `awk '/^0\.0\.0\.0/ {print $2}'` extrae los dominios.
3. `grep -Ev '^(localhost|broadcasthost|ip6-...)'` filtra ruido.
4. `sort -u` deduplica.
5. **Sanity check**: si `wc -l` da menos de 1000, aborta (probablemente la lista descargada esta corrupta). Mantiene la lista anterior.
6. `cmp -s` con el actual → si no hay cambios, exit sin reload.
7. Si cambio: `install -m 0644 ...` + `systemctl reload squid` (no restart — Squid hot-reloads su ACL list).

Tiene su homologo en el Mini PC: `update-bind-rpz` para la zona `rpz.blocklist` (mismas fuentes, formato RPZ en vez de hosts). Ver `DOCS/minipc/DNS-BIND9.md`.

---

## 6. Patrones comunes a recordar

### 6.1. Idempotencia
Los scripts se pueden correr 100 veces seguidas; los runs sin cambio salen con `No changes — skipping reload`. Esto es clave para los crons: si por algun motivo dos ejecuciones se solapan (cron + run manual), el `flock` rechaza la segunda, no corrompe nada.

### 6.2. Atomic swap
Para los ZIMs y la blocklist, primero se baja a `<final>.tmp` o `${TMP_DIR}/zone.new` y solo cuando todo es OK (size, named-checkzone, etc.) se hace `install` o `mv`. Asi no se rompe el servicio a mitad de update.

### 6.3. Resume
- ZIMs: `curl --continue-at -` permite reanudar HTTP range.
- Kolibri: `importcontent` chequea hashes y reanuda automaticamente.
- Jellyfin: el scan en si es idempotente; archivos ya indexados se saltan por mtime.

### 6.4. Rate limit
- ZIMs: `2M/s` para no saturar el enlace.
- Kolibri: no hay rate limit explicito; Studio sirve a su propio ritmo.
- Blocklist: archivos pequeños, no aplica.

### 6.5. WAN check antes de bajar
- Kiwix: `curl HEAD download.kiwix.org/zim/`.
- Kolibri: `curl studio.learningequality.org/`.
- Jellyfin scan: no necesita WAN.
- Blocklist: implicito en el `curl -f` de cada source.

### 6.6. Disk guard
ZIMs y Kolibri verifican `MIN_FREE_MB=4000` antes de empezar. La RPi tiene ~60 GB; con Khan Academy + Wikipedia + Kolibri canales medianos, el margen es ajustado. Si quedan menos de 4 GB libres, skipea para no llenar el disco y dejar el sistema sin /var/log.

### 6.7. Lock files
Todos en `/run/lock/<servicio>-update.lock`. `flock -n` (no-block) → si esta tomado, exit limpio con "Another instance is running".

---

## 7. Agregar contenido nuevo

### 7.1. Nuevo ZIM Kiwix

1. Buscar la categoria + prefix en `https://download.kiwix.org/zim/<category>/`. El prefix es el filename sin la fecha (e.g. `wiktionary_es_all_nopic` para `wiktionary_es_all_nopic_2026-04.zim`).
2. **Primera instalacion manual** (porque el script skipea si no hay current):
   ```bash
   cd /var/lib/biblioteca/zim
   sudo -u kiwix curl -L -O https://download.kiwix.org/zim/<category>/<prefix>_<fecha>.zim
   sudo -u kiwix kiwix-manage library.xml add <prefix>_<fecha>.zim
   sudo systemctl restart kiwix-serve
   ```
3. Editar `raspberry/rpi-setup/group_vars/all.yml` agregando el entry a `kiwix_zim_sources`.
4. (Opcional) re-correr el role kiwix para que cron se actualice si cambia algo del cron line.

### 7.2. Nuevo canal Kolibri

1. Buscar el canal en https://studio.learningequality.org/channels/public → copiar el UUID.
2. Editar `group_vars/all.yml` agregando `{ id: "<uuid>", name: "<descripcion>" }` a `kolibri_channels`.
3. Importar la primera vez manualmente o esperar el siguiente cron (mar/vie 03:00):
   ```bash
   sudo /usr/local/sbin/update-kolibri-content
   ```

### 7.3. Nuevo video Jellyfin

1. Copiar el archivo al directorio apropiado (ej. `/var/lib/biblioteca/videos/educativos/<archivo>.mp4`).
2. Disparar scan o esperar el cron de las 04:30:
   ```bash
   sudo /usr/local/sbin/scan-jellyfin-library
   ```

### 7.4. Nueva libreria Jellyfin

Crearla via API REST (no en el script — es una accion one-shot):

```bash
API="http://127.0.0.1:8096"
KEY="<api key>"
NAME="Documentales"
PATH_="/var/lib/biblioteca/videos/documentales"

# Crear el dir
sudo mkdir -p "$PATH_" && sudo chown jellyfin:jellyfin "$PATH_"

# Crear la library
curl -X POST "$API/Library/VirtualFolders?api_key=$KEY&name=$NAME&collectionType=movies"

# Asociar el path (la API requiere request aparte)
curl -X POST "$API/Library/VirtualFolders/Paths?api_key=$KEY" \
    -H "Content-Type: application/json" \
    -d "{\"Name\":\"$NAME\",\"PathInfo\":{\"Path\":\"$PATH_\"}}"

# Refresh
curl -X POST "$API/Library/Refresh?api_key=$KEY"
```

Luego agregar el path a `group_vars/all.yml > jellyfin_media_dirs` para que quede declarativo.

---

## 8. Operacion y troubleshooting

```bash
# Ver todos los crons del root
sudo crontab -l

# Forzar un ciclo de todos los updates en serie
sudo /usr/local/sbin/update-kiwix-content
sudo /usr/local/sbin/update-kolibri-content
sudo /usr/local/sbin/scan-jellyfin-library

# Liberar lockfile colgado (raro — flock se libera al matar el proceso)
ls -la /run/lock/*-update.lock
sudo rm /run/lock/kiwix-update.lock   # solo si el proceso no existe

# Logs unificados via journalctl
journalctl -t kiwix-update -t kolibri-update -t jellyfin-scan -t squid-blocklist \
    --since today

# Verificar espacio en disco antes de un update grande
df -h /var/lib/biblioteca/

# Si update-kiwix muere a la mitad, .tmp queda. El siguiente run resume:
ls /var/lib/biblioteca/zim/*.tmp

# Forzar re-import de un canal Kolibri desde cero (borra y rebaja)
sudo -u akasicom KOLIBRI_HOME=/home/akasicom/.kolibri \
    kolibri manage deletechannel <channel_id>
sudo /usr/local/sbin/update-kolibri-content
```

### Senales de problemas

- **`up to date` pero el contenido se ve viejo**: cache del browser o de nginx. Limpiar caches.
- **Kiwix-serve 502 despues de update**: el `library.xml` quedo inconsistente. Re-armar: `sudo -u kiwix kiwix-manage /var/lib/biblioteca/zim/library.xml add <each-zim>`.
- **Kolibri 500 despues de update**: `sudo systemctl restart kolibri`.
- **Disco lleno**: `du -sh /var/lib/biblioteca/* | sort -h` para ver el peso. Khan Academy suele ser el culpable.
- **Cron no corrio**: revisar `journalctl -u cron --since today` y `grep CRON /var/log/syslog`.

---

## 9. Como esto se integra con el modo WAN-offline

Cuando la WAN cae:
- Los crons siguen disparando pero los scripts hacen `wan_check` y salen con `No internet — skipping`. **No hay efectos colaterales**.
- El contenido ya descargado sigue siendo servido por Kiwix/Kolibri/Jellyfin sin necesidad de WAN.
- Bind9 RPZ `rpz.offline` hace que `biblioteca.tel` siga resolviendo a la RPi (passthru), y todo el contenido local sigue disponible.

Ver `DOCS/minipc/WAN-OFFLINE-MODE.md` para detalles del modo offline.
