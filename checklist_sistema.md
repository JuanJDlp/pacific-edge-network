# Checklist maestro — Pacific Edge Network
### Proyecto unificado: Infraestructura 2 + Plataformas 1 · Cerrito Bongo / Cocalito

> **Objetivo de este documento:** que puedas recorrer tu red actual servicio por servicio, verificar que cada cosa hace lo que el 100% de ambas rúbricas exige, correr tú mismo las pruebas antes de presentar, y anticipar los "casos extremos" con los que los profes suelen romper proyectos en vivo.

---

## 0. Cómo usar este documento

Cada servicio tiene tres bloques:

- **DoD (Definition of Done)** → qué debe existir y cómo debe comportarse para puntuar en el nivel *Accomplished* (4.5–5.0) o cumplir el requisito de Plataformas 1.
- **Pruebas propias** → comandos que TÚ corres antes de la sustentación. Si todos pasan, el servicio está blindado.
- **Casos extremos del profe** → lo que ellos pueden pedir/romper en vivo. Si sobrevives a esto, sacas 100%.

Marca cada `[ ]` cuando lo verifiques. Donde digo "verifica que exista", es porque **no aparece explícitamente en tu diagrama** y quiero que confirmes que está, no asumir.

---

## 1. Mapa requisito → estado objetivo

| # | Requisito | Materia | Dónde vive en tu arquitectura | Cuenta como 100% cuando… |
|---|-----------|---------|-------------------------------|--------------------------|
| 1 | Dual Stack (IPv4 + IPv6) | Plataformas 1 | Mini PC (router/NAT) + VLANs | Clientes y servicios alcanzables por IPv4 **e** IPv6 |
| 2 | DHCPv4 (+ decisión DHCPv6) | Plataformas 1 | Kea DHCPv4 (VLAN 10/20/30) | Clientes obtienen lease, GW y DNS local; decisión DHCPv6 sustentada |
| 3 | DNS primario + secundario, DNSSEC, TSIG, DNS64 | Plataformas 1 | Bind9 master (Mini PC) + slave (RPi) | Zona firmada, transferencia con TSIG, DNS64 operativo |
| 4 | Proxy-cache | Plataformas 1 + Infra 2 | Squid (:3128) + nginx (:8888) | Sirve contenido cacheado, también **sin internet** |
| 5 | Portal cautivo | Plataformas 1 + Infra 2 | nginx :2050/:2051, mark 0x1 (nftables) | Redirige no autenticados; tras login deja pasar |
| 6 | CDN / contenido offline | Plataformas 1 + Infra 2 | Kiwix :8080, Kolibri :8090, Jellyfin :8096 | Contenido educativo/web/video servido localmente |
| 7 | Mensajería privada tipo Matrix | Plataformas 1 | **(verifica que exista)** | Dos clientes registran, crean sala y chatean local |
| 8 | Sincronización NTP | Plataformas 1 | Chrony | Todos los nodos sincronizados, offset bajo |
| 9 | Monitoreo y observabilidad | Plataformas 1 + Infra 2 | Prometheus + Grafana, node_exporter :9100 | Tableros vivos + alertas que detectan caídas |
| 10 | Streaming de video (transcodificación) | Infra 2 | Jellyfin :8096 | Reproducción fluida offline, transcode si aplica |
| 11 | Gestión de almacenamiento 2–4 TB + scripts de purga | Infra 2 | Disco en RPi/Mini PC | Disco montado, estructura lógica, scripts automáticos |
| 12 | Portal/Dashboard con búsqueda | Infra 2 | nginx reverse proxy (RPi :80) | Dashboard categorizado, búsqueda local |
| 13 | Modo offline + actualización online inteligente | Infra 2 | Squid + scripts de refresco | Conmuta online(update)/offline sin intervención |

