# 02 — Decisiones técnicas y por qué

Este es el documento más importante: cada decisión técnica con sus alternativas, trade-offs y la razón final. Está ordenado más o menos por orden de impacto.

---

## Decisión 1 — Filtrado por DNS RPZ vs filtrado en proxy (Squid)

**Problema:** ¿Cómo bloqueamos páginas prohibidas?

**Alternativas:**

| Opción | Cómo funciona | Pros | Contras |
|---|---|---|---|
| **A. DNS RPZ en Bind9** | El resolver responde NXDOMAIN para dominios bloqueados | Muy barato; funciona para HTTP+HTTPS; no requiere descifrar | Bypaseable con DoH (cliente usa Cloudflare DoH y se salta el DNS); también con IPs hardcoded |
| **B. Filtrado en proxy Squid (SNI)** | Squid lee el SNI del ClientHello TLS y bloquea | Más robusto (sale del SNI directamente, no del DNS); funciona aunque el cliente use DoH para resolver; el filtro está en el path del tráfico | Requiere SSL bump (paquete squid-openssl); más complejo de configurar |
| **C. Ambos en cascada** | DNS bloquea primero, Squid es backup | Cobertura máxima | Doble mantenimiento; duplicación de blocklists |

**Elegimos: B (Squid SNI).**

**Por qué:**
- DoH es trivial de configurar en navegadores modernos (Firefox lo trae por defecto). Confiar solo en DNS es ingenuo en 2026.
- Squid YA está en el path para HTTP de clientes (el flujo HTTP intermediary existía). Añadir HTTPS solo requería un puerto más en Squid.
- El SNI viaja sin cifrar en el ClientHello — peek+splice puede leerlo sin descifrar nada. Es la solución estándar de la industria (Cisco WSA, Zscaler, Fortinet ProxySG todos hacen esto).
- Las listas se mantienen igual (un solo archivo `blocked_domains.txt`) — Squid las usa para HTTP (`dstdomain`) y HTTPS (`ssl::server_name`).

**Lo que perdemos al no usar RPZ también:** un cliente con DoH **podría** llegar a la IP por DoH y luego enviar un ClientHello con SNI vacío o falseado. Casos:
- SNI omitido (ESNI/ECH): tráfico se splice sin filtrar. Mitigación: bloquear los proveedores de ECH si vuelve a ser problema (es raro en clientes domésticos).
- SNI mentiroso (cliente pone `example.com` pero conecta a IP de Pornhub): Squid intentará conectar a `example.com` real (porque hace splice usando SO_ORIGINAL_DST que es la IP original) — pero como cliente miente al certificado, el TLS handshake falla. No es un bypass real.

---

## Decisión 2 — Paquete `squid` (GnuTLS) vs `squid-openssl`

**Problema:** El paquete `squid` por defecto en Ubuntu 24.04 viene compilado con `--with-gnutls`. ¿Sirve para ssl_bump?

**Verificación:**
```
configure options: ... --with-gnutls
                       (NO --with-openssl, NO --enable-ssl-crtd)
```

**Alternativas:**

| Opción | Resultado |
|---|---|
| **A. Usar `squid` (GnuTLS)** | Soporte parcial de SSL bump; `https_port ... ssl-bump` está documentado como no totalmente funcional con GnuTLS en Squid 6. Hay informes de errores en peek+splice. |
| **B. Compilar Squid desde fuente con OpenSSL** | Funciona pero rompe el modelo de actualizaciones de Ubuntu (apt no lo gestiona); cada parche de seguridad requiere recompilar. |
| **C. Instalar `squid-openssl` (paquete oficial Ubuntu)** | Mismo binario que `squid` pero compilado con OpenSSL. Disponible en `noble-updates/universe`. Conflicta con `squid` (uno reemplaza al otro). |

**Elegimos: C.**

**Por qué:**
- Soporte oficial Ubuntu. Misma versión (6.14-0ubuntu0.24.04.2). Mismas actualizaciones de seguridad.
- Drop-in replacement: `/etc/squid/squid.conf` se preserva. El servicio systemd no cambia.
- Soporta `--with-openssl --enable-ssl-crtd` que son requeridos para `ssl_bump peek` y `https_port ... ssl-bump` correctamente.
- Riesgo de instalación: cero (verificado con `apt --dry-run`: solo cambia 1 paquete, ningún otro).

