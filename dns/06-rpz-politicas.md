# 06 · RPZ: políticas de respuesta (bloqueo de contenido + modo offline)

> Bonus, pero parte real del despliegue DNS de este proyecto. RPZ convierte a BIND en un
> "firewall de DNS". Aquí se usa para **dos** cosas: bloquear porn/gambling siempre, y
> dar una experiencia decente cuando se cae el WAN.

---

## 6.1 ¿Qué es RPZ?

**RPZ (Response Policy Zone)** es un mecanismo de BIND para **reescribir respuestas DNS
según políticas**, expresadas como una zona DNS normal. En vez de responder lo que dicen
los datos reales, el resolver consulta una "zona de políticas" y, si hay coincidencia,
**modifica la respuesta**: la bloquea (`NXDOMAIN`), la redirige a otra IP, la deja pasar
(`PASSTHRU`), etc.

Ventaja sobre filtrar por IP/puerto en el firewall: actúa **a nivel de nombre**, antes de
que se establezca cualquier conexión, y **cubre HTTP y HTTPS por igual** (no necesita ver
el contenido cifrado: si el nombre no resuelve, no hay conexión). Es la base de los
"DNS sinkholes" y de servicios como Pi-hole.

### Acciones RPZ típicas (cómo se escriben en la zona de políticas)
| Quieres… | Registro en la zona RPZ |
|---|---|
| Bloquear → NXDOMAIN | `mal.com  CNAME  .` (CNAME al root pelado) |
| Redirigir a una IP | `mal.com  A  192.168.30.1` |
| Dejar pasar (excepción) | `bueno.com  CNAME  rpz-passthru.` |
| Responder NODATA | `mal.com  CNAME  *.` |

La zona se activa con un bloque `response-policy { zone "..."; };` en `options`.

---

## 6.2 Las dos RPZ de este proyecto

En `named.conf.options` (al final):
```bind
include "/etc/bind/named.conf.rpz";
```
Ese archivo se alterna entre dos versiones según el estado del WAN:

```bind
// named.conf.rpz.enabled  (WAN CAÍDO)
response-policy {
    zone "rpz.offline";       // primero: manda todo al portal
    zone "rpz.blocklist";     // y sigue bloqueando porn/gambling
} qname-wait-recurse no;

// named.conf.rpz.disabled  (WAN OK)
response-policy {
    zone "rpz.blocklist";     // solo bloqueo permanente
} qname-wait-recurse no;
```

- **El orden importa:** `rpz.offline` va primero para que, sin WAN, todo caiga al portal
  cautivo (excepto lo que el offline deje pasar).
- `qname-wait-recurse no` = aplica la política **sin** esperar a resolver recursivamente
  primero (más rápido, no hace falta resolver de verdad un dominio que vas a reescribir).
- `rpz.blocklist` **está activa en ambos casos** → el bloqueo de contenido nunca se apaga.

`wan-check.sh` (un timer cada ~15 s, definido en el rol `router`) **copia** el `.enabled`
o el `.disabled` sobre `/etc/bind/named.conf.rpz` y recarga BIND, según haya o no
internet.

---

## 6.3 `rpz.blocklist` — bloqueo permanente de porn + gambling

Zona master local en `/etc/bind/zones/rpz.blocklist.zone`. Declarada en
`named.conf.local`:
```bind
zone "rpz.blocklist" { type master; file ".../rpz.blocklist.zone"; allow-query { none; }; allow-transfer { none; }; };
```
- `allow-query { none; }` → nadie consulta la zona de políticas directamente; solo el
  motor RPZ la usa internamente. Igual `allow-transfer { none; }`: no se replica al slave.

### Cómo se genera el contenido (`/usr/local/sbin/update-bind-rpz`)
Script (en `roles/dns/files/update-bind-rpz`) que corre por un **timer systemd los
domingos 03:00** (`bind-rpz-update.timer`). Hace:

1. Descarga dos listas de **StevenBlack/hosts**: `porn-only` y `gambling-only`.
2. Extrae los dominios (`awk '/^0\.0\.0\.0/ {print $2}'`), limpia entradas raras y
   ordena único.
3. **Sanity-check:** si hay menos de 1000 dominios (descarga corrupta), **aborta y
   conserva la zona anterior** (no se queda sin bloqueo por un fallo de red).
4. Genera la zona con **serial = epoch** y, crucial, un **PASSTHRU para lo local**:
   ```dns
   biblioteca.tel    CNAME  rpz-passthru.
   *.biblioteca.tel  CNAME  rpz-passthru.
   ```
   → la biblioteca **nunca** se bloquea por accidente.
5. Cada dominio bloqueado se escribe como:
   ```dns
   ejemplo.com     CNAME  .      ; → NXDOMAIN
   *.ejemplo.com   CNAME  .      ; → también los subdominios
   ```
6. **Valida con `named-checkzone`** antes de instalar; si falla, conserva la anterior.
7. Si no cambió nada, no recarga. Si cambió, instala y hace `rndc reload rpz.blocklist`.

Tamaño actual: ~82.800 dominios. El **bootstrap** inicial lo hace el rol Ansible
(`/var/lib/bind-rpz-bootstrap.done` marca que ya corrió la primera vez).

