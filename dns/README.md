# DNS / DNSSEC / TSIG — Master class de Pacific Edge Network

> Objetivo de esta carpeta: que **entiendas y puedas modificar** todo el subsistema
> DNS de este proyecto sin tener que preguntarle a nadie (ni a una IA). No es un
> manual de "copia y pega": cada archivo explica **la teoría del protocolo**, luego
> **cómo está implementado aquí**, y por último **el porqué** de cada decisión.

Esta NO sustituye a los docs operativos (`DOCS/minipc/DNS-BIND9.md`,
`DOCS/raspberry/DNS-SECUNDARIO.md`); los amplía. Cuando haya conflicto entre un doc
viejo y lo que diga aquí, **gana esta carpeta**, porque está escrita leyendo los
templates de Ansible reales (la fuente de verdad de la configuración).

---

## Cómo está montado el DNS en este proyecto (vista de 10 segundos)

```
                    biblioteca.tel  (TLD local, NO existe en internet)
                            │
         ┌──────────────────┴───────────────────┐
         │                                       │
   Mini PC (plataformas)                  Raspberry Pi (akasicom2)
   192.168.10.1 / .20.1 / .30.1           192.168.20.10
   BIND9  ── MASTER (autoritativo)        BIND9 ── SLAVE (secundario)
   + recursivo con forwarders             + recursivo (forward al master)
   + FIRMA la zona con DNSSEC             recibe la zona YA firmada
   + RPZ (blocklist + offline)
         │                                       ▲
         │  zone transfer (AXFR/IXFR)            │
         └──── autenticado con TSIG ─────────────┘
              also-notify + masters { key }
```

- **Un solo dominio autoritativo:** `biblioteca.tel`. Es un TLD *inventado* (no existe
  en la raíz de internet). Por eso DNSSEC aquí necesita un *trust anchor* local
  (ver `05-dnssec.md`).
- **Master = Mini PC.** Tiene la copia editable de la zona, la firma con DNSSEC, y
  aplica políticas RPZ (bloqueo de contenido + modo offline).
- **Slave = Raspberry Pi.** Recibe una copia por transferencia de zona. Si el Mini PC
  muere, la RPi puede seguir respondiendo `biblioteca.tel`.
- **TSIG** es la clave compartida que autentica esa transferencia (para que cualquiera
  en la red no pueda pedir/forzar una copia de la zona ni suplantar al master).
- **Clientes (VLAN 30) nunca eligen su DNS:** nftables hace DNAT del puerto 53 hacia
  el BIND del Mini PC (`192.168.10.1:53`). Por eso, en la práctica, **el slave de la
  RPi casi nunca lo consultan los clientes** — es redundancia/cumplimiento, no balanceo.
  (ver memoria `project-dns-forced-to-master`).

---

## Ruta de aprendizaje (lee en este orden)

| # | Archivo | Qué aprendes | Nivel |
|---|---------|--------------|-------|
| 1 | [`01-teoria-dns.md`](01-teoria-dns.md) | Qué es DNS, resolvers, zonas, registros, TTL, recursivo vs autoritativo, el viaje de una query, formato del paquete | Teoría pura |
| 2 | [`02-bind9-implementacion.md`](02-bind9-implementacion.md) | Cómo está montado BIND9 aquí: archivos, `named.conf`, options, dónde mirar en el equipo, cómo editar con seguridad | Proyecto |
| 3 | [`03-zonas-y-registros.md`](03-zonas-y-registros.md) | Los archivos de zona reales (directa + inversas), el SOA campo por campo, serial, cómo agregar un host/CNAME/PTR | Proyecto + teoría |
| 4 | [`04-master-slave-tsig.md`](04-master-slave-tsig.md) | Transferencia de zona (AXFR/IXFR/NOTIFY), teoría de TSIG (HMAC), cómo está cableado aquí, cómo rotar la clave | DNS + DNSSEC + TSIG |
| 5 | [`05-dnssec.md`](05-dnssec.md) | Teoría DNSSEC completa (cadena de confianza, KSK/ZSK, RRSIG/DNSKEY/DS, NSEC, bit AD), y cómo se firma e implementa aquí | Lo más denso |
| 6 | [`06-rpz-politicas.md`](06-rpz-politicas.md) | Response Policy Zones: bloqueo de contenido y modo offline (bonus, parte del despliegue real) | Proyecto + teoría |
| 7 | [`07-operacion-troubleshooting.md`](07-operacion-troubleshooting.md) | Chuleta de `dig`/`rndc`/`named-check*`/`delv`, cómo verificar cada cosa, fallos comunes y el flujo Ansible para cambiar algo | Manos a la obra |
| 8 | [`08-preparacion-presentacion.md`](08-preparacion-presentacion.md) | Runbook de demos para sustentar: comandos de gestión + guión exacto (cambio en vivo, caída del master, DNSSEC roto, TSIG rechazado) con salidas esperadas y restauración | Presentación |

