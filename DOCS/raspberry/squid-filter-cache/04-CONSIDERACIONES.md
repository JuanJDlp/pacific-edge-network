# 04 — Consideraciones, límites y riesgos

> **NOTA HISTORICA (2026-05-30):** El filtrado HTTPS via Squid intercept en `:3130` descrito aqui **ya no esta desplegado**. El DNAT cross-host (Mini PC → RPi) hace que Squid pierda `SO_ORIGINAL_DST`, terminando con `TCP_DENIED CONNECT 192.168.20.10:3130` y rompiendo toda la navegacion HTTPS de los clientes autenticados. El filtrado porn/gambling para HTTPS se hace ahora a nivel DNS via Bind9 RPZ permanente (`rpz.blocklist`, ver `DOCS/minipc/DNS-BIND9.md`). Squid sigue cacheando HTTP (puerto 3129 accel) y aplicando la blocklist por dominio HTTP. Lo que sigue describe el diseno original — util como referencia historica y para las consideraciones sobre DoH, ECH, etc.

Lo que **hay que tener en cuenta** antes y después de operar este sistema. Cosas que pueden salir mal, bypasses conocidos, decisiones que hacen trade-offs.

## 1. Bypasses conocidos del filtrado

### 1.1. DNS-over-HTTPS (DoH)

**Qué es:** El cliente envía sus queries DNS dentro de una conexión HTTPS a un proveedor (Cloudflare, Google, NextDNS, etc.) en lugar de usar el DNS estándar (UDP/TCP 53).

**Cómo bypasea:** nuestro DNS forzado (`dport 53 → Bind9`) no afecta a DoH (que va por 443).

**¿Afecta nuestro filtro?** Parcialmente:
- El cliente resuelve `pornhub.com` vía DoH y obtiene su IP real. 
- Cuando intenta conectar, el paquete TCP/443 con esa IP llega a Mini PC.
- nftables DNATtea a Squid:3130 igual.
- Squid lee el SNI = `pornhub.com` → bloquea.

**Conclusión:** DoH bypasea el filtro DNS pero **NO el filtro SNI de Squid**, porque el SNI viaja en el ClientHello en texto plano. Estamos cubiertos.

**Cuándo SÍ es un problema:** si en el futuro queremos filtrar por DNS también (más rápido, más barato), DoH lo bypasea. Mitigación: bloquear los IPs/dominios de proveedores DoH conocidos (`mozilla.cloudflare-dns.com`, `dns.google`, etc.) — están listados públicamente.

### 1.2. Encrypted ClientHello (ECH) / Encrypted SNI (ESNI)

**Qué es:** Extensión TLS 1.3 donde el SNI también se cifra (con una clave del servidor).

**Cómo bypasea:** Squid no puede leer el SNI → no puede filtrar.

**¿Afecta hoy?** Mínimo. ECH está en draft estándar y solo lo usan navegadores muy nuevos (Firefox/Chrome con flags experimentales) hacia Cloudflare. Los clientes típicos de la red comunitaria (Android stock, iOS) no lo usan.

**Mitigación si se vuelve común:**
- Bloquear ECH detectando el campo `encrypted_client_hello` en el ClientHello (Squid no lo soporta nativamente — habría que cambiar a un firewall con DPI más avanzado).
- Bloquear los IPs de Cloudflare ECH (no es viable, muchos sitios legítimos los usan).

**Decisión:** no hacemos nada hoy. Si el problema crece, revisitar.

### 1.3. Static IP + DNS externo

**Qué es:** El usuario configura una IP estática en su dispositivo (e.g., 192.168.30.250) y un DNS externo (8.8.8.8) en lugar de los del DHCP.

**Cómo bypasea:** Si la IP estática que elige está fuera del set autorizado en `captive_allowed_mac`, el mark `0x1` no se asigna → forward chain en nftables `drop`. No tiene salida.

**Pero**: si el usuario primero se autentica vía portal cautivo (mark se asigna por MAC), luego cambia la IP a estática, el mark sigue aplicando (porque es por MAC, no por IP). Entonces puede salir.

**¿Bypasea el filtro?** No:
- DNS: la regla DNAT a Bind9 sigue aplicando (es por puerto 53, no por mark).
- HTTPS: el DNAT a Squid:3130 sigue aplicando (es por puerto 443 + mark, ambos satisfechos).
- HTTP: el DNAT a Squid:3129 sigue aplicando (igual).

