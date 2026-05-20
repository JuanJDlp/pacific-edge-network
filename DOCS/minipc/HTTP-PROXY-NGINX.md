# HTTP Proxy — nginx intermediario hacia Squid

## Rol Ansible

`minipc/router-setup/roles/captive_portal/` (junto con el portal cautivo)

## Descripción

nginx actúa como intermediario HTTP en el Mini PC para clientes autenticados que acceden a internet o servicios externos. Recibe el tráfico en el puerto 8888 y lo reenvía a Squid en la RPi como un forward proxy request, lo que permite que Squid use el `Host` header en lugar de depender de `SO_ORIGINAL_DST`.

## Por qué es necesario este intermediario

### El problema con DNAT cross-machine

Sin este intermediario, el flujo era:
```
Cliente → dport 80 → nftables DNAT → 192.168.20.10:3128 (Squid intercept)
```

Squid intercept necesita `SO_ORIGINAL_DST` (syscall del kernel) para saber a qué sitio iba realmente el request. Pero como el DNAT ocurrió en el Mini PC (no en la RPi), el kernel de la RPi no tiene registro del destino original. `SO_ORIGINAL_DST` devuelve `192.168.20.10:3128` — el propio Squid. Squid detecta un loop y retorna **403 Access Denied**.

### La solución: nginx como intermediario + Squid en modo forward proxy

```
Cliente (mark=0x1) → dport 80
    │  DNAT → Mini PC:8888
    ▼
[nginx Mini PC :8888]
    │  proxy_pass http://192.168.20.10:3129
    │  Host: $http_host (header original del cliente)
    ▼
[Squid RPi :3129 — forward proxy mode]
    │  Usa Host header (no necesita SO_ORIGINAL_DST)
    ▼
Internet / caché de Squid
```

Squid en modo forward proxy (puerto 3129) lee el destino del `Host` header del request HTTP. No necesita `SO_ORIGINAL_DST`. El 403 desaparece.

## Configuración nginx

```nginx
server {
    listen 8888;
    resolver 192.168.10.1 valid=30s ipv6=off;

    location / {
        proxy_pass         http://192.168.20.10:3129;
        proxy_http_version 1.0;
        proxy_set_header   Host $http_host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   Connection "";
    }
}
```

**`proxy_http_version 1.0`**: Squid en forward proxy mode maneja mejor HTTP/1.0 (sin chunked transfer encoding). Evita problemas de compatibilidad.

**`proxy_set_header Host $http_host`**: Preserva el Host header original del cliente. Squid lo usa para determinar el destino.

**`resolver 192.168.10.1`**: Bind9 local. nginx necesita un resolver para el `proxy_pass` con hostname dinámico.

**Template:** `templates/http-proxy.nginx.j2`
**Config desplegada:** `/etc/nginx/sites-available/http-proxy`

## Regla nftables correspondiente

```nft
# Clientes autenticados: HTTP → nginx intermediario (no directo a Squid)
iif "enp171s0.30" meta mark 0x1 ip daddr != 192.168.20.10 tcp dport 80 \
    dnat to 192.168.30.1:8888

# Input: permitir tráfico entrante al intermediario
tcp dport 8888 accept
```

La excepción `ip daddr != 192.168.20.10` evita que el acceso directo a la RPi (`http://biblioteca.local/`) pase por el intermediario — va directo al nginx de la RPi.

## Squid en RPi — cambio requerido

El puerto 3129 de Squid debe escuchar en todas las interfaces y en modo `accel vhost allow-direct`:

```
# /etc/squid/squid.conf en RPi
http_port 3129 accel vhost allow-direct
http_port 3128 intercept  # intercept para tráfico local RPi
```

**Por qué `accel vhost allow-direct`**: El forward proxy estándar (`http_port 3129`) espera URIs absolutas como `GET http://example.com/ HTTP/1.0`. Pero nginx como proxy transparente envía URIs relativas (`GET / HTTP/1.0` con `Host: example.com`). El modo `accel vhost` hace que Squid extraiga el destino del header `Host`, aceptando URIs relativas. `allow-direct` le permite conectarse directamente al origen.

Este cambio ya fue aplicado manualmente en la RPi.

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible |
|---|---|
| `/etc/nginx/sites-available/http-proxy` | `templates/http-proxy.nginx.j2` |

## Verificación

```bash
# Desde Mini PC — verificar que nginx escucha en 8888
ss -tlnp | grep 8888

# Probar el intermediario directamente (desde Mini PC)
curl -v --proxy http://192.168.30.1:8888 http://example.com
# → debe retornar HTTP/1.1 200 OK

# Verificar que Squid en RPi acepta conexiones desde Mini PC
curl -v --proxy http://192.168.20.10:3129 http://example.com
# → TCP_MISS: primera vez
# → TCP_HIT: segunda vez (caché activo)

# Desde cliente VLAN30 autenticado
curl http://example.com
# → debe funcionar (pasa por nftables DNAT → nginx :8888 → Squid :3129)
```

## Logs

```bash
# nginx intermediario
tail -f /var/log/nginx/access.log

# Squid en RPi (via SSH)
ssh raspberry "sudo tail -f /var/log/squid/access.log"
```