> **Nota sobre el DNS autoritativo:** según tu aclaración, queda **fuera de alcance** (nunca se proveyó). Aun así, ten una frase lista para la sustentación: *"El autoritativo externo no se entregó por parte de la asignatura, por lo que nuestra zona `biblioteca.tel` opera como autoritativa interna firmada con DNSSEC."*

---

## 2. Checklist por servicio

### 2.1 Dual Stack / IPv6 (transversal — esto suele ser lo que más cuesta)

**DoD**
- [ ] El Mini PC tiene IPv6 en WAN (o ULA/GUA interno) y enruta IPv6 entre VLANs.
- [ ] Cada VLAN (10/20/30) tiene prefijo IPv6 propio y los clientes obtienen dirección (SLAAC+RA **o** DHCPv6 — decisión documentada).
- [ ] RA anuncia DNS (RDNSS) o DHCPv6 entrega el DNS local.
- [ ] Servicios clave (DNS, portal, Jellyfin, Matrix) responden por IPv6, no solo IPv4.
- [ ] Si hay NAT64/DNS64: existe un NAT64 real (Jool o Tayga) al que apunta el DNS64.

**Pruebas propias**
```bash
ip -6 addr show                       # interfaces tienen IPv6
ping6 -c2 192.168... / fd00:...       # gateway IPv6 responde
ip -6 route                           # rutas entre VLANs
dig AAAA biblioteca.tel @<dns_local>  # resuelve por IPv6
curl -6 http://[fd00::...]:8096/       # Jellyfin por IPv6
```
Desde un cliente: confirmar que recibe IPv6 (`ip -6 addr`) y resuelve/alcanza un servicio interno usando solo IPv6.

**Casos extremos del profe**
- "Desconecta IPv4 en este cliente y muéstrame que sigue resolviendo y navegando el contenido local por IPv6."
- "¿DHCPv6 o SLAAC? Justifícame técnicamente la decisión." → ten lista la respuesta (p. ej. SLAAC+RDNSS por simplicidad en red comunitaria, o DHCPv6 stateful si necesitas trazabilidad/reservas).
- "Tu DNS64 sintetiza AAAA… ¿hacia qué NAT64?" → debes poder señalar el NAT64.

---

### 2.2 DHCPv4 — Kea

**DoD**
- [ ] Pools definidos para VLAN 10/20/30 con gateway y `domain-name-servers` apuntando al DNS local.
- [ ] Lease time razonable y leases persisten tras reinicio del servicio.
- [ ] Al menos una **reserva por MAC** demostrable (los profes lo piden seguido).
- [ ] Decisión DHCPv6 documentada (implementado o justificada su omisión).

**Pruebas propias**
```bash
systemctl status kea-dhcp4
cat /var/lib/kea/kea-leases4.csv          # o el backend que uses
journalctl -u kea-dhcp4 -f                # ver DISCOVER/OFFER/REQUEST/ACK en vivo
# En el cliente:
sudo dhclient -r && sudo dhclient -v eth0 # release + renew
```

**Casos extremos del profe**
- "Conecta MI portátil como tercer cliente y que tome IP del pool correcto."
- "Crea una reserva para esta MAC, recarga y muéstrame que toma esa IP." (cambio de config en vivo — el PDF lo exige).
- "¿Qué pasa si el pool se agota?" → ten claro el tamaño y comportamiento.

---

### 2.3 DNS — Bind9 (master + slave, DNSSEC, TSIG, DNS64)

**DoD**
- [ ] `biblioteca.tel` en master (Mini PC) y slave (RPi) sincronizados.
- [ ] **TSIG**: la transferencia de zona (AXFR/IXFR) está autenticada con clave; sin clave se rechaza.
- [ ] **DNSSEC**: zona firmada (DNSKEY, RRSIG, NSEC/NSEC3); resolución con flag `AD`.
- [ ] **DNS64**: para nombres solo-IPv4 sintetiza AAAA con prefijo `64:ff9b::/96` (o el tuyo).
- [ ] El slave sigue respondiendo si el master cae (dentro de la expiración del SOA).

