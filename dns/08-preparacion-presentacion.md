# 08 · Preparación para la presentación (runbook de demos)

> Esta es tu **chuleta de escenario**: los comandos que debes saber para gestionar el DNS
> y, para cada caso que te pueden pedir, **el guión exacto** (comando → salida esperada →
> qué decir → cómo restaurar). Practícalo una vez antes en seco. Todo asume:
>
> - **Master** = Mini PC (`ssh minipc`), domínio `biblioteca.tel`, escucha en `192.168.10.1`.
> - **Slave** = Raspberry Pi (`ssh raspberry`), responde en `192.168.20.10`.
> - **IP de transferencia** del master (la que usa el slave): `192.168.20.1`.
> - **Clave TSIG:** nombre `ns1-ns2.`, algoritmo `hmac-sha256`,
>   secret `QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg=`.

---

## 0. Pre-vuelo: verificá que TODO está verde ANTES de presentar

Corré esto 10 minutos antes. Si algo falla aquí, arréglalo antes de la demo (no en vivo).

```bash
# ── En el MASTER (ssh minipc) ─────────────────────────────────────────────────
systemctl is-active named                                  # → active
sudo named-checkconf                                       # → (silencio = OK)
sudo rndc zonestatus biblioteca.tel | grep -iE 'serial|secure'   # type master, secure: yes
dig @127.0.0.1 biblioteca.tel +short                       # → 192.168.20.10
dig @127.0.0.1 biblioteca.tel +dnssec | grep -i flags      # → ... ad   (valida DNSSEC)

# ── En el SLAVE (ssh raspberry) ───────────────────────────────────────────────
systemctl is-active named                                  # → active
dig @127.0.0.1 biblioteca.tel +short                       # → 192.168.20.10
sudo rndc zonestatus biblioteca.tel                        # serial == al del master

# ── Reloj sincronizado en ambos (TSIG lo necesita) ───────────────────────────
timedatectl | grep -i 'synchronized'                       # → System clock synchronized: yes
```

Tené **dos terminales abiertas**: una en el master, otra en el slave. Y una tercera con
un `journalctl -u named -f` en el master para mostrar los NOTIFY/transfers en vivo.

---

## 1. Comandos que TENÉS que saber (gestión del DNS)

### Control del servicio y de BIND en caliente (`rndc`)
```bash
systemctl status named                  # estado del servicio
sudo systemctl reload named             # recarga (= rndc reload)
sudo rndc status                         # visión general: zonas, queries, recursión
sudo rndc reload                         # recarga toda la config + zonas
sudo rndc reload biblioteca.tel          # recarga SOLO una zona
sudo rndc reconfig                       # relee config (zonas nuevas) sin recargar las viejas
sudo rndc zonestatus biblioteca.tel      # serial, tipo, 'secure' (DNSSEC), próximos eventos
sudo rndc retransfer biblioteca.tel      # (en el SLAVE) re-pide la zona al master AHORA
sudo rndc dnssec -status biblioteca.tel  # estado de claves/firmado DNSSEC
sudo rndc flush                          # vacía la caché del recursivo
sudo rndc notify biblioteca.tel          # (en el MASTER) re-envía NOTIFY a los slaves
```

### Validar ANTES de recargar (tu red de seguridad)
```bash
sudo named-checkconf                                                  # valida toda la config
sudo named-checkzone biblioteca.tel /var/lib/bind/db.biblioteca.tel   # valida la zona directa
sudo named-checkzone 20.168.192.in-addr.arpa /etc/bind/zones/db.20.168.192   # una inversa
```

