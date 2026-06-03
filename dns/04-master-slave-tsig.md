# 04 · Master/Slave, transferencia de zona y TSIG

> Aquí está medio del título de tu objetivo: **TSIG**. Para entenderlo de verdad
> primero hay que entender la infraestructura que protege: **la relación master/slave y
> la transferencia de zona**. Vamos: qué es y para qué sirve → cómo funciona y cómo
> notifica (con el código) → TSIG (teoría + implementación) → cómo agregar más slaves →
> cómo operarlo.

---

## 4.1 ¿Qué es la infra master/slave, por qué la tenemos y para qué se usa?

### El concepto
Una zona DNS puede ser servida por **varios servidores autoritativos** a la vez. Solo uno
es el **master (primary)**: el que tiene la copia *editable* de la zona (los archivos que
tú modificas). Los demás son **slaves (secondary)**: no se editan; reciben una **copia
exacta** del master por un mecanismo llamado **transferencia de zona** y la sirven como si
fueran autoritativos (de hecho lo son: responden con el flag `aa`).

```
        biblioteca.tel  (una zona, dos servidores autoritativos)
        ┌─────────────────────────────┬──────────────────────────────┐
        │  MASTER = Mini PC            │  SLAVE = Raspberry Pi          │
        │  copia EDITABLE de la zona   │  copia RECIBIDA (read-only)    │
        │  type master                 │  type slave                    │
        │  la firma con DNSSEC         │  la recibe ya firmada          │
        └──────────────┬──────────────┴──────────────────────────────┘
                       │  el slave SIEMPRE obtiene sus datos del master
                       └──────────── transferencia de zona ───────────▶
```

### En qué archivos se declara cada rol (el código)
El rol **no es una opción suelta**: se declara zona por zona.

- **Master**, en `minipc/router-setup/roles/dns/templates/named.conf.local.j2` (líneas ~10-33):
  ```bind
  zone "biblioteca.tel" {
      type master;                               // ← este servidor es el primario
      file "/var/lib/bind/db.biblioteca.tel";    // la copia editable
      ...
  };
  ```
- **Slave**, en `raspberry/rpi-setup/roles/dns_secondary/templates/named.conf.local.j2`:
  ```bind
  zone "biblioteca.tel" {
      type slave;                                // ← este servidor es secundario
      masters { 192.168.20.1 key "ns1-ns2."; };  // de quién recibe la copia
      file "/var/cache/bind/db.biblioteca.tel";  // dónde la guarda (read-only para ti)
  };
  ```

`type master` vs `type slave` en la declaración de la zona **es** lo que define el rol.
El mismo servidor puede ser master de unas zonas y slave de otras (de hecho la RPi es
slave de `biblioteca.tel` y master de `praticasaws.dev` — ver su `named.conf.local.j2`).

### Por qué tener un slave (los motivos clásicos)
1. **Resiliencia:** si el master (Mini PC) se reinicia, se cae o lo desconectas, la RPi
   puede seguir respondiendo `biblioteca.tel`. El DNS no se cae con un solo nodo.
2. **Requisito clásico de DNS:** una zona "bien hecha" se publica con **≥2 NS** en
   servidores distintos. Es buena práctica (y, en internet público, casi obligatorio).
3. **Reparto de carga / cercanía:** en redes grandes, los clientes pueden preguntar al NS
   más cercano. Aquí la zona es chica, así que este motivo es menor.

### Para qué se usa **en este proyecto** (el matiz honesto)
▶ Memoria `project-dns-forced-to-master`: los clientes de las VLANs tienen su puerto 53
**DNAT'd al Mini PC** por nftables (ver el rol `router`), así que en la práctica **casi
nunca consultan al slave**. Por eso aquí el slave es sobre todo **redundancia y
cumplimiento del requisito de ≥2 NS**, no balanceo de carga real. Pero está 100%
funcional: si apuntaras un cliente directamente a `192.168.20.10`, respondería igual. Es
el "plan B" caliente del DNS.

