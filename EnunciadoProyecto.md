Introducción
El proyecto se trata de un sistema de distribucion de contenido (CDN) local, disenado para operar sin conexion permanente a internet en la comunidad de Cocalito, corregimiento de Buenaventura, Valle del Cauca.

Objetivos del Proyecto:

• Implementar un servidor DHCPv4 para los clientes finales (deben
decidir y/o evaluar si se debe o no implementar un DHCPv6)
• Implementar al menos dos servidores DNS privados, primario y
secundarios, que implementen DNSSEC y TSIG; ademas de un
servidor DNS autoritativo (este se les ser´a asignado) y DNS64
• Implementar un servidor de Proxy-cache
• Implementar un portal cautivo
• Implementar CDN (Content Delivery Network)
• Implementar un servidor de mensajerıa privado tipo Matrix
• Se espera que todos los servidores esten sincronizados correcta-
mente contra un NTP server, bien sea un propio, o los NTP server
del pool global
• Implementar un sistema de monitoreo y observabilidad de la red

# Raspberry Pi 5 - Servicios y Funciones en la Red
## Biblioteca Digital Ladrilleros

 ┌─────────────────────────┐  
│ Proxy Cache (Squid) │  
│ Mirror Offline (Kiwix) │
│ Video Server (Jellyfin)│
│ Web Server (Nginx) │
 └─────────────────────────┘

## Información general

La Raspberry Pi 5 forma parte de la arquitectura de la Biblioteca Digital Ladrilleros y funciona como el **nodo de contenido** de la red comunitaria.

### Hardware

- Raspberry Pi 5
- 8 GB RAM
- Ubuntu Server 24.04 LTS (aarch64)

# Rol principal en la red

La Raspberry Pi tiene como objetivo central:

- Alojar contenido educativo y multimedia local.
- Servir contenido sin depender de Internet.
- Actuar como servidor de contenido para toda la comunidad.
- Mantener servicios accesibles aun cuando Starlink falle.

La Raspberry Pi **NO** es el gateway principal de Internet.  
Ese rol pertenece a la Mini-PC.

---

# Servicios desplegados en la Raspberry Pi

## 1. nginx

### Función

nginx funciona como:

- Servidor web principal.
- Proxy reverso.
- Punto unificado de acceso para todos los servicios locales.

Es el servicio que reciben directamente los clientes de la red.

### Puerto expuesto

| Puerto | Acceso |
|---|---|
| `80/tcp` | Público en LAN |

### Endpoints principales

| Endpoint | Servicio asociado |
|---|---|
| `/wikipedia/` | Kiwix |
| `/content/` | Kiwix |
| `/catalog/` | Kiwix |
| `/viewer/` | Kiwix |
| `/videos/` | Jellyfin |
| `/kolibri/` | Kolibri |
| `/status` | Health-check |

### Función en la red

- Centraliza todos los servicios web.
- Oculta los puertos internos.
- Simplifica el acceso para usuarios.
- Reduce exposición directa de servicios backend.
- Sirve el portal cautivo cuando es solicitado por la Mini-PC.
Ubicacion	Proposito
/home/akasicom/ap-bundle/var/www/html/splash.html	Original en tu repositorio (backup)
/var/www/html/splash.html	Activo (el que sirve Nginx)

Si es mejor, y consideras que html debe ser servido directamente por el mini pc, mandalo por scp y que luego despues de pasar el portal cautivo se mande al Document Root (/var/www/html/index.html) que sirve nginx por defecto.

---

# 2. Kiwix

## Función

Kiwix proporciona acceso offline a contenido educativo basado en archivos `.zim`.

### Contenido disponible

- Wikipedia en español
- Wikibooks
- Wikivoyage
- Wikinews
- Wikiversity

### Puerto interno

| Puerto | Acceso |
|---|---|
| `8080/tcp` | Solo localhost |


### Función en la red

* Permite consultar información educativa sin Internet.
* Disminuye consumo de ancho de banda.
* Mantiene acceso a conocimiento durante caídas de conectividad.

---

# 3. Jellyfin

## Función

Servidor multimedia para contenido:

* Educativo
* Cultural
* Comunitario

### Puerto expuesto

| Puerto     | Acceso         |
| ---------- | -------------- |
| `8096/tcp` | Público en LAN |

### Endpoint

```text
/videos/
```

### Función en la red

* Streaming local de video.
* Evita tráfico hacia Internet.
* Permite distribución de contenido audiovisual comunitario.

---

# 4. Kolibri

## Función

Plataforma educativa offline orientada a aprendizaje escolar.

### Características

* Cursos educativos
* Recursos interactivos
* Gestión de contenido pedagógico
* Base de datos local SQLite

### Puerto interno

| Puerto     | Acceso         |
| ---------- | -------------- |
| `8090/tcp` | Solo localhost |

### Función en la red

* Educación offline.
* Recursos pedagógicos permanentes.
* Acceso local incluso sin Internet.
* Plataforma central para estudiantes y docentes.

---

# 5. Squid

## Función

Proxy HTTP y sistema de caché web.

### Puerto expuesto

| Puerto     | Acceso        |
| ---------- | ------------- |
| `3128/tcp` | LAN + Netbird |

### Modos de operación

## Estado actual

Modo:

```text
offline_mode on
```

* Solo sirve contenido cacheado.
* No consulta Internet.

## Estado futuro

Modo:

```text
intercept
```

La Mini-PC redirige tráfico HTTP hacia Squid.

### Función en la red

* Cachea contenido HTTP.
* Acelera acceso a recursos frecuentes.
* Mantiene contenido parcialmente accesible offline.

### Limitación importante

Squid solo puede interceptar tráfico HTTP.

No puede cachear HTTPS sin SSL bumping.

---

# 6. Health-check automático

## Función

Sistema de monitoreo local mediante systemd timer.

### Endpoint

```text
/status
```

### Frecuencia

Cada:

```text
30 segundos
```

### Función en la red

* Detecta caídas de servicios.
* Permite monitoreo automatizado.
* Facilita integración con Prometheus y Grafana.

---

# Puertos utilizados en la Raspberry Pi

| Puerto     | Servicio | Función                |
| ---------- | -------- | ---------------------- |
| `80/tcp`   | nginx    | Portal y proxy reverso |
| `3128/tcp` | Squid    | Proxy HTTP             |
| `8080/tcp` | Kiwix    | Backend local          |
| `8090/tcp` | Kolibri  | Backend local          |
| `8096/tcp` | Jellyfin | Streaming multimedia   |
| `22/tcp`   | OpenSSH  | Administración remota  |

---

# Flujo de comunicación en la red cuando este completa

## Acceso a contenido local

```text
Cliente
   ↓
    AP
   ↓
   Switch l2
   ↓
   MiniPC
   ↓
Raspberry Pi
   ↓
nginx
   ↓
Kiwix / Kolibri / Jellyfin
```

---

# Relación con la Mini-PC

## La Mini-PC se encarga de

* DHCP
* Firewall
* NAT
* DNS principal
* Captive portal

## La Raspberry Pi se encarga de

* Contenido educativo
* Streaming local
* Caché HTTP
* Portal web de contenidos
