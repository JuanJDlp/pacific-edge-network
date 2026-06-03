# 02 · BIND9 en este proyecto: cómo está montado y cómo se toca

> Aquí pasamos de la teoría al despliegue real. Al terminar, deberías poder abrir
> cualquier archivo de configuración del Mini PC, entender qué hace cada línea, y saber
> dónde editarlo en el repo para cambiarlo sin romper nada.

---

## 2.1 ¿Qué es BIND9 y por qué este, y no otro?

**BIND** (Berkeley Internet Name Domain) es *el* servidor DNS de referencia, mantenido
por el ISC. La versión aquí es **9.18.39** (rama LTS). El binario del demonio se llama
`named` (name daemon) — por eso el servicio systemd es `named.service`, no "bind9".

### Por qué BIND y no systemd-resolved
Ubuntu trae `systemd-resolved` por defecto, que es un **stub resolver**: cachea y
reenvía, pero NO es un servidor autoritativo serio. No puede:
- alojar una zona local con muchos A/CNAME/PTR y firmarla con DNSSEC,
- escuchar en varias IPs (una por VLAN) como autoritativo,
- hacer transferencias de zona master↔slave,
- aplicar RPZ.

BIND hace todo eso. Por eso BIND es el servidor real y `systemd-resolved` queda
**reducido a `127.0.0.53`** solo para que el propio Mini PC resuelva sus cosas (apt,
etc.). Conviven porque escuchan en IPs distintas.

### Por qué no dnsmasq / Unbound / Knot
- *dnsmasq*: liviano y popular en routers, pero su soporte autoritativo y DNSSEC-signing
  es limitado; no hace master/slave clásico.
- *Unbound*: excelente **recursivo/validador**, pero NO es autoritativo (no firma zonas).
- *Knot/NSD*: autoritativos muy buenos, pero habría que sumar un recursivo aparte.
- BIND hace **autoritativo + recursivo + firmado + RPZ + transferencias** en un solo
  demonio, que es justo lo que esta red de un solo nodo necesita.

---

## 2.2 El árbol de configuración (`named.conf` y sus includes)

BIND arranca leyendo **`/etc/bind/named.conf`**, que en Debian/Ubuntu solo hace
`include` de tres archivos. Esquema real del Mini PC:

```
/etc/bind/named.conf                 (raíz, viene con el paquete)
   ├── include "named.conf.options"  ← opciones globales        [template options.j2]
   ├── include "named.conf.local"    ← zonas locales            [template local.j2]
   │      ├── include "named.conf.tsig"          ← clave TSIG   [template tsig.j2]
   │      └── (declara zonas: biblioteca.tel, inversas, rpz.*)
   └── include "named.conf.default-zones"  ← zonas estándar (localhost, etc.)

named.conf.options además incluye:
   ├── include "named.conf.trust-anchors"  ← KSK de biblioteca.tel  [generado por dnssec.yml]
   └── include "named.conf.rpz"             ← política RPZ activa     [.enabled/.disabled]
```

**Por qué tantos includes:** separa responsabilidades y permite que el rol Ansible
despliegue cada pieza por separado y que `wan-check.sh` cambie *solo* `named.conf.rpz`
sin tocar el resto. Es modularidad, no capricho.

> Nota de orden de carga (importante para entender `tasks/main.yml`): un archivo que
> hace `include` de otro **necesita que el incluido ya exista** al recargar BIND. Por
> eso el rol despliega `named.conf.tsig` y el trust-anchor *antes* de validar/recargar
> la config completa. Si recargas con un include faltante, BIND falla a cargar la zona.

---

## 2.3 `named.conf.options` explicado línea por línea

Archivo real: generado desde `templates/named.conf.options.j2`. Lo desglosamos por
bloques (el `{{ ... }}` es Jinja2 que Ansible rellena desde `vars/main.yml`).

### Trust anchor DNSSEC (arriba del todo)
```bind
include "/etc/bind/named.conf.trust-anchors";
```
Ancla la clave pública (KSK) de `biblioteca.tel` para que el resolver pueda **validar**
nuestra propia zona firmada (como `biblioteca.tel` no cuelga de la raíz, nadie más
publica el `DS`; lo anclamos nosotros). Empieza vacío y lo rellena `dnssec.yml`. → `05`.

