# Dual-Stack IPv4 + IPv6 — Pacific Edge Network

> Documento de referencia técnica de la implementación dual-stack desplegada
> en el Mini PC (router/gateway) y la Raspberry Pi (servidor de contenido).
> Fecha de despliegue: 2026-05-25.

---

## 1. Objetivo y alcance

La red comunitaria entrega a los clientes conectividad **dual-stack** (IPv4 + IPv6) en las tres VLANs internas, con el siguiente comportamiento:

| Tipo de cliente | IPv4 | IPv6 | IPv4 internet | IPv6 internet |
|---|---|---|---|---|
| Dual-stack (laptop moderno) | DHCP | SLAAC | Nativo (NAT44) | Solo destinos `64:ff9b::/96` vía NAT64 |
| Sólo-IPv6 | — | SLAAC | NAT64 + DNS64 (transparente) | Solo destinos `64:ff9b::/96` vía NAT64 |
| Sólo-IPv4 (legado) | DHCP | — | Nativo (NAT44) | No aplica |

**Lo que NO es esta implementación:** no hay IPv6 global nativo en el WAN (`enp170s0` solo tiene `172.16.0.11/16` y link-local). El direccionamiento IPv6 interno es **ULA** (`fd00::/8`). Por lo tanto, sitios IPv6-only del internet público no son alcanzables — su tráfico se sintetiza vía DNS64 y se traduce vía NAT64, llegando al destino por IPv4 si el sitio también tiene IPv4 (la gran mayoría), o fallando si es estrictamente IPv6-only.

Esta limitación es estructural a la red de uplink y se asume conscientemente.

---

## 2. Plano de direccionamiento

### 2.1 Prefijos por VLAN

| VLAN | Nombre | IPv4 (gateway) | IPv6 ULA (gateway) | Pool DHCPv4 |
|---|---|---|---|---|
| 10 | Gestión | `192.168.10.1/24` | `fd00:0:0:10::1/64` | `.50–.99` |
| 20 | Servidores | `192.168.20.1/24` | `fd00:0:0:20::1/64` | `.50–.99` (reserva RPi `.10`) |
| 30 | Clientes | `192.168.30.1/24` | `fd00:0:0:30::1/64` | `.100–.200` |

IPv6 cliente: se obtiene por **SLAAC** (EUI-64 o privacy extensions según el OS); no hay DHCPv6.

### 2.2 Direcciones críticas

| Host | IPv4 | IPv6 |
|---|---|---|
| Mini PC (VLAN10 gw) | `192.168.10.1` | `fd00:0:0:10::1` |
| Mini PC (VLAN20 gw) | `192.168.20.1` | `fd00:0:0:20::1` |
| Mini PC (VLAN30 gw) | `192.168.30.1` | `fd00:0:0:30::1` |
| Mini PC WAN | `172.16.0.11/16` | — (solo link-local) |
| Raspberry Pi (eth0) | `192.168.20.10` (DHCP reservada) | `fd00:0:0:20::10` (estática) |
| Pool NAT64 (Jool) | — | `64:ff9b::/96` (well-known) |

### 2.3 Sobre las direcciones ULA

`fd00::/8` es el bloque ULA de RFC 4193. Es el equivalente IPv6 de `192.168.0.0/16` — **no se enruta en el internet público**. Se eligió el rango `fd00:0:0:NN::/64` (donde `NN` = id de VLAN) por legibilidad operativa, no por aleatoriedad criptográfica (RFC 4193 sugiere generar los 40 bits aleatoriamente). En una red comunitaria aislada esto es aceptable; si en el futuro se interconectan múltiples sitios ULA podría haber colisiones — entonces conviene regenerar.

---

## 3. Componentes desplegados

### 3.1 Resumen