**Implementación:** la tarea Ansible `apt: name=squid-openssl state=present` hace el swap automáticamente. Si el `squid` GnuTLS está instalado, apt lo desinstala silenciosamente.

---

## Decisión 3 — SSL bump completo vs peek+splice

**Problema:** Para filtrar HTTPS necesitamos ver el dominio. ¿Descifrar (bump completo) o solo mirar el SNI (peek+splice)?

**Alternativas:**

| Opción | Squid descifra el tráfico? | Cert custom en clientes? | Rompe HTTPS de algunos sitios? |
|---|---|---|---|
| **A. Bump completo** (`ssl_bump bump`) | Sí, descifra todo | Sí, hay que instalar la CA bump en cada navegador/SO | Sí — banca, apps con cert pinning, Chrome safe-browsing, etc. |
| **B. Peek+splice** (`ssl_bump peek` + `splice`) | NO, solo lee SNI sin cifrar | NO necesario | NO — el cliente sigue hablando E2E con el server |
| **C. Solo bump para dominios específicos** | Sí, pero solo para los que tú decidas | Sí, pero menos sitios afectados | Sí (en los que bumpeas) |

**Elegimos: B (peek+splice).**

**Por qué:**
- **Privacidad real**: Squid nunca ve contraseñas, contenido de mensajes, datos bancarios. Solo el dominio (que ya conoce porque el cliente le envía el SNI). Esto es éticamente importante en una red comunitaria.
- **No requiere distribuir certificados** a clientes. En una red comunitaria de borde con dispositivos heterogéneos (Android viejo, iOS, laptops varias), distribuir y mantener una CA es operativamente imposible.
- **No rompe nada**: el cliente sigue hablando TLS con el server real. Cert pinning (banca, WhatsApp, Telegram), HSTS, certificate transparency — todo funciona.
- **El SNI es lo único que necesitamos** para bloquear por dominio.

**Lo que perdemos:**
- No podemos cachear HTTPS spliced (no podemos leer el contenido, mucho menos guardarlo). Por eso el cache HTTPS solo aplica a biblioteca.tel (donde sí terminamos TLS, ver Decisión 5).
- No podemos hacer filtrado por URL completa (e.g., bloquear `example.com/adult-section` mientras permitimos `example.com/`). Granularidad: solo dominio. Aceptable.

---

## Decisión 4 — Fuente de la blocklist: Shallalist vs StevenBlack vs comercial

**Problema:** ¿De dónde sacamos la lista de dominios bloqueados?

**Alternativas:**

| Opción | Cobertura | Categorías | Mantenimiento | Licencia |
|---|---|---|---|---|
| **A. Shallalist** | ~1.7M dominios categorizados | Sí (porn, gambling, drugs, violence, ...) | Caído / discontinuado al momento de impl. | Gratis |
| **B. StevenBlack/hosts (GitHub)** | ~76k porn + ~6k gambling (variantes categorizadas) | Sí (variantes por categoría) | Actualizado activamente | MIT |
| **C. URLhaus / Spamhaus** | ~100k malware/phishing | No la categoría que queremos | Activo | CC0 / restringida |
| **D. Comercial (Cisco Umbrella, etc.)** | Millones, mejor curado | Sí, finos | Suscripción $ | Pago |

**Elegimos: B (StevenBlack).**

**Por qué:**
- **Activo y mantenido** (commits semanales en GitHub).
- **Cobertura suficiente** (~82k entries para porn+gambling). Para una red comunitaria de un pueblo, esto cubre el 99%+ del tráfico problemático.
- **Gratis y open**: licencia MIT, no requiere registrarnos.
- **Categorización limpia**: tiene paths como `/alternates/porn-only/hosts` y `/alternates/gambling-only/hosts` que descargamos por separado y combinamos.
- **Formato fácil de parsear**: archivos de tipo hosts (`0.0.0.0 domain.com`), un `awk` extrae la columna 2.
- **Shallalist intentamos primero** — los servidores no responden (`Connection reset by peer`). Probablemente discontinuado.