**Pruebas propias**
```bash
# DNSSEC: debe aparecer "flags: ... ad" y registros RRSIG
dig @192.168.20.1 biblioteca.tel +dnssec
dig @192.168.20.1 DNSKEY biblioteca.tel
delv biblioteca.tel                       # validación completa

# TSIG: con clave funciona, sin clave debe FALLAR (REFUSED)
dig @192.168.20.10 biblioteca.tel AXFR -y hmac-sha256:NOMBRE:SECRETO
dig @192.168.20.10 biblioteca.tel AXFR    # sin clave → refused

# DNS64: nombre solo-IPv4 debe devolver AAAA 64:ff9b::
dig AAAA ftp.gnu.org @<dns_local>

# Sincronía master/slave
rndc zonestatus biblioteca.tel            # serial en ambos
```

**Casos extremos del profe**
- "Agrega el registro `A nuevo.biblioteca.tel` en el master, recarga, y muéstrame que el slave también lo tiene." (cambio en vivo + verificación de zone transfer).
- "Detén el master. ¿El slave sigue respondiendo? ¿Por cuánto tiempo según el SOA?"
- "Daña una firma / muéstrame qué pasa si DNSSEC falla." → debe dar `SERVFAIL` en un resolver validante (prepara cómo mostrarlo sin romper la demo real).
- "Cambia la clave TSIG y muestra que la transferencia se rechaza."

---

### 2.4 Proxy-cache — Squid (+ nginx :8888)

**DoD**
- [ ] Squid cachea HTTP; estrategia para **HTTPS** documentada (SSL-bump o caché por dominio/CONNECT) — el nivel top de la rúbrica pide "gestión de HTTPS".
- [ ] Jerarquía de almacenamiento de caché definida (tamaño, niveles `cache_dir`).
- [ ] Contenido cacheado se sirve **con internet caído**.

**Pruebas propias**
```bash
tail -f /var/log/squid/access.log    # 1ª petición TCP_MISS, 2ª TCP_HIT/TCP_MEM_HIT
squidclient -h localhost mgr:info    # estadísticas, hit ratio
squidclient mgr:storedir             # uso de los cache_dir
```
Prueba clave: pide una página, **desconecta WAN**, vuelve a pedirla → debe servirse desde caché.

**Casos extremos del profe**
- "Desconecta internet y navega un sitio que ya visitaste."
- "Muéstrame el hit ratio / dónde están físicamente los objetos cacheados."
- "Modifica una ACL (p. ej. bloquea un dominio), recarga Squid y compruébalo." (cambio en vivo).

---

### 2.5 Portal cautivo (nginx :2050/:2051 + nftables mark 0x1)

**DoD**
- [ ] Cliente nuevo en VLAN 30 es **redirigido** al portal antes de autenticar.
- [ ] Tras autenticar, la `mark 0x1` (nftables/conntrack) deja pasar el tráfico hacia el proxy/contenido.
- [ ] La marca se asocia al cliente correcto y caduca razonablemente.

**Pruebas propias**
```bash
nft list ruleset | grep -A3 mark        # reglas de marcado
conntrack -L | grep mark                # conexiones marcadas
# Cliente nuevo: abrir navegador → debe caer en el portal
curl -v http://example.com              # debe redirigir al portal si no autenticado
```

**Casos extremos del profe**
- "Conecto un dispositivo nuevo: demuéstrame el redirect → login → acceso."
- **Intento de bypass:** "¿Y si pongo IP directa o un DNS externo (8.8.8.8)?" → tu firewall debe forzar DNS local y bloquear salida no autenticada (verifica que no haya fuga por puerto 53/443).
- "Reinicia el cliente / expira la sesión: ¿vuelve a pedir login?"

---

### 2.6 CDN / contenido offline (Kiwix, Kolibri, Jellyfin, nginx reverse proxy)