| Componente | Tecnología | Ubicación | Rol Ansible |
|---|---|---|---|
| Direccionamiento estático IPv6 (gateways) | netplan | Mini PC | `router` |
| Direccionamiento estático IPv6 (RPi) | netplan drop-in | RPi | `network_ipv6` |
| SLAAC + RDNSS + DNSSL | radvd | Mini PC | `radvd` |
| DNS recursivo dual-stack | BIND 9.18 | Mini PC | `dns` |
| DNS64 (síntesis AAAA) | BIND 9.18 | Mini PC | `dns` |
| DNS secundario dual-stack | BIND 9.18 | RPi | `dns_secondary` |
| NAT64 (traducción) | Jool kernel module | Mini PC | `router` |
| Firewall IPv4 + IPv6 | nftables `inet filter` | Mini PC | `router` |
| Redirect DNS IPv6 | nftables `ip6 nat` | Mini PC | `router` |
| IPv4 NAT44 (masquerade) | nftables `ip nat` | Mini PC | `router` |
| IPv6 forwarding | sysctl | Mini PC | `router` |

### 3.2 SLAAC vía radvd

**Rol:** `minipc/router-setup/roles/radvd/`

`radvd` emite Router Advertisements en cada VLAN sub-interface (`enp171s0.{10,20,30}`). Cada RA incluye:

- **Prefix Information Option** con `AdvAutonomous on` → los clientes derivan su dirección IPv6 sumando un identificador de interfaz (EUI-64 o privacy random) al prefijo anunciado.
- **RDNSS** (RFC 8106) → anuncia el gateway IPv6 de la VLAN como recursor DNS (`fd00:0:0:10::1`, etc.).
- **DNSSL** → publica `biblioteca.tel` como dominio de búsqueda.
- **Default lifetime 1800 s** → tiempo de vida del router para los clientes; si radvd cae, los clientes pierden ruta default IPv6 después de ese tiempo.
- **Min/Max RTR Interval 30–100 s** → entre RAs no solicitados; clientes nuevos que envían Router Solicitation reciben respuesta inmediata.

**`AdvManagedFlag off` + `AdvOtherConfigFlag off`** → los clientes NO buscan DHCPv6 (ni para dirección ni para opciones). Todo viene por SLAAC + RDNSS.

Verificar:
```bash
sudo systemctl status radvd
sudo timeout 6 tcpdump -i enp171s0.30 -nn icmp6 and 'ip6[40] == 134'
```

### 3.3 DNS dual-stack y DNS64 (Mini PC, BIND 9.18)

**Rol:** `minipc/router-setup/roles/dns/`
**Plantillas:** `roles/dns/templates/{named.conf.options.j2,db.forward.j2}`

#### Listen addresses

```
listen-on    { 127.0.0.1; 192.168.10.1; 192.168.20.1; 192.168.30.1; };
listen-on-v6 { ::1; fd00:0:0:10::1; fd00:0:0:20::1; fd00:0:0:30::1; };
```

#### allow-recursion / allow-query

Incluye explícitamente las redes IPv4 (192.168.{10,20,30}.0/24) e IPv6 (fd00:0:0:{10,20,30}::/64). El recursor responde a cualquier cliente legítimo de cualquier VLAN por IPv4 o IPv6.

#### DNS64

Configurado **dentro del bloque `options { }`** (esto es importante: BIND9 no acepta `dns64` a nivel raíz):

```
dns64 64:ff9b::/96 {
    clients { any; };
    mapped {
        !10.0.0.0/8;
        !172.16.0.0/12;
        !192.168.0.0/16;
        any;
    };
    exclude {
        !fd00::/8;
        any;
    };
};
```

**Significado de cada ACL:**

| ACL | Qué controla | Lógica aplicada |
|---|---|---|
| `clients` | Qué clientes activan DNS64 | Todos |
| `mapped` | Qué IPv4 (en respuestas A) se prestan a síntesis | Excluye RFC1918: hosts internos IPv4-only NO devuelven AAAA sintético |
| `exclude` | Qué IPv6 reales se ignoran (y se sintetizan en su lugar) | Excluye ULA: AAAA autoritativos locales (RPi, etc.) NO se sobrescriben con sintéticos |

#### Por qué `exclude { !fd00::/8; any; }` y no `exclude { any; }`