### Directorio de trabajo y forwarders
```bind
options {
    directory "/var/cache/bind";

    forwarders { 8.8.8.8; 8.8.4.4; 1.1.1.1; };
    forward only;
```
- `directory`: dónde BIND guarda archivos relativos (cache, etc.).
- `forwarders`: a quién reenviar lo que no es nuestra zona. `forward only` = **no**
  intentes resolver desde la raíz tú mismo; si los forwarders no responden, falla.
  (El slave usa `forward first`, que sí intentaría por su cuenta — ver `04`.)
- ▶ Editar la lista de forwarders → `vars/main.yml`, lista `dns_forwarders`.

### DNSSEC: validación
```bind
    dnssec-validation auto;
```
Activa que este resolver **valide** las firmas DNSSEC de las respuestas (las externas
que entregan los forwarders, y nuestra zona local vía el trust anchor). Sin esto, no
verías el bit `AD`. → `05`.

### En qué IPs escucha (una por VLAN)
```bind
    listen-on port 53 { 127.0.0.1; 192.168.10.1; 192.168.20.1; 192.168.30.1; };
    listen-on-v6 port 53 { ::1; fd00:0:0:10::1; fd00:0:0:20::1; fd00:0:0:30::1; };
```
BIND responde DNS en el gateway de **cada VLAN** + loopback, en IPv4 e IPv6 (dual-stack).
- ▶ Editar las IPs → `dns_listen_ips` / `dns_listen_ips_v6` en `vars/main.yml`.
- Recuerda: aunque escuche en `.20.1` y `.30.1`, **los clientes son redirigidos por
  nftables al `.10.1`** vía DNAT del puerto 53 (memoria `project-dns-forced-to-master`).

### Quién puede preguntar y a quién se le da recursión
```bind
    recursion yes;
    allow-recursion { 127.0.0.1; 192.168.10.0/24; 192.168.20.0/24; 192.168.30.0/24; ::1; fd00:...; };
    allow-query     { (las mismas redes) };
```
- `recursion yes`: este servidor *sí* busca por ti (no solo responde su zona).
- `allow-recursion`: **solo las redes internas** pueden usarlo como recursivo. Esto es
  seguridad: un recursivo abierto a internet se usa para ataques de amplificación DNS.
- `allow-query`: quién puede consultar en general.
- ▶ Editar → `dns_allow_query` (+ v6) en `vars/main.yml`.

### Transferencias denegadas por defecto
```bind
    allow-transfer { none; };
```
Globalmente **nadie** puede transferir zonas. La autorización real se hace **por zona**
con TSIG en `named.conf.local`. "Denegar por defecto, permitir explícito" = buena
práctica. → `04`.

### DNS64 (síntesis de AAAA para NAT64)
```bind
    dns64 64:ff9b::/96 {
        clients { any; };
        mapped  { !10.0.0.0/8; !172.16.0.0/12; !192.168.0.0/16; any; };
        exclude { !fd00::/8; any; };
    };
```
Esto es la pieza IPv6 del proyecto: cuando un cliente IPv6-only pide un sitio que **solo
tiene IPv4** (no tiene AAAA real), BIND **sintetiza** una AAAA del estilo
`64:ff9b::<la-ipv4>`, que el router (Jool, en el rol `router`) traduce a IPv4 vía NAT64.
- `mapped`: para qué IPv4 SÍ sintetizar — excluye las privadas RFC1918 (no tiene sentido
  inventar IPv6 para hosts internos IPv4).
- `exclude`: qué AAAA reales **preservar** — las ULA `fd00::/8` (nuestros hosts internos
  dual-stack, como la propia `biblioteca.tel`), que NO deben ser pisadas por sintéticas.
- Está fuera del alcance "DNS/DNSSEC/TSIG", pero debes saber que existe porque vive en
  este mismo archivo. Detalle de NAT64 en el rol `router`.

### RPZ
```bind
    include "/etc/bind/named.conf.rpz";
};
```
Carga la política RPZ activa (bloqueo + modo offline). → `06`.

---

## 2.4 `named.conf.local`: dónde se declaran las zonas

Generado desde `templates/named.conf.local.j2`. Aquí se **declaran** las zonas (no su
contenido — eso va en los archivos `db.*`). Estructura real (master):

