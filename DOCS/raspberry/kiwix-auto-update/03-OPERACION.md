# 03 — Operacion y troubleshooting

## Ejecucion manual

Para ejecutar el script fuera del cron (e.g., para forzar una actualizacion):

```bash
ssh raspberry "sudo /usr/local/sbin/update-kiwix-content"
```

El output va a stdout y a syslog simultaneamente. Si se ejecuta manualmente, se ve en la terminal en tiempo real.

## Logs

### Log de archivo

```bash
ssh raspberry "cat /var/log/biblioteca/kiwix-update.log"
```

Ejemplo de output exitoso:

```
[2026-05-29T13:30:23-05:00] Starting content update check
[2026-05-29T13:30:27-05:00] wikipedia_es_all_mini: update available wikipedia_es_all_mini_2026-02.zim -> wikipedia_es_all_mini_2026-05.zim
[2026-05-29T13:30:28-05:00] wikipedia_es_all_mini: downloading wikipedia_es_all_mini_2026-05.zim (rate limit: 2M/s)
[2026-05-29T13:58:59-05:00] wikipedia_es_all_mini: installing wikipedia_es_all_mini_2026-05.zim
[2026-05-29T13:59:00-05:00] wikipedia_es_all_mini: homepage updated (wikipedia_es_all_mini_2026-02 -> wikipedia_es_all_mini_2026-05)
[2026-05-29T13:59:00-05:00] wikipedia_es_all_mini: removed old file wikipedia_es_all_mini_2026-02.zim
[2026-05-29T13:59:00-05:00] wikipedia_es_all_mini: update complete (wikipedia_es_all_mini_2026-02.zim -> wikipedia_es_all_mini_2026-05.zim)
[2026-05-29T13:59:01-05:00] wikibooks_es_all_nopic: up to date (wikibooks_es_all_nopic_2025-10.zim)
[2026-05-29T13:59:02-05:00] wikinews_es_all_nopic: up to date (wikinews_es_all_nopic_2026-04.zim)
[2026-05-29T13:59:03-05:00] wikiversity_es_all_nopic: up to date (wikiversity_es_all_nopic_2026-04.zim)
[2026-05-29T13:59:04-05:00] wikivoyage_es_all_nopic: up to date (wikivoyage_es_all_nopic_2026-03.zim)
[2026-05-29T13:59:04-05:00] kiwix-serve restarted
[2026-05-29T13:59:04-05:00] Content update check finished
```

### Syslog

```bash
ssh raspberry "journalctl -t kiwix-update --since '24 hours ago' --no-pager"
```

### Logrotate

Los logs se rotan mensualmente (6 copias comprimidas). Config en `/etc/logrotate.d/kiwix-update`.

## Verificaciones rapidas

### Estado general

```bash
ssh raspberry "
  echo '=== ZIMs en disco ==='
  ls -lh /var/lib/biblioteca/zim/*.zim

  echo '=== library.xml ==='
  grep -oP 'path=\"[^\"]+\"' /var/lib/biblioteca/zim/library.xml

  echo '=== Homepage links ==='
  grep -oP 'href=\"/content/[^\"]+\"' /var/www/html/index.html

  echo '=== kiwix-serve ==='
  systemctl is-active kiwix-serve

  echo '=== Descargas parciales ==='
  ls -lh /var/lib/biblioteca/zim/*.zim.tmp 2>/dev/null || echo 'Ninguna'

  echo '=== Cron ==='
  crontab -l 2>/dev/null | grep kiwix
"
```

### Verificar que el contenido es accesible

```bash
# Directo a kiwix-serve
ssh raspberry "curl -sI http://127.0.0.1:8080/ | head -3"

# Via nginx (como lo ve un cliente)
ssh raspberry "curl -sI http://127.0.0.1:80/ -H 'Host: biblioteca.tel' | head -3"
```

### Verificar un ZIM especifico

```bash
ssh raspberry "curl -sI http://127.0.0.1:8080/content/wikipedia_es_all_mini_2026-05/ | head -3"
# Respuesta esperada: HTTP/1.1 302 Found (redirige a la pagina principal del ZIM)
```