**Bug encontrado durante el despliegue:** con `exclude { any; }`, BIND9 reemplazaba TODOS los AAAA reales con sintéticos, **incluyendo los autoritativos locales**. La query `biblioteca.tel AAAA` devolvía `64:ff9b::c0a8:140a` (192.168.20.10 traducida) en vez del `fd00:0:0:20::10` real.

Con `!fd00::/8; any;` se excluye explícitamente la ULA → las AAAA locales se preservan y solo los AAAA reales del internet público se reemplazan (para forzar el path NAT64).

#### Por qué `mapped` excluye RFC1918

Si un host interno (ej. `switch.biblioteca.tel`, `192.168.10.2`) sólo tiene registro A, sin la exclusión BIND sintetizaría `AAAA 64:ff9b::c0a8:0a02`. Un cliente IPv6-only intentaría conectar ahí, Jool intentaría traducir a `192.168.10.2`, y todo el flujo se desvía innecesariamente por NAT64 para algo que es local. La exclusión deja que el cliente caiga limpiamente a IPv4 (Happy Eyeballs).

#### Zona `biblioteca.tel` con AAAA

`db.forward.j2` recorre `dns_hosts` y emite registros A y AAAA. Hosts actuales con AAAA: `minipc`, `ns1`, `biblioteca`, `rpi`. El apex (`@`) también tiene `A 192.168.20.10` + `AAAA fd00:0:0:20::10` → `http://biblioteca.tel` y `http://[fd00:0:0:20::10]/` resuelven ambos al servicio de la RPi.

### 3.4 DNS secundario en RPi

**Rol:** `raspberry/rpi-setup/roles/dns_secondary/`

BIND9 esclavo de las zonas en VLAN20. Tras el cambio:
- `listen-on { 127.0.0.1; 192.168.20.10; }`
- `listen-on-v6 { ::1; fd00:0:0:20::10; }`
- `allow-recursion`/`allow-query` incluyen `fd00::/8`
- `forwarders` incluye `192.168.10.1` + `fd00:0:0:10::1`

Las zonas slave (`biblioteca.tel`, `10.168.192.in-addr.arpa`, etc.) siguen pulled desde el master por IPv4 (`masters { 192.168.20.1; }`); no se requirió cambio porque el AXFR funciona igual.

### 3.5 NAT64 (Jool)

**Configuración:** ya estaba desplegada antes de este trabajo, no se modificó.

- Módulo kernel: `jool` (DKMS, cargado en boot vía `/etc/modules-load.d/jool.conf`)
- Servicio systemd: `jool-nat64.service`
  - `ExecStart=/usr/bin/jool instance add default --netfilter --pool6 64:ff9b::/96`
- Modo: `--netfilter` → Jool se engancha como netfilter hook (`PREROUTING`, alta prioridad)
- Pool6: `64:ff9b::/96` (RFC 6052 well-known prefix)
- Pool4: no configurado explícitamente → Jool toma direcciones IPv4 del propio router para el SNAT de salida

**Flujo de un paquete IPv6 → IPv4:**

```
Cliente IPv6 (fd00:0:0:30::abc) envía a 64:ff9b::8.8.8.8 (DNS64-sintetizado)
    ↓
Llega a enp171s0.30 del Mini PC
    ↓
NF_INET_PRE_ROUTING (Jool hook, alta prioridad)
    Jool traduce: 
      src IPv6 → src IPv4 (del pool del router)
      dst 64:ff9b::8.8.8.8 → dst 8.8.8.8
    ↓
Continúa como paquete IPv4 nativo
    ↓
Routing decision → sale por enp170s0
    ↓
nftables ip nat postrouting: masquerade
    ↓
Internet IPv4

Respuesta IPv4 entra → Jool sintetiza IPv6 inverso → cliente
```

Estado y stats:
```bash
sudo jool instance display
sudo jool stats display
```

### 3.6 nftables

**Plantilla:** `minipc/router-setup/roles/firewall/templates/nftables.conf.j2`
(el rol `firewall` es la única fuente del `/etc/nftables.conf` desplegado)

#### Tabla `inet filter` (IPv4 + IPv6)