---

## 4.2 Cómo funciona la sincronización y cómo notifica el master (con el código)

El master tiene la copia editable; el slave recibe **copias**. Hay **dos disparadores**
que mantienen al slave al día: el **NOTIFY** (push, rápido) y el **SOA Refresh** (pull,
de respaldo). Veamos el intercambio completo y de dónde sale cada parte en los templates.

```
   MASTER (Mini PC)                          SLAVE (RPi)
   192.168.20.1 (en VLAN20)                  192.168.20.10
        │                                         │
   1. La zona cambia y sube el serial            │   (lo editas tú, O BIND re-firma DNSSEC)
   2. ── NOTIFY (firmado con TSIG) ─────────────▶│   master: notify yes + also-notify
        │                                         │
   3.◀── consulta el SOA del master ─────────────│   "¿tu serial > el que tengo?"
        │                                         │
   4.◀── AXFR/IXFR (pide la zona, por TCP) ──────│   firmado con TSIG (masters { ip key })
   5. ── envía la zona (YA firmada) ────────────▶│   master: allow-transfer { key }
        │                                         │
                                       6. guarda en /var/cache/bind/db.biblioteca.tel
                                          y empieza a servirla
```

### Disparador A — NOTIFY (el "push" del master)
**NOTIFY** es un mensaje que el master envía al slave en cuanto la zona cambia, diciendo
"oye, recarga, tengo algo nuevo". Acelera la propagación: el slave no tiene que esperar a
su timer. Se configura en el master, en `named.conf.local.j2` (líneas ~27-32):

```bind
zone "biblioteca.tel" {
    type master;
    ...
    also-notify {
        192.168.20.10;        // ← avisar a la RPi explícitamente (IPv4)
        fd00:0:0:20::10;      // ← y por IPv6
    };
    notify yes;               // ← activar NOTIFY para esta zona
};
```

- `notify yes` activa el mecanismo para la zona.
- `also-notify { ... }` lista destinatarios **explícitos**. Por defecto BIND notificaría a
  los NS que aparecen en los registros `NS` de la zona; aquí lo hacemos explícito y
  apuntando a las IPs concretas de la RPi (v4 y v6) para no depender de eso.

**¿Qué hace que el master mande un NOTIFY?** Cualquier cosa que **suba el serial** de la
zona y recargue:
- Tú editás la zona (vía Ansible → nuevo serial epoch en `db.forward.j2`, líneas 14-19) y
  BIND recarga.
- **DNSSEC re-firma la zona automáticamente** (las firmas RRSIG expiran; BIND las renueva
  solo). Esto cambia la zona *sin que tú la toques* → también dispara NOTIFY. **Esta es la
  razón principal por la que `also-notify` es explícito aquí:** el slave debe enterarse de
  esos re-firmados automáticos, no solo de tus ediciones. El slave recibe la zona **ya
  firmada** (no firma él; no tiene las claves privadas — ver `05`).

El NOTIFY también va **firmado con TSIG**, gracias a los bloques `server` del master (ver
§4.5): cuando el master contacta a la RPi, firma. Así el slave sabe que el "oye, cambié"
es legítimo y no un atacante intentando que transfiera de más.

### Disparador B — SOA Refresh (el "pull" de respaldo)
Aunque se pierda un NOTIFY (paquete UDP perdido, slave reiniciándose), el slave **no se
queda desactualizado para siempre**: por su cuenta consulta el **SOA** del master cada
`Refresh` segundos y compara seriales. Esos timers viven en el **SOA de la zona**, en
`db.forward.j2` (líneas 14-19):

```dns
@   IN  SOA ns1.biblioteca.tel. admin.biblioteca.tel. (
            {{ ansible_date_time.epoch }} ; Serial  ← la "versión"; el slave compara ESTO
            3600                          ; Refresh ← cada cuánto el slave revisa el SOA
            900                           ; Retry   ← si el refresh falla, reintenta cada esto
            604800                        ; Expire  ← si no logra contactar tanto, descarta su copia
            300 )                         ; Neg TTL ← cuánto cachear un "no existe"
```

