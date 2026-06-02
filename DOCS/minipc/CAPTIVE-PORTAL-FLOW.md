# Portal cautivo — flujo técnico detallado

> Actualizado: 2026-06-02 · Aplica a VLAN30 (clientes WiFi via Linksys E2500 AP bridge).
>
> **Arquitectura nueva (2026-06-02)**: el portal vive en `http://biblioteca.tel/` (HTTP plano, estilo aeropuerto). El DNAT para HTTP unauth va a `:80` (no `:2050`), nginx tiene un server_name para biblioteca.tel y un default_server que 302 al dominio canónico. El conntrack flush del handler fue eliminado (rompía la respuesta en vuelo → causaba el bug del doble-click). El meta-refresh post-auth lleva a `https://biblioteca.tel/` (RPi, cert auto-firmado, warning una vez por dispositivo).

Este documento explica **paquete a paquete** como funciona el portal cautivo de Pacific Edge: qué pasa desde que un cliente WiFi asocia al AP hasta que navega libremente por internet (o ve el splash). Para la operación del día a día ver `DOCS/minipc/CAPTIVE-PORTAL.md`.

## 1. Componentes involucrados

| Componente | Donde corre | Rol |
|---|---|---|
| **Linksys E2500** | Switch puerto 4 (acceso VLAN30) | AP transparente: no DHCP, no routing. Pone clientes en VLAN30. |
| **Kea DHCPv4** | Mini PC, `kea-dhcp4-server.service` | Asigna IP `192.168.30.0/24` y empuja gateway/DNS = `192.168.30.1`. |
| **radvd** | Mini PC | Anuncia SLAAC `fd00:0:0:30::/64` con DNS `fd00:0:0:30::1`. |
| **Bind9** | Mini PC, `named.service` | Resuelve `biblioteca.tel` localmente; forward + DNS64 + RPZ blocklist + RPZ offline. |
| **Jool NAT64** | Mini PC | Traduce trafico IPv6 con prefijo `64:ff9b::/96` a IPv4 (clientes IPv6-only que alcanzan internet IPv4). |
| **nftables** | Mini PC, tabla `inet filter` + `ip nat` + `netdev dhcp_fix` | Marcado por MAC + DNAT al portal + reglas de forward + masquerade. |
| **nginx (`:80`, `:2050`, `:8888`)** | Mini PC, `nginx.service` | Sirve splash, intercepta probes OS, proxy intermediario a Squid. |
| **captive-accept.py (`:2051`)** | Mini PC, `captive-accept.service` | Agrega la MAC del cliente al set `captive_allowed_mac` y devuelve HTML "Success". |
| **Squid (`:3128/:3129/:443`)** | Raspberry Pi, `squid.service` | Cache HTTP autenticado + reverse proxy de `biblioteca.tel`. |
| **nginx RPi (`:80`)** | Raspberry Pi, `nginx.service` | Landing `biblioteca.tel` + proxy a Kiwix/Kolibri/Jellyfin. |

## 2. Etapas del flujo

```
Cliente WiFi
    │ 1. asocia al SSID del Linksys (modo bridge)
    │ 2. DHCPv4 + SLAAC IPv6
    │ 3. DNS lookups → Bind9 (192.168.10.1)
    │ 4. TCP SYN HTTP/HTTPS
    ▼
Mini PC — nftables prerouting
    │ A. mangle: si MAC ∈ captive_allowed_mac → mark = 0x1
    │ B. nat: si mark != 0x1
    │       y dport 80  → DNAT a 192.168.30.1:80   (nginx HTTP → splash o 302)
    │       y dport 443 → DNAT a 192.168.30.1:2050 (nginx SSL fallback)
    │    si mark = 0x1 y daddr != RPi y dport 80 → DNAT a :8888 (proxy a Squid)
    ▼
Splash en http://biblioteca.tel/ → click "Entrar a la biblioteca"
    │ GET http://biblioteca.tel/accept (URL absoluta del anchor)
    │ → nginx :80 location /accept → proxy_pass 127.0.0.1:2051
    │ → captive-accept.py: lookup MAC vía ARP, nft add element
    │ → 200 OK Connection: close + meta-refresh a https://biblioteca.tel/
    ▼
Cliente recibe Success HTML → CNA del OS cierra popup
    │ Browser cierra TCP (Connection: close)
    │ Meta-refresh dispara → nuevo TCP a 192.168.20.10:443 (RPi HTTPS)
    ▼
Nueva conexión: mark = 0x1 → sin DNAT (daddr=RPi) → RPi nginx :443 sirve landing
```

