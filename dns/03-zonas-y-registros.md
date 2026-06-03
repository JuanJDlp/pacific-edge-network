# 03 · Archivos de zona y registros: leerlos, entenderlos, editarlos

> Este archivo te enseña a leer y modificar **el contenido** de las zonas: la directa
> (`biblioteca.tel`) y las inversas (PTR). Es donde agregas hosts, alias y resolución
> inversa. Trabajamos sobre los templates Jinja2 reales del rol.

---

## 3.1 Sintaxis de un archivo de zona (formato RFC 1035)

Un archivo de zona es texto plano con una línea por registro:

```
NOMBRE   TTL   CLASE   TIPO   DATOS
```

Reglas que evitan el 90% de los errores:

- **El punto final importa.** `biblioteca.tel.` (con punto) es absoluto (FQDN). `ns1`
  (sin punto) es relativo: BIND le añade el `$ORIGIN` de la zona → `ns1.biblioteca.tel.`.
  Olvidar el punto en un FQDN produce monstruos como `biblioteca.tel.biblioteca.tel.`.
- **`@`** = el nombre de la zona (el "apex" u origen). En `biblioteca.tel` la zona, `@`
  significa `biblioteca.tel.`.
- **`$TTL`** al inicio fija el TTL por defecto de los registros que no lo especifican.
- **`$ORIGIN`** (implícito = nombre de la zona) es lo que se le pega a los nombres
  relativos.
- Si omites el NOMBRE en una línea, hereda el de la línea anterior.
- `;` inicia un comentario.
- Los paréntesis permiten partir un registro (como el SOA) en varias líneas.

---

## 3.2 La zona directa `biblioteca.tel` (template `db.forward.j2`)

Este es el template real, anotado. Recordá: el archivo en el equipo está en
`/var/lib/bind/db.biblioteca.tel`, y Ansible lo regenera desde este template.

```jinja
$TTL    3600

@   IN  SOA ns1.biblioteca.tel. admin.biblioteca.tel. (
            {{ ansible_date_time.epoch }} ; Serial (epoch)
            3600                          ; Refresh
            900                           ; Retry
            604800                        ; Expire
            300 )                         ; Negative TTL

; Name server de la zona
@   IN  NS  ns1.biblioteca.tel.

; El propio NS
ns1   IN  A     192.168.10.1
ns1   IN  AAAA  fd00:0:0:10::1

; Apex: biblioteca.tel "pelado" → RPi
@     IN  A     192.168.20.10
@     IN  AAAA  fd00:0:0:20::10

; Hosts (A) — generados con un bucle sobre dns_hosts
minipc      IN  A  192.168.10.1
ns1         IN  A  192.168.10.1
monitoreo   IN  A  192.168.10.1
switch      IN  A  192.168.10.2
biblioteca  IN  A  192.168.20.10
rpi         IN  A  192.168.20.10

; Hosts (AAAA) — solo los que tienen ipv6 definido
minipc      IN  AAAA  fd00:0:0:10::1
...

; CNAME — alias de servicios → biblioteca
wikipedia   IN  CNAME  biblioteca.biblioteca.tel.
educacion   IN  CNAME  biblioteca.biblioteca.tel.
videos      IN  CNAME  biblioteca.biblioteca.tel.
squid       IN  CNAME  biblioteca.biblioteca.tel.
kolibri     IN  CNAME  biblioteca.biblioteca.tel.
jellyfin    IN  CNAME  biblioteca.biblioteca.tel.
wiki        IN  CNAME  biblioteca.biblioteca.tel.
media       IN  CNAME  biblioteca.biblioteca.tel.
```

### Lo importante de esta zona

1. **El apex (`@`) es A/AAAA, no CNAME.** Es una regla dura de DNS: el nombre que tiene
   el SOA/NS no puede ser un alias. Por eso `biblioteca.tel` apunta directo a la IP de la
   RPi, y los *alias* (`wikipedia`, etc.) son CNAME hacia `biblioteca`.
2. **Todos los servicios resuelven a la misma IP** (`192.168.20.10`, la RPi). La
   diferenciación NO la hace DNS, la hace el **nginx de la RPi** mirando el header
   `Host:` y enrutando a Kiwix/Kolibri/Jellyfin. DNS solo lleva al cliente a la puerta
   correcta; nginx decide la habitación.
3. **El serial es el epoch del despliegue.** Cada vez que corres el playbook, el serial
   sube solo. Genial para no olvidarlo; peligroso si editas a mano (ver §3.6).
4. **Dual-stack:** cada host con `ipv6:` definido en `dns_hosts` obtiene también un AAAA.

### Cómo se genera (Jinja2)
El bloque de hosts no se escribe a mano: es un bucle sobre la lista `dns_hosts` de
`vars/main.yml`:

```jinja
{% for host in dns_hosts %}
{{ host.name.ljust(16) }}IN  A     {{ host.ip }}
{% endfor %}
```

Por eso **para agregar un host editas la lista de variables, no el template**.

---

## 3.3 Las zonas inversas: qué son, para qué se usan aquí y cómo funcionan

### Qué resuelven (recordatorio)
La búsqueda **directa** es nombre → IP (`biblioteca.tel` → `192.168.20.10`). La **inversa**
es lo contrario: IP → nombre (`192.168.20.10` → `biblioteca.tel`). Tipo de registro:
**PTR** (pointer). El detalle teórico de por qué la IP se escribe "al revés" bajo
`in-addr.arpa` está en `01` §1.10; aquí nos centramos en **para qué sirve en este
proyecto** y **cómo está armado en el código**.

### Para qué se usan en este proyecto
El DNS inverso es "opcional" para que la red funcione, pero aporta tres cosas concretas:

1. **Diagnóstico y legibilidad.** Cuando corrés `dig -x`, `ping`, `traceroute`, `ssh`,
   `nmap` o miras los **logs** de un servicio, ver `biblioteca.biblioteca.tel` en vez de
   `192.168.20.10` hace todo mucho más entendible. En una red con 3 VLANs y varios
   servicios, traducir IPs ↔ nombres ahorra confusión.
2. **Coherencia / completitud de la zona (buena práctica).** Una zona "bien hecha" tiene
   directa **e** inversa coherentes (lo que en internet se llama *forward-confirmed reverse
   DNS*, FCrDNS). Algunos servicios (correo, ciertos chequeos de seguridad) lo exigen;
   aquí no hay correo, pero mantenerlo correcto es parte de hacer el DNS "como debe ser"
   y demuestra dominio del tema.
3. **Herramientas de monitoreo / inventario.** Grafana, Prometheus y utilidades de red
   pueden mostrar nombres en vez de IPs si la inversa resuelve, lo que mejora los
   tableros y reportes del proyecto.

> ▶ Igual que el slave (ver `04` §4.1), la inversa aquí es más **higiene y cumplimiento**
> que algo de lo que dependa un cliente final. Pero está completa y funcional.

### Por qué hay TRES zonas inversas (una por VLAN)
Cada VLAN es una red `/24` distinta (`192.168.10.0/24`, `.20.0/24`, `.30.0/24`). En
`in-addr.arpa`, una red `/24` se mapea a una zona con los **tres primeros octetos
invertidos**:

| VLAN | Red | Zona inversa |
|------|-----|--------------|
| 10 (gestión) | `192.168.10.0/24` | `10.168.192.in-addr.arpa` |
| 20 (servidores) | `192.168.20.0/24` | `20.168.192.in-addr.arpa` |
| 30 (clientes) | `192.168.30.0/24` | `30.168.192.in-addr.arpa` |

El **cuarto octeto** (el host) no va en el nombre de la zona: va como el **nombre del
registro PTR** dentro de ella. Por eso son tres zonas separadas y no una sola.

### Cómo se declaran (el código: `named.conf.local.j2`)
En el master, las tres zonas se declaran con un **bucle Jinja** sobre la lista
`dns_reverse_zones` (`vars/main.yml`, líneas 57-61), en `named.conf.local.j2` (líneas ~38-53):

```jinja
{% for rz in dns_reverse_zones %}        {# rz = "10.168.192", "20.168.192", "30.168.192" #}
zone "{{ rz }}.in-addr.arpa" {
    type master;                          // el Mini PC también es autoritativo de las inversas
    file "/etc/bind/zones/db.{{ rz }}";   // en /etc/bind/zones (NO se firman → no necesitan /var/lib)
    allow-transfer { key "{{ tsig_key_name }}"; };   // se replican al slave, también con TSIG
    also-notify { {{ dns_slave_ip }}; {{ dns_slave_ipv6 }}; };
    notify yes;
};
{% endfor %}
```

Puntos clave de aquí:
- `type master` → las inversas son zonas autoritativas igual que la directa.
- Viven en **`/etc/bind/zones/`** (no en `/var/lib/bind`) porque **no se firman con
  DNSSEC** (ver `05` §5.8) y por tanto no necesitan que `named` escriba junto a ellas.
- Se **transfieren al slave** con la misma clave TSIG y `also-notify` (toda la mecánica de
  master/slave de `04` aplica idéntica a las inversas).

### Cómo se genera el contenido (el código: `db.reverse.j2`)
Un solo template genera las tres (se ejecuta una vez por cada `reverse_zone` del bucle de
tareas):