> **Si solo tienes 20 minutos antes de un examen/sustentación:** lee este README
> completo, luego `08-preparacion-presentacion.md` (el runbook de demos) y
> `07-operacion-troubleshooting.md` (los comandos), y hojea las secciones "El porqué"
> de `04` y `05`.

---

## Mapa de archivos: dónde vive cada cosa

### En el repo (lo que editas → Ansible lo despliega)

```
minipc/router-setup/roles/dns/          ← MASTER (Mini PC)
├── vars/main.yml                        ← TODAS las variables: hosts, IPs, claves, forwarders
├── tasks/main.yml                       ← orquestación (instala, despliega, valida, arranca)
├── tasks/tsig.yml                       ← despliega la clave TSIG
├── tasks/dnssec.yml                     ← fuerza firmado, espera "secure: yes", extrae trust anchor
├── handlers/main.yml                    ← reload/restart de BIND
├── files/update-bind-rpz                ← script que genera la blocklist RPZ
└── templates/
    ├── named.conf.options.j2            ← opciones globales (forwarders, listen, DNSSEC, DNS64)
    ├── named.conf.local.j2              ← declaración de zonas (master) + allow-transfer TSIG
    ├── named.conf.tsig.j2               ← la clave TSIG + a qué servidor presentarla
    ├── db.forward.j2                    ← zona directa biblioteca.tel (A/AAAA/CNAME)
    ├── db.reverse.j2                    ← zonas inversas (PTR), una por VLAN
    ├── named.conf.rpz.enabled.j2        ← RPZ con modo offline ACTIVO
    ├── named.conf.rpz.disabled.j2       ← RPZ con modo offline INACTIVO
    ├── rpz.offline.zone.j2              ← zona que manda todo a 192.168.30.1 (sin WAN)
    └── rpz.blocklist.seed.zone.j2       ← semilla vacía de la blocklist

raspberry/rpi-setup/roles/dns_secondary/ ← SLAVE (RPi)
├── tasks/main.yml
├── handlers/main.yml
└── templates/
    ├── named.conf.options.j2            ← opciones del slave
    ├── named.conf.local.j2              ← zonas type slave + la zona praticasaws.dev
    └── named.conf.tsig.j2               ← la MISMA clave TSIG

raspberry/rpi-setup/group_vars/all.yml   ← variables del slave (incl. tsig_secret, igual al master)
```

### En los equipos (lo que BIND lee en runtime)