- **Serial:** el slave transfiere **solo si el serial del master es mayor** que el suyo.
  Si editás a mano y no subís el serial, el slave **nunca** se entera (error clásico —
  ver `03` §3.6). Por Ansible no pasa: el serial es el epoch del despliegue, siempre sube.
- **Refresh (3600 s):** chequeo periódico de respaldo.
- **Retry (900 s):** ritmo de reintento si el master no respondió.
- **Expire (604800 s = 7 días):** si el slave pasa 7 días sin poder contactar al master,
  **deja de servir** la zona (mejor no responder que servir datos potencialmente rancios).
- **Neg TTL (300 s):** cuánto se cachea una respuesta "no existe".

### El paso 4 — AXFR vs IXFR
Cuando el slave decide actualizar, pide una **transferencia de zona** (siempre por **TCP**,
ver `01` §1.11):
- **AXFR** (Asynchronous Full Transfer): la zona **completa**. Se usa la primera vez, o si
  el journal incremental no alcanza.
- **IXFR** (Incremental Transfer): **solo los cambios** desde el serial que el slave ya
  tiene. Más eficiente; es lo normal cuando ambos están casi al día.

El slave guarda el resultado en `/var/cache/bind/db.biblioteca.tel` (en `/var/cache` porque
ahí `named` tiene permiso de escritura bajo AppArmor) y empieza a servirlo.

### De un vistazo: qué archivo controla qué
| Comportamiento | Dónde se configura (template) |
|---|---|
| Quién es master / slave | `named.conf.local.j2` de cada rol (`type master` / `type slave`) |
| A quién notifica el master | `named.conf.local.j2` master → `notify yes` + `also-notify` |
| Cada cuánto revisa el slave | `db.forward.j2` → timers del **SOA** (Refresh/Retry/Expire) |
| Qué versión es "más nueva" | `db.forward.j2` → **Serial** (epoch por Ansible) |
| De quién jala el slave | `named.conf.local.j2` slave → `masters { 192.168.20.1 key ... }` |
| Quién puede transferir | `named.conf.local.j2` master → `allow-transfer { key ... }` |

---

## 4.3 El problema: ¿cómo confía el master en el slave (y viceversa)?

Una transferencia de zona expone **toda** tu zona. No quieres que cualquiera en la red
pida un AXFR y se lleve el mapa completo de tus hosts. Y no quieres que un atacante
**suplante al master** y le mande al slave una zona envenenada.

La forma vieja y débil: `allow-transfer { 192.168.20.10; };` → autorizar **por IP**.
Problema: las IPs se **falsifican** (spoofing), sobre todo en una LAN. La IP de origen
no prueba identidad.

La forma correcta: **TSIG** — autenticar con una **clave criptográfica compartida**.

---

## 4.4 TSIG en teoría (Transaction SIGnature, RFC 8945)

TSIG firma **mensajes DNS individuales** (no los datos de la zona — eso es DNSSEC) con un
**MAC** (Message Authentication Code) basado en una **clave secreta simétrica compartida**
entre las dos partes.

Mecánica:
1. Master y slave comparten **el mismo secreto** (una cadena aleatoria, p. ej. 256 bits)
   y un **nombre de clave** y un **algoritmo** (aquí `hmac-sha256`).
2. Cuando el slave pide un AXFR, **añade al mensaje DNS un registro TSIG** que contiene:
   - el nombre de la clave,
   - una **marca de tiempo** (para evitar *replay* — mensajes re-enviados después),
   - el **HMAC** = `HMAC-SHA256(secreto, contenido-del-mensaje + timestamp)`.