```jinja
$TTL    3600
@   IN  SOA ns1.biblioteca.tel. admin.biblioteca.tel. ( {{ epoch }} 3600 900 604800 300 )
@   IN  NS  ns1.biblioteca.tel.

; PTR — solo los hosts de ESTA subred
{% set vlan_prefix = reverse_zone.split('.')[0] %}     {# "20" para 20.168.192 #}
{% for host in dns_hosts %}
{% if host.ip.startswith('192.168.' ~ vlan_prefix ~ '.') %}
{{ host.ip.split('.')[-1] }}  IN  PTR {{ host.name }}.biblioteca.tel.
{% endif %}
{% endfor %}
```

Cómo leerlo, paso a paso, para la zona `20.168.192.in-addr.arpa`:
1. `vlan_prefix = "20"` (toma el primer trozo del nombre de la zona).
2. El bucle recorre **todos** los `dns_hosts`, pero el `if` deja pasar **solo** los cuya
   IP empieza por `192.168.20.` → así cada zona contiene solo sus hosts.
3. `host.ip.split('.')[-1]` toma el **último octeto** (el `10` de `192.168.20.10`) y lo usa
   como nombre del PTR:

```dns
; zona 20.168.192.in-addr.arpa (generada)
10  IN  PTR  biblioteca.biblioteca.tel.    ; 192.168.20.10 → biblioteca.tel
```

`10` es relativo, así que BIND le pega el `$ORIGIN` de la zona → el nombre completo es
`10.20.168.192.in-addr.arpa`, que es exactamente lo que se consulta al hacer la búsqueda
inversa de `192.168.20.10`.

### La misma fuente única de verdad
Fíjate que `db.reverse.j2` itera sobre **la misma lista `dns_hosts`** que la zona directa
(§3.4). Por eso, cuando agregás un host a `dns_hosts`, **el A (directa) y el PTR (inversa)
se crean juntos y coherentes** en un solo deploy. No hay que mantener dos listas.

> Detalle: cada host genera **un** PTR (el que matchee su subred). El DNS inverso es,
> idealmente, 1 IP → 1 nombre canónico. Si una misma IP tuviera varios nombres en
> `dns_hosts` (p. ej. `biblioteca` y `rpi`, ambos `192.168.20.10`), se generarían **dos**
> PTR para `.10`; funciona, pero lo "canónico" sería dejar uno. Tenelo en cuenta si te
> piden un inverso limpio.

### Verificarlas
```bash
# Búsqueda inversa de un host
dig @192.168.10.1 -x 192.168.20.10 +short        # → biblioteca.biblioteca.tel.

# Ver/validar la zona inversa en el Mini PC
sudo named-checkzone 20.168.192.in-addr.arpa /etc/bind/zones/db.20.168.192
sudo rndc zonestatus 20.168.192.in-addr.arpa
```

---

## 3.4 La fuente única de verdad: `dns_hosts` y `dns_aliases`

Casi todo el contenido de las zonas sale de dos listas en
`minipc/router-setup/roles/dns/vars/main.yml`:

```yaml
dns_hosts:
  - { name: "minipc",     ip: "192.168.10.1",  ipv6: "fd00:0:0:10::1",  vlan_octet: "10" }
  - { name: "ns1",        ip: "192.168.10.1",  ipv6: "fd00:0:0:10::1",  vlan_octet: "10" }
  - { name: "monitoreo",  ip: "192.168.10.1",                            vlan_octet: "10" }
  - { name: "switch",     ip: "192.168.10.2",                            vlan_octet: "10" }
  - { name: "biblioteca", ip: "192.168.20.10", ipv6: "fd00:0:0:20::10", vlan_octet: "20" }
  - { name: "rpi",        ip: "192.168.20.10", ipv6: "fd00:0:0:20::10", vlan_octet: "20" }

dns_aliases:
  - { name: "wikipedia",  target: "biblioteca" }
  - { name: "educacion",  target: "biblioteca" }
  # ...
```

- `name`: la etiqueta del host (genera el A y, si hay `ipv6`, el AAAA, y el PTR).
- `ip` / `ipv6`: las direcciones. `ipv6` es **opcional**: si no está, no se publica AAAA.
- `vlan_octet`: informativo/organizativo (qué VLAN).
- `dns_aliases`: cada uno genera un CNAME `name → target.biblioteca.tel.`.

**Cambiar las listas = cambiar las zonas directa e inversa de forma consistente.** Esa es
la gracia: una sola edición, y los A/AAAA/PTR quedan coherentes.

---

## 3.5 Recetas: cómo modificar (lo que vas a hacer en la práctica)

### Agregar un host nuevo (p. ej. una cámara en `192.168.10.50`)
1. Edita `vars/main.yml`, agrega a `dns_hosts`:
   ```yaml
   - { name: "camara1", ip: "192.168.10.50", vlan_octet: "10" }
   ```
   (Sin `ipv6:` si no tiene IPv6.)
