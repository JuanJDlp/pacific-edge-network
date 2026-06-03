# 05 · DNSSEC: teoría completa e implementación en este proyecto

> El archivo más denso. DNSSEC tiene fama de difícil porque mezcla criptografía,
> jerarquía y mucha sigla. Lo desmontamos pieza por pieza y luego vemos exactamente cómo
> el Mini PC firma `biblioteca.tel`. Tómate tu tiempo; léelo dos veces.

---

## 5.1 ¿Qué problema resuelve DNSSEC? (y qué NO resuelve)

El DNS clásico **no tiene forma de probar que una respuesta es legítima**. Un atacante
en el camino (o que envenene un caché) puede responder `banco.com → IP-del-atacante` y tu
resolver se lo cree. Ataques: *cache poisoning* (Kaminsky), *spoofing*, *MITM*.

**DNSSEC (DNS Security Extensions)** añade **firmas criptográficas a los datos del DNS**,
de modo que un resolver pueda **verificar** que una respuesta:
- viene realmente del dueño de la zona (**autenticidad**), y
- no fue alterada en el camino (**integridad**).

Lo que DNSSEC **NO** hace:
- **No cifra** nada. Las respuestas siguen viajando en claro; cualquiera puede *leer* qué
  resolviste (para confidencialidad existen DoT/DoH, otra cosa).
- No protege la "última milla" entre tu resolver y tu laptop por sí solo (eso depende de
  que confíes en tu resolver / canal).
- No evita que un dominio malicioso *exista*; solo prueba que los datos son auténticos.

Mentalidad correcta: **DNSSEC = sellos de autenticidad sobre los datos, verificables por
una cadena de confianza.**

---

## 5.2 Las claves: KSK y ZSK

DNSSEC usa criptografía **asimétrica** (par de claves pública/privada). Cada zona tiene
típicamente **dos** pares de claves, con división de roles:

- **ZSK (Zone Signing Key):** firma los **registros de datos** de la zona (los A, AAAA,
  CNAME, etc.). Se usa mucho → se rota seguido → suele ser más corta (rendimiento).
- **KSK (Key Signing Key):** firma **solo el conjunto de DNSKEY** (es decir, firma a las
  claves). Es la "llave maestra". Se usa poco → se rota rara vez → suele ser más larga.

¿Por qué dos y no una? Para poder **rotar la ZSK sin avisar al padre**. El "ancla de
confianza" que el mundo exterior conoce es la KSK (vía el registro DS, §5.4); si rotas
solo la ZSK, el DS no cambia y nadie fuera tiene que actualizar nada. La KSK firma las
ZSK, así que basta confiar en la KSK para confiar en las ZSK que ella avala.

Las claves se publican en la zona como registros **DNSKEY**:
- DNSKEY con flag **256** = ZSK.
- DNSKEY con flag **257** = KSK (SEP, Secure Entry Point).

▶ En este proyecto, `dnssec.yml` extrae justamente la **DNSKEY 257 (la KSK)** para
anclarla localmente (§5.7). Recuerda ese 257.

---

## 5.3 Las firmas: RRSIG, y la prueba de no-existencia: NSEC/NSEC3

- **RRSIG (Resource Record SIGnature):** por cada **RRset** (recordá: todos los registros
  con el mismo nombre+tipo), DNSSEC añade un RRSIG = la **firma** de ese RRset. Cuando
  pides `biblioteca.tel A`, recibes el A **y** su RRSIG. El validador comprueba la firma
  con la DNSKEY (ZSK) correspondiente.
  - El RRSIG tiene **fecha de expiración**: por eso la zona hay que **re-firmarla
    periódicamente** (BIND lo hace solo aquí — y por eso el `also-notify` al slave, §4).