**Conclusión:** IP estática no bypasea el filtro mientras la MAC esté autorizada. El filtro siempre actúa.

### 1.4. MAC spoofing

**Qué es:** El usuario cambia la MAC de su dispositivo a una autorizada por el portal cautivo de OTRO dispositivo (e.g., copia la MAC del laptop del vecino que ya pasó por el portal).

**Cómo bypasea:** Si el set `captive_allowed_mac` tiene esa MAC, el mark se asigna y el tráfico sale.

**¿Bypasea el filtro?** No por las mismas razones que static IP.

**¿Bypasea el portal cautivo?** Sí. Es una limitación conocida del modelo de auth por MAC. La mitigación sería autenticación 802.1X en el switch (RADIUS), que es overkill para una red comunitaria.

### 1.5. VPN del cliente

**Qué es:** El usuario corre un cliente VPN (WireGuard, OpenVPN, Tailscale) que tunneliza TODO su tráfico cifrado al endpoint.

**Cómo bypasea:** desde el switch en adelante, ve solo paquetes UDP/443 (WireGuard) o TCP/443 (OpenVPN sobre TLS) hacia el endpoint del VPN. SNI = el del endpoint. Si el endpoint no está en blocklist, Squid lo splice y el usuario tiene salida sin filtrar.

**¿Lo prevenimos?** No (sería desproporcionado para una red comunitaria). Documentado para conciencia.

**Mitigación opcional (no implementada):** bloquear UDP outbound excepto 53/123/443-DNS, o bloquear endpoints de VPN comerciales conocidos (NordVPN, ExpressVPN). Caro de mantener.

## 2. Limitaciones de performance

### 2.1. RPi 4 / 5 — capacidad

**Squid en una RPi 5** puede manejar fácilmente ~200 conexiones HTTPS concurrentes con peek+splice (es operación TCP-relay, no hay descifrado).

**Para una red comunitaria de ≤50 clientes simultáneos, sobra margen.**

**Síntomas de saturación** (observar si la red crece):
- `top` muestra `squid` >50% CPU sostenido.
- `cache.log` reporta `Too many open files` (subir `ulimit -n` o el límite systemd).
- Latencia de respuesta sube notablemente (>500ms a contenido cacheado).

### 2.2. Cache size

**Configurado:** 10 GB en disco (`cache_dir aufs 10240 16 256`) + 512 MB en RAM (`cache_mem`).

**Monitoreo:**
```bash
ssh akasicom@100.90.81.168 'du -sh /var/lib/biblioteca/squid-cache'
```

**Si el cache se llena:** Squid evicta automáticamente entries viejas (LRU). No causa fallo, solo reduce hit rate.

**Si quieres más cache:** editar `raspberry/rpi-setup/roles/squid/templates/squid.conf.j2` línea `cache_dir aufs ... 10240 ...` (el `10240` son MB) y `cache_mem 512 MB`. Re-deploy. Squid requiere reinicio (no `reload`) cuando `cache_dir` cambia.

### 2.3. Tamaño de la blocklist

**Actual:** 82 803 dominios.

**Squid maneja `dstdomain` con archivo en O(log n)** — búsqueda en árbol binario. 82k es trivial (~17 comparaciones). Squid maneja sin problema hasta millones.

**Si pasas a 1M+ entries**, considera:
- Romper en categorías (un archivo por cada tipo) — facilita whitelisting selectivo.
- Pre-compilar a un formato más eficiente con helpers externos. Pero solo si notas latencia.

## 3. Privacidad

### 3.1. Qué Squid loguea

`/var/log/squid/access.log` registra POR CADA REQUEST:
- Timestamp
- IP del cliente
- Acción (HIT/MISS/DENIED/TUNNEL)
- URL completa (HTTP) o SNI + IP (HTTPS spliced) o domain (bloqueado)
- Tiempo de respuesta
- User-agent (si está en el formato)

**Implicaciones**:
- Esto es un registro de qué visitó cada IP. En una red comunitaria con DHCP no fijo, la IP cambia, pero la MAC podría correlacionarse.
- Si una persona usa el portal, su MAC se almacena con timestamp. La MAC + access.log = perfil de navegación.

**Recomendaciones**:
- Rotar `access.log` diariamente (logrotate ya lo hace por defecto en Ubuntu).
- Restringir lectura del log al user `root`/`adm` (es así por defecto).
- Considerar deshabilitar el access.log en producción si no se necesita para troubleshooting (`access_log none` en squid.conf). Tradeoff: pierdes debugging.