## 3. Etapa 1 — Asignacion de IP

### IPv4 (Kea DHCPv4)

- Cliente envia `DHCPDISCOVER` (broadcast L2).
- El Linksys es bridge ⇒ el frame llega al puerto 4 del switch con tag `VLAN30` y de ahi sale por el trunk hacia el Mini PC `enp171s0.30`.
- Kea responde con `OFFER`/`ACK`: IP del pool `192.168.30.100-200`, lease 12 h, opcion 3 (router) = `192.168.30.1`, opcion 6 (DNS) = `192.168.30.1`.

> **Fix critico para macOS APIPA** — Kea usa `AF_PACKET` (bypasea netfilter); enviaria el `OFFER` en *unicast* L2 al cliente. macOS en APIPA solo acepta `OFFER` con `dst=255.255.255.255`. La tabla `netdev dhcp_fix` chain `out_vlan30` reescribe destino IP y MAC a broadcast en egress por `enp171s0.30`:
> ```nft
> udp sport 67 udp dport 68 ip daddr != 255.255.255.255 \
>     ip daddr set 255.255.255.255 ether daddr set ff:ff:ff:ff:ff:ff
> ```

### IPv6 (SLAAC via radvd)

- radvd envia Router Advertisements en `enp171s0.30` con prefijo `fd00:0:0:30::/64` y RDNSS `fd00:0:0:30::1`.
- El cliente autoconfigura una direccion estable + temporary (RFC 4941) basadas en su MAC + interface identifier.
- En el output del cliente: `inet6 fd00::30:cf:2837:3ee6:db63 prefixlen 64 autoconf secured`.
- Tambien obtiene `nat64 prefix 64:ff9b::/96` por DNS64 (PREF64 implicito), habilitando NAT64.

## 4. Etapa 2 — DNS

Todos los queries DNS de los clientes son **forzados a Bind9** (192.168.10.1) por nftables:

```nft
iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } udp dport 53 dnat to 192.168.10.1:53
iif { "enp171s0.30", "enp171s0.20", "enp171s0.10" } tcp dport 53 dnat to 192.168.10.1:53
```

Esto evita que un cliente con DNS hardcoded (8.8.8.8, 1.1.1.1) bypassee la blocklist ni el RPZ offline. (DoH/DoT siguen bypaseando — limitacion conocida.)

Bind9 resuelve:
- `biblioteca.tel` y subdominios → autoritativo, A=`192.168.20.10`, AAAA=`fd00:0:0:20::10`.
- Externos → `forwarders` (router upstream).
- RPZ `rpz.blocklist` (siempre activa) → NXDOMAIN para porn/gambling.
- RPZ `rpz.offline` (solo cuando WAN caido) → A=`192.168.30.1`. Ver `DOCS/minipc/WAN-OFFLINE-MODE.md`.
- DNS64 sintetiza `AAAA 64:ff9b::<ipv4>` para dominios sin AAAA real (excepto `fd00::/8` que pasa intacto para servicios locales dual-stack).

## 5. Etapa 3 — Primer SYN y decision del firewall

Asumimos cliente con MAC `XX:XX:XX:XX:XX:XX`, IP `192.168.30.114`, abriendo `http://www.google.com`.

### 5a. Resolucion DNS

- Browser query A `www.google.com` → cliente → Bind9 (DNAT) → forward → respuesta (e.g. 142.250.218.206).
- Si el cliente prefiere IPv6 (Happy Eyeballs): AAAA → Bind9 DNS64 sintetiza `64:ff9b::8efa:dace`.

### 5b. SYN ingresa al Mini PC

El paquete entra por `enp171s0.30` (interfaz VLAN30 del trunk).

**Chain `inet filter` con prioridad mangle (-150):**