**Tradeoffs:**
- Cobertura menor que comercial. Si aparecen sitios nuevos, hay que esperar a que StevenBlack los agregue (o añadirlos manualmente, ver [`06-BLOCKLISTS.md`](06-BLOCKLISTS.md)).
- No incluye categorías como "social media" o "video streaming". Para añadirlas, basta con sumar otra URL al array `squid_blocklist_sources` en `group_vars/all.yml`.

---

## Decisión 5 — Cómo cachear biblioteca.tel HTTPS

**Problema:** biblioteca.tel sirve HTTPS (cert autofirmado). ¿Cómo metemos Squid entre cliente y nginx para cachear, sin romper el TLS?

**Alternativas:**

| Opción | Cómo |
|---|---|
| **A. Squid en intercept HTTPS para biblioteca.tel** | DNAT también el tráfico a biblioteca.tel hacia Squid 3130, hacer `ssl_bump bump` solo para biblioteca.tel | Requiere bump (descifrar) — pero biblioteca.tel es nuestro y el cert es nuestro, así que técnicamente factible |
| **B. Squid como reverse proxy (accel) en :443** | Squid termina TLS de biblioteca.tel directamente. nginx se mueve a otro puerto y queda como backend interno | Limpio, sin descifrar tráfico ajeno, sin bump |
| **C. nginx con módulo de cache** | Usar `proxy_cache` de nginx en lugar de Squid | Ya hay nginx; pero el cache de nginx es más simple, sin políticas tan ricas como Squid (refresh_pattern, etc.) |
| **D. Squid sidecar** | Squid en otro puerto público (e.g., :8443), redirigir clients ahí. nginx sigue en :443 | Confuso para clientes, requiere advertirles |

**Elegimos: B (Squid accel reverse-proxy en :443).**

**Por qué:**
- **Limpio arquitectónicamente**: Squid es el front HTTPS, nginx el backend HTTP. Cada uno hace lo suyo.
- **Sin SSL bump**: como Squid es el destino real (no un MITM), termina TLS legítimamente. Los clientes ven el mismo cert de siempre (`biblioteca-segura.crt`).
- **Cache nativo de Squid**: aprovecha `cache_dir aufs`, `cache_mem`, `refresh_pattern`. Mejor que el cache de nginx para nuestro caso (offline-first, retención larga).
- **Reutiliza infra existente**: el `cache_dir 10240 16 256` (10 GB) ya estaba configurado y montado.

**Lo que requiere:** mover nginx de `:443` a `127.0.0.1:8443` (ver Decisión 7).

---

## Decisión 6 — Backend de Squid: HTTPS (localhost:443/8443) vs HTTP (localhost:80)

**Problema:** Squid termina TLS en :443. ¿Cómo le habla a nginx? ¿HTTP o HTTPS?

**Alternativas:**

| Opción | Squid → nginx |
|---|---|
| **A. HTTPS a 127.0.0.1:443** | Mantiene cifrado end-to-end aun en loopback |
| **B. HTTPS a 127.0.0.1:8443** | Igual, en otro puerto |
| **C. HTTP a 127.0.0.1:80** | Plano HTTP en loopback |

**Elegimos: C (HTTP en :80).**

**Por qué:**
- **Loopback no necesita cifrado**: el tráfico nunca sale de la RPi (ni siquiera del kernel — es localhost). No hay sniffing posible.
- **Menos overhead**: cero handshakes TLS para cada request al backend.
- **Sin problemas de cert**: cuando intentamos HTTPS backend (opción B), Squid daba `SQUID_TLS_ERR_ACCEPT` por incompatibilidades cipher/SNI. Resolverlo requería opciones avanzadas (`sslflags=DONT_VERIFY_PEER`, etc.) que estaban deprecadas.
- **nginx ya escucha en :80**: el listener HTTP existía para servir biblioteca.tel HTTP a clientes y no se tocó.

**Lo que mantuvimos:** nginx sigue con un listener HTTPS interno en `127.0.0.1:8443` (no usado en flujo normal) como red de seguridad para diagnóstico/testing.

---

## Decisión 7 — Qué hacer con el listener HTTPS de nginx

**Problema:** Squid quiere bindear `:443`. nginx ya tenía `listen 443 ssl default_server`. Conflicto.

**Alternativas:**