```bind
include "/etc/bind/named.conf.tsig";   // la clave TSIG primero

zone "biblioteca.tel" {
    type master;                               // somos el dueño editable
    file "/var/lib/bind/db.biblioteca.tel";    // archivo fuente (sin firmar)
    dnssec-policy default;                     // firmar automáticamente
    inline-signing yes;                        // mantener .signed aparte
    key-directory "/var/lib/bind/keys";        // dónde van las claves DNSSEC
    allow-transfer { key "ns1-ns2."; };        // solo el slave con TSIG transfiere
    also-notify { 192.168.20.10; fd00:0:0:20::10; };  // avisar al slave
    notify yes;
};

zone "10.168.192.in-addr.arpa" { type master; file ".../db.10.168.192"; allow-transfer { key "ns1-ns2."; }; ... }
// ídem para 20.168.192 y 30.168.192

zone "rpz.offline"   { type master; file ".../rpz.offline.zone";   allow-query { none; }; allow-transfer { none; }; }
zone "rpz.blocklist" { type master; file ".../rpz.blocklist.zone"; allow-query { none; }; allow-transfer { none; }; }
```

- `type master` → esta máquina es la autoritativa primaria de la zona.
- Las directivas `dnssec-policy`/`inline-signing`/`key-directory` solo están en la zona
  directa → **solo `biblioteca.tel` se firma**; las inversas no (decisión: ver `05`).
- ▶ Para cambiar a quién se permite transferir, a quién notificar, etc. → editar
  `templates/named.conf.local.j2` (o las vars que usa: `tsig_key_name`, `dns_slave_ip`).

---

## 2.5 ¿Por qué la zona directa vive en `/var/lib/bind` y no en `/etc/bind/zones`?

Esta es una de las decisiones que **tienes que poder explicar**. Razón: **AppArmor**.

Ubuntu protege a `named` con un perfil AppArmor (`/etc/apparmor.d/usr.sbin.named`) que
define qué archivos puede leer/escribir el demonio:
- `/etc/bind/**` → **solo lectura**.
- `/var/lib/bind/**` y `/var/cache/bind/**` → **lectura y escritura**.

El `inline-signing` de DNSSEC necesita **escribir** junto a la zona:
- `db.biblioteca.tel.signed` (la versión firmada),
- `db.biblioteca.tel.jnl` (el journal de cambios incrementales),
- y leer/escribir las claves en `key-directory`.

Si la zona estuviera en `/etc/bind/zones` (solo-lectura para named), el firmado fallaría
con un error de permisos críptico. Por eso:
- **Zona directa firmada** → `/var/lib/bind/db.biblioteca.tel` (rw).
- **Claves DNSSEC** → `/var/lib/bind/keys` (rw).
- **Zonas inversas** (estáticas, sin firmar) → pueden quedarse en `/etc/bind/zones`.

▶ Variable: `dns_forward_zone_path: "/var/lib/bind/db.{{ dns_domain }}"` en `vars/main.yml`.

> Si alguna vez mueves la zona firmada a `/etc/bind` "por orden", romperás DNSSEC. Es un
> error tentador. No lo hagas (o ajusta el perfil AppArmor, que es más trabajo).

---

## 2.6 El gotcha de systemd-resolved y el TCP 53

Recordando §1.11: BIND necesita el **TCP 53** en las IPs de las VLANs (para AXFR/IXFR y
respuestas grandes de DNSSEC). Un drop-in viejo (`/etc/systemd/resolved.conf.d/lan-stub.conf`)
con `DNSStubListenerExtra` hacía que `systemd-resolved` ocupara ese TCP, **bloqueando a
BIND** y rompiendo las transferencias de zona.

El rol DNS lo arregla en `tasks/main.yml`:
1. **Elimina** `lan-stub.conf`.
2. Deja `DNSStubListener=yes` en `resolved.conf` → resolved solo escucha en `127.0.0.53`.
3. Reinicia resolved y BIND.

▶ Diagnóstico rápido si las transferencias fallan o "el DNS responde por UDP pero no por
TCP": `ss -tlnp 'sport = :53'` en el Mini PC y verifica que **named** (no
`systemd-resolve`) posee el TCP 53 en `.10.1/.20.1/.30.1`.

---

## 2.7 Cómo el rol Ansible despliega todo (lectura de `tasks/main.yml`)

El orden de las tareas **no es casual**; refleja dependencias. Resumen del flujo:

1. **Instala** `bind9`, `bind9utils`, `bind9-doc`.
2. **Crea `/etc/bind/zones`** y el **`key-directory`** (`/var/lib/bind/keys`, owner `bind`).
3. **Crea un trust-anchor placeholder** (vacío) para que `named.conf.options` no falle al
   incluirlo antes de que la zona esté firmada.
