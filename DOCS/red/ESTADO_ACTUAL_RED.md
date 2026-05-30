# Estado Actual de la Red — Pacific Edge Network
**Fecha:** 2026-05-30
**Actualizado desde:** diagnosticos remotos via SSH a ambos equipos.

---

## 1. Topologia fisica

```
                Internet
                   |
         +---------+----------+
         |  Router externo    |   (uplink WAN, red 172.16.0.0/16)
         +---------+----------+
                   |
                   | enp170s0 (172.16.0.11/16)
         +---------+----------+
         |     Mini PC        |   plataformas - Ubuntu 24.04.4 LTS
         | (Router/DHCP/DNS/  |   kernel 6.8.0-111-generic
         |  NAT/Captive/NTP/  |   NetBird: 100.90.95.134
         |  Monitoring)       |   Uptime: 22 dias
         +---------+----------+
                   | enp171s0 (trunk 802.1Q, VLAN 10/20/30)
         +---------+----------+
         | Switch L2 (Cisco)  |  P24 -> Mini PC (trunk)
         | SG350X-24 / 2960   |  P1  -> RPi (access VLAN20)
         |                    |  P4  -> Linksys E2500 AP (access VLAN30)
         +--------+-+-+------+
                  |  |  |
       +----------+  |  +----------+
       |             |             |
 +-----+------+     |       +-----+------+
 | Raspberry  |     |       | Linksys    |
 | akasicom2  |     |       | E2500 (AP  |
 | 192.168.   |     |       | bridge)    |
 |  20.10     |     |       +-----+------+
 +------------+  Clientes         |
              (VLAN 10/20/30)  Clientes WiFi
                               (VLAN 30)
```

### Mapeo de puertos del switch L2

| Puerto | Dispositivo                | Modo                              |
|--------|----------------------------|-----------------------------------|
| 1      | Raspberry Pi (akasicom2)   | Acceso (VLAN 20 -- Servidores)    |
| 4      | Linksys E2500 (AP bridge)  | Acceso (VLAN 30 -- Clientes)      |
| 24     | Mini PC (plataformas)      | Trunk 802.1Q (VLAN 10/20/30)     |

---

## 2. Direccionamiento IP

### WAN (uplink hacia router de Internet)

| Interfaz   | IP              | Descripcion           |
|------------|-----------------|-----------------------|
| enp170s0   | 172.16.0.11/16  | WAN del Mini PC       |
| Gateway    | 172.16.0.1      | Router externo        |

### LAN (Mini PC como router, sub-interfaces 802.1Q)

| VLAN | Interfaz       | Subred             | Gateway        | Proposito            |
|------|----------------|--------------------| ---------------|----------------------|
| 10   | enp171s0.10    | 192.168.10.0/24    | 192.168.10.1   | Gestion/management   |
| 20   | enp171s0.20    | 192.168.20.0/24    | 192.168.20.1   | Servidores           |
| 30   | enp171s0.30    | 192.168.30.0/24    | 192.168.30.1   | Clientes (portal cautivo) |

### IPv6 (radvd SLAAC)

| VLAN | Prefijo              |
|------|----------------------|
| 10   | fd00:0:0:10::/64     |
| 20   | fd00:0:0:20::/64     |
| 30   | fd00:0:0:30::/64     |

### Overlay NetBird (wt0)

| Equipo        | IP NetBird       |
|---------------|------------------|
| Mini PC       | 100.90.95.134/16 |
| Raspberry Pi  | 100.90.81.168/16 |

### Otras interfaces

| Interfaz | IP             | Estado | Nota              |
|----------|----------------|--------|--------------------|
| docker0  | 172.17.0.1/16  | DOWN   | Docker instalado, no en uso activo |

---

## 3. Mini PC -- `plataformas` (100.90.95.134)

**Rol:** Router de borde + DHCP + DNS + NAT + portal cautivo + NTP + monitoreo.

**SO:** Ubuntu 24.04.4 LTS, kernel 6.8.0-111-generic
**Uptime:** 22 dias (al 2026-05-30)
**Disco:** 468G total, 14G usado (3%), 431G libre
**RAM:** 16GB total, 1.4GB en uso

**Acceso SSH:**
```
ssh -i ~/.ssh/id_ed25519_ladrilleros user@100.90.95.134
# o bien:
ssh minipc
```

### 3.1 Servicios activos