| Equipo | Ruta | Qué es |
|--------|------|--------|
| Mini PC | `/etc/bind/named.conf` | raíz; incluye los tres `.conf` siguientes |
| Mini PC | `/etc/bind/named.conf.options` | opciones globales |
| Mini PC | `/etc/bind/named.conf.local` | zonas locales (master) |
| Mini PC | `/etc/bind/named.conf.tsig` | clave TSIG |
| Mini PC | `/etc/bind/named.conf.trust-anchors` | trust anchor DNSSEC de `biblioteca.tel` |
| Mini PC | `/etc/bind/named.conf.rpz` | symlink lógico al `.enabled`/`.disabled` (lo cambia `wan-check.sh`) |
| Mini PC | `/var/lib/bind/db.biblioteca.tel` | **zona directa fuente** (sin firmar) — la editable |
| Mini PC | `/var/lib/bind/db.biblioteca.tel.signed` | versión firmada (la genera BIND, no se toca) |
| Mini PC | `/var/lib/bind/keys/` | claves DNSSEC KSK/ZSK (las gestiona BIND) |
| Mini PC | `/etc/bind/zones/db.10.168.192` etc. | zonas inversas |
| Mini PC | `/etc/bind/zones/rpz.blocklist.zone` | blocklist generada (porn+gambling) |
| RPi | `/etc/bind/named.conf.local` | zonas type slave |
| RPi | `/var/cache/bind/db.biblioteca.tel` | copia recibida del master (no se edita a mano) |

> **Regla de oro del proyecto (memoria `feedback-keep-playbooks-synced-with-live`):**
> nunca edites a mano un archivo `// Managed by Ansible`. Edita el template/var en el
> repo y vuelve a correr el playbook. Si tocas el equipo en caliente para una urgencia,
> después reflejá el cambio en el rol.

---

## Las 6 decisiones de diseño que tienes que poder defender

Si te preguntan "¿por qué lo hicieron así?", estas son las respuestas (cada una se
desarrolla en el archivo indicado):

1. **BIND9 y no systemd-resolved** → necesitábamos un servidor *autoritativo* con
   muchos A/CNAME y escucha por VLAN; resolved es solo un stub. → `02`.
2. **Zona directa en `/var/lib/bind` y no en `/etc/bind/zones`** → AppArmor deja
   `/etc/bind` como solo-lectura para `named`; el `inline-signing` de DNSSEC necesita
   escribir el `.signed` y el `.jnl` junto a la zona. → `02`, `05`.
3. **Master/slave con un secundario en la RPi** → redundancia del DNS autoritativo y
   requisito del proyecto, aunque los clientes (DNAT) casi siempre pegan al master. → `04`.
4. **TSIG en vez de `allow-transfer` por IP** → la IP se puede falsificar; la clave
   HMAC autentica de verdad y permite también firmar los NOTIFY. → `04`.
5. **DNSSEC con `dnssec-policy default` + `inline-signing` y trust anchor local** →
   firmado y rotación automáticos; y como `biblioteca.tel` no cuelga de la raíz, hay
   que anclar la KSK localmente para que el resolver marque `AD`. → `05`.
6. **RPZ para bloqueo + modo offline** → filtrado de contenido a nivel DNS (cubre HTTP
   y HTTPS por igual) y una experiencia "sin internet" decente cuando cae el WAN. → `06`.

---

## Glosario express (para no perderte)

- **Zona:** porción del árbol DNS sobre la que un servidor es autoritativo (aquí: `biblioteca.tel` y las inversas).
- **Autoritativo:** servidor que *tiene* los datos de una zona y responde con `aa=1`.
- **Recursivo / resolver:** servidor que *busca por ti* preguntando a otros y cachea.
- **Forwarder:** un recursivo al que le reenvías las preguntas que no sabes responder.
- **Master/Primary:** dueño de la copia editable de la zona.
- **Slave/Secondary:** copia recibida por transferencia.
- **AXFR/IXFR:** transferencia de zona completa / incremental.
- **TSIG:** firma HMAC con clave compartida para autenticar mensajes (transfers, NOTIFY, updates).
- **DNSSEC:** firmas criptográficas *de los datos* de la zona, validables por cadena de confianza.
- **RPZ:** "firewall de DNS"; reescribe respuestas según políticas (bloquear, redirigir).
- **TTL:** segundos que una respuesta puede cachearse.

Sigue con [`01-teoria-dns.md`](01-teoria-dns.md).
