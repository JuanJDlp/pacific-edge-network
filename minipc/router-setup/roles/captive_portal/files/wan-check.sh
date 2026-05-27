#!/bin/bash
# WAN health check — activa/desactiva modo offline (Bind9 RPZ + nginx)
# Ejecutado por wan-check.timer cada 15 segundos.
#
# Cuando WAN esta caido:
#   1. Activa RPZ en Bind9 → todos los dominios externos resuelven a 192.168.30.1
#   2. Cambia nginx:8888 a modo offline → sirve offline.html directamente (sin Squid)
#   3. biblioteca.tel sigue resolviendo normalmente (RPZ passthru)
#
# Cuando WAN se recupera:
#   1. Desactiva RPZ → DNS normal via forwarders
#   2. Restaura nginx:8888 → proxy a Squid

set -euo pipefail

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

wan_is_up() {
    ping -c1 -W2 "$GATEWAY" >/dev/null 2>&1
}

enter_offline() {
    # No-op si ya estamos offline
    [ -f "$FLAG" ] && return 0

    logger -t wan-check "WAN DOWN — activando modo offline (RPZ + nginx offline)"

    # Activar RPZ en Bind9
    if [ -f "$RPZ_ENABLED" ]; then
        cp "$RPZ_ENABLED" "$RPZ_ACTIVE"
        rndc reconfig >/dev/null 2>&1 || true
    fi

    # Cambiar nginx a modo offline
    if [ -f "$PROXY_OFFLINE" ]; then
        ln -sf "$PROXY_OFFLINE" "$PROXY_LINK"
        nginx -s reload 2>/dev/null || true
    fi

    touch "$FLAG"
}

enter_online() {
    # No-op si ya estamos online
    [ ! -f "$FLAG" ] && return 0

    logger -t wan-check "WAN UP — desactivando modo offline"

    # Desactivar RPZ en Bind9
    if [ -f "$RPZ_DISABLED" ]; then
        cp "$RPZ_DISABLED" "$RPZ_ACTIVE"
        rndc reconfig >/dev/null 2>&1 || true
    fi

    # Restaurar nginx a modo proxy normal
    if [ -f "$PROXY_ONLINE" ]; then
        ln -sf "$PROXY_ONLINE" "$PROXY_LINK"
        nginx -s reload 2>/dev/null || true
    fi

    rm -f "$FLAG"
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
