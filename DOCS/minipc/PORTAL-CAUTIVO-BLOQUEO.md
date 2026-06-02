# Portal cautivo — Estado del bloqueo de navegación sin autenticación

> **Última verificación:** 2026-06-02 (arquitectura nueva: portal en `http://biblioteca.tel/`).
> **Veredicto:** ✅ Un cliente **no autenticado NO puede navegar** — ni por IPv4 ni por IPv6.
> Toda navegación HTTP/HTTPS termina en el splash con URL bar canónica `biblioteca.tel`.

Este documento resume **cómo se bloquea la navegación de clientes no autenticados**, los
**hallazgos** que llevaron al estado actual y **cómo verificarlo**. Complementa:
- `DOCS/minipc/CAPTIVE-PORTAL.md` — arquitectura del portal (splash, accept handler).
- `DOCS/minipc/FIREWALL-NFTABLES.md` — firewall nftables completo.

Fuente de verdad del ruleset: rol Ansible **`minipc/router-setup/roles/firewall/`**
(`templates/nftables.conf.j2` → `/etc/nftables.conf`).

---

## 1. Resumen ejecutivo (estado actual)

El portal cautivo intercepta a los clientes de VLAN30 (`192.168.30.0/24`, WiFi vía el
Linksys E2500) y los obliga a aceptar el splash antes de navegar. La autorización se guarda
por **MAC** en el set nftables `captive_allowed_mac` (timeout 8h).

| Vector de un cliente NO autenticado | Comportamiento | Estado |
|---|---|---|
| HTTP IPv4 (`tcp/80`) | DNAT → nginx `:80` → splash en `http://biblioteca.tel/` (Host=biblioteca.tel) o 302 al canónico (otros Host) | ✅ atrapado |
| HTTPS IPv4 (`tcp/443`) | DNAT → portal `:2050` SSL (cert autofirmado / aviso → splash) | ✅ atrapado |
| Cualquier otro IPv4 → WAN | `forward` exige `mark 0x1` → drop | ✅ bloqueado |
| **IPv6 vía NAT64** (`64:ff9b::/96`) | drop en `captive_mangle` (prerouting) | ✅ bloqueado |
| IPv6 nativo → WAN | sin ruta v6 + `forward` exige marca | ✅ bloqueado |
| Probe de detección de portal del SO | recibe 302 → biblioteca.tel → SO detecta portal → abre CNA | ✅ correcto |

Un cliente **autenticado** (su MAC en el set) recibe `meta mark 0x1` y navega normal
(HTTP por el proxy cache, HTTPS directo, IPv6/NAT64 permitido).

---

## 2. Cómo funciona el bloqueo — flujo de una request

### 2.1 Marcado del cliente (cadena `captive_mangle`, prio mangle −150)

Corre **antes** que el DNAT (`dstnat` −100) y antes que Jool. Por cada paquete de VLAN30:

```nft
chain captive_mangle {
    type filter hook prerouting priority mangle; policy accept;
    # 1) Si la MAC está autorizada → marca el paquete como autenticado
    iif "enp171s0.30" ether saddr @captive_allowed_mac meta mark set 0x1
    # 2) IPv6/NAT64 de NO autenticados → log (rate-limited) + drop incondicional
    iif "enp171s0.30" ip6 daddr 64:ff9b::/96 meta mark != 0x1 \
        limit rate 5/minute log prefix "NFT DROP: CAPTIVE-V6-NAT64: "
    iif "enp171s0.30" ip6 daddr 64:ff9b::/96 meta mark != 0x1 drop
}
```

### 2.2 IPv4 — intercepción HTTP/HTTPS (tabla `ip nat`, prerouting)

```nft
# NO autenticado: HTTP → nginx :80 (HTTP plano, server_name biblioteca.tel sirve
# splash; default_server hace 302 a http://biblioteca.tel/ → URL bar canónica)
iif "enp171s0.30" meta mark != 0x1 tcp dport 80  dnat to 192.168.30.1:80
# NO autenticado: HTTPS → portal :2050 SSL (cert autofirmado fallback — el
# usuario debe aceptar warning, después llega al splash y el botón Aceptar
# usa URL absoluta a http://biblioteca.tel/accept)
iif "enp171s0.30" meta mark != 0x1 tcp dport 443 dnat to 192.168.30.1:2050
# Autenticado: HTTP → proxy nginx (:8888) → Squid RPi (cache)
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80 dnat to 192.168.30.1:8888
```

### 2.3 IPv4 — control de salida (cadena `forward`, policy drop)

```nft
# VLAN30 → WAN / servidores: SOLO con marca 0x1 (autenticado)
iif "enp171s0.30" oif "enp170s0"     meta mark 0x1 accept
iif "enp171s0.30" oif "enp171s0.20"  meta mark 0x1 accept
```
Sin marca, el tráfico (que no sea 80/443, ya interceptado) cae en el `policy drop`.

