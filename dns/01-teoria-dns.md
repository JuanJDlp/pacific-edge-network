# 01 · Teoría de DNS desde cero

> Antes de tocar BIND, necesitas un modelo mental sólido del protocolo. Este archivo
> es teoría pura, pero con anclas (▶) a cómo aparece en *este* proyecto, para que no
> sea abstracto.

---

## 1.1 ¿Qué problema resuelve DNS?

Las máquinas se hablan por **direcciones IP** (`192.168.20.10`, `8.8.8.8`). Los
humanos recordamos **nombres** (`biblioteca.tel`, `google.com`). DNS (Domain Name
System) es la **guía telefónica distribuida** que traduce nombres ↔ IPs (y algo más).

"Distribuida" es la palabra clave: no hay un único servidor con todos los nombres del
mundo. El espacio de nombres está **particionado en zonas**, y cada zona la administra
quien corresponde. Tu navegador no sabe dónde está `google.com`, pero sabe *a quién
preguntar para averiguarlo*.

▶ En este proyecto inventamos un dominio que **no existe en internet**: `biblioteca.tel`.
Funciona solo dentro de la red porque *nuestro* servidor (el Mini PC) se declara
autoritativo de esa zona y los clientes preguntan a ese servidor.

---

## 1.2 El árbol de nombres y la jerarquía

Los nombres DNS se leen **de derecha a izquierda**, del más general al más específico:

```
                          . (raíz, "root")
                          │
        ┌─────────────┬───┴────┬──────────────┐
       com           org      tel            ...        ← TLDs (Top-Level Domains)
        │                       │
     google                 biblioteca                  ← dominios de 2º nivel
        │                       │
      www                   wikipedia                    ← subdominios / hosts
```

- `www.google.com.` → el punto final (a veces implícito) es **la raíz**.
- Cada nivel es una **etiqueta** (label), máximo 63 bytes; el nombre completo (FQDN),
  máximo 255 bytes.
- **FQDN (Fully Qualified Domain Name):** nombre absoluto con el punto final implícito,
  p. ej. `biblioteca.tel.`. Si NO termina en punto dentro de un archivo de zona, BIND
  le pega el nombre de la zona (`$ORIGIN`). Esta regla causa el 90% de los errores de
  novato en archivos de zona (ver `03`).

▶ `tel` es un TLD real en internet, pero **nosotros no lo usamos contra la raíz**:
nuestro BIND responde `biblioteca.tel` localmente y nunca delega hacia arriba. Es un
"squat" intencional de un TLD para una red cerrada.

---

## 1.3 Zonas vs dominios (no son lo mismo)

- **Dominio:** un subárbol completo de nombres (`biblioteca.tel` y *todo* lo que cuelga).
- **Zona:** la porción de ese subárbol que un servidor administra **directamente**, sin
  delegar. Si `biblioteca.tel` delegara `aula.biblioteca.tel` a otro servidor, esa parte
  sería *otra* zona.

▶ Aquí no hay delegaciones internas: una sola zona `biblioteca.tel` cubre todo el
dominio. Además tenemos zonas **inversas** independientes (una por VLAN) para los PTR.

---

## 1.4 Tipos de servidor DNS (la distinción más importante)

Hay dos roles que la gente confunde todo el tiempo. Un mismo BIND puede hacer ambos.

### a) Servidor **autoritativo**
*Tiene* los datos de una o más zonas (en archivos de zona) y responde con la bandera
`aa` (authoritative answer). No "busca" nada: o sabe la respuesta porque está en su
zona, o responde `NXDOMAIN` (no existe) / referral.

### b) Servidor **recursivo** (resolver)
No es dueño de los datos; **busca por ti**. Recibe "¿cuál es la IP de X?", y si no la
tiene cacheada, va preguntando (a la raíz, al TLD, al autoritativo del dominio) hasta
conseguir la respuesta, te la entrega y la **cachea**.

▶ El BIND del Mini PC es **las dos cosas a la vez**:
- *Autoritativo* de `biblioteca.tel` y de las inversas.
- *Recursivo* para todo lo demás (`google.com`...), pero en vez de empezar desde la
  raíz, **reenvía** (forwarding) a `8.8.8.8 / 8.8.4.4 / 1.1.1.1` (`forward only`).