| Servicio                   | Puerto / Interfaz                          | Estado     | Descripcion                                            |
|----------------------------|--------------------------------------------|------------|--------------------------------------------------------|
| nginx (CNA + cert)        | TCP `:80`                                  | activo     | Redirecciones CNA de OS + descarga certificado CA      |
| nginx (captive splash)    | TCP `:2050` (SSL)                          | activo     | Splash page del portal cautivo + proxy a /accept       |
| nginx (HTTP proxy)        | TCP `:8888`                                | activo     | Proxy HTTP hacia Squid (192.168.20.10:3129) + probes OS|
| nginx (monitoreo)         | TCP `:80` vhost monitoreo.biblioteca.tel   | activo     | Reverse proxy hacia Grafana :3000                      |
| captive-accept.py         | TCP `127.0.0.1:2051`                       | activo     | Handler Python: agrega MAC/IP a nft set captive_allowed|
| captive-portal.service    | --                                         | INACTIVO   | Deshabilitado; funcionalidad absorbida por nginx       |
| Kea DHCPv4                | UDP `:67` en VLANs 10/20/30               | activo     | v2.4.1, sirve las 3 VLANs                             |
| BIND9 / named             | UDP/TCP `:53` en VLANs 10/20/30           | activo     | v9.18.39, dominio biblioteca.tel, DNS autoritativo     |
| Chrony (NTP)              | UDP `:123`                                 | activo     | Stratum 3, sincronizado con 0.co.ntp.edgeuno.com      |
| radvd                     | --                                         | activo     | SLAAC IPv6 para VLANs (fd00:0:0:{10,20,30}::/64)      |
| Prometheus                | TCP `:9090`                                | activo     | Scrapes: minipc:9100, rpi:9100, switch SNMP:9116       |
| Grafana                   | TCP `:3000`                                | activo     | v13.0.1, acceso via monitoreo.biblioteca.tel           |
| node_exporter             | TCP `:9100`                                | activo     | Metricas del Mini PC                                   |
| snmp_exporter             | TCP `:9116`                                | activo     | Metricas SNMP del switch (192.168.10.2)                |
| Docker                    | --                                         | activo     | Instalado, sin contenedores en uso                     |
| NetBird                   | WireGuard `wt0`                            | activo     | 100.90.95.134/16                                       |
| SSH                       | TCP `:22`                                  | activo     | Acceso remoto                                          |

### 3.2 nftables -- Resumen del ruleset

**Tablas activas:**

- `inet filter` -- Filtrado general (input/forward/output)
  - Set `captive_allowed_mac` -- MACs autenticadas via portal (timeout dinamico)
  - Set `ssh_bruteforce` -- Proteccion contra fuerza bruta SSH
  - Chain `captive_mangle` (prerouting, prioridad mangle) -- marca paquetes de autenticados con `0x1`
  - Chain `input` -- policy drop; acepta lo, wt0, established/related, ICMP, puertos de servicios en VLANs
  - Chain `forward` -- policy drop; VLAN 10/20 libre a WAN; VLAN 30 solo autenticados; RST en :443 para no autenticados
  - Chain `output` -- policy accept

- `ip nat` -- NAT y redirecciones
  - Chain `prerouting`:
    - DNS DNAT (UDP/TCP 53) desde todas las VLANs hacia 192.168.10.1:53
    - VLAN 30 sin marca 0x1: HTTP (80) redirigido al portal cautivo 192.168.30.1:2050
    - VLAN 30 con marca 0x1: HTTP (80) redirigido al proxy nginx 192.168.30.1:8888 (hacia Squid)
    - VLAN 30 con marca 0x1: HTTPS filtrado via Squid SNI 192.168.20.10:3130
  - Chain `postrouting`: masquerade saliendo por enp170s0

- `netdev dhcp_fix` -- Fix DHCP broadcast para macOS (APIPA)
  - Convierte unicast DHCP Offers a broadcast (dst=255.255.255.255) en egress de enp171s0.30

### 3.3 Arquitectura del portal cautivo

```
Puerto :80 (nginx)
+-- CNA probes de OS (generate_204, hotspot-detect, connecttest, etc.)
+-- Descarga de certificado CA
+-- monitoreo.biblioteca.tel -> Grafana :3000

Puerto :2050 SSL (nginx)
+-- GET /              -> splash.html (portal cautivo)
+-- GET /accept        -> proxy_pass -> captive-accept.py :2051
                                        +-- extrae IP/MAC del cliente
                                        +-- nft add element captive_allowed_mac { MAC }
                                        +-- responde 200 con HTML "Success"

Puerto :8888 (nginx)
+-- HTTP proxy para autenticados -> Squid 192.168.20.10:3129
+-- Respuestas a probes de OS (para evitar re-trigger del CNA)
```

### 3.4 Monitoreo (Prometheus + Grafana)

