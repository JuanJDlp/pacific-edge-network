# Fix: Portal cautivo — botón "Entrar" requiere múltiples clicks (keep-alive + conntrack)

**Fecha:** 2026-05-21
**Afecta:** Mini PC (`plataformas`) — captive-portal.nginx.j2 + captive-accept.py

## Síntoma

Al hacer clic en "Entrar a la biblioteca" en el splash del portal cautivo, el usuario tenía que dar más de un clic y esperar varios segundos antes de ser redirigido a `http://biblioteca.tel`. El handler Python autorizaba correctamente la MAC en el primer click (logs confirmaban `Authorized: IP=... MAC=...`), pero el browser seguía mostrando el splash.

## Diagnóstico

Los logs de nginx mostraban un bucle tras el primer `/accept`:

```
GET /accept → 200 (captive-accept.py autoriza MAC, envía SUCCESS_HTML + meta-refresh a biblioteca.tel)
GET /        → 200 (splash.html, 1461 bytes) ← referer: biblioteca.tel/accept
GET /accept  → 200
GET /        → 200 (splash.html)
...
```

El cliente SÍ accedía a internet (HTTPS a 34.149.66.137:443 funcionaba) — el mark `0x1` se estaba aplicando correctamente en nuevas conexiones TCP. El problema era la conexión TCP existente.

### Causa raíz: HTTP/1.1 keep-alive + caché DNAT de conntrack

1. El browser abre una conexión TCP a `biblioteca.tel:80` mientras no está autenticado.
2. nftables DNAT esa conexión al portal cautivo `192.168.30.1:2050` (nginx).
3. **conntrack registra la decisión DNAT por conexión** — mientras esa TCP siga abierta, conntrack redirige todos sus paquetes al portal, independientemente de si la MAC fue autorizada después.
4. HTTP/1.1 usa keep-alive por defecto. Nginx devuelve el SUCCESS_HTML en esa misma conexión TCP (que sigue DNAT'd).
5. El meta-refresh (`url=http://biblioteca.tel`) se ejecuta en esa misma conexión reutilizada → sigue llegando al portal cautivo, no a la RPi.
6. Solo al abrir una **nueva** conexión TCP (después de que conntrack expire la entrada vieja) el mark `0x1` se aplica correctamente y el tráfico llega a la RPi.

## Fixes aplicados

### 1. `captive-portal.nginx.j2` — forzar `Connection: close` en `/accept`

**Archivo:** `minipc/router-setup/roles/captive_portal/templates/captive-portal.nginx.j2`

```diff
 location = /accept {
     proxy_pass         http://127.0.0.1:{{ captive_accept_port }};
     proxy_set_header   X-Real-IP $remote_addr;
     proxy_read_timeout 5s;
+    # keepalive_timeout 0 hace que nginx envíe Connection: close en esta
+    # respuesta, cerrando el TCP. El browser abre nueva conexión para el
+    # meta-refresh, que pasa por nftables fresh y recibe mark=0x1 (no DNAT).
+    keepalive_timeout  0;
 }
```

`keepalive_timeout 0` hace que nginx incluya `Connection: close` en la respuesta. El browser cierra el TCP y abre una nueva conexión para ejecutar el meta-refresh. Esa nueva conexión pasa por nftables fresh y recibe el mark `0x1` → llega a la RPi correctamente.

> **Nota:** Se usó `keepalive_timeout 0` en lugar de `add_header Connection close` porque nginx ya añade su propio header `Connection`, y agregar uno manual produce headers duplicados.

### 2. `captive-accept.py` — flush de conntrack al autorizar

**Archivo:** `minipc/router-setup/roles/captive_portal/files/captive-accept.py`

```python
# Eliminar entradas conntrack cacheadas para este cliente.
# El DNAT del portal cautivo queda registrado por conexión en conntrack.
# Sin este flush, el browser reutiliza la conexión HTTP keep-alive DNAT'd
# y sigue llegando al captive portal en lugar de al destino real.
try:
    subprocess.run(
        ['conntrack', '-D', '-s', client_ip],
        capture_output=True, timeout=2
    )
    logging.info('Conntrack flushed for %s', client_ip)
except (subprocess.TimeoutExpired, FileNotFoundError):
    pass  # degradación graceful si conntrack no está disponible
```

Belt-and-suspenders: aunque `keepalive_timeout 0` cierra la conexión activa, el flush de conntrack limpia cualquier otra conexión keep-alive que el browser pudiera tener abierta en paralelo.

### 3. `tasks/main.yml` — instalar conntrack-tools

**Archivo:** `minipc/router-setup/roles/captive_portal/tasks/main.yml`

```diff
 - name: Instalar paquetes del portal cautivo
   apt:
     name:
       - nginx
+      - conntrack  # para conntrack -D: limpiar entradas DNAT cacheadas al autenticar
     state: present
```

### 4. `handlers/main.yml` — corregir handler `reload nginx`

**Archivo:** `minipc/router-setup/roles/captive_portal/handlers/main.yml`

```diff
 - name: reload nginx
   systemd:
-    name: captive-portal
-    state: restarted
+    name: nginx
+    state: reloaded
   become: true
```

El handler anterior intentaba reiniciar `captive-portal.service`, que fallaba porque `nginx.service` ya tenía los puertos 2050 y 8888. El fix lo cambia a recargar directamente `nginx.service`.

## Verificación

```bash
# 1. Confirmar que Connection: close está presente en la respuesta de /accept
curl -v -H 'X-Real-IP: 192.168.30.101' http://192.168.30.1:2050/accept 2>&1 | grep -i connection
# → Connection: close ✅

# 2. Confirmar que conntrack flush funciona
ssh minipc "sudo conntrack -L -s 192.168.30.101 2>/dev/null | wc -l"
# → 0 después de autenticar ✅

# 3. Prueba funcional
# - Conectar dispositivo a VLAN30
# - Intentar navegar → splash aparece
# - Clic en "Entrar a la biblioteca" UNA vez
# - Debe redirigir a biblioteca.tel al primer clic ✅
```

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags captive_portal
```

## Limpiar MACs autorizadas para re-probar

```bash
ssh -i ~/.ssh/id_ed25519_ladrilleros user@100.90.95.134 \
  "sudo nft flush set inet filter captive_allowed_mac"
```