```nft
chain captive_mangle {
    type filter hook prerouting priority mangle; policy accept;
    iif "enp171s0.30" ether saddr @captive_allowed_mac meta mark set 0x00000001
}
```

- Si la MAC origen esta en el set `captive_allowed_mac` (entries: `{ MAC expires Nh }`) → `mark = 0x1`.
- Sino → `mark = 0x0`.

**Chain `ip nat prerouting` con prioridad dstnat (-100):**

```nft
# Captive HTTP — va al :80 plano (no SSL). nginx server_name biblioteca.tel sirve
# el splash directo; default_server hace 302 a http://biblioteca.tel/ para que la
# URL bar quede en el dominio canónico.
iif "enp171s0.30" meta mark != 0x00000001 tcp dport 80  dnat to 192.168.30.1:80
# Captive HTTPS — fallback con cert auto-firmado en :2050. Browser muestra warning;
# si el usuario lo acepta, ve el splash. El botón Aceptar usa URL absoluta a
# http://biblioteca.tel/accept así la auth aterriza en el dominio HTTP canónico.
iif "enp171s0.30" meta mark != 0x00000001 tcp dport 443 dnat to 192.168.30.1:2050
# HTTP proxy autenticado (excepto a RPi)
iif "enp171s0.30" meta mark 0x00000001 ip daddr != 192.168.20.10 tcp dport 80  dnat to 192.168.30.1:8888
```

- **Sin auth, HTTP**: SYN `→ 142.250.218.206:80` se reescribe a `→ 192.168.30.1:80` (HTTP plano). nginx server_block según `Host` header: si el browser pidió `biblioteca.tel` ve el splash directo; cualquier otro Host (`example.com`, `www.google.com`, probes del SO, etc.) recibe `302 http://biblioteca.tel/` → browser navega → DNS → 192.168.20.10 → DNAT vuelve al mismo `:80` → ahora Host es biblioteca.tel → splash. **URL bar del cliente queda en `http://biblioteca.tel/` sin warnings de cert.**
- **Sin auth, HTTPS**: SYN `→ 142.250.218.206:443` → `→ 192.168.30.1:2050`. nginx negocia TLS con el cert auto-firmado `Pacific Edge` (CN `portal.pacificedge.local`). El cliente, esperando el cert de `google.com` o `biblioteca.tel`, muestra warning. Si lo acepta, ve el splash.
- **Con auth (mark=0x1)**: HTTP → `:8888` (intermediario nginx → Squid RPi cache); HTTPS → **sin DNAT**, sale directo a WAN via masquerade. El filtrado de porn/gambling se hace via Bind9 RPZ (no Squid intercept HTTPS — ver `DOCS/minipc/DNS-BIND9.md`).

> El destino `192.168.20.10` se excluye del DNAT para que `biblioteca.tel` (que resuelve a la RPi) llegue directo: la RPi tiene Squid en modo `accel` para HTTP cache y reverse proxy HTTPS.

**Chain `inet filter` chain `forward`:**

```nft
chain forward {
    type filter hook forward priority filter; policy drop;
    ct state established,related accept
    ct state invalid drop
    iif "enp171s0.30" oif "enp170s0"    meta mark 0x00000001 accept   # → WAN
    iif "enp171s0.30" oif "enp171s0.20" meta mark 0x00000001 accept   # → VLAN20
    iif "enp171s0.30" oif "enp171s0"    meta mark 0x00000001 accept   # → VLAN20 (tagged)
    # VLAN20→VLAN30 y VLAN10→VLAN30 logean+dropean
}
```

Por la politica `drop`, **un cliente sin mark no puede atravesar a otra zona**. Solo le quedan caminos hacia el propio Mini PC (INPUT chain) — y ahi solo los puertos del portal cautivo estan abiertos para VLAN30: `:80`, `:443`, `:2050`, `:8888`.

## 6. Etapa 4 — Sirviendo el splash

El cliente HTTP termina abriendo TCP con `192.168.30.1:80`. El cliente HTTPS (caso fallback) llega a `192.168.30.1:2050`.

### Server block nginx :80 — biblioteca.tel (canónico)