| Target                      | Endpoint                        |
|-----------------------------|---------------------------------|
| Mini PC (node_exporter)     | localhost:9100                   |
| Raspberry Pi (node_exporter)| 192.168.20.10:9100               |
| Switch (SNMP via exporter)  | 192.168.10.2 via snmp_exporter:9116 |

Grafana: v13.0.1, accesible en `http://monitoreo.biblioteca.tel`.

### 3.5 Routing

- `net.ipv4.ip_forward = 1`
- Ruta por defecto: `via 172.16.0.1 dev enp170s0`
- NAT (masquerade) en la interfaz WAN para todo el trafico saliente

---

## 4. Raspberry Pi -- `akasicom2` (100.90.81.168 / 192.168.20.10)

**Rol:** Servidor de contenido offline (educacion, media, proxy/cache, DNS secundario).

**SO:** Ubuntu 24.04.4 LTS, kernel 6.8.0-1056-raspi (arm64)
**Uptime:** 1 dia 19 horas (al 2026-05-30)
**Disco:** 59G total, 51G usado (91%), 5.6G libre -- ATENCION: disco casi lleno
**RAM:** 7.8GB total, 1.1GB en uso

**Acceso SSH:**
```
ssh -i ~/.ssh/id_ed25519_ladrilleros akasicom@100.90.81.168
# o bien:
ssh raspberry
```

### 4.1 Interfaces de red

| Interfaz | IP                   | Descripcion               |
|----------|----------------------|---------------------------|
| eth0     | 192.168.20.10/24     | LAN (VLAN 20 -- Servidores)|
| wlan0    | 192.168.131.174/24   | WiFi (conexion alternativa)|
| wt0      | 100.90.81.168/16     | NetBird overlay            |

Ruta por defecto: `via 192.168.20.1 dev eth0`

### 4.2 Servicios activos

| Servicio                   | Puerto / Interfaz                    | Estado       | Descripcion                                       |
|----------------------------|--------------------------------------|--------------|---------------------------------------------------|
| nginx                      | TCP `:80`                            | activo       | v1.24.0, reverse proxy (Kiwix/Kolibri/Jellyfin) + CNA probe redirects |
| Squid (publico)            | TCP `:3128`                          | activo       | v6.14, proxy web con cache                        |
| Squid (interno captive)    | TCP `:3129`                          | activo       | Forward proxy para trafico del portal cautivo      |
| Squid (HTTPS SNI filter)   | TCP `:3130`                          | activo       | Filtrado HTTPS por SNI (blocklist)                 |
| Kiwix                      | TCP `127.0.0.1:8080`                 | activo       | Biblioteca offline (Wikipedia, Wikibooks, etc.)    |
| Kolibri                    | TCP `127.0.0.1:8090`                 | activo       | Plataforma educativa offline                       |
| Jellyfin                   | TCP `127.0.0.1:8096`                 | activo       | Servidor de medios (video)                         |
| BIND9 / named (slave)      | UDP/TCP `:53`                        | activo       | v9.18.39, DNS secundario de biblioteca.tel         |
| Conduit (Matrix)           | --                                   | activo       | Servidor Matrix (servicio adicional)               |
| node_exporter              | TCP `:9100`                          | INACTIVO     | Necesita revision -- reportado como inactive       |
| NetBird                    | WireGuard `wt0`                      | activo       | 100.90.81.168/16                                   |
| avahi-daemon               | --                                   | activo       | mDNS/DNS-SD                                        |
| SSH                        | TCP `:22`                            | activo       | Acceso remoto                                      |

### 4.3 Kiwix -- Biblioteca offline

**Proceso:** kiwix-serve en `127.0.0.1:8080`
**Biblioteca:** `/var/lib/biblioteca/zim/library.xml`

| Archivo ZIM                          | Tamano |
|--------------------------------------|--------|
| wikipedia_es_all_mini_2026-05        | 3.5G   |
| wikibooks_es                         | 107M   |
| wikinews_es                          | 33M    |
| wikiversity_es                       | 18M    |
| wikivoyage_es                        | 36M    |

Actualizacion automatica: cron lunes y jueves a las 02:00.

### 4.4 Kolibri -- Plataforma educativa

**Proceso:** Kolibri en `127.0.0.1:8090`
**KOLIBRI_HOME:** `/home/akasicom/.kolibri`
**Contenido:** 41G en `/home/akasicom/.kolibri/content/`

**Canales instalados:**

| Canal                   |
|-------------------------|
| Khan Academy (Espanol)  |
| EiE Familias            |
| Proyecto Biosfera       |
| Biblioteca Elejandria   |
| Ciencia NASA            |

