# 02 — Configuracion

## Variable principal: `kiwix_zim_sources`

Definida en `raspberry/rpi-setup/group_vars/all.yml`:

```yaml
kiwix_zim_sources:
  - { category: "wikipedia",   prefix: "wikipedia_es_all_mini" }
  - { category: "wikibooks",   prefix: "wikibooks_es_all_nopic" }
  - { category: "wikinews",    prefix: "wikinews_es_all_nopic" }
  - { category: "wikiversity", prefix: "wikiversity_es_all_nopic" }
  - { category: "wikivoyage",  prefix: "wikivoyage_es_all_nopic" }
```

Cada entrada tiene dos campos:
- **`category`**: subdirectorio en `download.kiwix.org/zim/`. Es el proyecto Wikimedia (wikipedia, wikibooks, etc.).
- **`prefix`**: nombre del archivo ZIM sin la fecha. Debe coincidir exactamente con el nombre en el servidor remoto.

### Como encontrar el prefix correcto

1. Ir a `https://download.kiwix.org/zim/` y buscar la categoria.
2. Dentro de la categoria, buscar el archivo deseado.
3. El prefix es el nombre completo **sin** `_YYYY-MM.zim`.

Ejemplo: si el archivo es `wikipedia_es_all_mini_2026-05.zim`:
- category: `wikipedia`
- prefix: `wikipedia_es_all_mini`

### Agregar un nuevo ZIM

1. Agregar la entrada en `group_vars/all.yml`:
   ```yaml
   kiwix_zim_sources:
     # ... entradas existentes ...
     - { category: "wiktionary", prefix: "wiktionary_es_all_nopic" }
   ```

2. Descargar manualmente la primera version (el script no descarga ZIMs que no existen aun en disco):
   ```bash
   ssh raspberry
   cd /var/lib/biblioteca/zim/
   sudo wget https://download.kiwix.org/zim/wiktionary/wiktionary_es_all_nopic_2026-05.zim
   sudo chown kiwix:kiwix wiktionary_es_all_nopic_2026-05.zim
   sudo -u kiwix kiwix-manage library.xml add wiktionary_es_all_nopic_2026-05.zim
   sudo systemctl restart kiwix-serve
   ```

3. Agregar el link en la homepage (`/var/www/html/index.html`).

4. Re-deploy Ansible para que el script incluya el nuevo ZIM:
   ```bash
   cd raspberry/
   ansible-playbook -i rpi-setup/inventory.ini services/kiwix.yml
   ```

A partir de ahi, el script lo mantiene actualizado automaticamente.

### Quitar un ZIM del auto-update

Simplemente eliminar la linea de `kiwix_zim_sources` y re-deploy. El ZIM existente en disco **no se elimina** — solo deja de actualizarse.

## Schedule (cron)

El cron esta configurado para ejecutarse **lunes y jueves a las 02:00**:

```
0 2 * * 1,4  /usr/local/sbin/update-kiwix-content >> /var/log/biblioteca/kiwix-update.log 2>&1
```

### Por que lunes y jueves a las 2am

- **2x/semana es suficiente**: los ZIMs se publican mensualmente. Ejecutar mas seguido no detectaria nada nuevo.
- **02:00**: en la madrugada, cuando no hay usuarios conectados a la red de la biblioteca.
- **Lunes y jueves**: distribuido en la semana para detectar publicaciones rapido.
- No interfiere con el cron existente de `update-squid-blocklist` (domingos 03:30).

### Cambiar el schedule

Modificar en `roles/kiwix/tasks/main.yml`:

```yaml
- name: Cron nocturno — actualizar contenido ZIM (lunes y jueves 02:00)
  cron:
    name: "update-kiwix-content"
    weekday: "1,4"     # 0=dom, 1=lun, ..., 6=sab
    hour: "2"
    minute: "0"
    user: root
    job: "/usr/local/sbin/update-kiwix-content >> /var/log/biblioteca/kiwix-update.log 2>&1"
```

Re-deploy despues de cambiar.

## Limite de ancho de banda

El script descarga a maximo **2 MB/s** (`curl --limit-rate 2M`). Esto significa:

| ZIM | Tamano | Tiempo estimado |
|-----|--------|-----------------|
| Wikipedia ES mini | ~3.5 GB | ~29 min |
| Wikibooks ES | ~107 MB | ~54 seg |
| Wikinews ES | ~33 MB | ~17 seg |
| Wikiversity ES | ~18 MB | ~9 seg |
| Wikivoyage ES | ~36 MB | ~18 seg |

A 2 MB/s se consumen ~7 GB/hora — suficiente para actualizar todo el contenido en una noche sin saturar el enlace WAN si algun usuario madrugador se conecta.

### Cambiar el limite

Editar la variable `RATE_LIMIT` en el template `update-kiwix-content.sh.j2`:

```bash
RATE_LIMIT="2M"         # 2 MB/s ≈ 7 GB/hora
```

Valores validos: `500K` (500 KB/s), `1M` (1 MB/s), `5M` (5 MB/s), etc.

## Espacio en disco

El script verifica espacio libre antes de cada descarga:
- **Minimo absoluto**: 4 GB libres (`MIN_FREE_MB=4000`)
- **Por descarga**: tamano del archivo + 500 MB de margen

Si no hay espacio suficiente, el ZIM se salta con un log de error y se reintenta en la siguiente ejecucion.

## Archivos en la RPi

| Ruta | Descripcion |
|------|-------------|
| `/usr/local/sbin/update-kiwix-content` | Script principal (generado por Ansible) |
| `/var/log/biblioteca/kiwix-update.log` | Log de ejecuciones |
| `/etc/logrotate.d/kiwix-update` | Rotacion mensual, 6 copias comprimidas |
| `/var/lib/biblioteca/zim/*.zim` | Archivos ZIM activos |
| `/var/lib/biblioteca/zim/*.zim.tmp` | Descargas parciales (resume) |
| `/var/lib/biblioteca/zim/library.xml` | Catalogo de kiwix-serve |
| `/var/www/html/index.html` | Homepage con links a cada ZIM |
| `/run/lock/kiwix-update.lock` | Lock de exclusion mutua |