```nginx
# Server 1: Host == biblioteca.tel → splash directo
server {
    listen 80;
    server_name biblioteca.tel;
    root /etc/captive-portal;

    location = /certificado.crt {
        alias /etc/nginx/ssl/captive.crt;
        add_header Content-Disposition 'attachment; filename="PacificEdge_Cert.crt"';
        types { application/x-x509-ca-cert crt; }
    }

    location = /accept {
        proxy_pass         http://127.0.0.1:2051;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_read_timeout 5s;
        keepalive_timeout  0;   # Connection: close → ver nota
    }

    location = / {
        try_files /splash.html =503;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    location / { return 302 http://biblioteca.tel/; }
}

# Server 2: cualquier otro Host → 302 a biblioteca.tel
server {
    listen 80 default_server;
    server_name _;
    root /etc/captive-portal;

    location = /generate_204         { return 302 http://biblioteca.tel/; }
    location = /hotspot-detect.html  { return 302 http://biblioteca.tel/; }
    location = /connecttest.txt      { return 302 http://biblioteca.tel/; }
    location = /ncsi.txt             { return 302 http://biblioteca.tel/; }
    # … más probes …
    location = /certificado.crt { alias /etc/nginx/ssl/captive.crt; ... }

    location / { return 302 http://biblioteca.tel/; }
}
```

**Por qué `keepalive_timeout 0` en `/accept`**: HTTP/1.1 reutiliza la conexión TCP existente. El meta-refresh post-auth necesita un TCP nuevo para que pase por nftables fresh y obtenga `mark=0x1` (porque la MAC ya está en el set). Forzando `Connection: close`, el browser cierra la conexión actual y abre una nueva para el siguiente request — ese SYN sí es evaluado fresh.

**Por qué dos server blocks**: el `default_server` cubre los probes del SO (que vienen con `Host: captive.apple.com` o similar) y cualquier sitio externo que el usuario haya tipeado. Devuelve `302 http://biblioteca.tel/` → browser navega → DNS → 192.168.20.10 → DNAT vuelve a `:80` pero ahora con `Host: biblioteca.tel` → matchea el server 1 → splash. Resultado: la barra de URL del cliente queda en el dominio canónico, sin warnings de cert.

### Server block nginx :2050 — fallback HTTPS (clientes que llegan vía :443)

```nginx
server {
    listen 2050 ssl default_server;
    ssl_certificate     /etc/nginx/ssl/captive.crt;   # CA Pacific Edge
    ssl_certificate_key /etc/nginx/ssl/captive.key;
    error_page 497 http://biblioteca.tel/;            # HTTP-on-HTTPS → portal canónico

    location = /accept {
        proxy_pass         http://127.0.0.1:2051;
        proxy_set_header   X-Real-IP $remote_addr;
        keepalive_timeout  0;
    }

    location / {
        try_files /splash.html =503;
    }
}
```

El cert es auto-firmado con CN `portal.pacificedge.local`. El browser muestra `NET::ERR_CERT_AUTHORITY_INVALID` o `_COMMON_NAME_INVALID`. Si el usuario hace "Avanzado → Continuar", ve el splash. El botón "Entrar" usa URL absoluta a `http://biblioteca.tel/accept` así la auth termina en el dominio canónico HTTP sin más warnings.

### Probes del SO — detección de portal cautivo

Cuando el cliente WiFi se asocia, el SO hace probes HTTP a URLs conocidas para detectar conectividad:

| SO | URL del probe | Body esperado |
|---|---|---|
| macOS / iOS | `captive.apple.com/hotspot-detect.html` | `<HTML>…<TITLE>Success</TITLE>…</HTML>` |
| Android | `connectivitycheck.gstatic.com/generate_204` | HTTP 204 vacío |
| Windows | `www.msftconnecttest.com/connecttest.txt` | Body `Microsoft Connect Test` |

Como esos hostnames resuelven a sus IPs reales, el SYN sale a la WAN. nftables lo intercepta con el DNAT `dport 80 → 192.168.30.1:80`. nginx default_server matchea el `Host` (no es biblioteca.tel) y devuelve `302 http://biblioteca.tel/`. El SO recibe `302` en lugar del body de éxito → "captive portal detectado" → abre el CNA (Captive Network Assistant) con la URL del Location → `http://biblioteca.tel/` → ve el splash.