### 3.2. Qué NO logueamos

- **Contenido de las páginas** (no descifratmos HTTPS, no inspeccionamos HTTP body).
- **Headers HTTP individuales** (solo el método + URL en HTTP).
- **Cookies, posts, etc.**

### 3.3. Squid en peek+splice ≠ MITM

A pesar del nombre "ssl-bump", peek+splice NO es un man-in-the-middle. El TLS sigue siendo end-to-end entre cliente y servidor. Squid solo observa el SNI (visible públicamente en el ClientHello). Es análogo a leer el "TO:" de un sobre.

## 4. Qué pasa cuando algo se cae

### 4.1. Squid down → consecuencias

**Si Squid se cae** (crash, OOM, manual stop):
- biblioteca.tel HTTPS → **inaccesible** (nadie en :443). nginx solo escucha en 127.0.0.1:8443.
- biblioteca.tel HTTP → **funciona** (va directo a nginx :80, no pasa por Squid).
- internet HTTPS (filtrado) → la regla DNAT en Mini PC apunta a 192.168.20.10:3130. Si Squid no responde, los clientes ven `connection refused`. → no hay salida HTTPS para clientes autenticados.
- internet HTTP → la regla DNAT apunta a Mini PC nginx :8888, que también requiere Squid:3129 vivo. Si Squid muere, clients ven nginx offline page.

**Mitigación a corto plazo (sin restaurar Squid)**:
1. Para restaurar biblioteca.tel HTTPS rápido: en RPi cambiar nginx temporalmente a `listen 443 ssl` y reload. Los clientes vuelven a ver el contenido directo (sin cache).
2. Para deshabilitar el filtro HTTPS: en Mini PC, `sudo nft delete rule ip nat prerouting handle <N>` (la regla del DNAT a 3130) — clients pasan directo a internet sin filtro.

**Restauración real**: `systemctl restart squid` en la RPi. Si el config está roto, `squid -k parse` muestra el FATAL.

**Monitoreo**: Prometheus + node_exporter ya están instalados. Considera añadir alerta cuando `up{instance="rpi:9100"}` baja o cuando el listener :443 cae (Blackbox exporter probe).

### 4.2. nginx (RPi) down → consecuencias

**Si nginx se cae**:
- biblioteca.tel HTTP → **inaccesible**.
- biblioteca.tel HTTPS via Squid → MISS cae a cache_peer (127.0.0.1:80) que no responde → 503 al cliente.
- biblioteca.tel HTTPS HIT desde cache → todavía sirve (Squid no necesita backend para hits).

### 4.3. RPi entera down → consecuencias

- Toda biblioteca.tel inaccesible.
- Filtro HTTPS DNAT apunta a un host que no responde → clientes ven `connection refused` para HTTPS.
- Filtro HTTP DNAT a Mini PC nginx :8888 → nginx Mini PC intenta proxy a Squid RPi → falla → muestra `offline.html`.

**Plan**: tener un imagen de respaldo de la RPi (microSD clonada). Restauración estimada: 30 min.

### 4.4. Mini PC down → consecuencias

- Sin DHCP, DNS, NAT a internet, portal cautivo.
- biblioteca.tel sigue accesible solo si los clientes ya tienen IP estática + ruta directa a la RPi (improbable).

**Plan**: Mini PC es el SPOF principal. Considera backup o redundancia. Fuera del scope de esta implementación.

### 4.5. WAN (internet upstream) down

- Internet inaccesible (esperado).
- biblioteca.tel sigue accesible 100% (sirve desde caches locales).
- Squid tiene `connect_timeout 15s` para fallar rápido. nginx Mini PC intercepta el 503/504 y muestra `offline.html`.

**Diseño explícito**: el sistema funciona offline. Cache de biblioteca.tel y blocklist están locales, no requieren WAN.

## 5. Mantenimiento

### 5.1. Actualización del paquete Squid

```bash
ssh akasicom@100.90.81.168 'sudo apt update && sudo apt upgrade squid-openssl'
```

Tras upgrade, verificar:
```bash
ssh akasicom@100.90.81.168 'squid -v | grep -- "--with-openssl"'
```

Si por alguna razón Ubuntu retira `squid-openssl` y solo deja `squid` (GnuTLS), el filtrado HTTPS dejaría de funcionar tras el upgrade. Verificar el cambio antes de aceptar el upgrade.

### 5.2. Renovar la CA bump

La CA bump (`bump-ca.crt/.key`) está creada con `days=3650` (10 años). No requiere renovación frecuente.