2. Desplegá: `cd minipc/ && ansible-playbook -i router-setup/inventory.ini services/dns.yml`
3. Verificá:
   ```bash
   dig @192.168.10.1 camara1.biblioteca.tel +short      # → 192.168.10.50
   dig @192.168.10.1 -x 192.168.10.50 +short            # → camara1.biblioteca.tel.
   ```
Esto crea automáticamente el A y el PTR en la inversa de la VLAN 10.

### Agregar un alias (CNAME) a un servicio existente
1. Edita `dns_aliases` en `vars/main.yml`:
   ```yaml
   - { name: "libros", target: "biblioteca" }
   ```
2. Desplegá igual.
3. `dig @192.168.10.1 libros.biblioteca.tel` → debe mostrar el CNAME a
   `biblioteca.biblioteca.tel.` y luego el A.

> Recordá: si agregas un servicio nuevo de verdad (no solo un alias), también hay que
> enseñarle al **nginx de la RPi** a enrutar ese `Host:`. DNS solo resuelve el nombre.

### Cambiar la IP de un host
1. Modifica el `ip:`/`ipv6:` en `dns_hosts`.
2. Desplegá. (Si el cambio es delicado y los clientes cachean, considerá bajar el `$TTL`
   antes — ver §3.7.)

### Agregar una zona inversa nueva (otra VLAN/subred)
1. Agrega el prefijo a `dns_reverse_zones` (p. ej. `"40.168.192"`).
2. El template `named.conf.local.j2` ya declara una zona master por cada elemento de esa
   lista, y `db.reverse.j2` genera el archivo. Solo desplegás.

---

## 3.6 El tema del serial (cuándo SÍ tienes que tocarlo)

- **Si despliegas con Ansible:** el serial es `ansible_date_time.epoch`, sube solo cada
  vez. No haces nada. ✔
- **Si editas la zona a mano en el equipo** (urgencia): **DEBES** incrementar el serial
  manualmente, o el slave (RPi) no detectará el cambio y servirá la versión vieja para
  siempre. El convenio seguro: usar el epoch actual.
  ```bash
  date +%s        # → pon ese número como serial en el SOA
  ```
  Y como la zona está firmada con `inline-signing`, en realidad **no edites el archivo
  fuente y reloads a secas**: usa el flujo de `rndc` para zonas firmadas o, mejor,
  hacelo por Ansible (ver `05` §"editar una zona firmada"). Editar a mano una zona con
  inline-signing es justamente lo que más se presta a errores.

> Regla de oro: en una zona con DNSSEC + inline-signing, **prefiere SIEMPRE el flujo
> Ansible** para cambios de contenido. El firmado y el serial se resuelven solos.

---

## 3.7 Bajar el TTL antes de un cambio (técnica profesional)

Si vas a cambiar un registro que los clientes cachean mucho:
1. Unas horas antes, baja el `$TTL` de la zona (o del registro) a `60`.
2. Esperá a que el TTL viejo expire en los cachés.
3. Hacé el cambio (los clientes lo recogen en ≤60 s).
4. Subí el `$TTL` de nuevo a `3600`.

Esto evita el limbo de "unos ven la IP nueva y otros la vieja" durante una hora.

---

## 3.8 Validar una zona antes de confiar en ella

Siempre, después de editar:

```bash
# Sintaxis y consistencia de la zona (en el Mini PC)
sudo named-checkzone biblioteca.tel /var/lib/bind/db.biblioteca.tel
# → "zone biblioteca.tel/IN: loaded serial NNNN  OK"

# Una inversa
sudo named-checkzone 20.168.192.in-addr.arpa /etc/bind/zones/db.20.168.192

# Config global
sudo named-checkconf
```

`named-checkzone` detecta el error clásico de los puntos finales, registros duplicados,
CNAME mal usados, etc. Si te dice "OK" con un serial, la zona es válida.

---

## Resumen de este archivo

- Una zona = registros `NOMBRE TTL CLASE TIPO DATOS`; el **punto final** y `@` son las
  trampas clásicas.
- La zona directa tiene el apex como A/AAAA (no CNAME), todos los servicios apuntando a
  la RPi, y los alias como CNAME; nginx en la RPi hace el enrutamiento fino.
- Las inversas generan PTR usando el último octeto como nombre.
- **Editas listas (`dns_hosts`, `dns_aliases`) en `vars/main.yml`, no los archivos de
  zona** — Ansible los regenera coherentemente.
- El serial sube solo vía Ansible; a mano, súbelo tú. Con DNSSEC, prefiere Ansible.
- Validá siempre con `named-checkzone` / `named-checkconf`.

Sigue con [`04-master-slave-tsig.md`](04-master-slave-tsig.md).