| Opción | nginx :443 |
|---|---|
| **A. Eliminar el bloque HTTPS de nginx** | Removido completamente. Si Squid se cae, biblioteca.tel HTTPS no funciona. |
| **B. Mover a 127.0.0.1:8443** | Solo loopback. nginx sigue capaz de servir HTTPS, pero solo internamente. |
| **C. Mover a otro puerto público (e.g., 8443 público)** | Permite acceso HTTPS sin Squid, pero confunde a clientes |

**Elegimos: B (127.0.0.1:8443).**

**Por qué:**
- **Resiliencia**: si Squid se cae, basta con cambiar `nginx_serve_https: true` en group_vars y re-deployar — vuelve nginx a :443 y biblioteca.tel sigue accesible. El rol nginx lo controla con un `{% if %}`.
- **Diagnóstico**: desde la RPi puedo `curl -k https://127.0.0.1:8443/` para verificar que nginx HTTPS sigue bien, sin tocar Squid.
- **Cero impacto**: nadie usa el listener internamente excepto para tests; pero está disponible.

**Operacionalmente:** cuando se hace deploy, el playbook nginx se aplica ANTES que el playbook squid. El handler `reload nginx` libera :443. Luego `reload squid` lo agarra. La ventana de "nadie en :443" es <1 segundo.

---

## Decisión 8 — DNAT cross-machine vs policy routing vs proxy adicional

**Problema:** El tráfico HTTPS de clientes VLAN30 debe llegar a Squid en la RPi (otra máquina). ¿Cómo lo enrutamos?

**Alternativas:**

| Opción | Mecanismo |
|---|---|
| **A. DNAT cross-machine en Mini PC** | nftables prerouting NAT: `DstIP=<internet> → DstIP=192.168.20.10:3130` |
| **B. Policy routing** | Mini PC enruta paquetes VLAN30:443 hacia la RPi como next-hop, sin DNAT. RPi hace DNAT local a Squid. |
| **C. Proxy intermediario en Mini PC** | Como hacemos con HTTP (nginx :8888) — un HAProxy o nginx stream que pase TCP a Squid |

**Elegimos: A (DNAT cross-machine en Mini PC).**

**Por qué:**
- **Simple**: una sola regla nftables en una sola máquina.
- **Probado**: ya hacíamos DNAT cross-machine para HTTP a Squid:3129 (vía nginx intermediario). El mismo patrón funciona para HTTPS:3130 (directo, sin nginx intermediario).
- **No tiene el problema de SO_ORIGINAL_DST que sí afecta a HTTP**: para HTTP intercept en Squid, `SO_ORIGINAL_DST` devolvía la IP de la RPi (porque el DNAT fue en Mini PC, no en RPi) → Squid detectaba loop → 403. Por eso para HTTP usamos un proxy nginx intermediario en Mini PC que arma una request con Host header (modo `accel vhost`). Para HTTPS no es un problema porque Squid en `https_port ssl-bump` puede usar el SNI del ClientHello para identificar destino, no `SO_ORIGINAL_DST`.

**Lo que requirió:** añadir 1 regla nftables al `roles/firewall/templates/nftables.conf.j2`.

```nft
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 443 \
    dnat to 192.168.20.10:3130
```

---

## Decisión 9 — Excluir la RPi del DNAT (`daddr != rpi_ip`)

**Problema:** Si la regla DNAT aplica a TODO el tráfico HTTPS de VLAN30, también afectaría a `https://biblioteca.tel` (que va a la RPi). Eso causaría que Squid:3130 intente "peek" un dominio que él mismo sirve.

**Solución:** excluir el destino RPi.

```nft
ip daddr != 192.168.20.10 tcp dport 443  ← solo HTTPS que NO va a la RPi
    dnat to 192.168.20.10:3130
```

**Por qué la excepción funciona:** el cliente, cuando pide `https://biblioteca.tel`, resuelve DNS → 192.168.20.10. Entonces el `daddr` del paquete ES 192.168.20.10. La regla no aplica. El paquete sigue su routing normal → llega a la RPi al puerto 443, donde está Squid en modo accel (no intercept). Squid termina TLS con el cert de biblioteca.tel y sirve desde cache_peer.

**Cuando un cliente pide `https://google.com`** → DNS resuelve a una IP de Google (algo como `142.250.x.x`). `daddr != 192.168.20.10` matchea. Se DNATtea a Squid:3130 (intercept). Squid peek+splice.