3. El master recalcula el HMAC con *su* copia del secreto sobre el mismo contenido. Si
   coincide → el mensaje es auténtico (vino de quien conoce el secreto) y no fue alterado.
   Si no coincide o el timestamp está fuera de ventana (típico ±5 min) → rechaza con
   `BADKEY`/`BADSIG`/`BADTIME`.

Propiedades que da TSIG:
- **Autenticación:** solo quien tiene el secreto puede firmar válidamente.
- **Integridad:** si el mensaje se altera en tránsito, el MAC no cuadra.
- **Anti-replay:** el timestamp evita reusar una petición vieja (→ **los relojes deben
  estar sincronizados**; por eso el proyecto corre chrony/NTP).

Lo que TSIG **NO** es:
- No cifra (el contenido va en claro; protege autenticidad/integridad, no
  confidencialidad).
- No es DNSSEC (TSIG = autenticar un *mensaje* entre dos servidores con clave
  **simétrica**; DNSSEC = firmar los *datos de la zona* con claves **asimétricas** para
  cualquier validador). Ver tabla en §4.8.

---

## 4.5 Cómo está implementado TSIG aquí

### La clave (compartida, estática)
Definida idéntica en ambos lados:

- Master: `minipc/router-setup/roles/dns/vars/main.yml`
  ```yaml
  tsig_key_name: "ns1-ns2."
  tsig_secret:   "QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg="
  ```
- Slave: `raspberry/rpi-setup/group_vars/all.yml` (los **mismos** dos valores).

El nombre `ns1-ns2.` (con punto final, es un nombre DNS) identifica la clave; el secret
es 32 bytes aleatorios en base64; el algoritmo es `hmac-sha256`.

### En el master (`named.conf.tsig`, template `named.conf.tsig.j2`)
```bind
key "ns1-ns2." {
    algorithm hmac-sha256;
    secret "QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg=";
};

# El master USA la clave cuando contacta al slave (NOTIFY / transfer), IPv4 e IPv6
server 192.168.20.10      { keys { ns1-ns2.; }; };
server fd00:0:0:20::10     { keys { ns1-ns2.; }; };
```
- El bloque `key` define la clave.
- Los bloques `server` dicen: "cuando hables con la RPi, firma con esta clave". Así los
  **NOTIFY** del master hacia el slave también van firmados.

### En el master, por zona (`named.conf.local`)
```bind
zone "biblioteca.tel" {
    type master;
    ...
    allow-transfer { key "ns1-ns2."; };   // SOLO quien presente esta clave transfiere
    also-notify { 192.168.20.10; fd00:0:0:20::10; };
    notify yes;
};
```
Fíjate: `allow-transfer` ya **no** lleva una IP — **solo la clave**. Comentario del
template: *"Se elimina la IP explícita — la llave es suficiente y más seguro"*. La clave
autentica de verdad; la IP era teatro.

### En el slave (`named.conf.local` de la RPi)
```bind
zone "biblioteca.tel" {
    type slave;
    masters { 192.168.20.1 key "ns1-ns2."; };   // a quién pedir, firmando con la clave
    file "/var/cache/bind/db.biblioteca.tel";
};
```
- `masters { 192.168.20.1 key "ns1-ns2."; }` → "pide la zona a esta IP y **firma la
  petición** con la clave". El master verifica la firma y autoriza.
- El slave guarda la copia en `/var/cache/bind/` (rw para named).

El slave tiene también su copia de `named.conf.tsig` (solo el bloque `key`, no necesita
los `server`).

---

## 4.6 El gotcha de la IP del master: `192.168.20.1`, no `192.168.10.1`

Esto confunde a todo el mundo y **tienes que entenderlo**:

- El NS primario "oficial" (el que aparece en el SOA/NS y donde escuchan los clientes) es
  `ns1 = 192.168.10.1` (VLAN 10).
- Pero el slave pide la transferencia a **`192.168.20.1`** (la IP del Mini PC en la
  **VLAN 20**), no a `.10.1`.

