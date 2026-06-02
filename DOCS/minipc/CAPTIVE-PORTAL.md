# Portal Cautivo

> Actualizado: 2026-06-02 (arquitectura nueva en HTTP sobre `biblioteca.tel`)

## Rol Ansible

`minipc/router-setup/roles/captive_portal/`

## Descripción

El portal cautivo intercepta el tráfico de clientes no autenticados en VLAN30 y los redirige a un splash en **`http://biblioteca.tel/`** (HTTP plano, estilo portal de aeropuerto). Al hacer click en "Entrar a la biblioteca", el cliente queda autorizado y puede navegar. Post-auth, el meta-refresh lo lleva a **`https://biblioteca.tel/`** (landing en la RPi).

## Arquitectura actual (2026-06-02)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Cliente VLAN30 NO autenticado                                        │
│   tipea http://lo-que-sea  →  DNS resuelve a IP real                 │
│   SYN tcp/80                                                          │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Mini PC nftables prerouting (tabla ip nat)                           │
│   iif enp171s0.30 mark != 0x1 tcp dport 80  → DNAT 192.168.30.1:80   │
│   iif enp171s0.30 mark != 0x1 tcp dport 443 → DNAT 192.168.30.1:2050 │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│ nginx :80 (Mini PC)                                                  │
│   • server_name biblioteca.tel  → sirve /splash.html (200)           │
│   • default_server (otros Host) → 302 a http://biblioteca.tel/       │
│   • probes OS (/generate_204, /hotspot-detect.html, …) → 302 idem    │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼  click "Entrar"  →  GET /accept
┌──────────────────────────────────────────────────────────────────────┐
│ nginx :80 location /accept  →  proxy_pass 127.0.0.1:2051             │
│ captive-accept.py:                                                   │
│   1. lookup MAC vía ARP de la X-Real-IP                              │
│   2. nft add element captive_allowed_mac { MAC }  (timeout 8h)       │
│   3. return 200 con meta-refresh a https://biblioteca.tel/           │
│   (NO conntrack flush — rompe el reverse-NAT mid-respuesta)          │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼  meta-refresh fires
┌──────────────────────────────────────────────────────────────────────┐
│ Browser abre TCP nuevo a 192.168.20.10:443 (RPi)                     │
│   • mark=0x1 (MAC en set) → sin DNAT                                 │
│   • forward chain accept                                              │
│   • RPi nginx :443 ssl sirve landing biblioteca.tel                   │
│   • cert auto-firmado → warning una vez por dispositivo               │
└──────────────────────────────────────────────────────────────────────┘
```

## Cambios respecto a la versión anterior

| Aspecto | Antes (≤2026-05-30) | Ahora (2026-06-02) |
|---|---|---|
| URL canónica del portal | `https://192.168.30.1:2050/` | `http://biblioteca.tel/` |
| DNAT HTTP unauth | `tcp dport 80 → :2050` (SSL, devolvía 497) | `tcp dport 80 → :80` (HTTP plano, sirve splash directo) |
| DNAT HTTPS unauth | `tcp dport 443 → :2050` | igual: `tcp dport 443 → :2050` (fallback con cert warning) |
| Botón "Aceptar" en splash | `<a href="/accept">` (URL relativa) | `<a href="http://biblioteca.tel/accept">` (URL absoluta) |
| Redirect post-auth | `https://biblioteca.tel/` (vía meta-refresh, con bug del doble-click) | `https://biblioteca.tel/` (vía meta-refresh, **sin** conntrack flush) |
| Conntrack flush en /accept | sí — rompía respuesta en vuelo | **eliminado** — `Connection: close` ya fuerza TCP nuevo |
| Probes OS | redirigían a `https://192.168.30.1:2050/` | redirigen a `http://biblioteca.tel/` |

### Por qué se quitó el `conntrack -D`

Estaba en `captive-accept.py` con la intención de invalidar entradas DNAT cacheadas para que el meta-refresh evaluara nftables fresh. **Pero corría ANTES del `wfile.write()` final**: eliminaba la entrada conntrack en pleno medio de la respuesta HTTP, los paquetes salientes perdían el reverse-NAT (salían con `src=192.168.30.1:80` en vez de `src=biblioteca.tel:443/80` que esperaba el TCP del cliente), el browser los descartaba, el meta-refresh nunca disparaba, y el usuario tenía que hacer click en "Aceptar" dos veces.

