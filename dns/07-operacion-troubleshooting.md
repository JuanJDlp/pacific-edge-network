# 07 · Operación y troubleshooting: la chuleta de manos a la obra

> Todo lo anterior aterrizado en comandos. Esta es la página que vas a tener abierta
> cuando algo falle o cuando quieras demostrar que funciona. Empieza por las
> herramientas, sigue por "verificar todo en orden", y termina en el árbol de fallos.

---

## 7.1 Las cuatro herramientas que tienes que dominar

| Herramienta | Para qué | Dónde corre |
|---|---|---|
| **`dig`** | hacer consultas DNS y leer la respuesta cruda | cualquier cliente/servidor |
| **`rndc`** | controlar BIND en caliente (reload, status, zonestatus, dnssec) | en el servidor BIND |
| **`named-checkconf` / `named-checkzone`** | validar config y zonas **antes** de recargar | en el servidor |
| **`delv`** | como `dig` pero hace la **validación DNSSEC** y te la explica | cliente/servidor |

### `dig` — anatomía de un comando
```bash
dig @SERVIDOR  NOMBRE  TIPO  [opciones]
dig @192.168.10.1  biblioteca.tel  A  +short
```
Opciones que usarás siempre:
- `+short` → solo la respuesta, sin ruido.
- `+dnssec` → pide DNSSEC y muestra RRSIG + el bit `ad`.
- `+multiline` → registros largos (DNSKEY, SOA) legibles.
- `+trace` → simula la resolución iterativa desde la raíz (no útil con `forward only`).
- `+norecurse` / `+cd` → sin recursión / sin validación (diagnóstico DNSSEC).
- `-x IP` → consulta **inversa** (PTR).
- `-y algo:nombre:secret` → firma la consulta con **TSIG** (para AXFR).

### `rndc` — control remoto del demonio
```bash
sudo rndc status                       # visión general (zonas, queries, etc.)
sudo rndc reload                       # recarga toda la config + zonas
sudo rndc reload biblioteca.tel        # recarga solo una zona
sudo rndc reconfig                     # relee config sin recargar zonas no cambiadas
sudo rndc zonestatus biblioteca.tel    # serial, tipo, secure (DNSSEC), última carga
sudo rndc retransfer biblioteca.tel    # (en el slave) re-pide la zona al master
sudo rndc dnssec -status biblioteca.tel# estado de claves/firmado DNSSEC
sudo rndc flush                        # vacía la caché del recursivo
```

---

## 7.2 Verificación completa, en orden (el "todo funciona" de cabo a rabo)

Corre esto para confirmar que **toda la pila** está sana. Ideal para una sustentación.

```bash
# ── A. El servicio está vivo y escuchando ────────────────────────────────────
ssh minipc
systemctl status named
sudo ss -tulnp 'sport = :53'         # named en .10.1/.20.1/.30.1, TCP y UDP

# ── B. Resolución directa (autoritativa) ──────────────────────────────────────
dig @192.168.10.1 biblioteca.tel +short            # → 192.168.20.10
dig @192.168.10.1 wikipedia.biblioteca.tel +short  # → CNAME biblioteca → 192.168.20.10
dig @192.168.10.1 minipc.biblioteca.tel +short     # → 192.168.10.1

# ── C. Resolución inversa (PTR) ────────────────────────────────────────────────
dig @192.168.10.1 -x 192.168.20.10 +short          # → biblioteca.biblioteca.tel.

# ── D. Forwarding externo (recursivo) ──────────────────────────────────────────
dig @192.168.10.1 google.com +short                # → IPs reales (vía 8.8.8.8/1.1.1.1)

# ── E. DNSSEC: la zona está firmada y el resolver valida ───────────────────────
sudo rndc zonestatus biblioteca.tel | grep -i secure   # → secure: yes
dig @192.168.10.1 biblioteca.tel +dnssec | grep -i flags   # → debe incluir "ad"
delv @127.0.0.1 biblioteca.tel A                       # → "; fully validated"

# ── F. TSIG / transferencia de zona ────────────────────────────────────────────
# CON clave (funciona):
dig @192.168.20.1 biblioteca.tel AXFR -y hmac-sha256:ns1-ns2.:QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg=
# SIN clave (rechazado → prueba que TSIG protege):
dig @192.168.20.1 biblioteca.tel AXFR              # → REFUSED / Transfer failed

# ── G. El slave tiene la copia ─────────────────────────────────────────────────
ssh raspberry
dig @192.168.20.10 biblioteca.tel +short           # → 192.168.20.10 (responde el slave)
sudo rndc zonestatus biblioteca.tel                # serial == al del master
ls -l /var/cache/bind/db.biblioteca.tel            # existe, fecha reciente

# ── H. RPZ: bloqueo activo, local en passthru ──────────────────────────────────
dig @192.168.10.1 bet365.com +short                # → NXDOMAIN (bloqueado)
dig @192.168.10.1 biblioteca.tel +short            # → resuelve (passthru)
```