¿Por qué? Porque **la RPi vive en la VLAN 20** (`192.168.20.10`). El camino directo
RPi → master es por la interfaz de la VLAN 20 del Mini PC (`192.168.20.1`), que es el
gateway de la propia RPi. Pedirle al slave que alcance `.10.1` lo obligaría a cruzar de
VLAN; usar `.20.1` es el camino natural en su mismo segmento. La variable es
`dns_master_transfer_ip: "192.168.20.1"` en el `group_vars/all.yml` de la RPi.

Como BIND escucha en **las dos** IPs (`.10.1` y `.20.1`), el master responde el AXFR por
cualquiera; el slave simplemente usa la que tiene a mano.

---

## 4.7 El otro gotcha: por qué la clave es estática y no se genera en runtime

El comentario en `tasks/tsig.yml` lo explica: un enfoque "más elegante" sería generar la
clave con `tsig-keygen` en el master y **copiarla al slave** con `delegate_to`. Pero:

- El master y el slave se despliegan con **inventarios Ansible separados** (uno en
  `minipc/`, otro en `raspberry/`).
- La laptop de control **no alcanza la VLAN 20** directamente, lo que rompía el
  `delegate_to` cross-host.

Solución pragmática: **pre-generar la clave una vez** (`tsig-keygen` u
`openssl rand -base64 32`) y ponerla como variable en *ambos* repos. Cada playbook
despliega su lado sin depender del otro. Es menos "mágico" pero robusto y reproducible.

> Implicación de seguridad: el secret está **en texto en el repo**. Para un proyecto
> universitario / red comunitaria cerrada es aceptable, pero en producción real se
> guardaría con **Ansible Vault**. Si publicas el repo, **rota la clave** (§4.9).

---

## 4.8 TSIG vs DNSSEC (la tabla que despeja la confusión)

| | **TSIG** | **DNSSEC** |
|---|---|---|
| Qué firma | un **mensaje** DNS (transfer, NOTIFY, UPDATE) | los **datos** de la zona (RRsets) |
| Cripto | **simétrica** (HMAC, secreto compartido) | **asimétrica** (claves pública/privada) |
| Quién valida | las **dos** partes que comparten el secreto | **cualquier** resolver con el trust anchor |
| Protege contra | transfers/updates no autorizados, spoofing entre 2 servers | datos falsificados/envenenados para todos |
| Alcance | punto a punto (master↔slave) | extremo a extremo (zona→cualquier cliente) |
| En este proyecto | autentica AXFR/IXFR/NOTIFY Mini PC↔RPi | firma `biblioteca.tel`, marca `AD` |
| Archivo | `named.conf.tsig` | `db...signed`, `keys/`, `trust-anchors` |

Resumen de una línea: **TSIG protege la tubería entre tus dos servidores; DNSSEC protege
los datos para cualquiera que los reciba.** Son complementarios y aquí se usan ambos.

---

## 4.9 Operación: verificar, forzar y rotar

### Verificar que la transferencia funciona
```bash
# En la RPi: forzar una re-transferencia desde cero
sudo rndc retransfer biblioteca.tel
# Ver estado de la zona slave (serial, última transferencia)
sudo rndc zonestatus biblioteca.tel
ls -l /var/cache/bind/db.biblioteca.tel        # debe existir y tener fecha reciente

# Probar un AXFR manual CON la clave (debe funcionar)
dig @192.168.20.1 biblioteca.tel AXFR \
    -y hmac-sha256:ns1-ns2.:QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg=

# Probar un AXFR SIN la clave (debe ser RECHAZADO → prueba que TSIG protege)
dig @192.168.20.1 biblioteca.tel AXFR
# → "Transfer failed" / REFUSED
```
El último par de comandos es **la demostración** de que TSIG funciona: con clave
transfiere, sin clave no. Úsalo en una sustentación.