**Acceso:** anonimo (landing_page=learn, allow_guest_access=True).
**Actualizacion automatica:** cron martes y viernes a las 03:00.

### 4.5 Jellyfin -- Servidor de medios

**Proceso:** Jellyfin en `127.0.0.1:8096`
**API key:** `1e2ba6b4e3ca45aa95627eddc7f46bf2`

**Bibliotecas de medios:**

| Biblioteca   | Ruta                                         | Contenido                                                        |
|--------------|----------------------------------------------|------------------------------------------------------------------|
| Comunitarios | /var/lib/biblioteca/videos/comunitarios      | test.mp4 (1.1M)                                                  |
| Educativos   | /var/lib/biblioteca/videos/educativos        | 4 videos (822MB): Tiburones Discovery, Tierra Fragil, WOW Discovery, Cueva de los Tallos |
| Culturales   | /var/lib/biblioteca/videos/culturales        | --                                                               |

**Usuarios:**
- `Invitado` -- sin contrasena (acceso publico)
- `admin` -- contrasena: admin2026 (administracion)

**Escaneo automatico:** cron diario a las 04:30.

### 4.6 Squid -- Proxy web

**Version:** 6.14

| Puerto | Modo        | Descripcion                                                |
|--------|-------------|------------------------------------------------------------|
| 3128   | Publico     | Proxy web con cache, accesible desde la red                |
| 3129   | Interno     | Forward proxy local, destino del HTTP proxy del Mini PC     |
| 3130   | HTTPS SNI   | Filtrado HTTPS por nombre de dominio (SNI)                  |

**Funcionalidades:**
- Blocklist: bloqueo de pornografia y apuestas (actualizacion: cron domingos 03:30)
- Cache de reverse proxy para biblioteca.tel en :443
- `always_direct allow all` -- si no hay cache, va directo a internet

### 4.7 DNS secundario

BIND9 configurado como slave de la zona `biblioteca.tel`, transfiere desde `192.168.10.1` (Mini PC).

### 4.8 Uso de disco (detalle)

| Ruta                              | Tamano aprox. | Descripcion            |
|-----------------------------------|---------------|------------------------|
| /home/akasicom/.kolibri/content/  | 41G           | Contenido Kolibri      |
| /var/lib/biblioteca/zim/          | ~3.7G         | ZIMs de Kiwix          |
| /var/lib/biblioteca/videos/       | ~823M         | Videos Jellyfin        |
| Otros (SO, paquetes, logs, etc.)  | ~5.5G         | Sistema                |
| **Total usado**                   | **51G / 59G** | **91% -- casi lleno**  |

---

## 5. Tareas cron programadas (Raspberry Pi)

| Tarea                           | Horario              | Descripcion                                 |
|---------------------------------|----------------------|---------------------------------------------|
| Actualizacion ZIMs Kiwix        | Lun/Jue 02:00       | Descarga y actualiza archivos ZIM           |
| Actualizacion contenido Kolibri | Mar/Vie 03:00       | Sincroniza canales de Kolibri               |
| Actualizacion blocklist Squid   | Dom 03:30           | Actualiza listas de bloqueo                 |
| Escaneo biblioteca Jellyfin     | Diario 04:30        | Detecta nuevos videos automaticamente       |

---

## 6. Flujos de trafico

### 6.1 Cliente NO autenticado -- acceso HTTP

```
Cliente (192.168.30.x, NO autenticado)

1. DHCP -> obtiene IP en 192.168.30.0/24, GW 192.168.30.1, DNS 192.168.30.1
2. Browser intenta HTTPS:
   TCP SYN -> sitio:443
   -> nftables forward: REJECT with tcp reset (respuesta inmediata, < 1ms)
   -> Browser falla rapido, intenta HTTP
3. DNS: sitio A? -> DNAT -> BIND9 (192.168.10.1:53) -> forwarders
4. TCP SYN -> sitio:80
   -> nftables DNAT: mark!=0x1, dport 80 -> 192.168.30.1:2050
5. nginx :2050 (SSL) responde con splash.html
6. Usuario hace click "Entrar":
   GET /accept -> proxy_pass -> captive-accept.py :2051
   -> nft add element captive_allowed_mac { MAC } (timeout 8h)
   -> 200 OK con HTML "Success"
   -> Redireccion a http://biblioteca.tel
```

### 6.2 Cliente NO autenticado -- probe automatico de OS

