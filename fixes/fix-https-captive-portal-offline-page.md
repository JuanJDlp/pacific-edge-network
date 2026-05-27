# Fix: HTTPS en portal cautivo + página offline (sin WAN)

**Fecha:** 2026-05-27
**Afecta:** Mini PC (`plataformas`, 100.90.95.134) · Raspberry Pi (`akasicom2`, 100.90.81.168)

---

## Problema 1 — Portal cautivo sin HTTPS

### Síntoma
- Clientes que navegaban a `https://` en VLAN30 recibían un TCP RST inmediato en lugar de ver el splash del portal.
- El redirect post-autenticación apuntaba a `http://biblioteca.tel` (HTTP), ignorando el HTTPS ya disponible en la RPi.
- Clientes HTTP que llegaban al puerto SSL del portal (por DNAT) recibían `400 Bad Request` de nginx en lugar de ser redirigidos al splash.

### Causa raíz

**nftables (forward chain):**
```nft
# Antes — RST inmediato para HTTPS unauthenticated
iif "enp171s0.30" meta mark != 0x1 tcp dport 443 reject with tcp reset
```
No había DNAT para el puerto 443, así que los clientes HTTPS nunca llegaban al portal.

**nginx error 497:**
nftables enviaba el tráfico HTTP del puerto 80 → puerto 2050 (SSL). Nginx devuelve el código interno `497` cuando recibe HTTP plano en un puerto SSL. Sin `error_page 497` configurado, el browser veía un error crudo en lugar de ser redirigido al splash HTTPS.

**captive-accept.py:**
```python
# Antes
REDIRECT = 'http://biblioteca.tel'
```

### Solución

#### 1. nftables — DNAT puerto 443 + quitar RST/DROP

**Archivos:** `minipc/router-setup/roles/router/templates/nftables.conf.j2`
y `minipc/router-setup/roles/firewall/templates/nftables.conf.j2`

```diff
+       # Portal cautivo: interceptar HTTPS de VLAN30 no autenticados
+       iif "{{ client_iface }}" meta mark != 0x1 tcp dport 443 \
+           dnat to {{ client_vlan_ip }}:{{ captive_portal_port }}

-       iif "{{ client_iface }}" meta mark != 0x1 tcp dport 443 reject with tcp reset
+       # HTTPS no autenticado redirigido por DNAT — ya no se necesita RST/DROP
```

#### 2. nginx — error_page 497

**Archivo:** `minipc/router-setup/roles/captive_portal/templates/captive-portal.nginx.j2`

En el server block HTTPS (`listen {{ captive_portal_port }} ssl`):

```diff
     ssl_ciphers HIGH:!aNULL:!MD5;

+    # Fix HTTP-on-HTTPS-port: nftables DNAT envía port 80 → port 2050 (SSL).
+    # El cliente habla HTTP plano al puerto SSL → nginx devuelve 497.
+    # Este error_page lo redirige al splash HTTPS correctamente.
+    error_page 497 https://{{ captive_portal_ip }}:{{ captive_portal_port }}/;
```

#### 3. captive-accept.py — redirect post-auth a HTTPS

**Archivo:** `minipc/router-setup/roles/captive_portal/files/captive-accept.py`

```diff
-REDIRECT = 'http://biblioteca.tel'
+REDIRECT = 'https://biblioteca.tel'
```

#### 4. RPi nginx — bloque HTTPS sincronizado en template Ansible

El bloque `listen 443 ssl` ya existía en la RPi (desplegado manualmente con cert en `/var/www/html/biblioteca-segura.crt`). Se sincronizó el template Ansible para que futuros deploys no lo rompan.

**Archivo:** `raspberry/rpi-setup/roles/nginx/templates/biblioteca.nginx.j2`
Se agregó el server block HTTPS con las mismas locations que el server HTTP.

**Archivo:** `raspberry/rpi-setup/roles/nginx/tasks/main.yml`
Se agregó task idempotente para generar el cert si no existe:
```yaml
- name: Generar certificado autofirmado para biblioteca.tel
  command: >
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048
    -keyout /etc/ssl/private/biblioteca.key
    -out /var/www/html/biblioteca-segura.crt
    -subj "/C=CO/.../CN=biblioteca.tel"
    -addext "subjectAltName=DNS:biblioteca.tel,DNS:www.biblioteca.tel,IP:192.168.20.1"
  args:
    creates: /var/www/html/biblioteca-segura.crt
```

### Flujo resultante — HTTPS unauthenticated

```
Cliente → https://cualquier-sitio.com:443
  → nftables DNAT → 192.168.30.1:2050 (SSL nginx)
  → SSL handshake: cert del portal (autofirmado, CN=portal.pacificedge.local)
  → browser: "Tu conexión no es privada" (cert no coincide con el dominio)
  → usuario hace clic "Continuar de todos modos" → ve splash HTTPS ✓
  → clic "Entrar" → autenticado → redirect a https://biblioteca.tel ✓

Cliente → http://cualquier-sitio.com:80
  → nftables DNAT → 192.168.30.1:2050 (SSL nginx)
  → nginx 497 (HTTP plano en puerto SSL)
  → error_page 497 → redirect a https://192.168.30.1:2050/
  → browser abre HTTPS splash ✓
```