### Logs útiles
```bash
# En master o slave
journalctl -u named -f | grep -iE 'transfer|notify|tsig|axfr|ixfr'
```
Errores típicos: `TSIG verify failure (BADKEY)` (nombres/secret no coinciden),
`(BADTIME)` (relojes desincronizados → revisa chrony/NTP), `(BADSIG)` (secret distinto).

### Rotar la clave TSIG (cuando se filtró o por higiene)
1. Genera un secret nuevo:
   ```bash
   openssl rand -base64 32
   ```
2. Pégalo en **ambos** lados (mismo valor):
   - `minipc/router-setup/roles/dns/vars/main.yml` → `tsig_secret`
   - `raspberry/rpi-setup/group_vars/all.yml` → `tsig_secret`
   (Opcional: cambia también `tsig_key_name`, pero entonces cámbialo en los dos.)
3. Desplegá **primero el master, luego el slave** (o ambos casi a la vez). Si quedan
   desincronizados un momento, los transfers fallarán con `BADKEY` hasta que ambos tengan
   la clave nueva — por eso conviene hacerlo seguido.
4. Verificá con el `dig ... AXFR -y ...` de arriba (usando el secret nuevo).

> Para rotación sin downtime, BIND permite tener varias claves a la vez, pero para esta
> red el pequeño parpadeo de un redeploy es aceptable.

---

## 4.10 Cómo agregar más secundarios (slaves)

Supongamos que querés un **segundo slave** (otra RPi, una VM, etc.) en `192.168.20.20`.
Hay que tocar **el master** (para que lo notifique y le permita transferir) y **crear la
config del nuevo slave**. La clave TSIG `ns1-ns2.` se reutiliza (todos los slaves
comparten el mismo secreto en este diseño).

> 💡 **Detalle elegante de este diseño:** como el master autoriza con
> `allow-transfer { key "ns1-ns2."; }` (por **clave**, no por IP), **cualquier** servidor
> nuevo que tenga la clave queda autorizado a transferir automáticamente — no hay que
> tocar `allow-transfer`. Solo hay que (a) notificarlo y (b) firmarle los NOTIFY.

### Lado MASTER (Mini PC) — 3 cambios en `roles/dns/`

1. **Notificarlo** — en `templates/named.conf.local.j2`, agregá su IP al `also-notify` de
   cada zona (directa + inversas):
   ```bind
   also-notify {
       192.168.20.10;     fd00:0:0:20::10;     // slave 1 (RPi actual)
       192.168.20.20;     fd00:0:0:20::20;     // ← slave 2 nuevo
   };
   ```

2. **Firmarle los NOTIFY con TSIG** — en `templates/named.conf.tsig.j2`, agregá un bloque
   `server` para la IP nueva (para que el master firme cuando le hable):
   ```bind
   server 192.168.20.20   { keys { ns1-ns2.; }; };
   server fd00:0:0:20::20  { keys { ns1-ns2.; }; };
   ```

3. **`allow-transfer`: NO se toca** (ya autoriza por clave, ver el recuadro arriba).

> **Forma limpia (recomendada si vas a tener varios):** hoy los templates usan variables
> de **un solo** slave (`dns_slave_ip` / `dns_slave_ipv6` en `vars/main.yml`, líneas
> 73-75). Para soportar N slaves sin duplicar a mano, conviene refactorizar a una **lista**
> y recorrerla con un bucle Jinja. Ejemplo en `vars/main.yml`:
> ```yaml
> dns_slaves:
>   - { ip: "192.168.20.10", ipv6: "fd00:0:0:20::10" }
>   - { ip: "192.168.20.20", ipv6: "fd00:0:0:20::20" }
> ```
> y en `named.conf.local.j2`:
> ```jinja
> also-notify {
> {% for s in dns_slaves %}
>     {{ s.ip }};   {{ s.ipv6 }};
> {% endfor %}
> };
> ```
> e igual en `named.conf.tsig.j2` para los bloques `server`. Así agregar un slave futuro
> es **una línea** en la lista.