Con `keepalive_timeout 0` en la location `/accept` de nginx, el header `Connection: close` ya garantiza que el browser cierra el TCP al recibir la respuesta. El siguiente request (el meta-refresh) abre un TCP nuevo que pasa por nftables fresh → mark=0x1 ya está → sin DNAT → llega directo a la RPi. No hace falta tocar conntrack.

### Por qué la URL del portal es ahora `biblioteca.tel`

El usuario veía siempre `https://192.168.30.1:2050` en la barra de URL después de aceptar — feo y dejaba la red sin identidad propia. La solución requirió tres cambios coordinados:

1. **nftables**: HTTP unauth ya no va a `:2050` (SSL) sino a `:80` (HTTP plano).
2. **nginx :80**: dos server blocks — `biblioteca.tel` sirve el splash directo; cualquier otro Host (`example.com`, `captive.apple.com`, etc.) responde `302` a `http://biblioteca.tel/`. El browser sigue el 302 y la URL bar queda en el dominio canónico.
3. **splash.html**: el botón usa URL absoluta `http://biblioteca.tel/accept` para que aún viniendo desde el HTTPS fallback (cert warning aceptado en `:2050`) la auth salga del dominio IP y aterrice en `biblioteca.tel`.

## Componentes

### 1. nginx :80 — splash + redirect canonical (NEW)

**Template**: `templates/captive-portal.nginx.j2`
**Config desplegada**: `/etc/nginx/sites-available/captive-portal`

Server blocks (en orden de declaración en el template):

```nginx
# Server 1: biblioteca.tel → splash + /accept + /certificado.crt
server {
    listen 80;
    server_name biblioteca.tel;
    location = /accept { proxy_pass http://127.0.0.1:2051; keepalive_timeout 0; }
    location = /      { try_files /splash.html =503; }
    location /        { return 302 http://biblioteca.tel/; }
}

# Server 2: cualquier otro Host → 302 a biblioteca.tel
server {
    listen 80 default_server;
    server_name _;
    location = /generate_204         { return 302 http://biblioteca.tel/; }
    location = /hotspot-detect.html  { return 302 http://biblioteca.tel/; }
    location = /connecttest.txt      { return 302 http://biblioteca.tel/; }
    # … más probes del SO …
    location /                       { return 302 http://biblioteca.tel/; }
}
```

### 2. nginx :2050 — fallback HTTPS (sin cambios en su rol)

Se mantiene para que clientes que llegan vía HTTPS (DNAT `:443 → :2050`) puedan al menos aceptar el cert warning y ver el splash. El botón sigue siendo absoluto a `http://biblioteca.tel/accept` así que la auth termina en el dominio canónico HTTP igual.

### 3. captive-accept.py (puerto 2051)

**Archivo**: `files/captive-accept.py`
**Systemd unit**: `captive-accept.service`
**Socket**: `127.0.0.1:2051`

Cambios:
- `REDIRECT = 'https://biblioteca.tel/'` (HTTPS post-auth a la landing de la RPi).
- **Quitado** el `conntrack -D -s <ip>` que corría mid-respuesta.
- Mantiene `lookup_mac_for_ip` vía `ip neigh` y `nft add element captive_allowed_mac { MAC }` con timeout 8h.

### 4. nftables — set `captive_allowed_mac`

Sin cambios estructurales. Sigue siendo:
```nft
set captive_allowed_mac {
    type ether_addr
    flags dynamic, timeout
    timeout 8h
}
```

La cadena `captive_mangle` (prio mangle -150) marca `meta mark 0x1` los paquetes cuyo `ether saddr` esté en el set. La cadena `ip nat prerouting` hace los DNAT en base a esa marca. Ver `DOCS/minipc/FIREWALL-NFTABLES.md`.

### 5. splash.html

**Archivo**: `files/splash.html`
**Desplegado en**: `/etc/captive-portal/splash.html`

Botones con URLs absolutas:
```html
<a href="http://biblioteca.tel/accept">Entrar a la biblioteca</a>
<a href="http://biblioteca.tel/certificado.crt">Descargar certificado</a>
```

## Servicios systemd

- `nginx.service` — **active, enabled** — sirve :80, :2050 (SSL), :8888
- `captive-accept.service` — **active, enabled** — handler Python en :2051
- `captive-portal.service` — **disabled** — legado, NO usar (peleaba puertos con nginx)

## Flujo de autenticación detallado