- **¿Cómo se prueba que algo NO existe, sin firmar "no existe" sobre la marcha?** No
  puedes firmar al vuelo (la clave privada no está en el servidor que responde, idealmente)
  y firmar cada posible "no existe" es infinito. Solución: **NSEC / NSEC3**.
  - **NSEC:** encadena los nombres existentes en orden. "Entre `aula.biblioteca.tel` y
    `ns1.biblioteca.tel` no hay nada" → prueba firmada de que `claustro.biblioteca.tel`
    no existe. Problema: permite **enumerar** toda la zona (zone walking).
  - **NSEC3:** igual pero sobre **hashes** de los nombres, para dificultar la
    enumeración.

▶ La `dnssec-policy default` de BIND 9.18 usa **NSEC** por defecto (simple). Para una
zona local pequeña y privada como `biblioteca.tel`, la enumeración no es una preocupación
real. Si quisieras NSEC3, definirías una política propia (§5.9).

---

## 5.4 La cadena de confianza y el registro DS (la idea central)

DNSSEC no pide que confíes en cada zona por separado: construye una **cadena de confianza
desde la raíz hacia abajo**, igual que la jerarquía de nombres.

```
  Raíz (.)  ── tiene una KSK famosa (el "trust anchor" que todos los validadores conocen)
     │  publica un DS de .tel (hash de la KSK de .tel)  → "confío en .tel"
   .tel
     │  publica un DS de ejemplo.tel (hash de la KSK de ejemplo.tel) → "confío en ejemplo.tel"
  ejemplo.tel
     │  su KSK firma sus DNSKEY; sus ZSK firman sus datos (A, AAAA...)
   datos
```

La pieza que enlaza padre e hijo es el **DS (Delegation Signer)**: es un **hash de la KSK
de la zona hija**, publicado **en la zona padre** y firmado por el padre. Así:

> "Confío en la raíz (la tengo anclada de fábrica). La raíz me da un DS firmado de `.tel`
> → confío en la KSK de `.tel`. `.tel` me da un DS firmado de `ejemplo.tel` → confío en
> su KSK. Su KSK firma sus DNSKEY, sus ZSK firman sus datos → **confío en los datos**."

Eso es **validación**: seguir la cadena de DS+firmas desde un **trust anchor** conocido
(la raíz) hasta el dato. Si toda la cadena valida, el resolver marca el bit **AD**
(Authenticated Data) en la respuesta.

---

## 5.5 El problema especial de este proyecto: `biblioteca.tel` NO cuelga de la raíz

Aquí está **el porqué** de toda la peculiaridad DNSSEC del proyecto, y lo más importante
que debes saber explicar:

`biblioteca.tel` es un **TLD local inventado**. La raíz real de internet **no delega**
`biblioteca.tel` a nuestro Mini PC, así que **nadie publica un DS** de nuestra zona en
ningún padre. La cadena de confianza normal (`. → tel → biblioteca.tel`) **no existe**
para nosotros.

Entonces, ¿cómo logramos que el resolver valide nuestra zona firmada y marque `AD`?
**Anclando nuestra propia KSK como trust anchor local.** En vez de heredar la confianza
de un padre vía DS, le decimos directamente a *nuestro* resolver:

> "La KSK de `biblioteca.tel` es ESTA. Confía en ella como punto de partida."

Eso es exactamente lo que hace el archivo `/etc/bind/named.conf.trust-anchors`
(generado por `dnssec.yml`). Es un trust anchor **adicional** a la raíz: el resolver
confía en la raíz (de fábrica) para todo internet, y en *nuestra* KSK para
`biblioteca.tel`.

> Analogía: la cadena normal es como un pasaporte validado por tu país y reconocido por
> tratados internacionales. Como `biblioteca.tel` es un "micro-país" que nadie reconoce,
> nosotros mismos pegamos su sello en la lista de "documentos en los que confío" de
> nuestro propio control fronterizo (el resolver).

---

## 5.6 Cómo se firma la zona aquí: `dnssec-policy` + `inline-signing`