4. **Arregla systemd-resolved** (§2.6).
5. **Despliega** `named.conf.options`, `named.conf.local`, la zona directa y las inversas.
   (No valida cada fragmento por separado: `options` referencia zonas declaradas en
   `local`, así que solo tiene sentido validar la config **completa**.)
6. **Despliega TSIG** (`tsig.yml`) — *antes* de DNSSEC, porque `named.conf.local` lo
   incluye y firmar dispara un reload.
7. **`named-checkconf`** valida la config COMPLETA. Si falla, el playbook se detiene y
   **no** se recarga BIND (no rompes el DNS en producción).
8. **DNSSEC** (`dnssec.yml`): fuerza el reload, espera `secure: yes`, extrae la KSK y
   publica el trust anchor. → `05`.
9. **RPZ**: despliega zonas/config offline + blocklist, script y timer. → `06`.
10. **`named-checkzone`** valida la zona directa, **habilita/arranca** `named`, y espera
    a que el puerto 53 esté escuchando.

Idea clave: **validar antes de recargar**. `named-checkconf` y `named-checkzone` son tus
redes de seguridad; el playbook las usa para no aplicar una config rota.

---

## 2.8 Dónde mirar en el equipo (sin Ansible)

Para inspeccionar la config **viva** en el Mini PC (`ssh minipc`):

```bash
# Estado del servicio y versión
systemctl status named
named -v                       # → BIND 9.18.x

# Ver la config efectiva
sudo cat /etc/bind/named.conf.options
sudo cat /etc/bind/named.conf.local
sudo cat /etc/bind/named.conf.tsig          # contiene el secret (root/bind)

# Validar config y zonas
sudo named-checkconf                         # silencio = OK
sudo named-checkzone biblioteca.tel /var/lib/bind/db.biblioteca.tel

# Ver en qué IPs escucha (TCP y UDP 53)
sudo ss -tulnp 'sport = :53'

# Archivos de zona vivos
ls -l /var/lib/bind/                          # db.biblioteca.tel, .signed, .jnl, keys/
ls -l /etc/bind/zones/                        # inversas + rpz.*

# Control en caliente (ver 07 para el detalle)
sudo rndc status
sudo rndc zonestatus biblioteca.tel
```

---

## 2.9 Cómo cambiar algo (el flujo correcto)

> Memoria del proyecto: **no edites a mano los archivos `Managed by Ansible`.** Edita el
> repo y redesplegá. Esto evita que el próximo `ansible-playbook` borre tu cambio.

**Para cambiar una opción global** (forwarders, IPs de escucha, redes permitidas):
1. Edita `minipc/router-setup/roles/dns/vars/main.yml` (o el template `.options.j2` si es
   una opción no parametrizada).
2. Validá local si puedes, y desplegá solo el DNS:
   ```bash
   cd minipc/
   ansible-playbook -i router-setup/inventory.ini services/dns.yml
   ```
   (Existe `minipc/services/dns.yml` para correr solo el rol DNS — ver CLAUDE.md.)
3. Verificá en el equipo (`07`).

**Para un cambio urgente en caliente** (caso excepcional):
1. Editás `/etc/bind/...` en el Mini PC.
2. `sudo named-checkconf && sudo rndc reload`.
3. **Después** reflejás el cambio en el template/var del rol (si no, el próximo deploy lo
   pisa).

El detalle de "agregar un host", "agregar un CNAME", "agregar una IP de escucha" está en
`03` y `07`.

---

## Resumen de este archivo

- `named` (BIND9 9.18) es el servidor; se eligió por ser autoritativo + recursivo +
  DNSSEC + RPZ en un solo demonio. `systemd-resolved` queda solo en `127.0.0.53`.
- Config modular: `named.conf` → `options` (globales) + `local` (zonas) + includes
  (`tsig`, `trust-anchors`, `rpz`).
- La zona directa vive en `/var/lib/bind` por **AppArmor + inline-signing**.
- El rol Ansible despliega con un orden que respeta dependencias y **valida antes de
  recargar**.
- Para cambiar algo: edita el repo (vars/templates) y redesplegá; no edites el equipo a
  mano salvo urgencias (y luego sincroniza).

Sigue con [`03-zonas-y-registros.md`](03-zonas-y-registros.md).
