# Informe de completitud — Pacific Edge Network

> **Propósito.** Base para confirmar que el proyecto está completo de cara a la máxima nota.
> Se evalúa **componente por componente del `checklist_sistema.md`**, contrastando el **DoD (Definition of Done)** contra **diagnósticos ejecutados en vivo** sobre el Mini PC, la Raspberry Pi **y un cliente real conectado a la WiFi del sistema**.
>
> - **Fecha del diagnóstico:** 2026-06-02
> - **Método:** comandos por SSH/NetBird contra ambos nodos + **sesión de cliente real en VLAN 30** (laptop conectada a SSID `Cerrito Bongo`, IP `192.168.30.120`).
>   - Mini PC: `ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134` (sudo NOPASSWD)
>   - RPi: `ssh -i ~/.ssh/id_ed25519_ladrilleros akasicom@100.90.81.168` (sudo NOPASSWD)
> - **Alcance excluido por indicación:** Componente **#11 Almacenamiento 2–4 TB** y **alertas del monitoreo** (descopados).

---

## 1. Resumen ejecutivo (semáforo)

| # | Componente | Estado | Veredicto corto |
|---|-----------|:------:|-----------------|
| 1 | Dual Stack / IPv6 | 🟢 | **Cliente real con SLAAC + RDNSS**; NAT64 (Jool) + DNS64; servicio servido por IPv6 (HTTP 200) |
| 2 | DHCPv4 (Kea) | 🟢 | **Cliente tomó `192.168.30.120` del pool**, gw y DNS local; reserva por MAC; DHCPv6 = SLAAC (decisión) |
| 3 | DNS (master+slave / DNSSEC / TSIG / DNS64) | 🟢 | Master+slave y **failover probado ✅**, DNS64 ✅, **DNSSEC ✅** (zona firmada, `secure: yes`, `delv` *fully validated*), **TSIG ✅** (AXFR con `ns1-ns2`; sin clave → REFUSED) |
| 4 | Proxy-cache (Squid) | 🟢 | ssl-bump (HTTPS), `cache_dir` 10 GB jerárquico, refresh_patterns |
| 5 | Portal cautivo | 🟢 | **Redirect→login probado en cliente**, mark 0x1 deja pasar, **anti-bypass DNS probado** |
| 6 | CDN / contenido offline | 🟢 | **Navegado desde cliente**: dashboard, Kiwix, Kolibri, Jellyfin, búsqueda |
| 7 | Mensajería tipo Matrix | 🟠 | **Conduit accesible desde cliente (`:8448` responde)**, pero `server_name`/DNS desalineados |
| 8 | NTP (Chrony) | 🟢 | Stratum 3, `allow 192.168/16`, `local stratum 10` (offline), offset µs |
| 9 | Monitoreo y observabilidad | 🟢 | 4 targets UP + Grafana con dashboards (alertas descopadas por indicación) |
| 10 | Streaming Jellyfin (transcode) | 🟢 | Activo; transcode por **software** (HW accel = none) — justificar |
| 11 | Almacenamiento 2–4 TB | ⚪ | **Excluido por indicación** |
| 12 | Dashboard con búsqueda | 🟢 | Dashboard categorizado + **búsqueda probada desde cliente** (`/search`→Kiwix, HTTP 200) |
| 13 | Modo offline + actualización online | 🟢 | `wan-check.timer` + scripts de update con guard de conectividad/disco |

**Leyenda:** 🟢 cumple DoD · 🟠 parcial / con hueco · 🔴 no implementado · ⚪ fuera de alcance.

### Huecos que aún bloquean el 100% (prioridad)

1. ~~**DNSSEC no activo**~~ ✅ **RESUELTO** (2026-06-02) — zona `biblioteca.tel` firmada con `dnssec-policy default` + `inline-signing` (BIND 9.18). `secure: yes`, CSK ECDSAP256SHA256, DNSKEY+RRSIG servidos en master y slave; `delv +root=biblioteca.tel` → *fully validated* con el trust-anchor local.
2. ~~**TSIG no configurado**~~ ✅ **RESUELTO** (2026-06-02) — transferencias master↔slave autenticadas con la clave `ns1-ns2` (hmac-sha256). `allow-transfer` global = `none`, por-zona `key`; AXFR sin clave → **REFUSED**, con clave → 80 registros firmados. Logs del slave: `transferred serial …: TSIG 'ns1-ns2'`.
3. **Matrix desalineado** (DoD 2.7) — funciona en `:8448` pero `server_name = praticasaws.dev` y `matrix.biblioteca.tel` **no resuelve**; `allow_federation = true`.
4. **Faltan scripts de purga por umbral y de backup de configs** (Sección 3 de Infra 2).

---

## 2. Sesión de cliente real (VLAN 30) — evidencia clave