La tabla `inet` opera sobre ambos protocolos. Las reglas existentes ya gobiernan IPv6:

- **input:** `ip6 nexthdr ipv6-icmp accept` permite ICMPv6 (NDP, RA, etc.).
- **forward:** `ct state established,related accept` + reglas por VLAN. La política `drop` aplica a IPv6 unauth.
- **captive_mangle:** match en `ether saddr` → marca `0x1` cubre IPv4 y IPv6 del mismo MAC indistintamente.

#### Tabla `ip nat` (IPv4)

Sin cambios respecto al pre-dual-stack:
- DNS DNAT a `192.168.10.1:53` para todas las VLANs.
- Portal cautivo HTTP DNAT IPv4.
- Masquerade en `enp170s0`.

#### Tabla `ip6 nat` (IPv6) — **NUEVA**

```
table ip6 nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iif { enp171s0.10, enp171s0.20, enp171s0.30 } udp dport 53 dnat to [fd00:0:0:10::1]:53
        iif { enp171s0.10, enp171s0.20, enp171s0.30 } tcp dport 53 dnat to [fd00:0:0:10::1]:53
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
    }
}
```

**Propósito:** redirigir cualquier query DNS IPv6 saliente (incluso si el cliente hardcodea DNS público como `2001:4860:4860::8888`) al Bind9 local con DNS64. Esto garantiza que la síntesis de AAAA siempre suceda — sin este DNAT, un cliente apuntando a Google DNS directo recibiría AAAA reales que serían inalcanzables (sin WAN IPv6) y no se beneficiaría de NAT64.

**Sin postrouting masquerade IPv6** — no hay WAN IPv6, todo tráfico saliente pasa por Jool que lo convierte en IPv4 antes de salir.

### 3.7 IPv6 forwarding

```
net.ipv6.conf.all.forwarding = 1
```

Aplicado vía `ansible.posix.sysctl` en `roles/router/tasks/main.yml`. Persistente. Habilita el reenvío de paquetes IPv6 entre interfaces, prerrequisito para que radvd opere y Jool funcione.

---

## 4. Flujos de tráfico

### 4.1 Cliente dual-stack visita un sitio con A y AAAA

Ejemplo: `github.com` (tiene A y AAAA reales)

```
1. Cliente DNS query AAAA + A en paralelo (Happy Eyeballs)
2. DNS query IPv6 a fd00:0:0:10::1 (RDNSS)
   → nftables ip6 nat DNAT (no-op, ya va al destino correcto)
   → Bind9 forward a 8.8.8.8 → AAAA real recibida
   → DNS64 exclude { any; }: AAAA real NO matchea fd00::/8 → es replaced con sintético
   → Cliente recibe AAAA = 64:ff9b::<github_ipv4>
3. Cliente DNS query A a 192.168.10.1 (DHCP option)
   → Cliente recibe A = <github_ipv4>
4. Happy Eyeballs: típicamente prefiere IPv6 → intenta 64:ff9b::<github_ipv4>
   → Jool traduce → IPv4 nativo → respuesta vía NAT64
   → Funciona, pero con la latencia extra de la traducción
   (También podría caer a A directo según implementación del SO)
```

### 4.2 Cliente IPv6-only visita sitio IPv4-only

Ejemplo: hipotético `legacy.example.com` (sólo A)

```
1. Cliente DNS query AAAA a fd00:0:0:10::1
2. Bind9 hace lookup AAAA → no existe → mira A → 1.2.3.4
3. DNS64: 1.2.3.4 NO matchea RFC1918 (no es interno) → mapped permite síntesis
   → Devuelve 64:ff9b::1.2.3.4 (= 64:ff9b::102:304)
4. Cliente conecta a 64:ff9b::102:304
5. Jool traduce a 1.2.3.4
6. Masquerade en WAN → internet IPv4
```

### 4.3 Cliente visita biblioteca.tel (servicio local)

