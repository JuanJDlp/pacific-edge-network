# Estado Actual del Sistema — Pacific Edge Network
**Fecha:** 2026-05-20  
**Validado por:** inspección en vivo vía SSH

---

## Acceso SSH

| Dispositivo | Comando |
|---|---|
| Mini PC | `ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134` |
| Raspberry Pi | `ssh -i ~/.ssh/plats_mini_pc akasicom@100.90.81.168` |

La clave `plats_mini_pc` está copiada en ambos equipos. Los inventarios de Ansible ya usan esta clave.

---

## Mini PC (`plataformas` — 100.90.95.134)

### Interfaces de red

| Interfaz | IP | Estado |
|---|---|---|
| enp170s0 | 172.16.0.11/16 | UP — WAN hacia router externo |
| enp171s0 | (trunk sin IP) | UP |
| enp171s0.10 | 192.168.10.1/24 | UP — VLAN Gestión |
| enp171s0.20 | 192.168.20.1/24 | UP — VLAN Servidores |
| enp171s0.30 | 192.168.30.1/24 | UP — VLAN Clientes |
| wt0 | 100.90.95.134/16 | UP — NetBird |

### Servicios

| Servicio | Estado | Puerto | Notas |
|---|---|---|---|
| `named` (Bind9) | ✅ activo | 192.168.{10,20,30}.1:53 | Zona biblioteca.tel autoritativa |
| `kea-dhcp4-server` | ✅ activo | 192.168.{10,20,30}.1:67 | Raw sockets, fix macOS APIPA |
| `captive-portal` (nginx) | ✅ activo | 0.0.0.0:2050 | Splash + OS probes |
| `captive-accept` (python) | ✅ activo | 127.0.0.1:2051 | Agrega IPs a nft set |
| `nginx` (apt, http-proxy) | ✅ activo | 0.0.0.0:8888 | Intermediario → Squid RPi:3129 |
| `nginx.service` (apt unit) | ✅ inactivo | — | Sin conflicto con captive-portal |
| `nftables` | ✅ activo | — | Ruleset completo con captive portal |
| `prometheus` | ✅ activo | :9090 | Métricas |
| `grafana-server` | ✅ activo | :3000 | Dashboard |
| `node_exporter` | ✅ activo | :9100 | Métricas del host |

### DNS — validación

```
biblioteca.tel        → 192.168.20.10 ✓
wikipedia.biblioteca.tel → CNAME → biblioteca.biblioteca.tel. → 192.168.20.10 ✓
kolibri.biblioteca.tel   → CNAME → biblioteca.biblioteca.tel. → 192.168.20.10 ✓
google.com             → 172.217.162.110 ✓  (internet activo)
```

### nftables — set captive_allowed

Al momento de la validación había un cliente real autenticado:
```
192.168.30.101  (expires ~7h42m)
```
El flujo de autenticación funciona: `captive-accept.py` agrega IPs correctamente y redirige a `http://biblioteca.tel`.

### Portal cautivo — pruebas

| Prueba | Resultado |
|---|---|
| `GET /` splash page | HTTP 200 ✓ |
| `GET /hotspot-detect.html` (iOS probe) | HTTP 302 → http://192.168.30.1:2050/ ✓ |
| `GET /generate_204` (Android probe) | HTTP 302 → http://192.168.30.1:2050/ ✓ |
| `GET /accept` con X-Real-IP (simular auth) | HTTP 302 → http://biblioteca.tel/ ✓, IP agregada al set ✓ |

### ✅ Fix aplicado — nftables regla 443 (2026-05-20)

Regla corregida a `reject with tcp reset`:
```nft
iif "enp171s0.30" meta mark != 0x00000001 tcp dport 443 reject with tcp reset
```
Template `roles/router/templates/nftables.conf.j2` actualizado. Aplicado vía Ansible.

---

## Raspberry Pi (`akasicom2` — 100.90.81.168 / 192.168.20.10)

### Interfaces de red

| Interfaz | IP | Estado |
|---|---|---|
| eth0 | 192.168.20.10/24 | UP — LAN VLAN20 |
| wlan0 | 192.168.131.174/24 | UP |
| wt0 | 100.90.81.168/16 | UP — NetBird |

### Servicios