Es exactamente la misma lógica que ya existía para HTTP (`tcp dport 80 ... ip daddr != rpi_ip dnat to nginx:8888`).

---

## Decisión 10 — `always_direct` + `never_direct` para forzar el cache_peer

**Problema:** En la config existente había `always_direct allow all`. Esto le dice a Squid: "para cualquier request, conéctate directo al origen, no uses cache_peer". Pero queremos que biblioteca.tel SÍ pase por el cache_peer.

**Cómo lo resolvimos:**

```squid
# Excepción: biblioteca.tel NO va directo, va por cache_peer
always_direct deny biblioteca_dom
never_direct allow biblioteca_dom

# Resto sigue como antes (forward proxy directo a internet)
always_direct allow all
```

**Por qué este orden importa:**
- Squid evalúa `always_direct` en orden, el primer match gana.
- `always_direct deny biblioteca_dom` matchea biblioteca.tel y dice "NO sigas evaluando always_direct para esto". → biblioteca.tel no va directo.
- `never_direct allow biblioteca_dom` dice "para biblioteca.tel, OBLIGATORIO usar cache_peer".
- `always_direct allow all` matchea TODO LO DEMÁS → google.com, example.com, etc. van directo (forward proxy normal).

**Por qué declarar `biblioteca_dom` antes de las reglas:** Squid procesa el archivo de arriba a abajo y los ACL deben estar declarados antes de su primer uso en `http_access`/`always_direct`/etc. Por eso reordenamos el archivo (ver [`03-IMPLEMENTACION.md § sección squid.conf`](03-IMPLEMENTACION.md)).

---

## Decisión 11 — `cache deny !cache_allowed` para no cachear internet

**Problema:** El forward proxy HTTP (:3129) podría cachear respuestas de cualquier sitio de internet. Esto:
- Consume espacio en disco que queremos para biblioteca.tel.
- Riesgo de servir contenido obsoleto (e.g., un anuncio que ya cambió).
- Privacidad: el cache es un registro de qué se visitó.

**Solución:**

```squid
acl cache_allowed dstdomain biblioteca.tel
cache deny !cache_allowed
```

**Cómo funciona:** Squid ANTES de almacenar una respuesta evalúa la directiva `cache`. Si `!cache_allowed` matchea (es decir, NO es biblioteca.tel), entonces `deny` → no se cachea. El response se sirve al cliente pero no se almacena.

**Resultado en logs:** internet siempre marca `TCP_MISS/200` (porque cada request es un miss; nunca se almacena para servir como hit). biblioteca.tel marca `TCP_MISS/200` la primera vez y `TCP_HIT/200` o `TCP_MEM_HIT/200` las siguientes.

**Lo que esto NO hace:** no impide que Squid REENVÍE la request a internet. Solo impide que la guarde. El cliente sigue viendo el contenido.

---

## Decisión 12 — Script de actualización + cron vs `external_acl` de Squid

**Problema:** ¿Cómo mantenemos la blocklist actualizada?

**Alternativas:**

| Opción | Mecanismo |
|---|---|
| **A. Cron descarga la lista → archivo → `squid -k reconfigure`** | Archivo estático, refrescado periódicamente |
| **B. `external_acl_type` con un helper Python** | Squid consulta un proceso externo en cada request |
| **C. Lista en RAM compartida con Redis/etc.** | Más complejo, requiere otro servicio |

**Elegimos: A (script + cron).**

**Por qué:**
- **Performance**: una ACL `dstdomain` con archivo es O(log n) en Squid (búsqueda en árbol). Con 82k entries es ~17 comparaciones. Imperceptible.
- **Robustez**: si el script falla (URL caída, JSON parse error), la lista anterior queda intacta. Sanity-check: si la nueva lista tiene <1000 entries, el script aborta.
- **Operacionalmente simple**: un solo bash script de ~40 líneas, cron de Ansible, log en `/var/log/squid-blocklist.log`.
- **Audit-friendly**: el archivo `blocked_domains.txt` puede leerse con `grep`, contarse con `wc`, versionarse, etc.

**Helper externos** (opción B) son útiles para listas masivas o dinámicas (e.g., consultar APIs). Innecesario para nuestro caso.

**Schedule del cron:** domingos 03:30. Razón: bajo tráfico, sin clientes activos, ventana de mantenimiento natural. Si el reconfigure falla, hay 6 días para detectarlo antes del siguiente intento.