Si A–H pasan, el subsistema DNS/DNSSEC/TSIG está completo y correcto.

---

## 7.3 Cómo leer la salida de `dig` (lo que el profe va a preguntar)

```
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 51234
;; flags: qr aa rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 2
;;            │  │  │  │  └─ ad = validado por DNSSEC ✔
;;            │  │  │  └──── ra = el servidor ofrece recursión
;;            │  │  └─────── rd = el cliente pidió recursión
;;            │  └────────── aa = respuesta AUTORITATIVA (es nuestra zona) ✔
;;            └───────────── qr = es una respuesta
;; ANSWER SECTION:
biblioteca.tel.   3600  IN  A  192.168.20.10
;     nombre      TTL  clase tipo  dato
```

- `status: NOERROR` + ANSWER con datos = todo bien.
- `status: NXDOMAIN` = el nombre no existe (o RPZ lo bloqueó).
- `status: SERVFAIL` = el servidor falló → **muy a menudo es DNSSEC roto** (confirma con
  `+cd`: si con `+cd` sí responde, era validación DNSSEC).
- `status: REFUSED` = el servidor no te quiere responder (recursión denegada, transfer sin
  clave, etc.).
- `aa` presente → vino del autoritativo. Ausente en respuestas reenviadas (google.com).

---

## 7.4 Árbol de diagnóstico de fallos comunes

### "No resuelve nada / el cliente no tiene DNS"
1. ¿`named` corriendo? `systemctl status named`.
2. ¿Escucha en el 53? `sudo ss -tulnp 'sport = :53'`. ¿Es **named** o se coló
   `systemd-resolve`? Si es resolved en una IP de VLAN → revisá el drop-in `lan-stub.conf`
   (debe estar ausente; ver `02` §2.6).
3. ¿El cliente está en una red de `allow-query`? Si no, `REFUSED`.
4. Recordá: el cliente quizá esté DNAT'd al `.10.1` por nftables (memoria
   `project-dns-forced-to-master`) — probá directo `dig @192.168.10.1`.

### "Resuelve biblioteca.tel pero no internet" (o al revés)
- Solo interno OK, externo falla → problema de **forwarding**: ¿hay WAN?, ¿llegan
  `8.8.8.8/1.1.1.1`? `dig @8.8.8.8 google.com` desde el Mini PC. Recordá `forward only`:
  si los forwarders no responden, no hay plan B.
- Solo externo OK, interno falla → la **zona** no carga: `named-checkzone`,
  `rndc zonestatus biblioteca.tel`, revisá serial/errores de sintaxis.

### "Cambié un registro pero sigue el valor viejo"
1. ¿Subió el **serial**? Sin serial nuevo, el slave (y la caché) no se enteran. (`03` §3.6)
2. ¿Caché? Es el **TTL**: esperá a que expire o `rndc flush` en el recursivo, o probá con
   `dig @servidor` directo (sin pasar por cachés intermedios).
3. ¿Recargaste? `rndc reload biblioteca.tel`. ¿Validó? `named-checkconf` antes.
4. Si es zona firmada y editaste a mano: ¿re-firmó? `rndc zonestatus` (serial + secure).

### "SERVFAIL al pedir biblioteca.tel"
- Casi seguro **DNSSEC**. Confirmá: `dig @192.168.10.1 biblioteca.tel +cd` (si así sí
  responde → es validación).
- Causas: trust anchor **desincronizado** con la KSK (rotaste la KSK y no re-corriste el
  rol → re-correr el rol DNS re-extrae la KSK), o **firmas expiradas**
  (`rndc zonestatus`, `rndc dnssec -status`).

### "El slave no se actualiza / transfer falla"
1. Logs: `journalctl -u named -f | grep -iE 'transfer|notify|tsig|axfr'` en ambos.
2. `BADKEY`/`BADSIG` → el `tsig_secret`/`tsig_key_name` **difiere** entre master y slave.
   Tienen que ser idénticos (`vars/main.yml` ↔ `group_vars/all.yml`). (`04` §4.9)
3. `BADTIME` → **relojes desincronizados**. Revisá chrony/NTP en ambos.
4. ¿El slave apunta a la IP correcta? Debe ser **`192.168.20.1`**
   (`dns_master_transfer_ip`), no `.10.1` (`04` §4.6).
5. ¿TCP 53 bloqueado? Las transferencias van por **TCP** (`01` §1.11) — revisá el
   `lan-stub.conf` y nftables.
6. Forzá: `sudo rndc retransfer biblioteca.tel` en la RPi.