### Consultar y diagnosticar (`dig` / `delv`)
```bash
dig @192.168.10.1 biblioteca.tel +short        # consulta directa, respuesta limpia
dig @192.168.10.1 -x 192.168.20.10 +short      # consulta INVERSA (PTR)
dig @192.168.10.1 biblioteca.tel +dnssec       # pide DNSSEC; mirá el flag 'ad' y los RRSIG
dig @192.168.10.1 biblioteca.tel +cd           # 'checking disabled': NO valida (diagnóstico)
dig @192.168.10.1 biblioteca.tel DNSKEY +multiline   # ver las claves (256=ZSK, 257=KSK)
delv @127.0.0.1 biblioteca.tel A               # como dig pero te DICE si validó DNSSEC
dig @192.168.20.1 biblioteca.tel AXFR -y hmac-sha256:ns1-ns2.:<secret>   # transferencia con TSIG
```

### Ver puertos y logs
```bash
sudo ss -tulnp 'sport = :53'                   # ¿named escucha en TCP+UDP 53 en las VLANs?
journalctl -u named -f                          # logs en vivo
journalctl -u named -f | grep -iE 'notify|transfer|tsig|axfr|ixfr|signed'
```

### Aplicar cambios "como debe ser" (Ansible)
```bash
cd minipc/     && ansible-playbook -i router-setup/inventory.ini services/dns.yml
cd raspberry/  && ansible-playbook -i rpi-setup/inventory.ini services/dns_secondary.yml
```

### Diccionario de salidas (reconocelas en vivo)
| En `dig` ves… | Significa |
|---|---|
| `status: NOERROR` + ANSWER | todo bien, hay respuesta |
| flag `aa` | respuesta **autoritativa** (vino de su propia zona) |
| flag `ad` | el resolver **validó DNSSEC** ✔ |
| `status: NXDOMAIN` | el nombre no existe (o lo bloqueó RPZ) |
| `status: SERVFAIL` | falló — **muy a menudo es DNSSEC roto** (confirmá con `+cd`) |
| `status: REFUSED` | el server no te responde (recursión/transfer no autorizada) |

---

## 2. DEMO 1 — Agregar `nuevo.biblioteca.tel` en el master y verlo en el slave

**Qué demuestra:** cambio en vivo en el master + propagación automática (NOTIFY +
transferencia TSIG) al slave + que la zona sigue firmada (DNSSEC).

> La zona usa **inline-signing**: editás el archivo **fuente** sin firmar; BIND re-firma
> solo al recargar. **Hay que subir el serial** o el slave no se entera.

### Paso a paso (terminal en el MASTER)
```bash
ssh minipc

# (a) Editar la zona fuente: agregar el A y SUBIR el serial
sudo nano /var/lib/bind/db.biblioteca.tel
#   1. En la línea del Serial, poné el epoch actual (corré `date +%s` en otra terminal
#      y pegá ese número), o simplemente incrementá el número en 1.
#   2. Agregá al final, en la sección de A records:
#         nuevo            IN  A     192.168.20.50

# (b) Validar ANTES de recargar
sudo named-checkzone biblioteca.tel /var/lib/bind/db.biblioteca.tel
#   → "zone biblioteca.tel/IN: loaded serial NNNN  OK"

# (c) Recargar la zona (BIND la re-firma con DNSSEC automáticamente)
sudo rndc reload biblioteca.tel

# (d) Comprobar en el master: existe, está firmado, serial nuevo
dig @127.0.0.1 nuevo.biblioteca.tel +short          # → 192.168.20.50
dig @127.0.0.1 nuevo.biblioteca.tel +dnssec | grep RRSIG   # → tiene firma RRSIG ✔
sudo rndc zonestatus biblioteca.tel | grep -i serial
```

### Verificar la propagación (terminal en el SLAVE)
```bash
ssh raspberry

# El NOTIFY ya debería haberlo actualizado en segundos. Si querés forzarlo:
sudo rndc retransfer biblioteca.tel

dig @127.0.0.1 nuevo.biblioteca.tel +short          # → 192.168.20.50  ✔ (el slave lo tiene)
sudo rndc zonestatus biblioteca.tel | grep -i serial   # mismo serial que el master
```