```
iOS:     GET /hotspot-detect.html   Host: captive.apple.com
Android: GET /generate_204          Host: connectivitycheck.gstatic.com
Windows: GET /connecttest.txt       Host: www.msftconnecttest.com

-> DNS resuelve la IP del host externo
-> TCP SYN a esa IP:80
-> DNAT: mark!=0x1, dport 80 -> 192.168.30.1:2050
-> nginx :2050 responde con redirect 302 a /
-> OS detecta redireccion -> muestra popup "Conectar a red"
-> Usuario acepta -> splash.html -> /accept -> autenticado
```

### 6.3 Cliente autenticado -- navegacion normal

```
HTTP (puerto 80):
  -> DNAT a 192.168.30.1:8888 (nginx intermediario Mini PC)
  -> proxy_pass a 192.168.20.10:3129 (Squid forward proxy RPi)
  -> Squid: cache HIT -> responde local / cache MISS -> internet -> cachea

HTTPS (puerto 443):
  -> Filtrado SNI via Squid en 192.168.20.10:3130 (blocklist)
  -> Trafico permitido: forward -> MASQUERADE -> internet

DNS (puerto 53):
  -> DNAT a 192.168.10.1:53 -> BIND9 -> forwarders (8.8.8.8 / 8.8.4.4 / 1.1.1.1)
```

---

## 7. DNS -- dominio biblioteca.tel

**Servidor primario:** BIND9 en Mini PC (192.168.10.1:53), escucha en las tres VLANs.
**Servidor secundario:** BIND9 slave en RPi (192.168.20.10:53), transfiere desde 192.168.10.1.

Todo el trafico DNS de las VLANs es forzado via DNAT al servidor primario, independientemente del DNS configurado en el cliente.

**Registros principales (biblioteca.tel):**

| Nombre                       | Resuelve a         |
|------------------------------|--------------------|
| biblioteca.tel               | 192.168.20.10      |
| monitoreo.biblioteca.tel     | 192.168.10.1       |

---

## 8. Accesos SSH

| Equipo        | Comando                                                              | Atajo       |
|---------------|----------------------------------------------------------------------|-------------|
| Mini PC       | `ssh -i ~/.ssh/id_ed25519_ladrilleros user@100.90.95.134`            | `ssh minipc`     |
| Raspberry Pi  | `ssh -i ~/.ssh/id_ed25519_ladrilleros akasicom@100.90.81.168`        | `ssh raspberry`  |

---

## 9. Alertas y pendientes

| Prioridad | Item                                          | Detalle                                                    |
|-----------|-----------------------------------------------|------------------------------------------------------------|
| CRITICO   | Disco RPi al 91%                              | 5.6G libres de 59G. Kolibri usa 41G. Evaluar limpieza o disco externo. |
| ALTO      | node_exporter inactivo en RPi                 | El servicio prometheus-node-exporter esta reportado como inactive. Prometheus no puede recolectar metricas de la RPi. |
| MEDIO     | captive-portal.service deshabilitado en Mini PC | Funcionalidad absorbida por nginx. El service unit puede eliminarse para evitar confusion. |
| INFO      | Conduit (Matrix) corriendo en RPi             | Servicio adicional no documentado en Ansible. Evaluar si se formaliza en los roles. |

---

## 10. Requisitos del curso -- estado actualizado

| Requisito                                | Estado          | Notas                                                           |
|------------------------------------------|-----------------|-----------------------------------------------------------------|
| DHCPv4                                   | Implementado    | Kea v2.4.1 en Mini PC, VLANs 10/20/30                          |
| DHCPv6 / SLAAC                           | Implementado    | radvd activo con prefijos fd00:0:0:{10,20,30}::/64              |
| DNS primario + secundario                | Implementado    | BIND9 en Mini PC (primario) y RPi (slave)                       |
| DNSSEC + TSIG                            | Pendiente       | BIND9 activo pero sin DNSSEC ni TSIG configurados               |
| DNS64                                    | Pendiente       | No configurado                                                  |
| Proxy-cache (Squid)                      | Implementado    | Squid v6.14 en RPi (:3128/:3129/:3130), cache + filtrado        |
| Portal cautivo                           | Implementado    | nginx + captive-accept, probes OS, RST en 443                   |
| CDN local                                | Implementado    | Kiwix + Kolibri + Jellyfin en RPi                               |
| Servidor Matrix                          | Implementado    | Conduit corriendo en RPi (pendiente formalizacion en Ansible)   |
| NTP                                      | Implementado    | Chrony en Mini PC, stratum 3                                    |
| Monitoreo / observabilidad               | Implementado    | Prometheus + Grafana v13.0.1 + node_exporter + snmp_exporter    |

---

*Documento generado a partir de diagnosticos remotos ejecutados el 2026-05-30.*
