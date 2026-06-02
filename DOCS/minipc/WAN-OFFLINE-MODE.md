# Modo WAN offline — deteccion y reroute a `biblioteca.tel`

> Actualizado: 2026-05-30

Cuando el enlace al ISP (router externo en `172.16.0.0/16`) cae, la red comunitaria debe **seguir funcionando para acceder al contenido local** (biblioteca.tel: Kiwix, Kolibri, Jellyfin). Este documento explica como se detecta la caida y como se reconfiguran Bind9 + nginx + nftables en caliente para que cualquier navegacion del cliente termine en una pagina "WAN offline" o en biblioteca.tel — sin timeouts ni errores del navegador.

## 1. Componentes

| Pieza | Donde | Rol cuando WAN cae |
|---|---|---|
| `wan-check.service` + `wan-check.timer` | Mini PC, systemd | Cada 15 s: pinguea el gateway, decide online/offline |
| `/usr/local/bin/wan-check.sh` | Mini PC | Logica del swap (RPZ + nginx + nftables) |
| Bind9 `rpz.offline` | Mini PC | Reescribe **todos** los dominios externos a `192.168.30.1`. Passthru para `biblioteca.tel`. |
| `/etc/bind/named.conf.rpz{,.enabled,.disabled}` | Mini PC | Switch on/off del RPZ offline (la blocklist sigue activa siempre) |
| `nginx http-proxy-offline` | Mini PC | Reemplaza `http-proxy` cuando offline; bindea `:443` con cert y sirve `offline.html`. |
| `/etc/nginx/sites-available/http-proxy{,-offline}` | Mini PC | Variantes online/offline del server block. |
| nftables NAT rule (offline) | Mini PC | `DNAT 443 → 192.168.30.1:443` para que HTTPS termine en nginx local. |
| `offline.html` | Mini PC, `/etc/captive-portal/offline.html` | Pagina con boton "Ir a la biblioteca". |

## 2. Deteccion de caida

`wan-check.timer` corre cada 15 s con `OnUnitActiveSec=15s`. Su servicio `wan-check.service` es `Type=oneshot` y ejecuta `/usr/local/bin/wan-check.sh`.

El script pinguea el gateway upstream (no Google/Cloudflare — eso requiere que la WAN exista y que el DNS funcione; aqui solo queremos saber si la NIC esta enlazada al ISP).

```bash
GATEWAY="172.16.0.1"
wan_is_up() {
    ping -c1 -W2 "$GATEWAY" >/dev/null 2>&1
}
```

Para evitar oscilacion en degradaciones transitorias, **antes de declarar offline el script hace doble check** con 2 s de espera:

```bash
if wan_is_up; then
    enter_online
else
    sleep 2
    if ! wan_is_up; then
        enter_offline
    fi
fi
```

Estado persistente en `/var/run/wan-offline` (flag file). Las funciones `enter_offline`/`enter_online` son **idempotentes** — no hacen nada si el sistema ya esta en el estado deseado.

## 3. Que cambia al entrar en offline

`enter_offline()` ejecuta **en este orden** (importante para evitar ventana sin destino para los clientes):

### 3a. Activar RPZ `rpz.offline` en Bind9

```bash
cp /etc/bind/named.conf.rpz.enabled /etc/bind/named.conf.rpz
rndc reconfig
```

El archivo `.enabled` contiene:

```
response-policy {
    zone "rpz.offline";
    zone "rpz.blocklist";   // blocklist sigue activa
} qname-wait-recurse no;
```

La zona master `rpz.offline` esta cargada permanentemente en Bind9 (`named.conf.local`) con este contenido:

```
$TTL 5
biblioteca.tel        CNAME   rpz-passthru.    ; passthru
*.biblioteca.tel      CNAME   rpz-passthru.    ; passthru
*                     A       192.168.30.1     ; todo lo demas a Mini PC
```

`rpz-passthru.` es la convencion RPZ para "no aplicar reescritura". Asi `biblioteca.tel` resuelve normal a `192.168.20.10` (la RPi), y **cualquier otro dominio** (www.google.com, instagram.com, etc.) resuelve a `192.168.30.1` (la VLAN30 IP del Mini PC). TTL bajo (5 s) para acelerar recovery cuando vuelva la WAN.

### 3b. Cambiar nginx a modo offline