### "El bloqueo RPZ no funciona / bloquea de más"
- `rndc zonestatus rpz.blocklist` (¿cargada? ¿serial reciente?).
- ¿`response-policy` activa? `cat /etc/bind/named.conf.rpz`.
- Re-generar: `sudo systemctl start bind-rpz-update.service` y mirá su journal.
- Si bloquea `biblioteca.tel` → revisá el passthru (no debería pasar; el script lo
  garantiza).

---

## 7.5 El flujo Ansible (cómo aplicar cambios de verdad)

```bash
# ── MASTER (Mini PC) — solo el rol DNS ──────────────────────────────────────
cd minipc/
ansible-playbook -i router-setup/inventory.ini services/dns.yml
# o todo el router:
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml

# ── SLAVE (RPi) — solo el DNS secundario ────────────────────────────────────
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/dns_secondary.yml

# Modo simulación (no aplica, solo muestra qué cambiaría)
ansible-playbook ... --check --diff
```

Reglas de oro (memorias del proyecto):
- **Editá el repo, no el equipo.** Si tocás el equipo en una urgencia, después reflejá el
  cambio en el rol (`feedback-keep-playbooks-synced-with-live`).
- **Diagnosticá antes de arreglar:** presentá el problema y las opciones, no apliques a
  ciegas (`feedback-diagnose-before-fixing`).
- **Si un problema se repite tras "arreglarlo", buscá la causa raíz** y confirmá que el
  fix tomó efecto (`feedback-recurring-pattern-find-root-cause`).

---

## 7.6 Inventario de archivos para tener a mano (referencia rápida)

**Repo (editar aquí):**
- `minipc/router-setup/roles/dns/vars/main.yml` → hosts, IPs, forwarders, TSIG, DNSSEC.
- `minipc/router-setup/roles/dns/templates/*.j2` → la config en sí.
- `minipc/router-setup/roles/dns/tasks/{main,tsig,dnssec}.yml` → orquestación.
- `raspberry/rpi-setup/roles/dns_secondary/` → el slave.
- `raspberry/rpi-setup/group_vars/all.yml` → vars del slave (incl. TSIG, debe igualar al master).

**Mini PC (inspeccionar aquí):**
- `/etc/bind/named.conf.{options,local,tsig,trust-anchors,rpz}`
- `/var/lib/bind/db.biblioteca.tel{,.signed,.jnl}`, `/var/lib/bind/keys/`
- `/etc/bind/zones/db.*` (inversas), `/etc/bind/zones/rpz.*`
- `/usr/local/sbin/update-bind-rpz`
- logs: `journalctl -u named`

**RPi (inspeccionar aquí):**
- `/etc/bind/named.conf.{options,local,tsig}`
- `/var/cache/bind/db.biblioteca.tel` (copia recibida)

---

## 7.7 Mini-laboratorio: ejercicios para volverte fluido

Hacelos en orden; cada uno consolida un concepto:

1. **Agregá un host** `impresora` en `192.168.20.20` (edita `dns_hosts`, desplegá,
   verificá A + PTR). → consolida `03`.
2. **Bajá el TTL** de la zona a 60, desplegá, observá con `dig` que el TTL bajó, subilo de
   nuevo. → consolida caché/TTL.
3. **Demostrá TSIG:** hacé el AXFR con y sin `-y`. Explicá por qué uno funciona y el otro
   no. → consolida `04`.
4. **Demostrá DNSSEC:** mostrá el bit `ad`, listá DNSKEY (256 vs 257), y con `delv` el
   "fully validated". → consolida `05`.
5. **Rompé y arreglá:** parové BIND, mostrá que el slave **sigue** respondiendo
   `biblioteca.tel` (resiliencia del secundario), reiniciá BIND. → consolida master/slave.
6. **RPZ:** mostrá `bet365.com → NXDOMAIN` y `biblioteca.tel` resolviendo; forzá el update
   de la blocklist. → consolida `06`.

Si podés hacer y **explicar** los 6, dominas el DNS de este proyecto.

---

## Resumen de este archivo

- Cuatro herramientas: `dig` (consultar), `rndc` (controlar), `named-check*` (validar),
  `delv` (validar DNSSEC).
- Hay una secuencia A–H que verifica **toda** la pila (servicio, directa, inversa,
  forward, DNSSEC, TSIG, slave, RPZ).
- Leé los **flags** de `dig` (`aa`, `ad`) y el **status** (`NXDOMAIN`/`SERVFAIL`/`REFUSED`)
  para diagnosticar.
- SERVFAIL ≈ DNSSEC; "valor viejo" ≈ serial/TTL; transfer falla ≈ TSIG/reloj/IP/TCP.
- Aplicá cambios por **Ansible**, no a mano; diagnosticá antes de tocar.

Volvé al [`README.md`](README.md) para el índice. ¡Listo — ahora dominas el DNS de
Pacific Edge!