Si quieres rotarla:
```bash
ssh akasicom@100.90.81.168
sudo rm /etc/squid/ssl/bump-ca.{crt,key} /var/lib/squid/ssl_db/*
# Luego ansible-playbook services/squid.yml — los regenera idempotentemente
```

### 5.3. Renovar el cert biblioteca.tel

Lo gestiona el rol `nginx` (task "Generar certificado autofirmado"). Idempotente con `creates:`. Para forzar regen:
```bash
ssh akasicom@100.90.81.168 'sudo rm /var/www/html/biblioteca-segura.crt /etc/ssl/private/biblioteca.key'
# Re-run playbook nginx + squid (porque squid copia el cert a su dir)
```

### 5.4. Limpiar el cache

```bash
ssh akasicom@100.90.81.168
sudo systemctl stop squid
sudo rm -rf /var/lib/biblioteca/squid-cache/*
sudo squid -z              # re-inicializa estructura
sudo systemctl start squid
```

Útil si: cache corrupto, ocupando demasiado espacio, contenido obsoleto que no se refresca.

### 5.5. Ver logs de actualización de blocklist

```bash
ssh akasicom@100.90.81.168 'tail -50 /var/log/squid-blocklist.log'
```

## 6. Riesgos y sus mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Squid no levanta tras config nueva | Media | Alto (servicios HTTPS caídos) | `validate: /usr/sbin/squid -k parse` en el template task — falla en deploy, no en runtime |
| Blocklist URL caída | Baja | Bajo | Script aborta sin tocar la lista vigente |
| Cache corrupto causa crashes | Muy baja | Medio | `squid -z` en startup repara estructura |
| Cliente reporta sitio bueno bloqueado falso positivo | Media | Bajo | Whitelist explícita (ver [`06-BLOCKLISTS.md`](06-BLOCKLISTS.md)) |
| Memoria/CPU saturada en RPi | Baja | Medio | Reducir `cache_mem`, optimizar `refresh_pattern` |
| Cert biblioteca.tel expirado | Baja (10y) | Medio | Renovar con regla idempotente del rol nginx |
| WAN caído → Squid timeouts | Alta (en zonas con conectividad inestable) | Bajo | `connect_timeout 15s` + offline.html fallback |
| Squid 6 deprecation warnings en logs | Baja | Nulo | Squid sigue funcionando; revisitar en 1-2 años |

## 7. Cosas que NO hace este setup

Para evitar expectativas equivocadas:

- ❌ **No filtra por categoría dinámica** (e.g., "todo lo relacionado con noticias"). Solo por dominio exacto.
- ❌ **No inspecciona contenido HTTPS** (no descifra). Si una página tiene contenido malo pero el dominio no está bloqueado, pasa.
- ❌ **No tiene panel admin web**. Toda la configuración es vía Ansible + commits a git.
- ❌ **No tiene estadísticas en vivo** (más allá de los logs). Squid expone métricas via `squidclient mgr:*` pero no están en Grafana actualmente.
- ❌ **No bloquea por horario / quotas / por usuario**. Es bloqueo por dominio plano.
- ❌ **No cumple ningún estándar de cumplimiento legal** (PCI, HIPAA, GDPR, etc.). Es proyecto de laboratorio comunitario.

## 8. Mejoras futuras opcionales

Listadas en orden de complejidad ascendente:

1. **Más categorías de blocklist** — añadir URLs a `squid_blocklist_sources` en group_vars. Trivial.
2. **Whitelist explícita** — para sitios falsamente bloqueados. Ver [`06-BLOCKLISTS.md`](06-BLOCKLISTS.md).
3. **Página de error custom** cuando Squid bloquea — actualmente cliente solo ve `connection closed`. Implica usar `deny_info` + página HTML.
4. **Bloqueo de DoH/DoT** — añadir dominios de proveedores a blocklist + drop puerto 853.
5. **Métricas Prometheus** — usar `squid-exporter` (proyecto comunitario) para exponer hit rate, latencia, etc.
6. **Logging configurable por categoría** — separar `access.log` por flow (filter vs accel).
7. **HTTPS biblioteca.tel con Let's Encrypt** — si en el futuro DNS público apunta a la RPi. Hoy no aplica (DNS interno).
8. **Multi-tenant**: distintas blocklists para distintas VLANs (e.g., VLAN30 estricto, VLAN40 más laxo). Squid soporta múltiples ACL por `src`.