> El probe de iOS puede tardar varios minutos en disparar si el dispositivo no detecta cambio de SSID inmediatamente. No es bug del portal.

## 7. Etapa 5 — captive-accept.py

El handler en `127.0.0.1:2051` es un mini servidor Python (BaseHTTPRequestHandler). Recibe GET `/accept`, ejecuta:

1. **Lee la IP real** del cliente via header `X-Real-IP` (puesto por nginx).
2. **Consulta ARP**: `ip neigh show <IP> dev enp171s0.30` y extrae la MAC con regex `lladdr ([0-9a-f]{2}(?::...){5})`. La entrada ARP existe con certeza porque el kernel resolvió la MAC al recibir el SYN.
3. **Autoriza la MAC**: `nft add element inet filter captive_allowed_mac { <MAC> timeout 8h }`. El set es `dynamic,timeout 8h` → la entrada caduca sola.
4. **Devuelve HTML Success** con `Connection: close`: `<TITLE>Success</TITLE>` + `meta-refresh` + JS a `https://biblioteca.tel/`. El `<TITLE>Success</TITLE>` es **fundamental** para que el CNA de macOS cierre el popup: el sheet hace polling a `captive.apple.com` y al ver "Success" en el body decide que ya hay internet.

> **No hay `conntrack -D`** en esta etapa. Una versión anterior del handler ejecutaba `conntrack -D -s <client_ip>` antes del `wfile.write()` final con la intención de invalidar la entrada DNAT cacheada. Pero esto eliminaba el reverse-NAT para los paquetes de respuesta en vuelo — la respuesta salía con `src=192.168.30.1:80` en lugar del `src` que el TCP del cliente esperaba (la IP/puerto que pidió originalmente) → el cliente descartaba la respuesta → el meta-refresh nunca se procesaba → el usuario tenía que clickear "Aceptar" dos veces (bug del doble-click). Se eliminó: con `keepalive_timeout 0` en nginx, el header `Connection: close` ya garantiza que el browser cierra el TCP al recibir la respuesta y abre uno nuevo para el meta-refresh, que es evaluado fresh por nftables.

```
GET /accept HTTP/1.1
Host: biblioteca.tel
X-Real-IP: 192.168.30.114
↓
captive-accept.py:
  IP = 192.168.30.114
  MAC = lookup_mac_for_ip(IP)  → 3e:31:b8:b9:0c:d1
  nft add element ... captive_allowed_mac { 3e:31:b8:b9:0c:d1 }
  return SUCCESS_HTML (Connection: close, meta-refresh a https://biblioteca.tel/)
↓
nginx :80 → cliente: 200 OK <html><title>Success</title>...
↓
browser cierra TCP (Connection: close)
↓
meta-refresh dispara → nuevo TCP a 192.168.20.10:443 (RPi)
  ahora mark=0x1 (MAC en el set) → sin DNAT → cliente HTTPS a la landing
```

## 8. Etapa 6 — Trafico post-autenticacion

El cliente esta marcado `mark=0x1` en cada paquete proveniente de su MAC. Tres rutas:

### 8a. HTTP a internet (no `biblioteca.tel`)
- SYN dport 80 → matches `ip daddr != 192.168.20.10 dnat to 192.168.30.1:8888`.
- Conexion termina en nginx local `:8888`.
- nginx tiene server blocks especiales para probes (`captive.apple.com`, `gstatic.com`, `msftconnecttest.com`) que retornan Success localmente — evita que el CNA reaparezca despues de autenticarse.
- Para todo lo demas, `proxy_pass http://192.168.20.10:3129` con `proxy_set_header Host $http_host`. Squid recibe la peticion en modo `accel vhost allow-direct`, usa el header `Host` para conectar al destino real (sin necesidad de `SO_ORIGINAL_DST`), cachea y responde.
- Si el dominio esta en la blocklist de Squid → 403.

### 8b. HTTPS a internet (no `biblioteca.tel`)
- SYN dport 443 → **no hay DNAT**. La regla legacy `dnat to 192.168.20.10:3130` fue removida porque cross-host DNAT pierde `SO_ORIGINAL_DST` en la RPi → Squid no sabia el destino real y devolvia `TCP_DENIED CONNECT 192.168.20.10:3130`.
- Forward chain: `iif enp171s0.30 oif enp170s0 mark 0x1 accept` → masquerade → WAN.
- El filtrado de porn/gambling para HTTPS se hace **a nivel DNS** via la zona `rpz.blocklist` de Bind9 (~82 800 dominios, NXDOMAIN). Ver `DOCS/minipc/DNS-BIND9.md`.