**DoD**
- [ ] Kiwix sirve ZIM (Wikipedia, etc.), Kolibri canales educativos, Jellyfin video — todo **offline**.
- [ ] nginx reverse proxy (RPi :80) agrega los servicios bajo nombres/paths limpios.
- [ ] Contenido categorizado (educación, salud, ocio) según pide la rúbrica top.

**Pruebas propias**
```bash
curl -I http://192.168.20.10:8080/       # Kiwix
curl -I http://192.168.20.10:8090/       # Kolibri
curl -I http://192.168.20.10:8096/       # Jellyfin
```
Con WAN desconectada: navega un artículo de Kiwix, un curso de Kolibri y reproduce un video.

**Casos extremos del profe**
- "Dos clientes reproduciendo video al tiempo" → mira CPU/transcode.
- "Busca un contenido específico desde el portal."

---

### 2.7 Mensajería tipo Matrix  ⚠️ (no aparece en tu diagrama — confirma que está)

**DoD**
- [ ] Homeserver Matrix (Synapse / Dendrite / Conduit) corriendo y accesible (DNS + reverse proxy + TLS interno).
- [ ] Registro de usuarios habilitado (local).
- [ ] Dos clientes (Element web/escritorio) pueden crear sala y chatear **sin internet**.
- [ ] Federación deshabilitada o solo-local (es red aislada).

**Pruebas propias**
```bash
curl https://matrix.biblioteca.tel/_matrix/client/versions   # responde JSON
systemctl status matrix-synapse                              # o el que uses
```
Registra dos usuarios, crea una sala, envía mensajes entre dos clientes de distintas VLANs.

**Casos extremos del profe**
- "Que un cliente de VLAN 20 y uno de VLAN 30 chateen entre sí."
- "Reinicia el servidor Matrix: ¿persisten los mensajes y usuarios?" → base de datos persistente.

---

### 2.8 NTP — Chrony

**DoD**
- [ ] Un nodo actúa como servidor NTP interno; los demás sincronizan contra él (y/o pool global cuando hay internet).
- [ ] Offset bajo y estable; sirve hora **aunque caiga internet**.

**Pruebas propias**
```bash
chronyc sources -v        # fuentes y estado (^* = sincronizado)
chronyc tracking          # offset, stratum
timedatectl               # en cada nodo: "System clock synchronized: yes"
```

**Casos extremos del profe**
- "Desconecta internet: ¿siguen todos sincronizados contra tu NTP interno?"
- "¿Qué stratum tiene tu servidor y por qué?"

---

### 2.9 Monitoreo y observabilidad — Prometheus + Grafana

**DoD**
- [ ] node_exporter en **todos** los hosts (Mini PC, RPi); targets `UP` en Prometheus.
- [ ] Tableros Grafana: CPU, RAM, disco (¡importante por los 2–4 TB!), red, por host.
- [ ] (Ideal) exporters de servicio: blackbox (up/down de DNS, portal, Jellyfin, Matrix), squid, bind.
- [ ] Al menos **una alerta** que dispare cuando un servicio cae o el disco se llena.

**Pruebas propias**
```bash
curl http://<host>:9100/metrics | head      # node_exporter responde
# Prometheus → Status → Targets: todos UP
```
En Grafana: abre el dashboard y muéstralo poblado.

**Casos extremos del profe**
- "Mata un servicio (p. ej. `systemctl stop squid`) y muéstrame que el monitoreo lo detecta."
- "Llena el disco / simula carga y muéstralo en Grafana."
- "Muéstrame métricas de uso del disco de contenido."

---

### 2.10 Streaming de video — Jellyfin (Infra 2, nivel top)

**DoD**
- [ ] Biblioteca de video organizada; reproducción **fluida** offline (sin buffering excesivo).
- [ ] Transcodificación configurada (HW si la RPi/Mini PC lo permite, o SW) y justificada.