Laptop conectada a `Cerrito Bongo` (red abierta, portal cautivo). Resultados:

| Prueba | Resultado |
|---|---|
| **DHCP** | IP `192.168.30.120/24` (pool `.100-.200`), gw `192.168.30.1`, DNS `192.168.10.1` ✅ |
| **Portal cautivo** | Apareció el portal y requirió login; tras autenticar hay salida a internet (`ping 1.1.1.1` OK) ✅ |
| **IPv6 SLAAC** | Direcciones globales `fd00::30:…` (temporary + mngtmpaddr), default v6 `proto ra` ✅ |
| **RDNSS (DNS v6 por RA)** | `IP6.DNS = fd00:0:0:30::1` anunciado por RA ✅ |
| **DNS local** | `biblioteca.tel → 192.168.20.10`; `AAAA biblioteca.tel → fd00:0:0:20::10` ✅ |
| **DNS64** | `AAAA ftp.gnu.org → 64:ff9b::d133:bc14` ✅ |
| **DNSSEC** | Zona firmada (`secure: yes`); master y slave sirven DNSKEY+RRSIG; `delv +root=biblioteca.tel` → *fully validated* ✅ (la respuesta autoritativa lleva `aa`, no `ad` — ver §3.3) |
| **Servicio por IPv6** | `curl -6 https://biblioteca.tel` (→`fd00:0:0:20::10`) = **HTTP 200** ✅ |
| **Contenido** | `http/https biblioteca.tel`=200, `/wikipedia/`=200, `/search?pattern=agua`=200, `/kolibri/`,`/videos/`=302 ✅ |
| **Anti-bypass DNS** | `dig @8.8.8.8 biblioteca.tel → 192.168.20.10` (DNS externo **forzado** al resolver local) ✅ |
| **Matrix** | `https://praticasaws.dev:8448/_matrix/client/versions` (→`192.168.20.10`) responde JSON; TCP `:8448` abierto ✅ pero por nombre `biblioteca.tel` da 404 ⚠️ |

> Para restaurar internet del operador: reconectar a la WiFi `PUBLICA` (`nmcli con up PUBLICA`).

---

## 3. Detalle por componente (DoD verificado en vivo)

### 3.1 Dual Stack / IPv6 — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Mini PC con IPv6 y enruta entre VLANs | ✅ | `net.ipv6.conf.all.forwarding = 1`; cada `enp171s0.{10,20,30}` con `fd00:0:0:N::1/64` |
| Cada VLAN con prefijo propio + cliente obtiene dirección | ✅ **(cliente real)** | Laptop recibió `fd00::30:…` por SLAAC; rutas `proto ra` por VLAN |
| RA anuncia DNS (RDNSS) | ✅ **(cliente real)** | `IP6.DNS = fd00:0:0:30::1` en el cliente |
| Servicios clave responden por IPv6 | ✅ **(cliente real)** | `curl -6 https://biblioteca.tel` = HTTP 200 (`fd00:0:0:20::10`); `named` escucha en `[fd00:…]:53` |
| NAT64 real al que apunta DNS64 | ✅ | `jool-nat64.service` active; DNS64 `64:ff9b::d133:bc14` |

**Decisión documentada:** SLAAC + RA (RDNSS) en lugar de DHCPv6, por simplicidad en red comunitaria.

### 3.2 DHCPv4 — Kea — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Pools VLAN 10/20/30 con gw y DNS local | ✅ | `.30`→pool `.100-.200`, gw `.30.1`, dns `192.168.10.1` (cliente lo confirmó) |
| Lease razonable + persistencia | ✅ | `valid-lifetime: 4000`; backend CSV |
| Al menos una reserva por MAC | ✅ | `2c:cf:67:d2:f0:98 → 192.168.20.10` (RPi) |
| Decisión DHCPv6 documentada | ✅ | SLAAC (ver 3.1) |

### 3.3 DNS — Bind9 (master+slave / DNSSEC / TSIG / DNS64) — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| `biblioteca.tel` en master y slave sincronizados | ✅ | Master `signed serial 1780434929`; slave (RPi) `secondary` con **mismo serial** |
| Slave responde si el master cae | ✅ **(probado en vivo)** | Ver §4 — con master detenido, slave resolvió la zona |
| **TSIG** en la transferencia | ✅ **(probado en vivo)** | Clave `ns1-ns2` (hmac-sha256); `allow-transfer { key "ns1-ns2."; }`, slave `masters { 192.168.20.1 key "ns1-ns2."; }`. **AXFR sin clave → REFUSED**; con clave → 80 registros. Log slave: `transferred serial 1780434929: TSIG 'ns1-ns2'` |
| **DNSSEC** (zona firmada) | ✅ **(probado en vivo)** | `dnssec-policy default` + `inline-signing` (BIND 9.18); `rndc zonestatus` → `secure: yes`; CSK `ECDSAP256SHA256` (3843); DNSKEY+RRSIG en master **y** slave; `delv +root=biblioteca.tel -a <ta>` → **`; fully validated`**. Trust-anchor local publicado en `named.conf.trust-anchors` |
| **DNS64** sintetiza AAAA `64:ff9b::` | ✅ | Cliente: `AAAA ftp.gnu.org → 64:ff9b::d133:bc14` |