**Para mostrar el "cómo se enteró" (opcional, muy efectivo):** en la terminal de
`journalctl -u named -f` del master vas a ver el `notify ... biblioteca.tel` salir hacia
`192.168.20.10`, y en el slave el `transfer ... biblioteca.tel ... Transfer completed`.

**Qué decir:** "Edité solo el master y subí el serial. BIND re-firmó la zona y disparó un
NOTIFY al slave; el slave comparó seriales, pidió una transferencia **autenticada con
TSIG** y ya sirve el registro nuevo — sin que yo tocara el slave."

### 🧹 Restaurar después de la demo
```bash
# Opción A (recomendada): dejar el repo como fuente de verdad
#   Quitá 'nuevo' de la zona (editá de nuevo y borrá la línea, subí serial, rndc reload),
#   o re-aplicá Ansible que regenera la zona desde dns_hosts (sin 'nuevo'):
cd minipc/ && ansible-playbook -i router-setup/inventory.ini services/dns.yml
# Nota de convención del proyecto: si un cambio va a quedarse, agregalo a dns_hosts en
# vars/main.yml, no a mano. (memoria: mantener playbooks sincronizados con lo vivo)
```

---

## 3. DEMO 2 — Detené el master: ¿el slave sigue? ¿por cuánto tiempo?

**Qué demuestra:** resiliencia del secundario y el rol de los timers del **SOA**.

### Paso a paso
```bash
# (a) Apagar el master
ssh minipc
sudo systemctl stop named
systemctl is-active named            # → inactive

# (b) El slave SIGUE respondiendo (no depende del master para servir)
ssh raspberry
dig @127.0.0.1 biblioteca.tel +short            # → 192.168.20.10  ✔
dig @127.0.0.1 nuevo.biblioteca.tel +short      # → 192.168.20.50  ✔ (si hiciste la demo 1)

# (c) ¿Por cuánto tiempo? — lo dice el SOA
dig @127.0.0.1 biblioteca.tel SOA +multiline
sudo rndc zonestatus biblioteca.tel             # busca la línea 'expires'
```

**La respuesta según el SOA** (valores reales de la zona, en `db.forward.j2`):
```
Serial 3600 900 604800 300
       │    │   │      └ Negative TTL
       │    │   └──────── Expire  = 604800 s = 7 DÍAS
       │    └──────────── Retry   = 900 s   (reintenta cada 15 min si el refresh falla)
       └───────────────── Refresh = 3600 s  (revisa el SOA del master cada 1 h)
```

**Qué decir:** "El slave tiene su propia copia, así que sigue respondiendo aunque el
master esté caído. Cada hora (**Refresh**) intenta revisar si hay cambios; si el master no
responde, reintenta cada 15 min (**Retry**). Solo si pasan **7 días** (**Expire**) sin
poder contactarlo, el slave **deja de servir** la zona para no entregar datos demasiado
viejos. O sea: tolera la caída del master hasta 7 días."

### 🧹 Restaurar
```bash
ssh minipc
sudo systemctl start named
systemctl is-active named            # → active
# (en el slave) confirmá que vuelve a sincronizar
ssh raspberry && sudo rndc retransfer biblioteca.tel
```

---

## 4. DEMO 3 — DNSSEC falla → SERVFAIL en un resolver validante

**El reto:** mostrar que una firma rota se rechaza, **sin romper tu zona real** en vivo.
Tenés dos formas; usá la **A** (cero riesgo) para la demo y mencioná la **B**.

### Forma A (RECOMENDADA, cero riesgo) — usar un dominio de prueba roto a propósito
Verisign mantiene `dnssec-failed.org` con firmas **deliberadamente inválidas**. Tu
resolver valida (`dnssec-validation auto`), así que lo rechaza:

```bash
# Un dominio con DNSSEC CORRECTO → NOERROR + flag 'ad'
dig @192.168.10.1 cloudflare.com +dnssec | grep -iE 'status|flags'
#   → status: NOERROR ... flags: ... ad   ✔ validó

# Un dominio con DNSSEC ROTO → SERVFAIL
dig @192.168.10.1 dnssec-failed.org +dnssec | grep -i status
#   → status: SERVFAIL          ✗ el resolver RECHAZA la firma inválida

# Prueba de que el SERVFAIL es por VALIDACIÓN (no por caída): desactivá la validación
dig @192.168.10.1 dnssec-failed.org +cd +short
#   → SÍ devuelve IPs   → confirma que lo que fallaba era la validación DNSSEC
```

**Qué decir:** "Con DNSSEC correcto, el resolver valida y marca `ad`. Con una firma
inválida, **se niega a entregar el dato** y responde SERVFAIL — protege al usuario de
datos falsificados. Y al pedirlo con `+cd` (checking disabled) sí responde, lo que prueba
que el problema era la **validación**, no el servidor." (Esta forma necesita WAN.)

### Forma B (sobre TU zona, reversible) — romper temporalmente el trust anchor
Si te piden verlo **en `biblioteca.tel`**, NO toques la zona ni las claves. En su lugar
"desafiná" el ancla de confianza del resolver y restaurala enseguida. Es reversible y no
corrompe ningún dato.

```bash
ssh minipc
# (a) Respaldar el trust anchor actual
sudo cp /etc/bind/named.conf.trust-anchors /tmp/ta.bak

# (b) Romperlo: cambiá UN carácter de la clave pública dentro del archivo
sudo nano /etc/bind/named.conf.trust-anchors      # alterá 1 letra de la cadena "AwEAA..."
sudo rndc reconfig

# (c) Ahora el resolver NO puede validar biblioteca.tel → SERVFAIL
dig @192.168.10.1 biblioteca.tel +dnssec | grep -i status     # → SERVFAIL  ✗
dig @192.168.10.1 biblioteca.tel +cd   +short                 # → 192.168.20.10 (con +cd sí)

# (d) RESTAURAR (imprescindible antes de seguir con otras demos)
sudo cp /tmp/ta.bak /etc/bind/named.conf.trust-anchors
sudo rndc reconfig
dig @192.168.10.1 biblioteca.tel +dnssec | grep -i flags      # → vuelve el 'ad'  ✔
```

> Por qué es seguro: solo tocás el **ancla de confianza** del resolver (qué clave
> considera válida), no la zona ni las claves DNSSEC. Restaurar el archivo y `rndc
> reconfig` lo deja exactamente como estaba. Si te ponés nervioso, `ansible-playbook ...
> services/dns.yml` regenera el ancla correcto desde cero.

**Qué NO hacer en vivo:** editar el `.signed` a mano o borrar claves de `/var/lib/bind/keys`
— eso sí puede dejar la zona rota y arruinar la demo.

---

## 5. DEMO 4 — Cambiar/usar mal la clave TSIG → la transferencia se rechaza

**Qué demuestra:** que la transferencia está **autenticada**: sin la clave correcta, el
master la rechaza. Dos formas; la **A** es instantánea y no cambia nada.

### Forma A (RECOMENDADA) — pedir la transferencia con la clave EQUIVOCADA
```bash
# Con la clave CORRECTA → la transferencia funciona (mostrá que normalmente sí se puede)
dig @192.168.20.1 biblioteca.tel AXFR \
    -y hmac-sha256:ns1-ns2.:QAY8sEB3xfyFnIbuwLdepnL3CszyywTvmCAuDRzdEsg=
#   → imprime TODA la zona  ✔

# Con una clave INCORRECTA (cambié el secret) → RECHAZADA
dig @192.168.20.1 biblioteca.tel AXFR \
    -y hmac-sha256:ns1-ns2.:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
#   → "; Transfer failed."  (el master responde BADKEY/REFUSED)

# Sin NINGUNA clave → también rechazada
dig @192.168.20.1 biblioteca.tel AXFR
#   → "; Transfer failed."
```
En el master, `journalctl -u named -f | grep -i tsig` muestra el rechazo:
`... request has invalid signature: TSIG ns1-ns2.: tsig verify failure (BADKEY)`.