> Por qué `CNAME .` = NXDOMAIN: es la convención RPZ. Un CNAME al **root pelado** (`.`)
> le dice al motor RPZ "responde como si el nombre no existiera".

---

## 6.4 `rpz.offline` — experiencia decente sin internet

Zona en `/etc/bind/zones/rpz.offline.zone` (template `rpz.offline.zone.j2`):
```dns
$TTL 5
@   IN SOA ns1.biblioteca.tel. admin.biblioteca.tel. ( 1 3600 600 86400 5 )
@   IN NS  ns1.biblioteca.tel.

; Passthru: lo local resuelve normal
biblioteca.tel        CNAME  rpz-passthru.
*.biblioteca.tel      CNAME  rpz-passthru.

; Todo lo demás → Mini PC VLAN30 (portal)
*                     A      192.168.30.1
```

Lógica: cuando **no hay WAN**, el `wan-check.sh` activa el `.enabled` y esta zona hace que
**cualquier** dominio externo (`*`) resuelva a `192.168.30.1` (nginx del portal en la
VLAN 30). Así el navegador del cliente, en vez de un *timeout* feo de DNS, llega a nginx y
ve una página "offline" / la biblioteca local. `biblioteca.tel` queda excluido (passthru)
para que la biblioteca siga 100% accesible sin internet.

- `$TTL 5` (5 segundos) → respuestas casi sin caché, para que al **volver** el WAN los
  clientes dejen de ir al portal rápidamente.
- Serial fijo en `1` → la zona es estática, no necesita versionarse (no se replica ni
  cambia su contenido).

---

## 6.5 Operación y verificación de RPZ

```bash
# Estado de las zonas RPZ
sudo rndc zonestatus rpz.blocklist
sudo rndc zonestatus rpz.offline

# Probar el bloqueo (un dominio de gambling) → NXDOMAIN
dig @192.168.10.1 bet365.com +short            # → (vacío) / NXDOMAIN
dig @192.168.10.1 google.com +short            # → resuelve normal (no bloqueado)
dig @192.168.10.1 biblioteca.tel +short        # → 192.168.20.10 (passthru, nunca bloqueado)

# Forzar actualización de la blocklist ahora
sudo systemctl start bind-rpz-update.service
journalctl -u bind-rpz-update.service --no-pager | tail

# Ver cuál RPZ está activa ahora mismo (offline o no)
sudo cat /etc/bind/named.conf.rpz              # ¿incluye rpz.offline?

# Ver el timer de actualización semanal
systemctl list-timers bind-rpz-update.timer
```

Cómo saber que una respuesta fue **reescrita por RPZ**: en los logs de queries de BIND
aparece `rpz ... rewrite`. También, un dominio bloqueado da `NXDOMAIN` desde *tu*
resolver pero resuelve normal desde `8.8.8.8` directo — esa diferencia confirma que el
bloqueo es local (RPZ), no del dominio.

### Añadir tu propia excepción o bloqueo manual
- **Para que algo NUNCA se bloquee:** el script ya hace passthru de `biblioteca.tel`. Si
  necesitas exceptuar otro dominio, lo más limpio es una **tercera zona RPZ** de
  "allowlist" puesta **antes** de `rpz.blocklist` en `response-policy`, con
  `dominio CNAME rpz-passthru.`. (No edites a mano `rpz.blocklist.zone`: el script lo
  regenera y borra tu cambio.)
- **Para bloquear algo extra de forma permanente:** igual, una zona RPZ propia
  (`rpz.local`) gestionada por el rol, no editar la generada.

---

## 6.6 Relación de RPZ con DNSSEC (un detalle fino)

RPZ **reescribe** respuestas; eso es, por definición, "falsificar" datos desde el punto de
vista de un validador DNSSEC. Por eso:
- Un dominio externo **firmado** que RPZ redirige/bloquea **no validará** DNSSEC (porque
  el dato fue alterado por la política). BIND lo sabe y trata las respuestas RPZ de forma
  especial; los clientes que validan estrictamente podrían ver SERVFAIL en un dominio
  reescrito. Para una red comunitaria con clientes normales (navegadores que no validan
  por su cuenta, confían en el resolver) esto no causa problemas prácticos.
- Nuestra zona local `biblioteca.tel` está en **passthru** en ambas RPZ → nunca se
  reescribe → su DNSSEC local sigue validando con `AD`. Coherente.

---

## Resumen de este archivo

- **RPZ** = firewall de DNS: reescribe respuestas según una zona de políticas; cubre HTTP
  y HTTPS porque actúa sobre el **nombre**.
- Dos políticas: **`rpz.blocklist`** (porn+gambling, siempre activa, generada desde
  StevenBlack/hosts por un script con sanity-check + validación) y **`rpz.offline`**
  (sin WAN, manda todo a `192.168.30.1`).
- `wan-check.sh` alterna `named.conf.rpz` entre `.enabled`/`.disabled`. `biblioteca.tel`
  siempre en **passthru**.
- Para personalizar, usa **zonas RPZ propias gestionadas por el rol**, no edites las
  generadas.

Sigue con [`07-operacion-troubleshooting.md`](07-operacion-troubleshooting.md).