---

## Decisión 13 — `connect_timeout 15 seconds`

**Problema:** Por defecto Squid tiene `connect_timeout 60s`. Si la WAN se cae, cada request HTTP se cuelga por un minuto antes de fallar. Mala UX.

**Solución:** bajar a 15 segundos.

**Por qué 15:**
- 60s era demasiado para clientes humanos.
- <10s causaba falsos timeouts en conexiones internacionales lentas (e.g., servidores asiáticos).
- 15s es el equilibrio: si en 15s no se conecta, asumimos WAN caído.

**Interacción con offline.html:** el nginx intermediario en Mini PC (`http-proxy-offline.nginx.j2`) intercepta el `503/504` que devuelve Squid cuando falla la conexión, y sirve una página `offline.html` al cliente. Con 15s en lugar de 60s, esa página aparece mucho más rápido.

**Esta config ya existía antes** — no la cambiamos en esta iteración. Se mantiene en la nueva config.

---

## Decisión 14 — Mantener el CA bump local (no instalarlo en clientes)

**Problema:** Squid en `https_port ssl-bump` requiere un certificado de CA (aunque solo hagamos peek+splice y no descifremos). ¿Lo distribuimos a los clientes?

**Decisión: NO distribuir.**

**Por qué:**
- Peek+splice **nunca genera ni presenta certificados a clientes**. La CA bump solo existe porque Squid syntactically la requiere para inicializar el listener `ssl-bump`. No se usa en runtime.
- Si en el futuro decidimos hacer bump completo (e.g., para inspeccionar URLs dentro de HTTPS), entonces sí habría que distribuirla. Hoy no.
- Distribuir CAs en una red comunitaria es operativamente caro: cada Android, cada iOS, cada laptop debe importarla; navegadores como Firefox tienen su propio almacén; apps con cert pinning (banca) no la respetan. No vale la pena el esfuerzo cuando peek+splice cubre el caso.

**Permisos:** la CA queda en `/etc/squid/ssl/bump-ca.{crt,key}` con dueño `proxy:proxy` y modo `0600` para la key. Squid la lee al arrancar. Nadie más debe leerla.

---

## Decisión 15 — `dstdomain biblioteca.tel` (exacto) vs `.biblioteca.tel` (con subdominios)

**Problema:** Squid soporta dos sintaxis para `dstdomain`:
- `biblioteca.tel` → matchea solo el dominio exacto.
- `.biblioteca.tel` → matchea biblioteca.tel **y** *.biblioteca.tel.

Intentamos usar ambas en la misma ACL:
```
acl biblioteca_dom dstdomain biblioteca.tel .biblioteca.tel
```

Squid rechazó: `ERROR: '.biblioteca.tel' is a subdomain of 'biblioteca.tel'. You need to remove '.biblioteca.tel'`.

**Por qué:** Squid 6 detecta redundancia (porque `.biblioteca.tel` ya incluye `biblioteca.tel`) y aborta para forzar al admin a elegir.

**Decisión:** usar solo `biblioteca.tel` (exacto).

**Por qué exacto y no subdominios:**
- Actualmente no servimos subdominios (`wikipedia.biblioteca.tel`, `kolibri.biblioteca.tel` no existen como hosts independientes — son paths `/wikipedia/`, `/kolibri/`).
- Si en el futuro decidimos servir subdominios, cambiar a `.biblioteca.tel` es una línea.
- Match exacto evita falsos positivos (un futuro `extra.biblioteca.tel.evil.com` no se confunde).

---

## Decisión 16 — Por qué la docs viven en `DOCS/raspberry/squid-filter-cache/`

**Problema:** ¿Un solo doc grande o varios pequeños?

**Decisión:** varios pequeños en una subcarpeta.

**Por qué:**
- Cada doc tiene un propósito claro (arquitectura, decisiones, testing, etc.).
- El usuario puede ir directo al que necesita.
- Los markdowns largos (5000+ líneas) son intimidantes y desactualizables.
- La subcarpeta no contamina `DOCS/raspberry/` (donde viven docs de servicios individuales).

Los docs preexistentes (`SQUID.md`, `SQUID-FILTERING-CACHE.md`) ahora apuntan aquí como índice canónico.