**Qué decir:** "La autorización de transferencia es por **clave**, no por IP. Con la clave
correcta el master entrega la zona; con una clave equivocada —o sin clave— la **rechaza**
con un error TSIG. Así nadie en la red puede llevarse una copia de la zona ni suplantar la
sincronización."

### Forma B (cambio real en un lado, reversible) — desincronizar el secret
Si te piden "**cambiá** la clave y mostrá que rompe", desafiná el secret en el **slave**,
forzá una transferencia (falla), y restaurá:

```bash
ssh raspberry
sudo cp /etc/bind/named.conf.tsig /tmp/tsig.bak
sudo sed -i 's/QAY8.*";/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";/' /etc/bind/named.conf.tsig
sudo rndc reload
sudo rndc retransfer biblioteca.tel
journalctl -u named -n 20 | grep -i tsig      # → tsig verify failure (BADKEY)
# el slave conserva su copia VIEJA pero ya no puede sincronizar

# RESTAURAR
sudo cp /tmp/tsig.bak /etc/bind/named.conf.tsig
sudo rndc reload
sudo rndc retransfer biblioteca.tel           # vuelve a sincronizar  ✔
```

> ⚠️ Hacé esta demo **al final**, o usá la Forma A: si dejás el secret desincronizado, la
> Demo 1 (propagación al slave) fallará. Restaurá siempre antes de seguir.

---

## 6. Orden sugerido en el escenario y reglas de seguridad

1. **Pre-vuelo** (sección 0) — todo verde.
2. **Demo 1** (agregar registro + propagación) — el plato fuerte; deja `nuevo` puesto.
3. **Demo 2** (apagar master, slave sigue) — reusa `nuevo`; **reiniciá named al terminar**.
4. **Demo 4 Forma A** (TSIG con clave mala) — instantáneo, no cambia nada.
5. **Demo 3 Forma A** (`dnssec-failed.org`) — instantáneo, no cambia nada.
6. **Limpieza final:** quitar `nuevo` (o re-aplicar Ansible), confirmar master y slave
   sincronizados y `secure: yes`.

**Reglas de oro para no arruinar la demo:**
- Siempre `named-checkconf` / `named-checkzone` **antes** de un `rndc reload`.
- Las formas **A** de las demos 3 y 4 no cambian nada → son las más seguras en vivo.
- Las formas **B** son reversibles **si restaurás** — hacé el backup (`cp ... /tmp`) ANTES.
- Si algo se enreda, el botón de pánico es: `ansible-playbook -i router-setup/inventory.ini
  services/dns.yml` (master) y `services/dns_secondary.yml` (slave) → regeneran todo a un
  estado bueno conocido.

---

## 7. Preguntas que te pueden hacer y respuesta corta

- **"¿Por qué el slave pide al `.20.1` y no al `.10.1`?"** → La RPi está en la VLAN 20; el
  master escucha también en su IP de esa VLAN (`192.168.20.1`), que es el camino directo
  en el mismo segmento. (`04` §4.6)
- **"¿TSIG cifra la zona?"** → No. TSIG **autentica** e **integra** el mensaje (HMAC con
  secreto compartido); no da confidencialidad. DNSSEC tampoco cifra: **firma** los datos.
  (`04` §4.4, `05` §5.1)
- **"¿Por qué `biblioteca.tel` necesita un trust anchor local?"** → Es un TLD inventado que
  no cuelga de la raíz, así que nadie publica su DS; anclamos su KSK localmente. (`05` §5.5)
- **"¿El slave firma la zona?"** → No, la recibe **ya firmada**; no tiene las claves
  privadas. (`04` §4.2, `05`)
- **"¿Y si cambio un registro y olvido el serial?"** → El slave no se entera nunca; por eso
  Ansible usa el epoch como serial (sube solo). (`03` §3.6)

Volvé al [`README.md`](README.md). ¡Suerte en la presentación!
