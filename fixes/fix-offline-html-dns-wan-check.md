# Fix: offline.html no se muestra cuando WAN esta caido

**Fecha:** 2026-05-27
**Componentes:** Bind9 RPZ, nginx, wan-check.sh (systemd timer)

## Problema

Cuando el Mini PC pierde conectividad WAN, los clientes en VLAN30 que intentan navegar HTTP ven un timeout de DNS (~30s) seguido del error del browser ("No se puede acceder a este sitio"). El mecanismo existente de `offline.html` (nginx:8888 con `proxy_intercept_errors on; error_page 502 503 504`) **nunca se dispara** porque el fallo ocurre en la capa DNS antes de que cualquier peticion HTTP llegue a nginx.

### Flujo roto (WAN caido, antes del fix)

```
Cliente -> http://example.com
  -> DNS query -> Bind9 (forward only -> 8.8.8.8/8.8.4.4/1.1.1.1)
  -> Forwarders inalcanzables -> timeout ~30s -> SERVFAIL
  -> Browser: "DNS_PROBE_FINISHED_NO_INTERNET"
  -> (nginx:8888 NUNCA recibe la peticion -> offline.html NO se muestra)
```

## Diagnostico

1. **Bind9 config**: `forward only` con 3 forwarders. Sin WAN, cada forwarder timeout ~10s con retries -> total ~30s antes de SERVFAIL.
2. **nginx:8888 (`http-proxy`)**: `proxy_intercept_errors on` funciona **solo si el trafico HTTP llega**. Con DNS roto, nunca llega.
3. **No habia health check de WAN** — deteccion era puramente pasiva (errores de Squid).

## Solucion: 3 componentes

### Componente 1 — Bind9 RPZ (Response Policy Zone)

Cuando WAN esta caido, una RPZ redirige **todos** los dominios externos a `192.168.30.1` (Mini PC VLAN30). `biblioteca.tel` queda excluido (passthru) para que siga resolviendo a la RPi.

**Archivos:**
- `roles/dns/templates/rpz.offline.zone.j2` -> `/etc/bind/zones/rpz.offline.zone`
- `roles/dns/templates/named.conf.rpz.enabled.j2` -> `/etc/bind/named.conf.rpz.enabled`
- `roles/dns/templates/named.conf.rpz.disabled.j2` -> `/etc/bind/named.conf.rpz.disabled`

**Clave:** La directiva `response-policy` debe estar **dentro** del bloque `options { }` en `named.conf.options`, no a nivel top-level. La definicion de la zona `rpz.offline` va en `named.conf.local` (siempre cargada, pero inactiva sin `response-policy`).

El archivo `/etc/bind/named.conf.rpz` se incluye desde `named.conf.options` dentro de `options { }`. wan-check.sh intercambia su contenido entre la version habilitada (con `response-policy`) y la deshabilitada (comentario vacio).

**Error original:** Se incluia `named.conf.rpz` desde `named.conf.local` (top-level), y el archivo contenia tanto `response-policy` como la declaracion de zona. Bind9 rechazaba con: `unknown option 'response-policy'` porque esa directiva solo es valida dentro de `options { }`.

### Componente 2 — nginx offline mode

Cuando WAN esta caido, nginx:8888 sirve `offline.html` directamente sin proxy a Squid (Squid resolveria via RPZ -> loop). OS captive portal probes siguen respondiendo para evitar popups del CNA.

**Archivo:** `roles/captive_portal/templates/http-proxy-offline.nginx.j2`

wan-check.sh intercambia el symlink `/etc/nginx/sites-enabled/http-proxy` entre:
- WAN UP: `-> /etc/nginx/sites-available/http-proxy` (proxy a Squid)
- WAN DOWN: `-> /etc/nginx/sites-available/http-proxy-offline` (sirve offline.html)

### Componente 3 — Health check script + systemd timer

`/usr/local/bin/wan-check.sh` ejecutado por `wan-check.timer` cada 15 segundos:
1. Ping al gateway (`172.16.0.1`)
2. Doble check tras 2s para evitar falsos positivos
3. Si WAN esta caido y no estamos en modo offline: activar RPZ + nginx offline
4. Si WAN esta up y estamos en modo offline: desactivar RPZ + restaurar nginx

Flag: `/var/run/wan-offline` (existe cuando estamos en modo offline).

**Archivos:**
- `roles/captive_portal/files/wan-check.sh`
- `roles/captive_portal/templates/wan-check.service.j2`
- `roles/captive_portal/templates/wan-check.timer.j2`

## Archivos modificados

| Archivo | Accion |
|---------|--------|
| `roles/dns/templates/named.conf.options.j2` | MODIFICADO — include RPZ dentro de options{} |
| `roles/dns/templates/named.conf.local.j2` | MODIFICADO — zona rpz.offline siempre cargada |
| `roles/dns/templates/rpz.offline.zone.j2` | CREADO |
| `roles/dns/templates/named.conf.rpz.enabled.j2` | CREADO |
| `roles/dns/templates/named.conf.rpz.disabled.j2` | CREADO |
| `roles/dns/tasks/main.yml` | MODIFICADO — deploy RPZ files |
| `roles/dns/vars/main.yml` | MODIFICADO — captive_portal_ip |
| `roles/captive_portal/templates/http-proxy-offline.nginx.j2` | CREADO |
| `roles/captive_portal/files/wan-check.sh` | CREADO |
| `roles/captive_portal/templates/wan-check.service.j2` | CREADO |
| `roles/captive_portal/templates/wan-check.timer.j2` | CREADO |
| `roles/captive_portal/tasks/main.yml` | MODIFICADO — deploy wan-check + offline nginx |

## Deploy

```bash
cd minipc/
ansible-playbook -i router-setup/inventory.ini services/dns.yml
ansible-playbook -i router-setup/inventory.ini services/captive_portal.yml -e @router-setup/roles/router/vars/main.yml
```

## Pruebas de validacion

### Test: WAN UP (operacion normal)
```bash
dig +short example.com @192.168.10.1
# -> IP real (e.g. 104.20.23.154)

ls /var/run/wan-offline
# -> No such file

readlink /etc/nginx/sites-enabled/http-proxy
# -> /etc/nginx/sites-available/http-proxy
```

### Test: WAN DOWN (simular bloqueando ICMP al gateway)
```bash
sudo nft add rule inet filter output oif enp170s0 ip daddr 172.16.0.1 icmp type echo-request drop comment wan-test
sudo /usr/local/bin/wan-check.sh

dig +short example.com @192.168.10.1
# -> 192.168.30.1 (RPZ wildcard)

dig +short biblioteca.tel @192.168.10.1
# -> 192.168.20.10 (passthru)

curl -s http://127.0.0.1:8888/ -H 'Host: example.com' | head -1
# -> <!DOCTYPE html> (offline.html)

curl -s http://127.0.0.1:8888/ -H 'Host: captive.apple.com'
# -> <HTML>...<TITLE>Success</TITLE>... (CNA probe)
```

### Test: WAN RESTORED
```bash
# Quitar regla de bloqueo
sudo nft -a list chain inet filter output | grep wan-test
sudo nft delete rule inet filter output handle <N>
sudo /usr/local/bin/wan-check.sh

dig +short example.com @192.168.10.1
# -> IP real

ls /var/run/wan-offline
# -> No such file

readlink /etc/nginx/sites-enabled/http-proxy
# -> /etc/nginx/sites-available/http-proxy
```