En `named.conf.local`, la zona directa tiene:

```bind
zone "biblioteca.tel" {
    type master;
    file "/var/lib/bind/db.biblioteca.tel";   // FUENTE, sin firmar
    dnssec-policy default;                     // ← firma automática
    inline-signing yes;                        // ← mantiene la versión firmada aparte
    key-directory "/var/lib/bind/keys";        // ← dónde guardar/leer las claves
};
```

Qué significa cada cosa (BIND 9.16+/9.18, el modelo moderno):

- **`dnssec-policy default`**: activa el firmado **totalmente automático** con una
  política predefinida ("default"). BIND se encarga de:
  - generar la KSK y la ZSK la primera vez (en `key-directory`),
  - firmar todos los RRsets (crear los RRSIG),
  - generar NSEC,
  - **re-firmar** antes de que expiren las firmas,
  - **rotar las claves** según el calendario de la política,
  todo sin intervención humana. Antes de 9.16 esto se hacía a mano con `dnssec-keygen` +
  `dnssec-signzone` + cron; `dnssec-policy` lo reemplaza y es lo recomendado hoy.

- **`inline-signing yes`**: BIND mantiene **dos versiones** de la zona:
  - la **fuente** que tú editas (`db.biblioteca.tel`, sin firmas), y
  - la **firmada** que sirve a los clientes (`db.biblioteca.tel.signed`), generada
    automáticamente.
  Tú editas la fuente "normal" (sin pensar en firmas); BIND produce la firmada. Sin
  inline-signing tendrías que editar y re-firmar manualmente la zona ya firmada, que es
  doloroso y propenso a errores.

- **`key-directory "/var/lib/bind/keys"`**: dónde viven las claves. Está en `/var/lib`
  (no `/etc`) por **AppArmor**: named necesita **escribir** ahí (generar/rotar claves).
  Misma razón por la que la zona fuente está en `/var/lib/bind` (ver `02` §2.5).

Y en `named.conf.options`:
```bind
dnssec-validation auto;
```
Esto hace que **este mismo resolver valide** DNSSEC: tanto las respuestas externas (que
los forwarders Google/Cloudflare entregan con sus RRSIG) como nuestra zona local (vía el
trust anchor). `auto` = usa el trust anchor de la raíz que trae BIND + los que añadamos.

---

## 5.7 Lo que hace `tasks/dnssec.yml`, paso a paso (el truco del trust anchor)

Firmar la zona es automático, pero **anclar nuestra propia KSK** no — eso lo orquesta
Ansible. Lectura del rol:

1. **`meta: flush_handlers`** — fuerza el reload pendiente de BIND para que **empiece a
   firmar** la zona (los handlers acumulados de los `notify: reload bind9`).
2. **`rndc reconfig`** — relee la configuración (asegura que la `dnssec-policy` está
   activa).
3. **Espera a `secure: yes`** — repite `rndc zonestatus biblioteca.tel` hasta 30 veces
   (cada 2 s) hasta ver `secure: yes`, que significa "la zona ya está firmada". Firmar
   toma un instante; este `until` evita seguir antes de tiempo.
4. **Extrae la KSK (DNSKEY flag 257)** de la zona ya firmada:
   ```bash
   dig +short @127.0.0.1 biblioteca.tel DNSKEY | awk '$1==257 {...}'
   ```
   Filtra por `257` = la **KSK** (no la ZSK 256), porque la KSK es el punto de anclaje.
