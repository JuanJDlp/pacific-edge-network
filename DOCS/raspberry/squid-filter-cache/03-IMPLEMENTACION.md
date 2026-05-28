# 03 — Implementación: archivo por archivo

Lista exhaustiva de qué se cambió, dónde, y por qué.

## Archivos nuevos

### `raspberry/rpi-setup/roles/squid/templates/update-squid-blocklist.sh.j2`

**Propósito:** Script de actualización semanal de la blocklist.

**Comportamiento:**
1. Descarga las URLs configuradas en `squid_blocklist_sources` (group_vars).
2. Si alguna descarga falla → aborta sin tocar la lista vigente.
3. Combina los archivos (formato hosts), extrae los dominios, deduplica.
4. Sanity-check: si resultan <1000 entries, aborta (probable archivo corrupto).
5. Si la nueva lista es idéntica a la actual, no hace nada (idempotente).
6. Si cambió, instala el archivo y ejecuta `squid -k reconfigure`.

**Cron asociado:** Domingos 03:30 (definido en `roles/squid/tasks/main.yml`).

**Log:** `/var/log/squid-blocklist.log`.

### `DOCS/raspberry/squid-filter-cache/*.md` (esta carpeta)

Documentación completa del sistema.

## Archivos modificados

### 1. `raspberry/rpi-setup/group_vars/all.yml`

**Antes:** Variables generales (red, dominio, puertos backends).

**Después:** + variables del filtrado/cache:

```yaml
# Squid feature flags
squid_enable_https_filter: true
squid_enable_biblioteca_accel: true

# Puertos
squid_intercept_https_port: 3130
squid_accel_https_port: 443
biblioteca_backend_port: 80

# Paths
squid_bump_ca_cert: "/etc/squid/ssl/bump-ca.crt"
squid_bump_ca_key:  "/etc/squid/ssl/bump-ca.key"
squid_ssl_db:       "/var/lib/squid/ssl_db"
biblioteca_cert:    "/etc/squid/ssl/biblioteca.crt"
biblioteca_key:     "/etc/squid/ssl/biblioteca.key"

# Blocklist sources (modificar aquí para añadir/quitar categorías)
squid_blocklist_sources:
  - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
  - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
squid_blocklist_path: "/etc/squid/blocklists/blocked_domains.txt"

# nginx libera :443 cuando Squid maneja HTTPS público
nginx_serve_https: false
```

**Por qué aquí:** son variables compartidas entre los roles `squid` y `nginx` de la RPi. `group_vars/all.yml` es el lugar canónico para variables cross-role.

### 2. `raspberry/rpi-setup/roles/squid/tasks/main.yml`

**Antes:** 4 tasks simples (apt install squid, mkdir cache, deploy config, enable service).

**Después:** ~15 tasks que automatizan:

| Task | Propósito |
|---|---|
| Install `squid-openssl` | Reemplaza `squid` GnuTLS (ver [Decisión 2](02-DECISIONES.md#decisión-2)) |
| Verify OpenSSL support | Falla rápido si el paquete equivocado se instaló |
| Crear `/var/lib/biblioteca/squid-cache` | Cache dir |
| Crear `/etc/squid/ssl/` (0750, proxy:proxy) | CA + cert dir |
| `openssl req -x509` para CA bump | Idempotente con `creates:` |
| chmod CA: cert 0644, key 0600 | Permisos |
| `security_file_certgen -c -s ssl_db -M 20MB` | Inicializa cert DB |
| Copiar `biblioteca.crt/key` a `/etc/squid/ssl/` | Squid necesita poder leerlos |
| Crear `/etc/squid/blocklists/` | Blocklist dir |
| Template `update-squid-blocklist` a `/usr/local/sbin/` | Script |
| Run inicial del script (`creates: blocked_domains.txt`) | Pobla la lista la primera vez |
| Cron domingos 03:30 | Actualización semanal |
| Template `squid.conf` con `validate:` | Parse-check antes de instalar |
| Enable + start squid | systemd |

**Cada task tiene `when: squid_enable_https_filter` o `when: squid_enable_biblioteca_accel`** para que el rol siga funcionando con los flags off (modo legacy compatible).

### 3. `raspberry/rpi-setup/roles/squid/templates/squid.conf.j2`

**Antes:** ~50 líneas, solo forward proxy HTTP (3128 intercept + 3129 accel) y cache.

**Después:** ~130 líneas, con bloques Jinja2 condicionales:

```jinja2
{% if squid_enable_https_filter | default(true) %}
https_port 3130 intercept ssl-bump tls-cert=... tls-key=... generate-host-certificates=off
sslcrtd_program ...
{% endif %}

{% if squid_enable_biblioteca_accel | default(false) %}
https_port 443 accel cert=... key=... defaultsite=biblioteca.tel vhost
cache_peer 127.0.0.1 parent 80 0 no-query originserver name=biblioteca_backend login=PASSTHRU
{% endif %}
```

**Reglas añadidas:**

| Tipo | Regla | Propósito |
|---|---|---|
| ACL | `blocked_domains  dstdomain        "/etc/squid/blocklists/blocked_domains.txt"` | HTTP filtering |
| ACL | `blocked_sni      ssl::server_name "/etc/squid/blocklists/blocked_domains.txt"` | HTTPS SNI filtering |
| ACL | `step1 at_step SslBump1` | Marker para peek (requerido por `ssl_bump peek step1`) |
| ACL | `biblioteca_dom dstdomain biblioteca.tel` | Para routing y cache |
| ACL | `cache_allowed dstdomain biblioteca.tel` | Solo cachea biblioteca.tel |
| http_access | `deny blocked_domains` | Bloqueo HTTP |
| http_access | `allow biblioteca_dom` | Habilita el acceso accel |
| cache_peer_access | `allow biblioteca_dom` / `deny all` | Solo biblioteca.tel pasa por cache_peer |
| never_direct/always_direct | `allow/deny biblioteca_dom` | Fuerza biblioteca.tel a usar cache_peer (ver [Decisión 10](02-DECISIONES.md#decisión-10)) |
| ssl_bump | `peek step1`, `terminate blocked_sni`, `splice all` | Filtrado por SNI |
| cache | `deny !cache_allowed` | No cachea internet |

**Orden importa** — los ACL se declaran ANTES de las reglas que los usan. Por eso el bloque "ACLs base" precede a "Reglas de acceso" y "SSL bump policy".

### 4. `raspberry/rpi-setup/roles/nginx/templates/biblioteca.nginx.j2`

**Antes:** 2 server blocks (HTTP en :80, HTTPS en :443).

**Después:** mismo, pero el server HTTPS tiene los listen condicionales:

```jinja2
server {
{% if nginx_serve_https | default(true) %}
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
{% else %}
    listen 127.0.0.1:8443 ssl;
{% endif %}
    ...
}
```

**Por qué:** con `nginx_serve_https: false` (que es lo que define `group_vars/all.yml` ahora), nginx libera :443 para que Squid lo tome. Queda solo en loopback como backup/diagnóstico.

**Cambiar a `nginx_serve_https: true`** en group_vars revierte: nginx vuelve a :443, Squid debería desactivarse (poner `squid_enable_biblioteca_accel: false`).

### 5. `minipc/router-setup/roles/firewall/templates/nftables.conf.j2`

**Antes:** En el chain `prerouting` de la tabla `ip nat` había 3 DNAT (DNS, HTTP unauth, HTTPS unauth, HTTP auth → nginx).

**Después:** + una regla nueva:

```jinja2
{% if enable_https_filter | default(false) %}
# ── Filtrado HTTPS: VLAN30 autenticada → Squid intercept en RPi ───────
iif "{{ client_iface }}" meta mark 0x1 ip daddr != {{ rpi_ip }} tcp dport 443 \
    dnat to {{ rpi_ip }}:{{ squid_intercept_https_port }}
{% endif %}
```

**Posición**: AL FINAL del bloque DNAT, después del DNAT HTTP. El orden importa por la semántica de nftables (primera regla que matchea gana), pero como las reglas son mutuamente excluyentes (HTTP vs HTTPS, mark != 0x1 vs mark == 0x1, daddr != RPi vs no especificado), el orden no rompe nada.

**Excepción importante:** `ip daddr != {{ rpi_ip }}` — excluye tráfico a la RPi para que biblioteca.tel HTTPS llegue directo a Squid:443 (accel mode) en lugar de ser DNATteado a :3130 (filter mode). Ver [Decisión 9](02-DECISIONES.md#decisión-9).

### 6. `minipc/router-setup/roles/firewall/vars/main.yml`

**Antes:** Variables del firewall (rate limits, listas de IPs/puertos).

**Después:** + 2 variables:

```yaml
enable_https_filter: true
squid_intercept_https_port: 3130
```

**Por qué aquí y no en `group_vars`:** el firewall role tiene sus variables en `vars/main.yml` por convención del proyecto. Mantener consistencia con cómo viven el resto de vars del rol.

### 7. `minipc/router-setup/roles/router/vars/main.yml`

**Antes:** Variables del router base (interfaces, VLANs, IPs, puertos de proxy).

**Después:** + 2 variables (duplicadas del firewall vars):

```yaml
squid_intercept_https_port: 3130
enable_https_filter: true
```

**Por qué duplicadas:** el rol `router` tiene SU PROPIO `nftables.conf.j2` (que es overridiado por el del rol `firewall` después). Si alguien deploya solo el rol `router` sin `firewall`, las variables tienen que estar disponibles. Es defensivo. Si se cambia un valor, hay que actualizar ambos archivos — la doc lo recuerda.

## Cambios manuales realizados en el sistema (todos también en Ansible)

Estas operaciones se ejecutaron manualmente en la RPi y/o Mini PC durante el desarrollo, **y todas están encodeadas en los roles Ansible** para futuras re-deploys o reconstrucciones:

| Operación manual | Equivalente Ansible | Idempotente? |
|---|---|---|
| `apt install squid-openssl` | Task "Asegurar squid-openssl instalado" | Sí |
| `mkdir /etc/squid/ssl && openssl req...` | Tasks "Crear /etc/squid/ssl" + "Generar CA bump" | Sí (`creates:`) |
| `mkdir /var/lib/squid/ssl_db && security_file_certgen -c` | Tasks correspondientes | Sí (`creates:`) |
| `cp /var/www/html/biblioteca-segura.crt /etc/squid/ssl/biblioteca.crt && chown` | Task "Copiar certificado biblioteca.tel" | Sí (copy module checksum) |
| `mkdir /etc/squid/blocklists && download lists && awk ...` | Task "Crear /etc/squid/blocklists" + script + run inicial | Sí |
| Editar `/etc/squid/squid.conf` con nueva config | Task "Desplegar configuración Squid" (template) | Sí |
| Editar `/etc/nginx/sites-available/biblioteca` quitando `listen 443` | Template `biblioteca.nginx.j2` condicional | Sí |
| `nft add rule ip nat prerouting ... dnat to 192.168.20.10:3130` | Template `firewall/nftables.conf.j2` + `nftables.service` | Sí |
| `systemctl reload nginx; systemctl reload squid` | Handlers `reload nginx`, `reload squid` | Sí (notify) |

## Cómo verificar que el código Ansible está al día

```bash
cd raspberry/
# Dry-run del rol squid: debe mostrar 0 changes
ansible-playbook -i rpi-setup/inventory.ini services/squid.yml --check --diff

# Dry-run del rol nginx: debe mostrar 0 changes
ansible-playbook -i rpi-setup/inventory.ini services/nginx.yml --check --diff

cd ../minipc/
# Dry-run del firewall: debe mostrar 0 changes
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags firewall --check --diff
```

Si los 3 dicen `0 changed` → el código está al día con el sistema en vivo.

## Re-deploy desde cero

Si alguien clona el repo en una RPi vacía + Mini PC vacío, esta secuencia reconstruye todo:

```bash
# 1. Mini PC: router base + firewall (la regla HTTPS DNAT está incluida)
cd minipc/
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml

# 2. RPi: servicios base + Squid con filtrado + nginx con :443 condicional
cd ../raspberry/
ansible-playbook -i rpi-setup/inventory.ini rpi-setup/playbook.yml
```

El orden importa: el firewall del Mini PC debe estar antes que Squid en RPi para que el DNAT exista cuando los clientes pruebes el filtro. Pero como cada máquina tiene su playbook independiente, esto es secuencial natural.