## Troubleshooting

### El script reporta "No internet — skipping"

La RPi no puede alcanzar `download.kiwix.org`. Verificar:

```bash
# Desde la RPi
ssh raspberry "curl -fsSL --max-time 10 https://download.kiwix.org/zim/ | head -5"

# Si falla, verificar conectividad basica
ssh raspberry "ping -c 3 192.168.20.1"      # gateway VLAN20
ssh raspberry "ping -c 3 172.16.0.1"          # gateway WAN (via Mini PC)
ssh raspberry "ping -c 3 8.8.8.8"             # internet
```

### La descarga falla repetidamente

Si un ZIM grande (Wikipedia, 3.5GB) falla en cada ejecucion:

1. Verificar que el `.tmp` crece entre ejecuciones (resume funciona):
   ```bash
   ssh raspberry "ls -lh /var/lib/biblioteca/zim/*.zim.tmp"
   # Ejecutar de nuevo y comparar tamanos
   ```

2. El enlace WAN puede ser inestable. El resume acumula progreso: si cada ejecucion descarga 500MB antes de fallar, en ~7 ejecuciones se completa.

3. Si nunca progresa, puede ser un bloqueo. Probar descarga manual:
   ```bash
   ssh raspberry "curl -fSL --limit-rate 2M -o /tmp/test.zim \
     https://download.kiwix.org/zim/wikipedia/wikipedia_es_all_mini_2026-05.zim"
   ```

### "ERROR: insufficient disk space"

El disco de la RPi esta lleno. Verificar:

```bash
ssh raspberry "df -h /var/lib/biblioteca/zim/"
ssh raspberry "du -sh /var/lib/biblioteca/zim/*"
```

Opciones:
- Eliminar ZIMs que ya no se necesitan
- Reducir `MIN_FREE_MB` si el margen es excesivo (no recomendado bajo 2000)

### "WARNING: no current ZIM for {prefix}"

El ZIM no existe en disco. El script solo **actualiza** ZIMs existentes, no descarga la version inicial. Instalar manualmente:

```bash
ssh raspberry "
  cd /var/lib/biblioteca/zim/
  sudo wget https://download.kiwix.org/zim/{category}/{prefix}_{YYYY-MM}.zim
  sudo chown kiwix:kiwix {prefix}_{YYYY-MM}.zim
  sudo -u kiwix kiwix-manage library.xml add {prefix}_{YYYY-MM}.zim
  sudo systemctl restart kiwix-serve
"
```

### Los links de la homepage no se actualizaron

El `sed` reemplaza el stem viejo por el nuevo. Si el link en `index.html` no usa el formato exacto `{prefix}_{YYYY-MM}`, el reemplazo no matchea.

Verificar:
```bash
ssh raspberry "grep -n 'wikipedia' /var/www/html/index.html"
```

El patron esperado es:
```html
href="/content/wikipedia_es_all_mini_2026-05/"
```

### kiwix-serve no reinicio

Verificar estado:
```bash
ssh raspberry "systemctl status kiwix-serve"
```

El reinicio solo ocurre si al menos un ZIM se actualizo (`RESTART_NEEDED=true`). Si todos estaban al dia, no se reinicia (correcto).

### "Another instance is running"

El lock en `/run/lock/kiwix-update.lock` impide ejecuciones simultaneas. Si aparece este mensaje pero no hay proceso corriendo, puede ser un stale lock (raro, ya que `flock` se libera automaticamente al terminar el proceso):

```bash
ssh raspberry "fuser /run/lock/kiwix-update.lock"
# Si no muestra PID, el lock es stale y se liberara en la proxima ejecucion
```

## Cronograma de cron en la RPi

| Dia | Hora | Script | Descripcion |
|-----|------|--------|-------------|
| Domingo | 03:30 | `update-squid-blocklist` | Actualizar blocklists de Squid |
| Lunes | 02:00 | `update-kiwix-content` | Actualizar ZIMs de Kiwix |
| Jueves | 02:00 | `update-kiwix-content` | Actualizar ZIMs de Kiwix |