```
1. Cliente DNS query AAAA y A
2. Bind9 es autoritativo de biblioteca.tel
   → A = 192.168.20.10
   → AAAA = fd00:0:0:20::10
3. DNS64 ve AAAA real fd00:0:0:20::10 → matchea !fd00::/8 → NO se reemplaza
   → Devuelve AAAA real
4. Cliente intenta IPv6 nativo dentro de la LAN → llega directo a la RPi
   → SIN pasar por Jool, SIN traducción, latencia mínima
```

### 4.4 Cliente VLAN30 NO autenticado intenta navegar

```
1. SLAAC le da IPv6, DHCP le da IPv4
2. Cliente abre browser → DNS query AAAA + A para algun.sitio
3. Recibe AAAA (sintetizado vía DNS64) y A real
4. Intenta IPv6 a 64:ff9b::x.y.z.w
   → Jool traduce → forward chain (inet filter)
   → Tráfico IPv4 ahora, mark != 0x1 → DROP (policy)
5. Intenta IPv4 a x.y.z.w
   → forward chain: mark != 0x1 + dport 443 → tcp reset (instantáneo)
   → forward chain: mark != 0x1 + dport 80 → DNAT a 192.168.30.1:2050 (portal)
6. Browser muestra portal cautivo
7. Usuario acepta → handler agrega MAC al set captive_allowed_mac
8. captive_mangle marca 0x1 a TODO tráfico (v4 y v6) de ese MAC en adelante
9. Ahora navegación funciona en ambos protocolos
```

**Implicación importante:** el portal cautivo funciona en clientes dual-stack **sin código IPv6 nuevo**. El match en `ether saddr` opera en L2 y cubre ambas familias. La autenticación se hace por IPv4 (DNAT del portal solo en `ip nat`), pero una vez autorizado el MAC, ambos protocolos pasan.

---

## 5. Cómo verificar el dual-stack

### 5.1 Servicios activos en Mini PC

```bash
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134

systemctl is-active radvd named nftables kea-dhcp4-server jool-nat64
# Esperado: active (todos)

cat /proc/sys/net/ipv6/conf/all/forwarding
# Esperado: 1

sudo jool instance display
# Esperado: una instancia "default" con pool6 64:ff9b::/96
```

### 5.2 Bind9 escuchando IPv6

```bash
sudo ss -lnp -A inet6 sport = :53
# Esperado: sockets en [::1], [fd00:0:0:10::1], [fd00:0:0:20::1], [fd00:0:0:30::1]
```

### 5.3 nftables IPv6 NAT activo

```bash
sudo nft list table ip6 nat
# Esperado: prerouting con DNAT UDP/TCP 53 → [fd00:0:0:10::1]:53
```

### 5.4 radvd emitiendo RAs

```bash
sudo timeout 6 tcpdump -i enp171s0.30 -nn icmp6 and 'ip6[40] == 134'
# Esperado: al menos 1 paquete dentro de 100s desde fe80::<minipc> a ff02::1
```

### 5.5 Resolución DNS

```bash
# AAAA local — NO debe pasar por DNS64
dig @::1 +short AAAA biblioteca.tel
# Esperado: fd00:0:0:20::10 (NO 64:ff9b::...)

# AAAA externo — DEBE sintetizar
dig @::1 +short AAAA ipv4.google.com
# Esperado: 64:ff9b::<hex de la IPv4>

# A interno IPv4-only — AAAA debe estar vacío
dig @::1 +short AAAA switch.biblioteca.tel
# Esperado: vacío (DNS64 no sintetiza por exclusión mapped)
```

### 5.6 NAT64 end-to-end (desde RPi u otro cliente)

```bash
# Desde la RPi:
ping6 -c 3 64:ff9b::8.8.8.8
# Esperado: respuestas con RTT ~10-20ms

curl -6 -v http://ipv4.google.com 2>&1 | grep -E "(Connected to|HTTP/)"
# Esperado: Connected to ipv4.google.com (64:ff9b::xxxx:yyyy) port 80
#           HTTP/1.1 200 OK
```

### 5.7 SLAAC en cliente

```bash
# En la RPi (o cualquier cliente):
ip -6 addr show dev eth0
# Esperado: una dirección global "scope global" derivada del prefijo fd00:0:0:20::/64
# Además de fd00:0:0:20::10 (estática) y fe80::... (link-local)

ip -6 route show default
# Esperado: default via fe80::<minipc-eui64> dev eth0 proto ra
```