Mezclar autoritativo + recursivo en el mismo servidor está bien para una red interna,
pero en internet público se separan (un recursivo abierto es un riesgo de amplificación
DDoS; por eso aquí `allow-recursion` está limitado a las redes internas — ver `02`).

---

## 1.5 Resolución recursiva vs iterativa (el viaje de una query)

Cuando tu laptop quiere `www.ejemplo.com` y no lo tiene cacheado:

```
Tu laptop ──(recursiva: "dame la respuesta final")──▶ Resolver (Mini PC)
                                                         │
   El resolver hace consultas ITERATIVAS:                │
   1. ──▶ Raíz (.)        "¿quién maneja .com?"  ◀── "pregunta a los NS de com"
   2. ──▶ TLD (.com)      "¿quién maneja ejemplo.com?" ◀── "pregunta al NS de ejemplo.com"
   3. ──▶ Autoritativo    "¿IP de www.ejemplo.com?"    ◀── "93.184.x.x" (aa=1)
                                                         │
Tu laptop ◀──────────── "93.184.x.x" ────────────────────┘
```

- **Recursiva:** "resuélvelo tú y dame el resultado final" (cliente → resolver).
- **Iterativa:** "dime lo que sepas o a quién preguntar" (resolver → servidores de la jerarquía).

▶ En este proyecto el paso "iterativo desde la raíz" **no ocurre**: el Mini PC usa
`forward only`, así que delega la recursión completa a Google/Cloudflare. Ventaja:
más simple y rápido en un enlace lento. Desventaja: dependes de esos forwarders (y de
que el WAN esté arriba — de ahí el modo RPZ offline, ver `06`).

---

## 1.6 Registros de recurso (RR) — el contenido de una zona

Una zona es un conjunto de **registros de recurso**. Cada uno: `NOMBRE  TTL  CLASE  TIPO  DATOS`.
La clase casi siempre es `IN` (Internet). Los tipos que importan aquí:

| Tipo | Para qué | Ejemplo en este proyecto |
|------|----------|--------------------------|
| **A** | nombre → IPv4 | `biblioteca.tel. → 192.168.20.10` |
| **AAAA** | nombre → IPv6 | `biblioteca.tel. → fd00:0:0:20::10` |
| **CNAME** | alias → otro nombre | `wikipedia → biblioteca` |
| **NS** | quién es autoritativo de la zona | `biblioteca.tel. NS ns1.biblioteca.tel.` |
| **SOA** | metadatos de la zona (serial, timers) | uno por zona, ver §1.8 |
| **PTR** | IP → nombre (inverso) | `10.20.168.192.in-addr.arpa → biblioteca.tel.` |
| **MX** | servidor de correo | (no se usa aquí) |
| **TXT** | texto arbitrario | (no se usa aquí) |
| **DNSKEY** | clave pública DNSSEC de la zona | generado por BIND (ver `05`) |
| **RRSIG** | firma DNSSEC de un conjunto de registros | generado por BIND |
| **DS** | hash de la DNSKEY hija (delega confianza) | no aplica (TLD local) |
| **NSEC/NSEC3** | prueba de "no existe" firmada | generado por BIND |

### Sobre CNAME (regla que confunde)
Un CNAME dice "este nombre es en realidad otro nombre; vuelve a resolver". Reglas:
- Un nombre con CNAME **no puede tener otros registros** (ni A, ni nada). Por eso el
  *apex* de la zona (`biblioteca.tel` "pelado") **no puede ser CNAME** — debe ser A/AAAA.
- ▶ Aquí `wikipedia.biblioteca.tel` es CNAME → `biblioteca.biblioteca.tel`, que sí es A
  → `192.168.20.10`. El navegador resuelve el alias, llega a la RPi, y nginx decide a
  qué servicio enrutar según el `Host:` header.

### RRset
Todos los registros con el mismo nombre+tipo forman un **RRset** (p. ej. los dos NS, o
las dos IPs de un balanceo). DNSSEC firma **RRsets completos**, no registros sueltos —
detalle clave en `05`.

---

## 1.7 TTL y caché (por qué a veces "no toma" un cambio)