### 2.4 IPv6 — por qué NAT64 necesitaba bloqueo explícito

La red es **dual-stack**: `radvd` anuncia IPv6 a VLAN30, **DNS64** (Bind9) sintetiza
registros AAAA hacia el prefijo NAT64 `64:ff9b::/96`, y **Jool** traduce ese IPv6 → IPv4 y
lo saca a Internet. Diagrama del problema:

```
Cliente VLAN30 (sin marca)
   │  DNS64: ejemplo.com → AAAA 64:ff9b::<ipv4>
   │  (Happy Eyeballs / RFC 6724: el SO PREFIERE IPv6)
   ▼
Paquete IPv6 a 64:ff9b::/96
   │
   ▼  Jool (netfilter) lo "roba" en PREROUTING ───────────────┐
   │                                                          │  ← la cadena forward
   ▼  traduce a IPv4 y reinyecta → masquerade → Internet      │     (control de marca)
                                                              │     NUNCA ve el paquete
   El control de marca de `forward` no aplica  ───────────────┘
```

Por eso el bloqueo IPv6 va en `captive_mangle` (prerouting, prio −150): corre **antes** de
que Jool procese el paquete y **después** de marcar al autenticado, así solo cae el tráfico
NAT64 de no autenticados. Efecto colateral deseable: la *probe* de detección de portal del
SO (que sale por IPv6) falla → el SO concluye que hay portal → cae a IPv4 → ve el splash.

---

## 3. Hallazgos

### Hallazgo 1 — Bypass del portal vía IPv6/NAT64 (causa raíz del bug original)

**Síntoma reportado:** un cliente nuevo podía navegar sin aceptar el splash.

**Causa:** el portal solo controlaba IPv4 (DNAT 80/443 + marca en `forward`). El tráfico
IPv6/NAT64 no tenía ni redirección al portal ni control de marca, porque Jool lo intercepta
en prerouting antes de `forward`. Con DNS64 sintetizando AAAA para todo, los dispositivos
preferían IPv6 y navegaban sin pasar por el portal (la probe del SO también pasaba por IPv6).

**Fix:** regla de `drop` para `ip6 daddr 64:ff9b::/96 meta mark != 0x1` en `captive_mangle`.

### Hallazgo 2 — `limit rate ... drop` en una sola regla fuga tráfico (bug en la propia mitigación)

Al probar en campo, el IPv6 **seguía navegando** pese a la regla de drop. Causa: en nftables
`limit rate N` (sin `over`) es un **matcher** que solo matchea mientras se está **bajo** el
límite. Si se escribe todo junto:

```nft
... meta mark != 0x1 log prefix "..." limit rate 5/minute drop   # ❌ INCORRECTO
```

el `drop` solo se aplica a los **primeros 5 paquetes/minuto**; el resto **no matchea, cae
fuera de la regla y se fuga**. Por eso `example.com` (muchos paquetes) pasaba mientras el log
marcaba cientos de entradas.

**Fix (idioma correcto):** separar en dos reglas — log rate-limited (no terminante) + drop
incondicional:

```nft
... meta mark != 0x1 limit rate 5/minute log prefix "..."   # ✅ solo loguea (no termina)
... meta mark != 0x1 drop                                    # ✅ dropea SIEMPRE
```

**Alcance:** el mismo patrón con fuga existía en **otras reglas preexistentes** del firewall.
Se corrigieron todas con la estructura de dos reglas:

| Regla | Qué fugaba antes |
|---|---|
| `SPOOF-WAN` | anti-spoofing WAN |
| `SSH-BAN` | IPs ya baneadas por fuerza bruta |
| `WAN-BLOCK-*` (10 puertos) | puertos peligrosos desde WAN |
| `VLAN20-TO-30`, `VLAN10-TO-30` | aislamiento entre VLANs |

(La regla `SSH-RATELIMIT` con `limit rate over` y los logs finales antes de `policy drop`
no fugan: su `add @ssh_bruteforce` es incondicional y, con `SSH-BAN` ya corregida, el baneo
es efectivo.)

### Hallazgo 3 — Higiene del repositorio / sincronización playbook ↔ máquina

- El `/etc/nftables.conf` lo generaba el rol **`firewall`**, no el `router`. El rol `router`
  desplegaba su propio `nftables.conf.j2` que `firewall` luego **sobreescribía** (dos
  plantillas al mismo archivo). Se **eliminó** la plantilla duplicada del rol `router` y su
  gestión de nftables se movió por completo al rol `firewall` (incluido deshabilitar UFW).