---

## 6. Cambios de Ansible — referencia rápida

### 6.1 Mini PC — `minipc/router-setup/`

**Roles nuevos:**
- `roles/radvd/`
  - `vars/main.yml` — VLANs, intervalos, RDNSS, DNSSL
  - `tasks/main.yml` — instala radvd, despliega config, valida activo
  - `templates/radvd.conf.j2` — un bloque `interface` por VLAN
  - `handlers/main.yml` — restart radvd

**Roles modificados:**
- `roles/dns/vars/main.yml` — añadido `dns_listen_ips_v6`, `dns_allow_query_v6`, `dns64_prefix`, `ipv6` por host, `dns_slave_ipv6`
- `roles/dns/templates/named.conf.options.j2` — `listen-on-v6` dinámico, allow-recursion/query IPv6, bloque `dns64`
- `roles/dns/templates/db.forward.j2` — loop AAAA, apex con AAAA, NS con AAAA
- `roles/router/templates/nftables.conf.j2` — añadido `table ip6 nat` con DNS DNAT
- `playbook.yml` — añadido rol `radvd` después de `dns`

**Servicios standalone:**
- `services/radvd.yml`

**Despliegue:**
```bash
cd minipc/
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags router,dns,radvd
# o solo radvd:
ansible-playbook -i router-setup/inventory.ini services/radvd.yml
```

### 6.2 RPi — `raspberry/rpi-setup/`

**Roles nuevos:**
- `roles/network_ipv6/`
  - `tasks/main.yml` — backup netplan, deploy drop-in, netplan apply, verifica IPv6
  - `templates/60-ipv6.yaml.j2` — drop-in agregando `fd00:0:0:20::10/64` a eth0

**Roles modificados:**
- `group_vars/all.yml` — añadido `rpi_ipv6`, `dns_primary_ipv6`, `dns_slave_listen_ips_v6`
- `roles/dns_secondary/templates/named.conf.options.j2` — `listen-on-v6` desde vars, forwarder IPv6, allow para `fd00::/8`
- `playbook.yml` — `network_ipv6` añadido como primer rol

**Servicios standalone:**
- `services/network_ipv6.yml`

**Despliegue:**
```bash
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini rpi-setup/playbook.yml
# o partes:
ansible-playbook -i rpi-setup/inventory.ini services/network_ipv6.yml
ansible-playbook -i rpi-setup/inventory.ini services/dns_secondary.yml
```

---

## 7. Decisiones de diseño y gotchas importantes

### 7.1 No hay DHCPv6

**Decisión:** se usa SLAAC + RDNSS (RFC 8106) en vez de DHCPv6 stateful o stateless.

**Razones:**
- Simplicidad operativa: un servicio menos (radvd) en vez de dos (radvd + kea-dhcp6).
- Compatibilidad: RDNSS en RA está soportado por Linux, macOS, Windows 10+, iOS, Android.
- Sin estado: no hay base de leases que sincronizar o mantener.

**Implicación:** los clientes obtienen direcciones SLAAC (EUI-64 o privacy random según el SO). No hay forma fácil de asignar una IPv6 fija a un cliente por su MAC sin DHCPv6. Hosts importantes (RPi) usan **dirección estática** vía netplan.

### 7.2 ULA en vez de prefijo global

**Decisión:** se usa `fd00::/8` (RFC 4193 ULA) en vez de un prefijo IPv6 global.

**Razón:** el uplink WAN (`172.16.0.0/16`) es IPv4-only y RFC1918 — no hay forma de obtener un prefijo IPv6 global del ISP por ahora.

**Consecuencia:** internet IPv6-only no es alcanzable nativamente. Se mitiga con DNS64 + NAT64 para el caso común (sitios con doble stack o IPv4-only).

