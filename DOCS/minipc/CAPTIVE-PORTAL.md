# Portal Cautivo

## Rol Ansible

`minipc/router-setup/roles/captive_portal/`

## Descripción

El portal cautivo intercepta el tráfico HTTP de clientes no autenticados en VLAN30 y los redirige a una splash page. Al hacer clic en "Entrar", el cliente queda autorizado y puede navegar.

## Arquitectura

```
[Cliente VLAN30 — no autenticado]
    │  HTTP dport 80
    ▼
[nftables — DNAT → 192.168.30.1:2050]
    │
[nginx captive portal :2050]
    ├── OS probes (captive.apple.com, connectivitycheck.gstatic.com, etc.)
    │   └── 302 → http://192.168.30.1:2050/
    └── Cualquier otro request
        └── 302 → http://192.168.30.1:2050/portal
            └── splash.html (botón "Entrar" → POST /accept)
                    │
                    ▼
            [captive-accept.py :2051]
                    │  nft add element inet filter captive_allowed {IP}
                    ▼
            302 → http://biblioteca.tel
```

## Componentes

### 1. nginx — splash page (puerto 2050)

Sirve la página de bienvenida y maneja los OS probes de detección de portal cautivo.

**OS probes soportados:**
- macOS/iOS: `captive.apple.com/hotspot-detect.html`
- Android: `connectivitycheck.gstatic.com/generate_204`
- Windows: `msftconnecttest.com/connecttest.txt`

El redirect apunta siempre a `http://192.168.30.1:2050/` (IP fija, no `$host:$server_port`). Esto es crítico: si se usa `$host`, el probe redirigiría a `captive.apple.com:2050`, que no es accesible.

**Template:** `templates/captive-portal.nginx.j2`
**Config desplegada:** `/etc/nginx/sites-available/captive-portal`

### 2. captive-accept.py (puerto 2051)

Script Python que recibe el POST del botón "Entrar" y agrega la IP del cliente al set nftables `captive_allowed`.

```python
# Acción principal al recibir POST /accept
nft add element inet filter captive_allowed { CLIENT_IP }
# Luego redirige a:
http://biblioteca.tel
```

El redirect post-autenticación apunta a `http://biblioteca.tel` (no a `http://192.168.20.10`). Bind9 resuelve este dominio a `192.168.20.10` (RPi).

**Archivo:** `files/captive-accept.py`
**Systemd unit:** `templates/captive-accept.service.j2`
**Socket:** `127.0.0.1:2051`

### 3. nftables — set `captive_allowed`

El set almacena las IPs autorizadas. Las reglas de nftables permiten tráfico saliente de IPs en este set sin DNAT al portal.

```nft
set captive_allowed {
    type ipv4_addr
    flags timeout
    timeout 8h
}
```

La entrada expira automáticamente después de 8 horas.

### 4. splash.html

Página de bienvenida del portal cautivo.

**Archivo:** `files/splash.html`
**Desplegado en:** `/var/www/captive-portal/splash.html`

## Flujo de autenticación detallado

1. Cliente conecta a VLAN30, obtiene IP vía DHCP (192.168.30.x)
2. Cliente abre browser o el OS hace probe automático
3. nftables: paquete HTTP → mangle mark=0x0 (no autenticado) → DNAT a 192.168.30.1:2050
4. nginx en :2050 responde con splash page
5. Usuario hace clic en "Entrar" → POST a `http://192.168.30.1:2050/accept`
6. nginx hace proxy del POST a captive-accept.py en :2051
7. captive-accept.py ejecuta `nft add element inet filter captive_allowed { 192.168.30.x }`
8. captive-accept.py responde 302 → `http://biblioteca.tel`
9. Próximo paquete HTTP del cliente: nftables verifica `captive_allowed` → mark=0x1 → DNAT a 192.168.30.1:8888 (nginx intermediario → Squid)

## Limpiar autorizaciones

```bash
# Ver clientes autorizados
nft list set inet filter captive_allowed

# Eliminar un cliente específico
nft delete element inet filter captive_allowed { 192.168.30.x }

# Eliminar todos los clientes (solo borra el set, sesiones TCP activas siguen hasta que expiren)
nft flush set inet filter captive_allowed

# Para cortar sesiones TCP activas también:
conntrack -D -s 192.168.30.x
```

## Archivos de configuración desplegados

| Archivo en Mini PC | Fuente Ansible |
|---|---|
| `/etc/nginx/sites-available/captive-portal` | `templates/captive-portal.nginx.j2` |
| `/var/www/captive-portal/splash.html` | `files/splash.html` |
| `/usr/local/bin/captive-accept.py` | `files/captive-accept.py` |
| `/etc/systemd/system/captive-accept.service` | `templates/captive-accept.service.j2` |

## Verificación

```bash
# Servicios activos
systemctl status nginx
systemctl status captive-accept

# Portal accesible
curl -I http://192.168.30.1:2050/
# → HTTP/1.1 302

# Verificar set nftables
nft list set inet filter captive_allowed

# Simular OS probe de macOS
curl -I http://captive.apple.com/hotspot-detect.html --resolve captive.apple.com:80:192.168.30.1
# → Location: http://192.168.30.1:2050/
```