> **Nota flag AD:** ambos servidores son *autoritativos* para `biblioteca.tel`, así que sus respuestas llevan `aa` (no `ad`); el `ad` solo aparece en un resolver recursivo no-autoritativo. La validación DNSSEC se demuestra con `delv` (*fully validated*) usando el trust-anchor de la zona (un TLD local no tiene cadena de confianza desde la raíz).

**Aplicado el 2026-06-02** ejecutando los playbooks (`minipc/services/dns.yml` + `raspberry/services/dns_secondary.yml`). De paso se corrigieron los bugs de los roles que impedían aplicarlos (ver §5).

### 3.4 Proxy-cache — Squid — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Cachea HTTP + estrategia HTTPS | ✅ | `https_port 443 accel` + `3130 intercept ssl-bump`; `ssl_bump peek/splice/terminate` |
| Jerarquía de caché definida | ✅ | `cache_dir aufs … 10240 16 256`; `cache_mem 512 MB`; `maximum_object_size 128 MB` |
| Sirve con internet caído | ✅ (por diseño) | Reverse-proxy/cache de `biblioteca.tel` (contenido local) |

### 3.5 Portal cautivo — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Cliente nuevo en VLAN 30 es redirigido | ✅ **(cliente real)** | Apareció el portal al conectarse; nat `prerouting` `mark != 0x1 dport 80/443 dnat …:80/:2050` |
| `mark 0x1` deja pasar tras autenticar | ✅ **(cliente real)** | Tras login hay salida (`ping 1.1.1.1` OK); `forward` solo deja `mark 0x1` |
| Anti-bypass (forzado de DNS) | ✅ **(cliente real)** | `dig @8.8.8.8 biblioteca.tel → 192.168.20.10` (DNS externo redirigido al local) |

> `captive-portal.service` dedicado inactivo: el **nginx principal** asume los listens `:2050`/`:8888` (redundante, no es fallo).

### 3.6 CDN / contenido offline — 🟢

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Kiwix / Kolibri / Jellyfin sirviendo | ✅ **(cliente real)** | `http://biblioteca.tel/wikipedia/`=200, `/kolibri/`=302, `/videos/`=302 |
| nginx reverse proxy con paths limpios | ✅ | `/wikipedia/ /content/ /search /suggest /random`→Kiwix; `/videos/`→Jellyfin; `/kolibri/`→Kolibri |
| Contenido categorizado | ✅ | `index.html` + páginas de categoría (`salud`, `seguridad`) |

### 3.7 Mensajería tipo Matrix — 🟠 (funciona, desalineado de nombre)

| Ítem DoD | Estado | Evidencia |
|---|:--:|---|
| Homeserver corriendo y accesible | ✅ / ⚠️ | `conduit.service` en `127.0.0.1:6167`; nginx lo expone en **`:8448`** (`server_name praticasaws.dev`). **Cliente** alcanza `https://…:8448/_matrix/client/versions` ✅, pero `matrix.biblioteca.tel` **no resuelve** y por `:443` da 404 |
| Registro de usuarios local | ✅ | `allow_registration = true` (con token) |
| Persistencia | ✅ | `database_path = /var/lib/matrix-conduit/` (~85 MB) |
| Federación deshabilitada / solo-local | ⚠️ | `allow_federation = true` |

**Acción para 100%:** alinear `server_name = biblioteca.tel`, crear DNS `matrix.biblioteca.tel`, exponer en `:443`, `allow_federation = false`; y **llevar Conduit a Ansible** (hoy es manual, §5).
**Para la demo hoy:** configurar Element con homeserver `https://192.168.20.10:8448`.

### 3.8 NTP — Chrony — 🟢
Stratum 3, `allow 192.168.0.0/16`, `local stratum 10` (sirve offline), `Leap: Normal`, offset ~18 µs.

### 3.9 Monitoreo y observabilidad — 🟢
4 targets en Prometheus, todos `up`; `prometheus-node-exporter` :9100 en Mini PC y RPi; Grafana :3000 con dashboards aprovisionados. *(Alertas descopadas por indicación.)*

> Cosmético: unidad `node_exporter.service` failed/huérfana en ambos hosts (se usa el paquete `prometheus-node-exporter`); conviene eliminarla.

### 3.10 Streaming Jellyfin — 🟢 (con matiz)
`jellyfin` :8096 active; `scan-jellyfin-library` diario. `encoding.xml`: `HardwareAccelerationType = none` → **transcode por software** (justificar: HW transcode limitado en la RPi). **⏳ pendiente:** 2 reproducciones simultáneas observando CPU.