**Si en el futuro hay IPv6 global** (DHCPv6-PD del upstream, túnel Hurricane Electric, etc.): se debería renumerar las VLANs al nuevo prefijo, actualizar `roles/radvd/vars/main.yml` y `roles/router/vars/main.yml`, y considerar si mantener Jool (puede convivir, queda como fallback para destinos exclusivamente IPv4).

### 7.3 `dns64` va DENTRO de `options { }`

**Gotcha confirmada durante deploy:** la sintaxis de BIND 9.18 requiere que la declaración `dns64 prefix { ... };` esté **dentro del bloque `options { }`**, no a nivel raíz. El primer intento fallaba con `unknown option 'dns64'`.

### 7.4 `exclude { any; }` rompe AAAA locales

**Gotcha confirmada:** con `exclude { any; }`, BIND9 reescribe TODOS los AAAA reales (incluyendo los autoritativos) con sintéticos. La query `biblioteca.tel AAAA` devolvía `64:ff9b::c0a8:140a` en vez del real `fd00:0:0:20::10`.

**Fix:** `exclude { !fd00::/8; any; };` — preserva los AAAA en ULA, reemplaza los demás.

### 7.5 `mapped` debe excluir RFC1918

**Razón:** sin esa exclusión, hosts internos solo-IPv4 (ej. `switch.biblioteca.tel = 192.168.10.2`) generan AAAA sintéticos hacia `64:ff9b::c0a8:0a02`. Un cliente intentaría llegar por NAT64, lo cual es absurdo (es local). Excluir RFC1918 deja que el cliente caiga a IPv4 directo.

### 7.6 Captive portal sigue siendo IPv4

**Por qué funciona en clientes dual-stack:** el match clave (`ether saddr @captive_allowed_mac`) está en L2 → cubre IPv4 y IPv6. Solo el flujo de autenticación (visita inicial al portal HTTP) ocurre por IPv4, después la marca `0x1` aplica a ambos protocolos.

**Cliente IPv6-only no podría autenticarse hoy** — el portal solo intercepta IPv4 HTTP. Si en el futuro se quiere soporte completo, hay que:
- Añadir DNAT IPv6 HTTP en `table ip6 nat`
- Adaptar el `captive-accept.service` handler para hacer lookup por NDP (`ip -6 neigh`) en vez de ARP

### 7.7 La RPi tiene 2 IPv6 simultáneas

Por diseño:
- `fd00:0:0:20::10/64` — estática (netplan), usada para AAAA records
- `fd00::20:2ecf:67ff:fed2:f098/64` — SLAAC (autoconfigurada porque `accept-ra: true`)

No interfieren. Ambas funcionan. Las conexiones entrantes a la estática usan esa; las salientes pueden usar cualquiera (el kernel elige por RFC 6724).

Si se quisiera **solo** la estática, en el drop-in cambiar `accept-ra: false` (perdería ruta default IPv6 si radvd cae, habría que poner ruta estática también).

### 7.8 El Mini PC no puede ping6 64:ff9b::

Jool intercepta tráfico **forwarded**, no el originado en el propio router. Esto es comportamiento normal de Jool en modo `--netfilter` y no afecta a los clientes. Para validar NAT64 hay que probar desde una VLAN (RPi sirve perfecto).

### 7.9 Restart de nftables borra el set de MACs autenticadas

`/etc/nftables.conf` empieza con `flush ruleset`. Cuando Ansible recarga nftables, todos los clientes VLAN30 autenticados pierden la marca y deben reautenticarse. Es aceptable en cambios programados; tener presente al redesplegar.

---

## 8. Limitaciones conocidas

| # | Limitación | Impacto | Workaround / futuro |
|---|---|---|---|
| 1 | Sin IPv6 global en WAN | No se alcanzan sitios IPv6-only del internet | NAT64 cubre el 95% (sitios con A). Para el resto: conseguir prefijo del upstream o túnel HE.net |
| 2 | Sin DHCPv6 | No se pueden asignar IPv6 fijas por MAC (excepto vía estática) | Hosts críticos con netplan estático. Para servidores se asume gestión manual |
| 3 | Captive portal no autentica IPv6-only | Cliente puramente IPv6 no puede pasar el portal hoy | Clientes dual-stack típicos autentican vía IPv4 sin notar diferencia |
| 4 | DNS64 fuerza NAT64 incluso si hay AAAA real upstream | Latencia extra (~5-15ms) en sitios con IPv6 nativo público | Aceptado conscientemente: la alternativa (AAAA reales) sería irruteable |
| 5 | Reload nftables flushea sesiones de portal | Usuarios reautentican | Operacional; ya documentado en CAPTIVE-PORTAL.md |