```bash
ln -sf /etc/nginx/sites-available/http-proxy-offline /etc/nginx/sites-enabled/http-proxy
nginx -s reload
```

El server block `http-proxy-offline` agrega un `listen 443 ssl` que sirve `offline.html` con el cert de Pacific Edge. El server block normal solo escuchaba `:8888`.

### 3c. Swap de la regla nftables HTTPS

```bash
nft_delete_by_comment "wan-https-filter"   # (legado; ya no existe en online)
nft add rule ip nat prerouting \
    iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 443 \
    dnat to 192.168.30.1:443 \
    comment "wan-offline-https"
```

Asi HTTPS de clientes autenticados se redirige al nginx local que ya esta escuchando en `:443`. (HTTP ya estaba siempre apuntando a `:8888`, asi que no hace falta cambiarlo — el server block offline en `:8888` tambien sirve `offline.html`.)

### 3d. Crear flag
```bash
touch /var/run/wan-offline
```

## 4. Que ve el cliente cuando WAN esta down

Cliente autenticado abre `https://www.google.com`:

1. DNS A `www.google.com` → Bind9 RPZ offline → A `192.168.30.1` (TTL 5).
2. Browser TCP SYN → `192.168.30.1:443`.
3. nftables NAT: `mark 0x1, dport 443, daddr != 192.168.20.10` → DNAT a `192.168.30.1:443` (no-op, ya es ahi).
4. nginx (offline) acepta TLS con cert `Pacific Edge` — browser muestra warning porque el cert no coincide con `www.google.com`.
5. Usuario acepta → nginx sirve `offline.html`.

`offline.html` contiene un mensaje "Sin internet — visita la biblioteca offline" y un boton/link a `http://biblioteca.tel`. Como `biblioteca.tel` es **passthru** en RPZ, resuelve normal a `192.168.20.10` (RPi), donde nginx + Squid sirven Kiwix/Kolibri/Jellyfin sin necesidad de WAN.

> Nota UX: el cert warning es inevitable porque hacemos MITM transparente en `:443`. Operativamente se mitiga distribuyendo el CA `Pacific Edge` a los dispositivos (descargable en `http://192.168.30.1/certificado.crt` desde el portal).

## 5. Recovery — volver a online

`enter_online()` corre cuando el siguiente tick detecta gateway alcanzable. Orden inverso para evitar ventana sin destino:

```bash
# 1. Quitar DNAT 443 → :443 offline antes de cualquier otra cosa
nft_delete_by_comment "wan-offline-https"
nft_delete_by_comment "wan-https-filter"      # limpieza defensiva (legado)

# 2. Desactivar RPZ offline en Bind9
cp /etc/bind/named.conf.rpz.disabled /etc/bind/named.conf.rpz
rndc reconfig

# 3. Volver nginx a modo proxy normal (libera :443)
ln -sf /etc/nginx/sites-available/http-proxy /etc/nginx/sites-enabled/http-proxy
nginx -s reload

# 4. Quitar flag
rm /var/run/wan-offline
```

El archivo `.disabled` solo deja la blocklist activa (la zona `rpz.blocklist`, ver `DOCS/minipc/DNS-BIND9.md`):

```
response-policy {
    zone "rpz.blocklist";
} qname-wait-recurse no;
```

Cuando los clientes vuelven a navegar:

- DNS A `www.google.com` → Bind9 forward → IP real (cache TTL 5 del RPZ caducado en segundos, ver §6).
- HTTPS → no hay DNAT → masquerade → WAN.
- HTTP → DNAT a `:8888` → nginx → Squid RPi cache.

## 6. Por que TTL 5 en `rpz.offline`

Los clientes/recursores cachean DNS. Si en offline una entrada `www.google.com → 192.168.30.1` se cachea por horas, cuando vuelva la WAN el cliente seguira yendo al nginx local. Con TTL 5, el cache se invalida casi al instante de salir de offline, restaurando rapidamente las IPs reales.

## 7. Por que `biblioteca.tel` queda passthru

Si `*.biblioteca.tel` se reescribiera a `192.168.30.1`, los clientes terminarian en el Mini PC en lugar de la RPi. La biblioteca offline-first **debe seguir accesible y cacheable** durante WAN-down — la RPi tiene Kiwix/Kolibri/Jellyfin localmente, no necesita la WAN.