Cada respuesta lleva un **TTL** (Time To Live) en segundos. Cualquier resolver que la
reciba puede **cachearla** ese tiempo y servir esa copia sin volver a preguntar. Cuando
el TTL expira, vuelve a consultar al autoritativo.

Consecuencia práctica: si cambias un registro pero su TTL era 3600, los clientes que ya
lo cachearon seguirán viendo el valor viejo **hasta una hora**.

▶ En este proyecto el `$TTL` por defecto de la zona directa es **3600 s (1 h)**. Si vas
a cambiar una IP de un host pronto, una buena práctica es **bajar el TTL** unas horas
antes del cambio (a 60 s), hacer el cambio, y luego subirlo de nuevo. Las zonas RPZ usan
TTL muy bajo (5–60 s) a propósito, porque deben reaccionar rápido (ver `06`).

**TTL negativo:** el último campo del SOA (aquí `300`) es cuánto se cachea un `NXDOMAIN`
(la respuesta "no existe"). Si pides un nombre inexistente, ese "no existe" también se
cachea.

---

## 1.8 El registro SOA, campo por campo

Toda zona empieza con **un** registro SOA (Start Of Authority). Es el "acta de
nacimiento" de la zona y controla la relación master↔slave. Ejemplo real (zona directa):

```dns
@   IN  SOA  ns1.biblioteca.tel.  admin.biblioteca.tel. (
            1748600000  ; Serial   (aquí: epoch — segundos desde 1970)
            3600        ; Refresh  cada cuánto el slave revisa si hay cambios
            900         ; Retry    si el refresh falla, reintenta cada esto
            604800      ; Expire   si el slave no logra contactar tanto tiempo, descarta la zona
            300 )       ; Negative TTL  cuánto cachear un "no existe"
```

- `ns1.biblioteca.tel.` → el **MNAME**: nombre del master primario de la zona.
- `admin.biblioteca.tel.` → el **RNAME**: email del responsable, con el primer punto
  haciendo de `@` (es decir, `admin@biblioteca.tel`). Sí, el email se escribe raro.
- **Serial:** el número de versión de la zona. **El slave compara su serial con el del
  master; si el del master es mayor, transfiere.** Si no incrementas el serial al editar,
  el slave NUNCA se entera del cambio. → este es *el* error clásico de DNS.
- **Refresh/Retry/Expire:** timers del slave (ver §1.9 y `04`).

▶ Aquí el serial se genera con `{{ ansible_date_time.epoch }}` (timestamp Unix del
momento en que Ansible despliega la zona). Ventaja: **cada despliegue produce un serial
mayor automáticamente**, así nunca te olvidas de incrementarlo. Desventaja: si editas la
zona a mano en el equipo sin pasar por Ansible, tienes que incrementar el serial tú
mismo o el slave no actualizará (ver `03` y `07`).

---

## 1.9 Master / Slave y transferencia de zona (vistazo)

El detalle completo está en `04`, pero el modelo mental:

1. Editas la zona en el **master** y subes el serial.
2. El master, si tiene `notify yes`, manda un **NOTIFY** al slave: "oye, cambié".
3. El slave consulta el **SOA** del master y compara seriales.
4. Si el del master es mayor, el slave pide una **transferencia de zona**:
   - **AXFR** = copia completa.
   - **IXFR** = solo los cambios (incremental), más eficiente.
5. El slave guarda la copia y empieza a responder con ella.
6. Aunque no haya NOTIFY, el slave revisa solo cada `Refresh` segundos.

▶ Aquí la transferencia va **autenticada con TSIG** y el master además hace
`also-notify` explícito hacia la RPi (porque al firmar con DNSSEC la zona cambia sola y
hay que avisar al slave). Todo esto en `04`.

---

## 1.10 Consultas inversas (PTR) y `in-addr.arpa`

La búsqueda **directa** es nombre → IP. La **inversa** es IP → nombre, y se hace con un
truco: la IP se escribe **al revés** bajo el pseudo-dominio `in-addr.arpa`.

`192.168.20.10` → se consulta `10.20.168.192.in-addr.arpa` tipo **PTR**.

¿Por qué al revés? Porque DNS es jerárquico de derecha (general) a izquierda
(específico), y en una IP lo "general" es el primer octeto. Invirtiéndola, la jerarquía
de la IP encaja con la del árbol DNS.