> **Nota:** Para sitios con HSTS preloading (google.com, etc.), el browser no mostrará la opción "Continuar de todos modos". En iOS/macOS esto no es un problema porque el CNA detecta el portal vía la probe HTTP antes de que el usuario navegue a HTTPS.

---

## Problema 2 — Sin internet: el usuario veía la página de error de Squid

### Síntoma
Cuando el Mini PC perdía conectividad WAN, los clientes autenticados que intentaban navegar por HTTP esperaban ~60 segundos y luego veían la página de error interna de Squid (en inglés, sin diseño) en lugar de un mensaje amigable.

### Causa raíz
- Squid tiene un `connect_timeout` de 60 segundos por defecto. El usuario esperaba un minuto antes de ver el error.
- nginx (http-proxy en puerto 8888) pasaba el error 502/503/504 de Squid directamente al browser sin interceptarlo.
- No existía ninguna página de fallback para esta situación.

### Solución

#### 5. Squid — connect_timeout reducido

**Archivo:** `raspberry/rpi-setup/roles/squid/templates/squid.conf.j2`

```diff
+connect_timeout 15 seconds
```

Reduce la espera de 60s → 15s antes de que Squid devuelva el error al nginx intermediario.

#### 6. nginx http-proxy — interceptar errores de Squid

**Archivo:** `minipc/router-setup/roles/captive_portal/templates/http-proxy.nginx.j2`

```diff
     location / {
         proxy_pass http://{{ rpi_ip }}:{{ squid_forward_port }};
         ...
+        proxy_intercept_errors on;
+        error_page 502 503 504 =200 @sin_internet;
     }

+    location @sin_internet {
+        root /etc/captive-portal;
+        try_files /offline.html =503;
+        add_header Cache-Control "no-store" always;
+    }
```

`proxy_intercept_errors on` — nginx intercepta los errores 5xx de Squid.
`=200` — el browser recibe código 200, renderiza la página sin overlay de error del browser.

#### 7. offline.html — página de fallback

**Archivo:** `minipc/router-setup/roles/captive_portal/files/offline.html` (NUEVO)

Página con el mismo diseño visual que `splash.html` (variables CSS `--verde-selva`, `--crema`, `--tierra`). Contiene:
- Badge: `"Red comunitaria · sin internet"`
- Título: `"Sin conexión a internet"`
- Botón: `"Ir a la biblioteca local"` → `href="https://biblioteca.tel"`

**Archivo:** `minipc/router-setup/roles/captive_portal/tasks/main.yml`
Se agregó task para copiar `offline.html` a `/etc/captive-portal/`.

### Flujo resultante — WAN caído

```
Cliente autenticado → http://google.com (mark=0x1)
  → nftables DNAT → nginx:8888
  → nginx → Squid:3129
  → Squid intenta conectar al origen (~15s connect_timeout) → falla
  → Squid devuelve 503 a nginx
  → proxy_intercept_errors → error_page 503 → offline.html (HTTP 200)
  → browser muestra "Sin conexión a internet" con botón a la biblioteca ✓

Cliente autenticado → https://biblioteca.tel
  → nftables: RPi excluida del DNAT del proxy → va directo a RPi:443
  → Kiwix / Kolibri / Jellyfin → disponibles sin WAN ✓
```

> **Limitación conocida:** HTTPS autenticado (`https://google.com`) va directo al WAN (no pasa por el proxy). No es posible interceptarlo sin SSL bumping. El cliente verá `ERR_CONNECTION_TIMED_OUT`.

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `minipc/router-setup/roles/captive_portal/templates/captive-portal.nginx.j2` | `error_page 497` en bloque HTTPS |
| `minipc/router-setup/roles/captive_portal/templates/http-proxy.nginx.j2` | `proxy_intercept_errors` + `@sin_internet` |
| `minipc/router-setup/roles/captive_portal/files/captive-accept.py` | `REDIRECT` → `https://` |
| `minipc/router-setup/roles/captive_portal/files/offline.html` | NUEVO |
| `minipc/router-setup/roles/captive_portal/tasks/main.yml` | Task para copiar `offline.html` |
| `minipc/router-setup/roles/router/templates/nftables.conf.j2` | DNAT 443 + quitar RST |
| `minipc/router-setup/roles/firewall/templates/nftables.conf.j2` | DNAT 443 + quitar DROP |
| `raspberry/rpi-setup/roles/nginx/templates/biblioteca.nginx.j2` | Bloque HTTPS (`listen 443 ssl`) |
| `raspberry/rpi-setup/roles/nginx/tasks/main.yml` | Task generación de cert (idempotente) |
| `raspberry/rpi-setup/roles/squid/templates/squid.conf.j2` | `connect_timeout 15 seconds` |
| `raspberry/rpi-setup/inventory.ini` | Corrección: SSH key `id_ed25519_ladrilleros` |

## Deploy aplicado

```bash
# Mini PC
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags captive_portal
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall

# RPi
cd raspberry/
ansible-playbook services/nginx.yml -i rpi-setup/inventory.ini
ansible-playbook services/squid.yml -i rpi-setup/inventory.ini
```
