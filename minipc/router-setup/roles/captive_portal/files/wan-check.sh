#!/bin/bash
# WAN health check — activa/desactiva modo offline (Bind9 RPZ + nginx + nftables)
# Ejecutado por wan-check.timer cada 15 segundos.
#
# Cuando WAN esta caido:
#   1. Activa RPZ offline en Bind9 → dominios externos resuelven a 192.168.30.1
#   2. Cambia nginx:8888 a modo offline → sirve offline.html directamente (sin Squid)
#   3. Agrega DNAT HTTPS local → puerto 443 a nginx local (sirve offline.html con TLS)
#   4. biblioteca.tel sigue resolviendo normalmente (RPZ passthru)
#
# Cuando WAN se recupera:
#   1. Quita DNAT HTTPS offline → tráfico HTTPS de autenticados pasa directo a WAN
#   2. Desactiva RPZ offline → DNS normal via forwarders (RPZ blocklist sigue activa)
#   3. Restaura nginx:8888 → proxy a Squid (HTTP cache + blocklist)
#
# Nota: el filtrado de dominios bloqueados (porn/gambling) se hace a nivel DNS
# via RPZ permanente (rpz.blocklist), no via Squid intercept HTTPS. La intercepcion
# transparente HTTPS cross-host no es viable (Squid pierde SO_ORIGINAL_DST).

set -euo pipefail

# Si cualquier comando falla inesperadamente, dejar rastro en journal.
# Antes este script abortaba en silencio (rc!=0 pero systemd lo marcaba
# "Deactivated successfully" por ser Type=oneshot) y dejaba el sistema a
# medio configurar — incluido el caso de quedar en RPZ offline sin flag.
trap 'logger -t wan-check "FATAL: aborted at line $LINENO (rc=$?)"' ERR

GATEWAY="172.16.0.1"
FLAG="/var/run/wan-offline"

# RPZ config files (desplegados por Ansible)
RPZ_ACTIVE="/etc/bind/named.conf.rpz"
RPZ_ENABLED="/etc/bind/named.conf.rpz.enabled"
RPZ_DISABLED="/etc/bind/named.conf.rpz.disabled"

# nginx config symlinks
PROXY_ONLINE="/etc/nginx/sites-available/http-proxy"
PROXY_OFFLINE="/etc/nginx/sites-available/http-proxy-offline"
PROXY_LINK="/etc/nginx/sites-enabled/http-proxy"

# nftables HTTPS DNAT rule swap
NFT_CHAIN="ip nat prerouting"
HTTPS_ONLINE_COMMENT="wan-https-filter"
HTTPS_OFFLINE_COMMENT="wan-offline-https"
CLIENT_IFACE="enp171s0.30"
RPI_IP="192.168.20.10"
MINIPC_IP="192.168.30.1"
SQUID_HTTPS_PORT="3130"

wan_is_up() {
    ping -c1 -W2 "$GATEWAY" >/dev/null 2>&1
}

# Eliminar regla nftables por comment. No-op si no existe.
# OJO: con `set -euo pipefail`, si `grep` no encuentra match retorna rc=1 y
# pipefail propaga el fallo → `handle=$(...)` aborta el script entero. Por eso
# el pipeline va dentro de `{ ...; } || true` y la asignación nunca falla.
nft_delete_by_comment() {
    local comment="$1"
    local handle
    handle=$( { nft -a list chain ${NFT_CHAIN} 2>/dev/null \
        | grep "comment \"${comment}\"" \
        | grep -oP 'handle \K[0-9]+' \
        | head -1; } || true )
    [ -n "$handle" ] && nft delete rule ${NFT_CHAIN} handle "$handle" 2>/dev/null || true
}

# Verificar si existe regla con el comment dado.
nft_rule_exists() {
    nft -a list chain ${NFT_CHAIN} 2>/dev/null | grep -q "comment \"$1\""
}

enter_offline() {
    # No-op si ya estamos offline
    [ -f "$FLAG" ] && return 0

    # Crear el flag PRIMERO. Representa "intención de estar en offline", no
    # "completitud del trampolín". Si alguno de los pasos siguientes aborta,
    # el flag queda creado y enter_online() del próximo tick podrá restaurar.
    # Antes el touch iba al final → si un paso intermedio fallaba, el flag
    # nunca se creaba y enter_online() retornaba inerte → sistema stuck offline.
    touch "$FLAG"

    logger -t wan-check "WAN DOWN — activando modo offline (RPZ + nginx + nftables HTTPS)"

    # 1. Activar RPZ en Bind9
    if [ -f "$RPZ_ENABLED" ]; then
        cp "$RPZ_ENABLED" "$RPZ_ACTIVE"
        rndc reconfig >/dev/null 2>&1 || true
    fi

    # 2. Cambiar nginx a modo offline (incluye listen 443 ssl)
    #    Debe hacerse ANTES del swap nftables para que :443 ya este escuchando
    if [ -f "$PROXY_OFFLINE" ]; then
        ln -sf "$PROXY_OFFLINE" "$PROXY_LINK"
        nginx -s reload 2>/dev/null || true
    fi

    # 3. Swap nftables: HTTPS de Squid (RPi:3130) → nginx local (:443)
    nft_delete_by_comment "$HTTPS_ONLINE_COMMENT"
    if ! nft_rule_exists "$HTTPS_OFFLINE_COMMENT"; then
        nft add rule ${NFT_CHAIN} \
            iif "${CLIENT_IFACE}" meta mark 0x1 ip daddr != ${RPI_IP} tcp dport 443 \
            dnat to ${MINIPC_IP}:443 \
            comment \"${HTTPS_OFFLINE_COMMENT}\" 2>/dev/null || true
    fi
}

enter_online() {
    # No-op si ya estamos online
    [ ! -f "$FLAG" ] && return 0

    # Borrar el flag PRIMERO (simetría con enter_offline). Si un paso intermedio
    # falla, el siguiente tick verá ! -f $FLAG → enter_online() retorna inerte y
    # enter_offline() del próximo ciclo restaurará offline si WAN sigue caído, o
    # se quedará así (cuyo estado coincide con "online intentado"). Lo importante
    # es no quedar atrapado en offline aunque WAN ya esté arriba.
    rm -f "$FLAG"

    logger -t wan-check "WAN UP — desactivando modo offline"

    # 1. Quitar DNAT HTTPS offline. HTTPS autenticado pasa directo a WAN.
    #    (El bloqueo de dominios prohibidos lo hace Bind9 RPZ a nivel DNS.)
    nft_delete_by_comment "$HTTPS_OFFLINE_COMMENT"
    # Limpieza defensiva: borrar cualquier resto de la regla rota antigua.
    nft_delete_by_comment "$HTTPS_ONLINE_COMMENT"

    # 2. Desactivar RPZ en Bind9
    if [ -f "$RPZ_DISABLED" ]; then
        cp "$RPZ_DISABLED" "$RPZ_ACTIVE"
        rndc reconfig >/dev/null 2>&1 || true
    fi

    # 3. Restaurar nginx a modo proxy normal (quita :443)
    if [ -f "$PROXY_ONLINE" ]; then
        ln -sf "$PROXY_ONLINE" "$PROXY_LINK"
        nginx -s reload 2>/dev/null || true
    fi
}

# --- Main ---

if wan_is_up; then
    enter_online
else
    # Doble check tras 2 segundos para evitar falsos positivos transitorios
    sleep 2
    if ! wan_is_up; then
        enter_offline
    fi
fi
