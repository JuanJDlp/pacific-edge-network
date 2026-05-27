# nginx — Reverse Proxy

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/nginx/`
**Servicio systemd:** `nginx`
**Puertos:** `:80` (HTTP) · `:443` (HTTPS)

---

## Qué hace

nginx actúa como reverse proxy unificado en la RPi. Recibe peticiones HTTP y HTTPS en los puertos 80 y 443 y las enruta a los servicios correspondientes según el path: Kiwix (Wikipedia offline), Kolibri (educación), o Jellyfin (videos). También sirve una página de portal estática e intercepta las probes de conectividad del OS.

---

## Upstreams configurados

| Upstream | Destino | Servicio |
|---|---|---|
| `kiwix_backend` | `127.0.0.1:8080` | Kiwix offline |
| `kolibri_backend` | `127.0.0.1:8090` | Kolibri educativo |
| `jellyfin_backend` | `127.0.0.1:8096` | Jellyfin media |

Todos escuchan en loopback — los clientes siempre pasan por nginx, nunca acceden directamente a los servicios.

---

## Rutas y paths

| Path | Destino | Descripción |
|---|---|---|
| `/` | `/var/www/html/index.html` | Portal de inicio (página estática) |
| `/wikipedia/` | `kiwix_backend` | Kiwix (con rewrite de path) |
| `/content/`, `/catalog/`, `/skin/`, `/search`, etc. | `kiwix_backend` | Recursos internos de Kiwix |
| `/kolibri/` | `kolibri_backend` | Plataforma Kolibri |
| `/videos/` | `jellyfin_backend` | Jellyfin (con soporte WebSocket) |
| `/status` | `/var/www/html/status.json` | Endpoint de salud JSON |

---

## HTTPS con certificado autofirmado

nginx sirve `https://biblioteca.tel` con un certificado autofirmado generado por el rol Ansible:

| Parámetro | Valor |
|---|---|
| Cert | `/var/www/html/biblioteca-segura.crt` |
| Key | `/etc/ssl/private/biblioteca.key` |
| CN | `biblioteca.tel` |
| SAN | `DNS:biblioteca.tel`, `DNS:www.biblioteca.tel`, `IP:192.168.20.1` |
| Validez | 10 años |

Los browsers mostrarán una advertencia de cert la primera vez (cert autofirmado, no firmado por CA pública). El destino post-autenticación del portal cautivo apunta directamente a `https://biblioteca.tel`.

El bloque HTTPS tiene las mismas locations que el HTTP — el contenido es idéntico por ambos protocolos.

```
/var/log/nginx/biblioteca-ssl-access.log
/var/log/nginx/biblioteca-ssl-error.log
```

---

## Probes de conectividad del OS

Cuando un dispositivo se conecta a una red nueva, el OS envía peticiones HTTP a dominios propios para verificar conectividad. La RPi puede recibir estas probes si el DNS las resuelve a `biblioteca.tel` (que apunta a la RPi).

nginx las redirige al portal cautivo del Mini PC en lugar de responder directamente, para que el OS abra el popup correcto:

| Path | Redirect a |
|---|---|
| `/generate_204` | `http://192.168.30.1:2050/` |
| `/gen_204` | `http://192.168.30.1:2050/` |
| `/hotspot-detect.html` | `http://192.168.30.1:2050/` |
| `/ncsi.txt` | `http://192.168.30.1:2050/` |
| `/connecttest.txt` | `http://192.168.30.1:2050/` |
| `/success.txt` | `http://192.168.30.1:2050/` |
| `/canonical.html` | `http://192.168.30.1:2050/` |

---

## Soporte WebSocket (Kolibri y Jellyfin)

Kolibri y Jellyfin usan WebSockets para actualizaciones en tiempo real. nginx está configurado con:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
```

---

## Configuración para contenido pesado

| Parámetro | Valor | Motivo |
|---|---|---|
| `client_max_body_size` | `200M` | Subida de archivos (Kolibri) |
| `proxy_read_timeout` | `600s` (Kolibri) / `6h` (Jellyfin) | Streams de video largos |
| `proxy_buffering off` | Kiwix, Jellyfin | Entrega directa sin buffer para contenido grande |

---

## Logs

```
/var/log/nginx/biblioteca-access.log
/var/log/nginx/biblioteca-error.log
```

---

## Flujo de una petición desde un cliente VLAN30

```
[Cliente autenticado 192.168.30.X]
    │ GET http://biblioteca.tel/wikipedia/Artículo
    ▼
[Mini PC — nftables]
    │ IP destino = RPi → excluida del DNAT del proxy
    │ va directo a RPi:80 (HTTP) o RPi:443 (HTTPS)
    ▼
[nginx RPi :80 o :443]
    │ path /wikipedia/ → kiwix_backend :8080
    ▼
[Kiwix :8080]
    │ sirve el artículo del ZIM

---

[Cliente autenticado — acceso a internet]
    │ GET http://google.com
    ▼
[Mini PC — nftables DNAT :8888]
    │ IP destino ≠ RPi → DNAT a nginx http-proxy
    ▼
[Mini PC — nginx :8888]
    │ reenvía a Squid RPi:3129 como forward proxy
    ▼
[Squid RPi :3129]
    │ ¿en caché? → sirve directo
    │ no → sale a internet
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status nginx

# Validar configuración
sudo nginx -t

# Recargar sin cortar conexiones
sudo systemctl reload nginx

# Ver accesos en tiempo real (HTTP)
sudo tail -f /var/log/nginx/biblioteca-access.log

# Ver accesos HTTPS
sudo tail -f /var/log/nginx/biblioteca-ssl-access.log

# Ver errores
sudo tail -f /var/log/nginx/biblioteca-error.log

# Verificar cert SSL
openssl x509 -in /var/www/html/biblioteca-segura.crt -noout -subject -dates -ext subjectAltName

# Probar HTTPS (desde la red interna)
curl -k https://192.168.20.10/status
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags nginx
# o:
ansible-playbook services/nginx.yml -i rpi-setup/inventory.ini
```