### 8c. HTTP/HTTPS a `biblioteca.tel`
- DNS resuelve a `192.168.20.10` (A) / `fd00:0:0:20::10` (AAAA).
- SYN → daddr `192.168.20.10`. Las reglas DNAT excluyen ese daddr.
- Forward: `iif enp171s0.30 oif enp171s0.20 mark 0x1 accept` → directo a la RPi.
- HTTP → nginx RPi :80 sirve `index.html` y proxy a Kiwix/Kolibri/Jellyfin.
- HTTPS → Squid RPi :443 (`accel` con cert `biblioteca.tel`) termina TLS, cachea, sirve via `cache_peer 127.0.0.1:80`.

## 9. Etapa 7 — Caducidad y re-auth

- El set `captive_allowed_mac` es `dynamic, timeout 8h`. Cada entrada se elimina sola tras 8 h.
- Cuando expira, el siguiente SYN del cliente no obtiene mark → vuelve a caer al portal.
- Si el cliente cambia de MAC (privacy MAC randomization en iOS/macOS al reasociarse) → re-auth necesaria.
- Operador puede expulsar manualmente: `sudo nft delete element inet filter captive_allowed_mac '{ <MAC> }'`. (No hace falta `conntrack -D`: las conexiones HTTP/HTTPS post-auth no estaban DNAT'd, así que no hay reverse-NAT que invalidar; simplemente la próxima conexión nueva caerá al portal.)

## 10. Resumen visual del decision tree (paquete dport 80)

```
SYN ingresa por enp171s0.30, ether saddr = MAC
     │
     ▼  ┌──────────────────────────────┐
        │ MAC ∈ captive_allowed_mac?   │
        └───┬──────────────┬───────────┘
            │ no           │ si
            ▼              ▼
    mark = 0           mark = 0x1
            │              │
            ▼              ▼
  ┌──────────────┐   ┌──────────────────────────┐
  │ DNAT → :80   │   │ daddr == 192.168.20.10 ? │
  │ (nginx       │   └───┬──────────────┬───────┘
  │  biblioteca  │       │ no           │ si
  │  .tel splash)│       ▼              ▼
  └──────────────┘  DNAT → :8888    sin DNAT
                   (nginx→Squid)   (directo a RPi)
```

## 11. Operacion

```bash
# Ver clientes autenticados
sudo nft list set inet filter captive_allowed_mac

# Forzar deauth a un cliente
sudo nft delete element inet filter captive_allowed_mac '{ AA:BB:CC:DD:EE:FF }'
# (No es necesario `conntrack -D`: la próxima conexión nueva del cliente cae al portal por sí sola.)

# Ver reglas DNAT del portal
sudo nft -a list chain ip nat prerouting

# Logs del handler
sudo journalctl -u captive-accept -f

# Logs del splash (nginx access) — todos los hits al portal
sudo tail -f /var/log/nginx/access.log | grep -E '/(accept|generate_204|hotspot-detect|connecttest)'

# Test rápido del splash desde el Mini PC (simulando Host header)
curl -s -o /dev/null -w "%{http_code} %{size_download}b\n" \
     -H "Host: biblioteca.tel" http://192.168.30.1/
# Esperado: 200 ~3637b (splash.html)

curl -s -o /dev/null -w "%{http_code} → %{redirect_url}\n" \
     -H "Host: example.com" http://192.168.30.1/
# Esperado: 302 → http://biblioteca.tel/

# Fallback HTTPS (cert auto-firmado)
curl -k -o /dev/null -w "%{http_code}\n" https://192.168.30.1:2050/
# Esperado: 200

# Test del handler /accept (simula auth)
curl -H "X-Real-IP: 192.168.30.42" http://127.0.0.1:2051/accept
sudo nft list set inet filter captive_allowed_mac   # debe contener la MAC de 192.168.30.42
```