5. **Verifica** que sí obtuvo una KSK (si no, falla con un mensaje claro: "la zona no
   quedó firmada").
6. **Publica el trust anchor** escribiendo `/etc/bind/named.conf.trust-anchors`:
   ```bind
   trust-anchors {
       "biblioteca.tel." static-key 257 3 8 "AwEAA...la-clave-publica...";
   };
   ```
   - `static-key` = un ancla fija (no gestionada por RFC 5011 rollover).
   - `257 3 8` = flags (KSK) · protocolo (3, siempre) · algoritmo (8 = RSA/SHA-256).
   - la cadena grande = la **clave pública** de la KSK.
7. **`reload bind9`** — recarga para que el resolver use el nuevo trust anchor y empiece a
   marcar `AD` en las respuestas de `biblioteca.tel`.

Resultado: la zona está firmada **y** nuestro propio resolver la valida como auténtica,
pese a no colgar de la raíz.

> El archivo `named.conf.trust-anchors` se incluye **al principio** de
> `named.conf.options` (ver `02` §2.3). Por eso el rol primero crea un **placeholder
> vacío** (para que el include no falle antes de firmar) y luego lo **sobrescribe** con la
> KSK real.

---

## 5.8 Por qué SOLO se firma la zona directa (y no las inversas)

En `named.conf.local`, solo `biblioteca.tel` tiene `dnssec-policy`/`inline-signing`; las
zonas inversas (`*.in-addr.arpa`) **no**. Decisión deliberada:

- El valor de DNSSEC aquí es **didáctico/demostrativo** y proteger la resolución directa
  de los nombres de servicios. Las inversas (PTR) son de bajo riesgo y su falsificación
  no compromete el acceso a la biblioteca.
- Firmar también las inversas multiplicaría claves, firmas y trust anchors sin beneficio
  proporcional para una red comunitaria cerrada.

Es un balance consciente: firmar lo que importa, mantener el resto simple. Si quisieras
firmarlas, les agregarías las mismas tres directivas y las moverías a `/var/lib/bind`
(por AppArmor) y publicarías sus KSK como trust anchors adicionales.

---

## 5.9 Editar una zona firmada (cómo NO romper DNSSEC)

Como hay `inline-signing`, **tú editas la FUENTE** (`/var/lib/bind/db.biblioteca.tel`),
nunca el `.signed`. Pero hay matices:

- **Vía Ansible (recomendado):** editás `dns_hosts`/`dns_aliases`, redesplegás. El rol
  regenera la fuente con un serial nuevo (epoch), BIND re-firma solo. Cero fricción. Es
  **el camino correcto** para una zona firmada.
- **A mano en el equipo (urgencias):** editás la fuente, subís el serial, y luego:
  ```bash
  sudo rndc reload biblioteca.tel        # BIND re-lee la fuente y re-firma
  sudo rndc zonestatus biblioteca.tel    # verifica secure: yes y el serial nuevo
  ```
  No edites el `.signed` ni el `.jnl` jamás. Si el serial no sube, ni el firmado ni el
  slave reflejarán el cambio.

### Cambiar la política / forzar re-firmado / rotar claves
```bash
# Ver estado DNSSEC de la zona (claves, próximos eventos de rotación)
sudo rndc dnssec -status biblioteca.tel

# Forzar mantenimiento DNSSEC ahora
sudo rndc dnssec -checkds ...            # (gestión de DS, no aplica sin padre)
sudo rndc loadkeys biblioteca.tel        # carga claves nuevas si las agregaste
sudo rndc signing -list biblioteca.tel   # estado de firmado
```
Si rotas la **KSK** (manual o por política), cambia la DNSKEY 257 → **hay que regenerar
el trust anchor** (`/etc/bind/named.conf.trust-anchors`). Como `dnssec.yml` lo extrae
automáticamente, **volver a correr el rol DNS** re-publica el trust anchor correcto. Esa
es otra razón para preferir el flujo Ansible: mantiene el ancla sincronizada con la KSK.

> ⚠️ Trampa: si rotas la KSK pero el trust anchor viejo sigue en `named.conf.trust-anchors`,
> tu resolver dejará de validar `biblioteca.tel` (SERVFAIL al validar). Re-corre el rol
> para re-extraer la KSK actual.

---

## 5.10 Verificar DNSSEC (lo que enseñas en una sustentación)

```bash
# 1) ¿La zona está firmada?
sudo rndc zonestatus biblioteca.tel | grep -i secure       # → secure: yes

# 2) ¿Existen las claves?
ls -l /var/lib/bind/keys/                                    # Kbiblioteca.tel.+008+*.key/.private

# 3) Ver la DNSKEY (256=ZSK, 257=KSK) y los RRSIG
dig @127.0.0.1 biblioteca.tel DNSKEY +multiline
dig @127.0.0.1 biblioteca.tel A +dnssec       # debe traer el A y su RRSIG

# 4) ¿El resolver VALIDA? — el bit "ad" en los flags
dig @192.168.10.1 biblioteca.tel +dnssec
# busca en la cabecera:  ;; flags: qr aa rd ra ad   ← "ad" = Authenticated Data ✔

# 5) Validación explícita con delv (te dice "fully validated")
delv @127.0.0.1 biblioteca.tel A
# → "; fully validated"  con los RRSIG listados

# 6) Demostrar que una firma rota se detecta:
#    (no lo hagas en producción) si manipulas el .signed, el validador da SERVFAIL.
```

Lectura clave: **el bit `ad`** en la respuesta de `dig +dnssec`. Si está, tu cadena de
confianza local funciona. Si pides con `+cd` (checking disabled) desaparece la
validación — útil para distinguir "el dato está mal" de "la validación falla".

Errores típicos:
- **SERVFAIL al pedir `biblioteca.tel`** y desaparece con `+cd` → problema de validación
  DNSSEC (trust anchor desincronizado con la KSK, o firmas expiradas). Re-corre el rol.
- **No aparece `ad`** → `dnssec-validation` no está en `auto`, o el trust anchor está
  vacío/incorrecto.

---

## 5.11 El algoritmo y el "default policy" en concreto

- BIND 9.18 `policy default` usa hoy **algoritmo 13 (ECDSA P-256/SHA-256)** en versiones
  recientes, o **8 (RSASHA256)** según versión/empaquetado. El `dnssec.yml` no asume cuál:
  extrae lo que haya (`flags proto alg key`) de la DNSKEY real, así que el trust anchor
  siempre cuadra con la KSK efectiva. **No hardcodees el algoritmo**; deja que el rol lo
  lea de la zona.
- Las firmas RRSIG de la política default expiran en semanas; BIND re-firma con
  antelación automáticamente. No hay cron de firmado que mantener (a diferencia del
  método antiguo `dnssec-signzone`).

---

## Resumen de este archivo

- DNSSEC firma **los datos** del DNS para probar **autenticidad e integridad** (no
  cifra). El resolver valida siguiendo una **cadena de confianza** y marca el bit **AD**.
- Claves: **KSK** (firma las DNSKEY, ancla de confianza, flag 257) y **ZSK** (firma los
  datos, flag 256). Firmas = **RRSIG**; no-existencia = **NSEC**.
- La confianza fluye por **DS** del padre al hijo desde la raíz. Como `biblioteca.tel`
  **no cuelga de la raíz**, aquí se **ancla la KSK localmente** en
  `named.conf.trust-anchors`.
- Implementación: `dnssec-policy default` + `inline-signing yes` + `key-directory` en
  `/var/lib/bind/keys` (AppArmor) → firmado y rotación automáticos. `dnssec.yml` espera
  `secure: yes`, extrae la KSK (257) y publica el trust anchor; `dnssec-validation auto`
  hace que el propio resolver valide.
- Solo se firma la zona directa (decisión de balance). Editá siempre la **fuente** (vía
  Ansible idealmente); si rotas la KSK, re-corre el rol para re-anclar el trust anchor.
- Verificá con `rndc zonestatus`, `dig +dnssec` (mirá el `ad`) y `delv`.

Sigue con [`06-rpz-politicas.md`](06-rpz-politicas.md).