El `rpz-passthru.` es la convencion estandar RPZ: el CNAME es interpretado por Bind como "no aplicar policy a este dominio, devolver la respuesta real de la zona autoritativa". Asi `dig biblioteca.tel` devuelve `192.168.20.10` aun con el RPZ offline activo.

## 8. Por que dos archivos `.enabled` / `.disabled`

`named.conf.rpz` se incluye desde `named.conf.options`:

```
include "/etc/bind/named.conf.rpz";
```

El swap de archivos es atomico (`cp` reemplaza el inode) + `rndc reconfig` reaplica policy sin reiniciar named (preserva cache y sesiones TCP). Si se editaba in-place, una race podria dejar Bind con la directiva incompleta.

Ambos archivos contienen `response-policy { zone "rpz.blocklist"; }` para que el bloqueo porn/gambling permanezca activo en cualquier estado de WAN.

## 9. Por que en `enter_offline` se swap-ea nftables al final

Si primero hacemos el DNAT 443 y luego nginx cambia a offline, hay una ventana de algunos ms donde los clientes son redirigidos a `:443` y nginx aun no escucha ahi → RST. Cambiando primero `nginx` (que ya bindea `:443` al recargar) y luego el DNAT, garantizamos que el destino siempre exista.

Simetricamente en `enter_online`: primero quitamos el DNAT (los clientes vuelven a ir directos a WAN — funciona si ya hay WAN), luego desactivamos RPZ, luego nginx libera `:443`. La ventana inversa es indolora.

## 10. Interaccion con el portal cautivo

- **Cliente no autenticado en modo offline**: las reglas captive (mark != 0x1) siguen DNATeando 80/443 → portal `:2050`. El usuario ve el splash con su mensaje normal. Al hacer click en Aceptar el handler sigue autorizando (no requiere internet). Luego el cliente entra a `biblioteca.tel` y todo funciona localmente.
- **Cliente autenticado en modo offline**: ya tiene `mark=0x1`. El DNAT offline lo lleva a `offline.html`. Boton "Ir a la biblioteca" → `biblioteca.tel` (passthru) → RPi.

> Caso especial: si la WAN cae *durante* la auth (entre el `/accept` y el meta-refresh), el redirect a `http://biblioteca.tel/` funciona porque `biblioteca.tel` resuelve passthru a la RPi.

## 11. Comandos de verificacion

```bash
# Estado actual (online/offline)
[ -f /var/run/wan-offline ] && echo "OFFLINE" || echo "ONLINE"

# Forzar simulacion offline (bloquear gateway)
sudo iptables -A OUTPUT -d 172.16.0.1 -j DROP
# (esperar ~20s, observar)
journalctl -u wan-check -n 20

# Restaurar
sudo iptables -D OUTPUT -d 172.16.0.1 -j DROP

# Ver que RPZ esta activo ahora
sudo cat /etc/bind/named.conf.rpz

# Ver que symlink usa nginx
ls -la /etc/nginx/sites-enabled/http-proxy

# Ver reglas NAT
sudo nft -a list chain ip nat prerouting | grep -E "wan-|443"

# Test de resolucion DNS en cada modo
dig +short @192.168.10.1 www.google.com   # offline: 192.168.30.1 ; online: IP real
dig +short @192.168.10.1 biblioteca.tel    # siempre: 192.168.20.10

# Logs del wan-check
sudo journalctl -u wan-check.service --since "10 minutes ago"
```

## 12. Limitaciones conocidas

- **DoH/DoT** bypasea el RPZ offline (igual que bypasea la blocklist). Un cliente con DoH configurado seguira tratando de alcanzar IPs reales de internet y vera timeouts. Mitigaciones posibles (no implementadas): bloquear puertos DoT (853) y proveedores DoH conocidos via nftables.
- **HSTS preload** en sitios como `*.google.com` impide aceptar el cert auto-firmado, mostrando un error fatal "NET::ERR_CERT_AUTHORITY_INVALID" sin opcion a continuar. El usuario solo vera la pagina offline si visita un dominio no-HSTS o si su browser tiene el CA `Pacific Edge` instalado.
- **TTL 5 del RPZ** acelera recovery pero aumenta la carga DNS durante WAN-down (los clientes vuelven a preguntar cada 5 s). Trade-off aceptado.