1. Cliente VLAN30 obtiene IP via Kea DHCP (`192.168.30.100-200`).
2. Cliente abre el browser, o el SO hace probe automático de portal cautivo.
3. **HTTP**: nftables `prerouting` DNAT → `192.168.30.1:80`.
   nginx server_block según `Host` → splash (si biblioteca.tel) o 302 (default).
4. **HTTPS**: nftables DNAT → `192.168.30.1:2050` (SSL). Browser: cert warning. Si el usuario "Continúa", ve el splash.
5. Click en "Entrar a la biblioteca" → GET `http://biblioteca.tel/accept`.
6. nginx `:80` location `/accept` → proxy_pass a `127.0.0.1:2051`.
7. `captive-accept.py`:
   - Lee `X-Real-IP` puesto por nginx.
   - `lookup_mac_for_ip` via `ip neigh show <ip> dev enp171s0.30`.
   - `nft add element inet filter captive_allowed_mac { <MAC> }`.
   - Devuelve 200 con `Connection: close` + body con meta-refresh + JS a `https://biblioteca.tel/`.
8. Browser cierra TCP (por `Connection: close`), abre uno nuevo a `192.168.20.10:443`:
   - nftables `captive_mangle`: MAC en set → `mark=0x1`.
   - `ip nat prerouting`: regla de auth `daddr != 192.168.20.10` no aplica (daddr ES la RPi) → sin DNAT.
   - Forward chain: `mark 0x1 → accept`.
9. RPi nginx `:443` sirve `biblioteca.tel` con cert auto-firmado → warning del browser → usuario acepta una vez por dispositivo.

## Para deauth o limpiar

```bash
# Ver clientes autorizados (MACs)
sudo nft list set inet filter captive_allowed_mac

# Borrar un cliente puntual (más seguro que flush si otros están conectados)
sudo nft delete element inet filter captive_allowed_mac { aa:bb:cc:dd:ee:ff }

# Borrar TODOS (CUIDADO: corta a todos los usuarios — incluyéndote a vos si navegás por VLAN30)
sudo nft flush set inet filter captive_allowed_mac

# Re-desplegar el firewall hace flush ruleset → también vacía el set
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
```

## Archivos desplegados

| Archivo en Mini PC | Fuente Ansible |
|---|---|
| `/etc/nginx/sites-available/captive-portal` | `templates/captive-portal.nginx.j2` |
| `/etc/captive-portal/splash.html` | `files/splash.html` |
| `/etc/captive-portal/offline.html` | `files/offline.html` |
| `/usr/local/bin/captive-accept.py` | `files/captive-accept.py` |
| `/etc/systemd/system/captive-accept.service` | `templates/captive-accept.service.j2` |
| `/etc/nginx/ssl/captive.crt` + `.key` | generado por openssl (CN portal.pacificedge.local) |

## Verificación operativa

```bash
# Smoke test desde el Mini PC (simula los Host headers de cada caso)
curl -s -o /dev/null -w 'biblioteca.tel: %{http_code} %{size_download}b\n' \
     -H 'Host: biblioteca.tel' http://192.168.30.1/

curl -s -o /dev/null -w 'example.com:     %{http_code} → %{redirect_url}\n' \
     -H 'Host: example.com'    http://192.168.30.1/

curl -s -o /dev/null -w 'captive.apple:   %{http_code} → %{redirect_url}\n' \
     -H 'Host: captive.apple.com' http://192.168.30.1/hotspot-detect.html

# Esperado:
# biblioteca.tel: 200 3637b
# example.com:    302 → http://biblioteca.tel/
# captive.apple:  302 → http://biblioteca.tel/

# Test del handler de aceptación (simula auth de la IP dada)
curl -s -H 'X-Real-IP: 192.168.30.99' http://127.0.0.1:2051/accept | grep -oE 'https://[^"]+' | head -1
# Esperado: https://biblioteca.tel/

# Ver auth en vivo
sudo journalctl -u captive-accept -f
```

## Documentación relacionada

- `DOCS/minipc/CAPTIVE-PORTAL-FLOW.md` — análisis paquete a paquete del flujo completo.
- `DOCS/minipc/PORTAL-CAUTIVO-BLOQUEO.md` — cómo se bloquea la navegación sin auth (incluyendo bypass IPv6/NAT64).
- `DOCS/minipc/FIREWALL-NFTABLES.md` — ruleset completo del firewall.
- `DOCS/minipc/WAN-OFFLINE-MODE.md` — interacción con el modo offline.
- `DOCS/minipc/portalCautivo/PORTAL-LEGACY.md` — arquitectura histórica anterior.