- Se recuperó en el template del `firewall` la tabla `ip6 nat` (redirección DNS IPv6 →
  Bind9), que existía solo en la plantilla muerta del `router` y no estaba en producción.

---

## 4. Resultados de la prueba de campo

Cliente real conectado al WiFi **"Cerrito Bongo"** (VLAN30), sin autenticar (set
`captive_allowed_mac` vacío).

**Pre-2026-06-02** (portal en `https://192.168.30.1:2050`):

| Prueba | Resultado | Veredicto |
|---|---|---|
| `curl http://example.com` (IPv4) | `302 → https://192.168.30.1:2050/` | ✅ atrapado por el portal |
| seguir redirección | HTML del splash "Bienvenido a Ladrilleros" | ✅ es el portal, no el sitio |
| `curl -k https://www.google.com` | splash del portal | ✅ atrapado |
| `curl -6 http://example.com` (NAT64) | `HTTP 000` / timeout 8s | ✅ bloqueado |
| `curl -6 http://[64:ff9b::101:101]` (NAT64 forzado) | `HTTP 000` / timeout | ✅ bloqueado |
| `curl -6 http://example.com` ×5 seguidas | `000` las 5 (sin fuga) | ✅ fix del Hallazgo 2 |
| `ping 1.1.1.1` | 100% pérdida | ✅ sin salida cruda |

**Post-2026-06-02** (portal canónico en `http://biblioteca.tel/`):

| Prueba | Resultado | Veredicto |
|---|---|---|
| `curl -H 'Host: example.com' http://192.168.30.1/` | `302 → http://biblioteca.tel/` | ✅ canonicalización a biblioteca.tel |
| `curl -H 'Host: biblioteca.tel' http://192.168.30.1/` | `200` con splash.html (3637 bytes) | ✅ splash directo |
| `curl -H 'Host: captive.apple.com' http://192.168.30.1/hotspot-detect.html` | `302 → http://biblioteca.tel/` | ✅ probe del SO atrapado |
| `curl http://192.168.30.1/generate_204` | `302 → http://biblioteca.tel/` | ✅ Android probe |
| `curl http://192.168.30.1/connecttest.txt` | `302 → http://biblioteca.tel/` | ✅ Windows NCSI |
| `curl -k https://192.168.30.1:2050/` | `200` splash (fallback HTTPS) | ✅ HTTPS sigue atrapado |
| URL bar después de aceptar | `https://biblioteca.tel/` | ✅ dominio canónico, sin IP visible |

---

## 5. Operación / verificación

```bash
# Ver clientes autenticados (MACs)
sudo nft list set inet filter captive_allowed_mac

# Borrar TODAS las autorizaciones (forzar re-aceptación del splash)
sudo nft flush set inet filter captive_allowed_mac

# Borrar un cliente puntual
sudo nft delete element inet filter captive_allowed_mac { aa:bb:cc:dd:ee:ff }

# Ver clientes NO autenticados cayendo por el bloqueo IPv6/NAT64
sudo journalctl -kf | grep "CAPTIVE-V6-NAT64"

# Re-desplegar el firewall (idempotente). OJO: el reload hace 'flush ruleset' y
# vacía el set de autenticados → todos re-aceptan el splash una vez.
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
```

### Probar como cliente no autenticado (resumen del método)

1. Vaciar el set: `sudo nft flush set inet filter captive_allowed_mac`.
2. Conectarse al WiFi "Cerrito Bongo" (VLAN30) con un equipo cuya MAC no esté autorizada.
3. `curl -4 -i http://example.com` → debe responder `302` a `http://biblioteca.tel/` (no el sitio).
4. `curl -6 http://example.com` → debe dar timeout (`HTTP 000`), bloqueado por NAT64.
5. Navegar a `http://biblioteca.tel/` → debe mostrar el splash (no la landing real).
6. Si **navega** a sitios reales sin aceptar → hay un problema.

---

## 6. Archivos involucrados

| Archivo | Rol |
|---|---|
| `minipc/router-setup/roles/firewall/templates/nftables.conf.j2` | **Fuente de verdad** del ruleset (incluye el bloqueo IPv6/NAT64 y los fixes de `limit`). |
| `minipc/router-setup/roles/firewall/vars/main.yml` | `nat64_prefix`, rate limits, puertos, etc. |
| `minipc/router-setup/roles/captive_portal/` | splash (`splash.html`), `captive-accept.py`, nginx del portal. |
| `/etc/nftables.conf` (en el Mini PC) | Render desplegado (no editar a mano). |

> Variables clave: `nat64_prefix = 64:ff9b::/96` (debe coincidir con el `pool6` de Jool y la
> directiva `dns64` de Bind9). `enable_drop_logging` activa los logs `NFT DROP:`.