| Servicio | Estado | Puerto | Notas |
|---|---|---|---|
| `nginx` | ✅ activo | :80 | Reverse proxy → kiwix/kolibri/jellyfin |
| `squid` | ✅ activo | :3128 (intercept), :3129 (accel) | Cache web |
| `kiwix-serve` | ✅ activo | 127.0.0.1:8080 | HTTP 200 ✓ |
| `kolibri` | ✅ activo | 127.0.0.1:8090 | HTTP 302 en /kolibri/ ✓ |
| `jellyfin` | ✅ activo | 127.0.0.1:8096 | HTTP 200 /health ✓ |
| `named` (DNS secundario) | ✅ activo | 127.0.0.1:53, 192.168.20.10:53 | Zona presente, refreshes fallando |
| `prometheus-node-exporter` | ✅ activo | :9100 | Nombre real del servicio en la RPi |

### Squid — configuración actual

```squid
http_port 3129 accel vhost allow-direct   # recibe requests del nginx del Mini PC
http_port 3128 intercept                  # tráfico local
always_direct allow all
cache_dir aufs /var/lib/biblioteca/squid-cache 10240 16 256
```

El modo `accel vhost allow-direct` en el puerto 3129 es compatible con el nginx del Mini PC que envía requests con `Host:` header y `proxy_http_version 1.0`.

### ⚠️ DNS secundario — zone transfers fallando

El Bind9 de la RPi tiene los datos de la zona `biblioteca.tel` (responde correctamente a queries locales), pero los refreshes periódicos desde el primario (`192.168.20.1:53`) están fallando con timeout.

```
zone biblioteca.tel/IN: refresh: retry limit for primary 192.168.20.1#53 exceeded
zone 20.168.192.in-addr.arpa/IN: Transfer started.
transfer from 192.168.20.1#53: failed to connect: timed out
```

**Causa probable:** conectividad entre RPi (192.168.20.10) y Mini PC (192.168.20.1) a través del switch — puede requerir que el switch esté configurado correctamente con VLAN20 en el puerto de la RPi.  
**Impacto:** la zona tiene datos iniciales correctos. El DNS secundario sirve correctamente mientras no haya cambios en la zona primaria.

### ⚠️ node_exporter — nombre de servicio distinto al Ansible role

El Ansible role usa `node_exporter.service` pero el paquete instalado (`prometheus-node-exporter`) crea `prometheus-node-exporter.service`. Los healthchecks del role que verifiquen `node_exporter` darán falso negativo, pero el servicio está activo.

---

## Flujo de usuario — estado de validación

| Paso | Estado | Observación |
|---|---|---|
| 1. DHCP → IP 192.168.30.x | ✅ Funcional | Kea activo, pool 100-200 VLAN30 |
| 2. HTTP interceptado → portal :2050 | ✅ Funcional | DNAT nftables operativo |
| 3. Splash page servida | ✅ Funcional | nginx 200 |
| 4. OS probes (iOS/Android) | ✅ Funcional | 302 correcto a IP directa |
| 5. Clic Entrar → /accept → IP en set | ✅ Funcional | captive-accept agrega IP |
| 6. Redirect a biblioteca.tel | ✅ Funcional | DNS resuelve → 192.168.20.10 |
| 7. Con internet: navegar normal | ✅ Funcional | HTTPS directo, HTTP vía Squid |
| 8. Sin internet: acceder servicios RPi | ✅ Funcional | DNS interno + nginx RPi OK |
| 9. HTTPS sin autenticar | ⚠️ Subóptimo | `drop` en vez de `reject` → delay 30s |

---

## Issues resueltos (2026-05-20)

| # | Issue | Estado |
|---|---|---|
| 1 | nftables 443: `drop` → `reject with tcp reset` | ✅ Corregido en template + vivo |
| 3 | node_exporter service name — Ansible role ya usa `prometheus-node-exporter` | ✅ Correcto, no requería cambio |
| 4 | RPi nginx rutas legacy `/accept` y `/splash` | ✅ Eliminadas del template y del vivo |

## Issues pendientes

| # | Issue | Prioridad | Fix |
|---|---|---|---|
| 2 | DNS zone transfers timeout RPi → Mini PC | 🟡 Media | Verificar config switch VLAN20 en puerto de la RPi |