---

## 9. Troubleshooting

### Cliente no obtiene IPv6 vía SLAAC

```bash
# En el Mini PC: ¿radvd corriendo?
systemctl status radvd

# ¿Forwarding habilitado?
cat /proc/sys/net/ipv6/conf/all/forwarding

# ¿Capturar RAs en la VLAN del cliente?
sudo tcpdump -i enp171s0.30 -nn icmp6 and 'ip6[40] == 134'

# En el cliente: ¿accept_ra activo?
cat /proc/sys/net/ipv6/conf/<iface>/accept_ra
# Debe ser 1 o 2
```

### DNS64 no sintetiza

```bash
# Verificar que la config DNS64 esté cargada:
sudo named-checkconf /etc/bind/named.conf
sudo grep -A 15 "dns64" /etc/bind/named.conf.options

# Probar query directa:
dig @::1 +short AAAA ipv4.google.com
# Si vacío: el sitio podría tener AAAA real upstream y exclude no estar matcheando — revisar logs

sudo journalctl -u named -n 50 | grep -i dns64
```

### NAT64 no traduce

```bash
# Módulo cargado?
lsmod | grep jool

# Instancia activa?
sudo jool instance display

# Stats — ¿hay traducciones?
sudo jool stats display | grep -i success

# ¿Hay errores recientes?
dmesg | grep -i jool | tail -20

# Probar desde un cliente (no desde el router):
ping6 -c 3 64:ff9b::8.8.8.8
```

### Bind9 no escucha en IPv6

```bash
sudo ss -lnp -A inet6 sport = :53

# Si solo aparece ::1 y no las VLANs:
# 1. Verificar que las interfaces VLAN tengan la IPv6 asignada
ip -6 addr show

# 2. Verificar que named arranque DESPUÉS de las interfaces (raro, pero posible)
sudo systemctl restart named
```

### Cliente VLAN30 IPv6 no llega al internet

```bash
# 1. ¿Tiene ruta default IPv6?
ip -6 route show default
# Debe apuntar a fe80::<minipc> dev <iface>

# 2. ¿Está autenticado en captive?
sudo nft list set inet filter captive_allowed_mac
# Su MAC debe estar listada

# 3. ¿Jool traduce su tráfico?
sudo jool stats display
# Counters de "v6 → v4" deberían incrementar al hacer ping6 64:ff9b::8.8.8.8

# 4. ¿Forward chain lo deja pasar?
sudo nft list chain inet filter forward
# Debe haber rule "iif vlan30 oif wan meta mark 0x1 accept"
```

---

## 10. Referencias

- RFC 4193 — Unique Local IPv6 Unicast Addresses
- RFC 4861 — Neighbor Discovery for IPv6
- RFC 4862 — IPv6 Stateless Address Autoconfiguration (SLAAC)
- RFC 6052 — IPv6 Addressing of IPv4/IPv6 Translators (define `64:ff9b::/96`)
- RFC 6146 — Stateful NAT64
- RFC 6147 — DNS64
- RFC 6724 — Default Address Selection for IPv6
- RFC 8106 — IPv6 Router Advertisement Options for DNS Configuration (RDNSS, DNSSL)
- BIND 9.18 ARM — sección "options" → "DNS64"
- Jool documentation — https://nicmx.github.io/Jool/en/index.html
- radvd man page — `man 5 radvd.conf`

---

## 11. Historial

| Fecha | Cambio | Autor |
|---|---|---|
| 2026-05-25 | Despliegue inicial dual-stack (radvd, DNS64, nftables ip6 nat, RPi IPv6 estática) | Equipo Pacific Edge + Claude |