### 3.12 Dashboard con búsqueda — 🟢
Dashboard categorizado con enlaces a servicios; **búsqueda probada desde cliente**: `/search?pattern=agua` → HTTP 200 (Kiwix full-text).

### 3.13 Modo offline + actualización online — 🟢

| Ítem (Sección 3) | Estado | Evidencia |
|---|:--:|---|
| Refresco / descarga de contenido | ✅ | cron RPi: `update-kiwix-content`, `update-kolibri-content`, `scan-jellyfin-library`, `update-squid-blocklist` |
| Detección online/offline | ✅ | Mini PC `wan-check.timer` (~15 s); scripts RPi con guard `"No internet — skipping"` |
| Health-check / auto-restart | ✅ | `biblioteca-health.timer` cada 30 s → `/status` |
| **Purga por umbral (>85%)** | ⚠️ | Hay guard de disco (`MIN_FREE_MB`) y rotación de versiones (`rm` ZIM viejo), pero no purga por umbral con log |
| **Backup de configs** | ⚠️ | Sin script de backup en runtime; la config vive en el repo Ansible/git |

---

## 4. Prueba en vivo del DNS secundario (failover) — ✅ PASA

Ejecutado con red de seguridad (auto-restart a 60 s). Downtime ≈ 22 s.

```
[A] Mini PC: systemctl stop named   → inactive
[B] RPi (master CAÍDO):
      dig @192.168.20.10 biblioteca.tel SOA → ns1.biblioteca.tel. … 1779917047 …
      dig @192.168.20.10 biblioteca.tel     → 192.168.20.10 (resuelve)
      dig @192.168.20.1  biblioteca.tel     → ;; no servers could be reached
[C] Mini PC: systemctl start named  → active; responde SOA
```

**Conclusión:** el slave sigue autoritativo con el master caído (según SOA `expire 604800`, hasta **7 días**).

---

## 5. Discrepancias repo (Ansible) ↔ sistema vivo

1. ~~**DNSSEC/TSIG**~~ ✅ **RESUELTO** (2026-06-02). Causa raíz: el rol nunca pudo aplicarse por **bugs** que se corrigieron: (a) `tsig.yml` copiaba la clave al slave con `delegate_to: 192.168.20.10` — inalcanzable desde la laptop de control; ahora la clave es **estática/compartida** vía var `tsig_secret` en ambos roles. (b) El slave no incluía ni usaba la clave TSIG. (c) `named.conf.options.j2` divergía del vivo (le faltaban `dns64 mapped/exclude` y el `include` de RPZ) y traía `filter-aaaa-on-v4` que rompía `named-checkconf` → **se reconcilió el template con el vivo**. (d) `validate: named-checkconf %s` validaba el fragmento `options` aislado y fallaba por el `response-policy` de RPZ → se cambió a validación de **config completa**. (e) Bajo **AppArmor**, `/etc/bind` es solo-lectura para `named` → las claves y el `.signed`/`.jnl` del `inline-signing` se reubicaron a `/var/lib/bind`. Roles y vivo ahora **sincronizados**.
2. **Matrix (Conduit)**: **no existe en el repo** (montaje manual en RPi) → no reproducible; crear rol Ansible.
3. **node_exporter**: el repo instala binario propio (unidad failed/huérfana); en vivo corre el paquete `prometheus-node-exporter`.

---

## 6. Plan corto para “máxima nota”

| Prioridad | Acción | Componente |
|:--:|---|---|
| ✅ Hecho | ~~Firmar zona `biblioteca.tel` (DNSSEC)~~ — `dnssec-policy`+`inline-signing`, `secure: yes`, `delv` validado (2026-06-02) | 3.3 |
| ✅ Hecho | ~~Configurar TSIG master↔slave~~ — clave `ns1-ns2` hmac-sha256, AXFR sin clave → REFUSED (2026-06-02) | 3.3 |
| 🟠 Media | Alinear Matrix: `server_name=biblioteca.tel`, DNS `matrix.biblioteca.tel`, `:443`, `federation=false`; llevarlo a Ansible | 3.7 |
| 🟠 Media | Script de purga por umbral (>85%) con log; script de backup de configs (cron/timer) | Sección 3 |
| 🟢 Baja | Justificar/coherentizar transcode Jellyfin (SW vs VAAPI) | 3.10 |
| 🟢 Baja | Limpiar unidad `node_exporter.service` huérfana | 3.9 |

> **Pendiente menor con cliente:** 2 reproducciones simultáneas en Jellyfin y chat entre 2 clientes Matrix (VLAN 20↔30).
> El **autoritativo externo** queda fuera de alcance; `biblioteca.tel` opera como autoritativa interna.
