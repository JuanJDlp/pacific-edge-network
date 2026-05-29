#!/bin/bash
# WAN health check — activa/desactiva modo offline (Bind9 RPZ + nginx + nftables)
# Ejecutado por wan-check.timer cada 15 segundos.
#
# Cuando WAN esta caido:
#   1. Activa RPZ en Bind9 → todos los dominios externos resuelven a 192.168.30.1
#   2. Cambia nginx:8888 a modo offline → sirve offline.html directamente (sin Squid)
#   3. Cambia DNAT HTTPS → redirige port 443 a nginx local (en vez de Squid RPi)
#   4. biblioteca.tel sigue resolviendo normalmente (RPZ passthru)
#
# Cuando WAN se recupera:
#   1. Restaura DNAT HTTPS → Squid en RPi (peek+splice normal)
#   2. Desactiva RPZ → DNS normal via forwarders
#   3. Restaura nginx:8888 → proxy a Squid

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
nft_delete_by_comment() {
    local comment="$1"
    local handle
    handle=$(nft -a list chain ${NFT_CHAIN} 2>/dev/null \
        | grep "comment \"${comment}\"" \
        | grep -oP 'handle \K[0-9]+' \
        | head -1)
    [ -n "$handle" ] && nft delete rule ${NFT_CHAIN} handle "$handle" 2>/dev/null || true
}

# Verificar si existe regla con el comment dado.
nft_rule_exists() {
    nft -a list chain ${NFT_CHAIN} 2>/dev/null | grep -q "comment \"$1\""
}

enter_offline() {
    # No-op si ya estamos offline
    [ -f "$FLAG" ] && return 0

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

    touch "$FLAG"
}

enter_online() {
    # No-op si ya estamos online
    [ ! -f "$FLAG" ] && return 0

    logger -t wan-check "WAN UP — desactivando modo offline"

    # 1. Swap nftables PRIMERO: restaurar HTTPS → Squid en RPi
    #    Debe hacerse ANTES de quitar nginx :443 para evitar ventana sin destino
    nft_delete_by_comment "$HTTPS_OFFLINE_COMMENT"
    if ! nft_rule_exists "$HTTPS_ONLINE_COMMENT"; then
        nft add rule ${NFT_CHAIN} \
            iif "${CLIENT_IFACE}" meta mark 0x1 ip daddr != ${RPI_IP} tcp dport 443 \
            dnat to ${RPI_IP}:${SQUID_HTTPS_PORT} \
            comment \"${HTTPS_ONLINE_COMMENT}\" 2>/dev/null || true
    fi

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