**Pruebas propias**
- Reproduce un video, fuerza un cambio de calidad para ver transcode; observa CPU en Grafana.

**Casos extremos del profe**
- "Reproduce en dos dispositivos a la vez."
- "¿Transcodifica o hace direct play? Demuéstralo."

---

### 2.11 Almacenamiento 2–4 TB + scripts (Infra 2, nivel top)

**DoD**
- [ ] Disco de 2–4 TB **montado** y en `/etc/fstab` (sobrevive reinicio).
- [ ] Estructura de directorios lógica (educación / salud / ocio / video / cache).
- [ ] Filesystem justificado (ext4/xfs/zfs) y, si aplica, redundancia o cuotas.
- [ ] Seguridad básica del SO: firewall, SSH endurecido, usuarios/permisos.

**Pruebas propias**
```bash
lsblk; df -h                 # disco montado y espacio
cat /etc/fstab               # montaje persistente
mount | grep <disco>         # opciones de montaje
```

**Casos extremos del profe**
- "Reinicia el equipo y muéstrame que el disco vuelve a montarse y los servicios arrancan solos."
- "¿Qué pasa cuando el disco se llene? Muéstrame tu política."

---

### 2.12 Portal/Dashboard con búsqueda (Infra 2, nivel top)

**DoD**
- [ ] Página de inicio profesional, categorizada (educación, salud, ocio) que enlaza a Kiwix/Kolibri/Jellyfin.
- [ ] Búsqueda local de contenidos (aunque sea sobre el índice de cada servicio).

**Casos extremos del profe**
- "Busca 'X' desde el portal y llévame al contenido."
- "Navega como lo haría un usuario sin terminal."

---

## 3. Scripts automatizados que DEBEN existir (Infra 2 lo puntúa explícitamente)

La rúbrica de Infra 2 premia *"scripts automáticos para purga de contenido viejo"* y *"conmuta inteligentemente entre modo online (update) y offline"*. Ten estos como archivos versionados, con su `cron`/`systemd-timer`, y listos para mostrar:

- [ ] **Refresco de caché / descarga de contenido** — cron que, cuando hay internet, actualiza ZIM de Kiwix, canales de Kolibri y precachea los sitios más visitados.
- [ ] **Purga de almacenamiento** — script que borra contenido viejo o menos usado cuando el disco supera un umbral (p. ej. >85%). Log de qué borró.
- [ ] **Detección online/offline** — script que prueba conectividad y dispara las actualizaciones solo cuando vuelve internet; en offline no rompe nada.
- [ ] **Health-check / auto-restart** — verifica servicios clave y los reinicia o alerta si caen.
- [ ] **Backup de configs** — Bind, Kea, Squid, nftables, Matrix, portal (para restaurar rápido si algo se daña en la demo).

Para cada script ten listo: **qué hace, cuándo corre (cron/timer), dónde loggea, cómo se prueba a mano.**

```bash
crontab -l ; ls /etc/cron.* ; systemctl list-timers   # demuestra que están programados
```

---

## 4. Persistencia y resiliencia — "que nada falle"

Esto no está en una celda de la rúbrica pero es lo que hace que la demo no se caiga:

- [ ] **Todos** los servicios con `systemctl is-enabled` = enabled (arrancan al boot).
- [ ] Reinicia Mini PC y RPi **antes** de la sustentación y verifica que todo vuelve solo.
- [ ] Montajes en `/etc/fstab` (disco de contenido).
- [ ] VLANs y trunk 802.1Q persistentes (netplan en Ubuntu, no comandos sueltos).
- [ ] nftables persistente (regla de NAT, marks del portal, forzado de DNS).
- [ ] Leases de Kea y zonas de Bind persisten.
- [ ] NetBird (wt0) sube solo si lo usas para administración remota.
- [ ] Ten un **snapshot/backup de configs** por si hay que revertir un cambio que pida el profe.