Después: desplegá el master → `cd minipc/ && ansible-playbook -i router-setup/inventory.ini services/dns.yml`.

### Lado SLAVE nuevo — crear su configuración

El slave nuevo necesita exactamente lo que tiene la RPi en
`raspberry/rpi-setup/roles/dns_secondary/`. La forma más rápida es **clonar ese rol** (o
aplicarlo al nuevo host) con tres archivos:

1. **`named.conf.tsig`** — la **misma** clave (`tsig_key_name` + `tsig_secret`,
   idénticos al master). Solo el bloque `key`; no necesita bloques `server`.
2. **`named.conf.local`** — declarar las zonas como `type slave` apuntando al master:
   ```bind
   zone "biblioteca.tel" {
       type slave;
       masters { 192.168.20.1 key "ns1-ns2."; };   // mismo dns_master_transfer_ip
       file "/var/cache/bind/db.biblioteca.tel";
   };
   // ídem para las tres inversas 10/20/30.168.192.in-addr.arpa
   ```
3. **`named.conf.options`** — escucha, forwarders, `allow-query`/`allow-recursion` para
   sus clientes (copiar el patrón del slave actual).

Requisitos que el slave nuevo **debe** cumplir (si no, el transfer falla):
- **Misma clave TSIG** que el master (`BADKEY` si difiere). → `04` §4.9.
- **Reloj sincronizado** (NTP/chrony), o TSIG falla con `BADTIME`. → `04` §4.4.
- **Alcanzar al master por `192.168.20.1`** y por **TCP 53** (las transferencias van por
  TCP; revisá firewall/VLAN). → `04` §4.6, `01` §1.11.

Verificá en el slave nuevo:
```bash
sudo rndc retransfer biblioteca.tel
sudo rndc zonestatus biblioteca.tel        # serial == al del master
dig @127.0.0.1 biblioteca.tel +short       # → 192.168.20.10
```

### (Opcional) Hacerlo "oficial" en la zona
Si querés que el slave nuevo sea un NS *anunciado* de la zona (buena práctica DNS), agregá
su registro en `db.forward.j2`: un `A`/`AAAA` para el host (vía `dns_hosts` en
`vars/main.yml`) y un registro `NS` extra apuntándolo. En esta red no es estrictamente
necesario, porque los clientes están DNAT'd al master y no descubren NS por su cuenta
(memoria `project-dns-forced-to-master`), pero lo deja correcto de cara a la teoría.

---

## Resumen de este archivo

- El **slave (RPi)** recibe copias de la zona por **transferencia** (AXFR/IXFR) disparada
  por **NOTIFY** y/o el **Refresh** del SOA; aquí es redundancia (los clientes pegan al
  master por DNAT).
- La transferencia se autentica con **TSIG**: un **HMAC con secreto compartido** que
  prueba identidad e integridad de cada mensaje, mejor que confiar en la IP de origen.
- Implementación: clave `ns1-ns2.`/`hmac-sha256` idéntica en ambos repos;
  `allow-transfer { key ... }` en el master, `masters { 192.168.20.1 key ... }` en el
  slave.
- El rol (master/slave) se define **por zona** con `type master` / `type slave`; el master
  **notifica** con `notify yes` + `also-notify` y los timers del **SOA** son el respaldo.
- Gotchas: el slave transfiere desde **`192.168.20.1`** (misma VLAN), y la clave es
  **estática** porque los inventarios están separados y la laptop no alcanza la VLAN 20.
- **Agregar más slaves** (§4.10): notificar + firmar NOTIFY en el master (`allow-transfer`
  no se toca, autoriza por clave) y crear la config `type slave` con la misma clave TSIG.
- TSIG ≠ DNSSEC: TSIG protege la tubería entre 2 servidores (simétrico); DNSSEC protege
  los datos para todos (asimétrico).

Sigue con [`05-dnssec.md`](05-dnssec.md).