▶ Aquí hay tres zonas inversas, una por VLAN:
- `10.168.192.in-addr.arpa` → VLAN 10 (`192.168.10.0/24`)
- `20.168.192.in-addr.arpa` → VLAN 20 (`192.168.20.0/24`)
- `30.168.192.in-addr.arpa` → VLAN 30 (`192.168.30.0/24`)

Nota: el nombre de la zona lleva solo **tres** octetos invertidos porque son redes `/24`
(el cuarto octeto es el host, que va como el *nombre* del registro PTR). IPv6 usa
`ip6.arpa` (nibble a nibble); aquí no publicamos PTR IPv6.

---

## 1.11 Transporte: UDP/TCP puerto 53 (y por qué importa TCP)

- DNS usa el **puerto 53**, históricamente **UDP** (rápido, sin conexión).
- Si la respuesta no cabe (>512 bytes en DNS clásico, o el límite EDNS negociado), el
  servidor marca el bit **TC (truncated)** y el cliente reintenta por **TCP**.
- **Las transferencias de zona (AXFR/IXFR) van SIEMPRE por TCP** (pueden ser enormes).
- DNSSEC infla mucho las respuestas (firmas) → más TCP, más importancia de EDNS0.

▶ Esto explica un *gotcha* documentado en el rol: `systemd-resolved` tenía un drop-in
(`lan-stub.conf`) que ocupaba el **TCP** en las IPs de las VLANs, lo que **bloqueaba las
transferencias de zona** de BIND. El rol DNS elimina ese drop-in y deja a resolved solo
en `127.0.0.53`. Si algún día el AXFR "no funciona pero el ping al 53 UDP sí", sospecha
de algo ocupando el **TCP 53**. (ver `02` y `04`).

---

## 1.12 Anatomía de un mensaje DNS (para leer capturas)

Un paquete DNS tiene 5 secciones:

```
+---------------------+
|       Header        |  ID, flags (QR, AA, RD, RA, AD, RCODE...), conteos
+---------------------+
|      Question       |  qué se pregunta (nombre, tipo, clase)
+---------------------+
|       Answer        |  los RR que responden
+---------------------+
|      Authority      |  los NS autoritativos / SOA en negativas
+---------------------+
|     Additional      |  "glue" (IPs de los NS), OPT (EDNS), etc.
+---------------------+
```

Flags que verás en `dig` y debes saber leer:
- **QR**: query (0) o response (1).
- **AA**: *Authoritative Answer* — la respuesta viene del dueño de la zona.
- **RD**: *Recursion Desired* — el cliente pide recursión.
- **RA**: *Recursion Available* — el servidor ofrece recursión.
- **AD**: *Authenticated Data* — **el resolver validó DNSSEC** y los datos son legítimos.
  Este bit es el que querrás ver al verificar DNSSEC (ver `05`).
- **RCODE**: `NOERROR`, `NXDOMAIN` (no existe), `SERVFAIL` (falló — ojo, DNSSEC roto
  suele dar SERVFAIL), `REFUSED` (no te quiero responder, p. ej. recursión denegada).

Ejemplo de `dig` y cómo leerlo:

```
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 4321
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, ...
;;                ^^^^ aa = respuesta autoritativa (es nuestra zona)
;; ANSWER SECTION:
biblioteca.tel.   3600  IN  A  192.168.20.10
;                 ^TTL      ^tipo  ^dato
```

---

## Resumen de este archivo

- DNS traduce nombres ↔ IPs mediante una jerarquía **distribuida** de zonas.
- **Autoritativo** = tiene los datos; **recursivo** = los busca por ti y cachea.
  El Mini PC es ambos (autoritativo de `biblioteca.tel`, forwarder para lo demás).
- Una zona = registros (A/AAAA/CNAME/NS/SOA/PTR…) + un SOA que controla versión (serial)
  y la relación master↔slave.
- **TTL** rige la caché; el **serial** del SOA rige la replicación. Olvidar incrementarlo
  es el bug clásico.
- Inversas viven en `in-addr.arpa` con la IP al revés.
- Transporte UDP/TCP 53; las transferencias y DNSSEC dependen de TCP.

Sigue con [`02-bind9-implementacion.md`](02-bind9-implementacion.md).