Prueba de fuego (hazla un día antes):
```bash
sudo reboot            # en cada nodo
# tras el boot, sin tocar nada, corre el smoke test de la sección 6
```

---

## 5. Guion de demo / sustentación

Orden sugerido (de lo más visual a lo más técnico):

1. **Topología en una diapositiva** (tu diagrama Pacific Edge) → explica WAN, VLANs, trunk P24, roles Mini PC vs RPi vs AP.
2. **Cliente nuevo se conecta** → DHCP da IP → portal cautivo → login → navega.
3. **Contenido offline** → Kiwix + Kolibri + Jellyfin desde el portal.
4. **Modo desconectado** → desconectas WAN en vivo y todo lo cacheado/local sigue funcionando.
5. **DNS** → DNSSEC (flag AD), transferencia con TSIG, failover al slave.
6. **Dual stack** → muestra un servicio por IPv6.
7. **Matrix** → dos clientes chateando.
8. **Monitoreo** → Grafana poblado; matas un servicio y la alerta lo detecta.
9. **Cambio en vivo** → practica de antemano: agregar un registro DNS, una reserva DHCP y una ACL de Squid, recargar y verificar.
10. **Scripts** → muestra purga y refresco con sus timers.

Ten listo para CADA servicio responder: *¿qué tecnología, por qué esa y no la alternativa, qué pasa si cae internet, dónde está el dato/config?* (la rúbrica de Infra 2 valora la **decisión sustentada técnicamente**, no solo que funcione).

---

## 6. Smoke test rápido (córrelo justo antes de presentar)

```bash
# --- Conectividad / VLANs ---
ping -c2 192.168.10.1 && ping -c2 192.168.20.1 && ping -c2 192.168.30.1

# --- DHCP ---
systemctl is-active kea-dhcp4

# --- DNS (IPv4, DNSSEC, AAAA/DNS64) ---
dig +short biblioteca.tel @192.168.20.1
dig +dnssec biblioteca.tel @192.168.20.1 | grep -i "flags:.*ad"
dig AAAA <nombre_solo_ipv4> @192.168.20.1

# --- Proxy / caché ---
systemctl is-active squid && squidclient mgr:info | grep -i "hit ratio"

# --- Contenido ---
for p in 8080 8090 8096; do curl -fsI http://192.168.20.10:$p >/dev/null && echo "puerto $p OK"; done

# --- Matrix ---
curl -fs https://matrix.biblioteca.tel/_matrix/client/versions >/dev/null && echo "matrix OK"

# --- NTP ---
chronyc tracking | grep -i "leap status"

# --- Monitoreo ---
curl -fs http://localhost:9100/metrics >/dev/null && echo "node_exporter OK"

# --- IPv6 básico ---
ip -6 addr | grep -q "scope global" && echo "IPv6 presente"

# --- Persistencia ---
systemctl is-enabled kea-dhcp4 bind9 squid chronyd 2>/dev/null
```

Si **todas** estas líneas responden OK tras un reinicio en frío, estás en condiciones de sustentar sin sorpresas.

---

## 7. Resumen de huecos a confirmar (no asumir que están)

Estos puntos no se ven en tu diagrama o son los que la rúbrica top exige y suelen quedar a medias. Revísalos primero:

1. **IPv6 / Dual Stack** real en clientes y servicios (el diagrama es solo IPv4).
2. **DNS64 + NAT64** (Jool/Tayga) — DNS64 sin NAT64 no sirve de nada.
3. **DNSSEC y TSIG** efectivamente configurados y verificables.
4. **Servidor Matrix** (no aparece en el diagrama).
5. **Scripts** de purga / refresco / online-offline con sus timers.
6. **Dashboard con búsqueda** (no solo lista de carpetas).
7. **Alertas** en el monitoreo (no solo dashboards).
8. **Decisión DHCPv6** documentada (sí/no + por qué).

> El autoritativo externo queda fuera de alcance por tu aclaración — solo deja la frase lista para explicarlo.
