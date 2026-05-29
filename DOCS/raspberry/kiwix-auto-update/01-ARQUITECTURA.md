# 01 — Arquitectura de la auto-actualizacion

## Componentes involucrados

```
                                  Internet
                                     |
                    download.kiwix.org/zim/{category}/
                                     |
                                     | HTTPS (curl --limit-rate 2M)
                                     |
                              +--------------+
                              |   Mini PC    |
                              |  (NAT/WAN)   |
                              +------+-------+
                                     |
                                VLAN 20
                                     |
                          +----------+-----------+
                          |    Raspberry Pi      |
                          |                      |
                          |  /usr/local/sbin/    |
                          |  update-kiwix-content|
                          |        |             |
                          |        v             |
                          |  /var/lib/biblioteca/|
                          |  zim/*.zim           |
                          |        |             |
                          |        v             |
                          |  kiwix-manage        |
                          |  (library.xml)       |
                          |        |             |
                          |        v             |
                          |  kiwix-serve:8080    |
                          |        |             |
                          |        v             |
                          |  nginx:80            |
                          |  (biblioteca.tel)    |
                          +----------------------+
```

## Flujo del script paso a paso

```
update-kiwix-content
    |
    +-- 1. Adquirir lock (/run/lock/kiwix-update.lock)
    |       Si otra instancia corre -> exit 0
    |
    +-- 2. WAN check (curl a download.kiwix.org)
    |       Sin internet -> exit 0
    |
    +-- 3. Limpiar .tmp stale
    |       Archivos .tmp que ya no corresponden
    |       a la ultima version remota -> rm
    |
    +-- 4. Para cada ZIM en kiwix_zim_sources:
    |       |
    |       +-- 4a. Obtener ZIM actual en disco
    |       |       ls ${ZIM_DIR}/${prefix}_*.zim | sort | tail -1
    |       |       Si no existe -> WARNING, skip
    |       |
    |       +-- 4b. Scrape version remota
    |       |       curl download.kiwix.org/zim/${category}/
    |       |       Extraer href="${prefix}_YYYY-MM.zim"
    |       |       Si no encuentra -> WARNING, skip
    |       |
    |       +-- 4c. Comparar
    |       |       current == latest -> "up to date", skip
    |       |
    |       +-- 4d. Verificar espacio en disco
    |       |       Content-Length + 500MB margen
    |       |       Minimo 4GB libres
    |       |       Insuficiente -> ERROR, skip
    |       |
    |       +-- 4e. Descargar
    |       |       curl --limit-rate 2M --continue-at -
    |       |       Fallo -> "will retry next run"
    |       |       (archivo parcial .tmp se conserva)
    |       |
    |       +-- 4f. Verificar tamano
    |       |       local_size != remote_size -> rm .tmp, skip
    |       |
    |       +-- 4g. Atomic swap
    |               1. mv .tmp -> .zim
    |               2. chown kiwix:kiwix
    |               3. kiwix-manage add (nuevo)
    |               4. kiwix-manage remove (viejo)
    |               5. sed homepage links
    |               6. rm ZIM viejo
    |               7. RESTART_NEEDED=true
    |
    +-- 5. Si RESTART_NEEDED:
            systemctl restart kiwix-serve
```

## Orden de operaciones en el swap (paso 4g)

El orden es critico para evitar downtime:

1. **Primero agregar el nuevo** al library (`kiwix-manage add`) — si falla aqui, el viejo sigue funcionando intacto.
2. **Luego quitar el viejo** del library (`kiwix-manage remove`) — si falla, kiwix-serve tiene ambos (funcional, solo desperdicia espacio temporalmente).
3. **Actualizar homepage** (`sed`) — reemplaza `{prefix}_{old_date}` por `{prefix}_{new_date}` en el HTML.
4. **Eliminar ZIM viejo** del disco — solo al final, cuando todo lo demas ya esta actualizado.
5. **Reinicio unico** al final del loop completo — no un restart por cada ZIM.

## Mecanismo de resume

Si la descarga se interrumpe (corte de WAN, reboot, timeout de curl), el archivo parcial `.tmp` queda en disco. En la siguiente ejecucion:

1. `curl --continue-at -` detecta el `.tmp` existente y reanuda desde el ultimo byte descargado.
2. No vuelve a descargar lo que ya tiene.
3. Si entre una ejecucion y otra se publico una version mas nueva, el `.tmp` de la version anterior se elimina en el paso de "limpieza de .tmp stale".

## Deteccion de versiones

El script hace scraping del directorio HTTP de `download.kiwix.org/zim/{category}/`. Los nombres de archivo siguen el patron:

```
{prefix}_{YYYY}-{MM}.zim
```

Ejemplo: `wikipedia_es_all_mini_2026-05.zim`

El script extrae todos los hrefs que matchean el prefix, los ordena lexicograficamente, y toma el ultimo (mas reciente).

## Interaccion con otros servicios

| Servicio | Interaccion |
|----------|-------------|
| **kiwix-serve** | Se reinicia al final si hubo updates. Downtime ~1-2 segundos. |
| **nginx** | No se toca. Sigue sirviendo de reverse proxy a kiwix-serve:8080. |
| **Homepage** (`index.html`) | Se actualizan los links con `sed` (reemplazo de stem viejo por nuevo). |
| **WAN** | Se usa para descargar. Si no hay WAN, el script sale limpiamente. |
| **wan-check.sh** | Independientes. Si WAN cae durante una descarga, curl falla y el `.tmp` queda para resume. |
