# Portal Cautivo — Arquitectura Legacy (2026-05-10)

> ⚠️ **DOCUMENTO HISTÓRICO** — Esta arquitectura fue reemplazada. La implementación actual usa **nginx** (`:2050`) + **captive-accept.py** (`:2051`). Ver `DOCS/minipc/CAPTIVE-PORTAL.md` para el estado actual.

**Nodo:** Cerrito Bongo
**Instalado en:** Mini PC (`100.90.95.134`, `ssh minipc`)
**Fecha de instalación:** 2026-05-10

---

## Descripción

El portal cautivo intercepta el tráfico HTTP de los clientes WiFi (VLAN 30) antes de permitirles navegar. El cliente ve una página de bienvenida y, al aceptar, queda autorizado para acceder a la red durante 8 horas.

---

## Flujo de funcionamiento

```
Cliente WiFi (VLAN 30: 192.168.30.x)
        │
        │  HTTP puerto 80 (cualquier sitio)
        ▼
┌─────────────────────────────────────────┐
│  nftables DNAT                          │
│  iif enp171s0.30, mark != 0x1           │
│  tcp dport 80 → 192.168.30.1:2050       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │  captive-portal.py   │
        │  :2050               │
        │  GET /  → splash.html│
        └──────────┬───────────┘
                   │  Usuario hace click
                   │  "Entrar a la biblioteca"
                   ▼
              GET /accept
                   │
        ┌──────────▼───────────┐
        │  nft add element     │
        │  inet filter         │
        │  captive_allowed     │
        │  { <IP cliente> }    │
        └──────────┬───────────┘
                   │  302 redirect
                   ▼
        http://biblioteca.tel
        (Bind9 resuelve → 192.168.20.10 — nginx RPi)
                   │
                   ▼
        Cliente navega libremente
        durante 8 horas
```

---

## Arquitectura de red

| Componente | IP | Rol |
|------------|----|-----|
| Mini PC — gateway VLAN30 | `192.168.30.1` | Corre el portal cautivo en `:2050` |
| Raspberry Pi — nginx | `192.168.20.10` | Destino final tras autenticación |
| Clientes WiFi | `192.168.30.100–200` | DHCP desde Kea, VLAN 30 |

---

## Archivos instalados en el Mini PC

| Ruta | Descripción |
|------|-------------|
| `/usr/local/bin/captive-portal.py` | Servidor HTTP Python del portal |
| `/etc/captive-portal/splash.html` | Página de bienvenida (copiada de la RPi) |
| `/etc/systemd/system/captive-portal.service` | Servicio systemd |
| `/etc/nftables.conf` | Ruleset nftables persistido |

---

## Componentes técnicos

### 1. Servidor Python (`captive-portal.py`)

Servidor HTTP minimalista (puerto `2050`) con dos endpoints:

| Endpoint | Comportamiento |
|----------|---------------|
| `GET /` y cualquier otra ruta | Sirve `splash.html` (200 OK) |
| `GET /accept` | Agrega IP del cliente al set nftables `captive_allowed`, redirige (302) a `http://192.168.20.10` |

La IP del cliente se valida con regex IPv4 antes de pasarla a `nft` para prevenir inyección.

### 2. Set nftables `captive_allowed`

```
table inet filter {
    set captive_allowed {
        type ipv4_addr
        flags dynamic, timeout
        timeout 8h
    }
}
```

- Las IPs expiran automáticamente a las **8 horas**
- El cliente debe volver a aceptar el portal al día siguiente
- Para autorizar manualmente una IP: `sudo nft add element inet filter captive_allowed { 192.168.30.x }`

### 3. Marca de paquetes (mangle prerouting)

```
chain captive_mangle {
    type filter hook prerouting priority mangle;  # prioridad -150
    iif "enp171s0.30" ip saddr @captive_allowed meta mark set 0x1
}
```

Los paquetes de clientes ya autorizados reciben marca `0x1` **antes** de que el hook DNAT (-100) los evalúe. Así el DNAT los deja pasar sin redirigir.

### 4. DNAT (interceptación HTTP)

```
# En table ip nat, chain prerouting:
iif "enp171s0.30" meta mark != 0x1 tcp dport 80 dnat to 192.168.30.1:2050
```

Solo intercepta tráfico de VLAN 30 sin marca `0x1` (no autenticados). HTTPS (443) no se intercepta — los clientes autenticados navegan con HTTPS normalmente.

---

## Instalación (pasos realizados)

> Estos pasos ya están aplicados. Se documentan para poder reinstalar si es necesario.

### 1. Copiar splash.html de la RPi al Mini PC

```bash
ssh raspberry "base64 /var/www/html/splash.html" \
  | ssh minipc "base64 -d | sudo tee /etc/captive-portal/splash.html > /dev/null"
```

### 2. Instalar el servidor Python

```bash
scp captive-portal.py minipc:/tmp/
ssh minipc "sudo cp /tmp/captive-portal.py /usr/local/bin/ && sudo chmod 755 /usr/local/bin/captive-portal.py"
```

### 3. Instalar el servicio systemd

```bash
scp captive-portal.service minipc:/tmp/
ssh minipc "sudo cp /tmp/captive-portal.service /etc/systemd/system/ \
  && sudo systemctl daemon-reload \
  && sudo systemctl enable --now captive-portal.service"
```

### 4. Aplicar reglas nftables

```bash
scp nftables.conf minipc:/tmp/nftables-new.conf
ssh minipc "sudo nft -c -f /tmp/nftables-new.conf"   # validar
ssh minipc "sudo nft -f /tmp/nftables-new.conf"        # aplicar
ssh minipc "sudo cp /tmp/nftables-new.conf /etc/nftables.conf"  # persistir
```

---

## Cómo probarlo

### Prueba 1 — Verificar que el servicio está corriendo

```bash
ssh minipc "sudo systemctl status captive-portal --no-pager"
```

Resultado esperado: `Active: active (running)`

---

### Prueba 2 — Verificar que el portal sirve la página de bienvenida

```bash
ssh minipc "curl -s -o /dev/null -w '%{http_code}' http://192.168.30.1:2050/"
```

Resultado esperado: `200`

```bash
# Ver el HTML completo
ssh minipc "curl -s http://192.168.30.1:2050/ | head -10"
```

---

### Prueba 3 — Simular el click "Entrar a la biblioteca"

```bash
ssh minipc "curl -v -o /dev/null http://192.168.30.1:2050/accept 2>&1 | grep -E 'HTTP|Location'"
```

Resultado esperado:
```
< HTTP/1.0 302 Found
< Location: http://192.168.20.10
```

---

### Prueba 4 — Verificar que la IP quedó en el set nftables

```bash
ssh minipc "sudo nft list set inet filter captive_allowed"
```

Resultado esperado (con IP de prueba `192.168.30.1` del paso anterior):
```
set captive_allowed {
    ...
    elements = { 192.168.30.1 expires 7h59m... }
}
```

Limpiar el set después de la prueba:
```bash
ssh minipc "sudo nft flush set inet filter captive_allowed"
```

---

### Prueba 5 — Prueba end-to-end con cliente real (WiFi)

Una vez conectado el AP en VLAN 30:

1. Conectar un dispositivo al WiFi del AP
2. Abrir el navegador e intentar acceder a cualquier URL HTTP (ej: `http://example.com`)
3. El navegador debe mostrar la página **"Biblioteca Digital Ladrilleros"**
4. Hacer click en **"Entrar a la biblioteca"**
5. El navegador debe redirigir a `http://192.168.20.10` (nginx de la RPi)
6. A partir de ese momento el dispositivo puede navegar libremente durante 8 horas

---

### Prueba 6 — Ver logs en tiempo real

```bash
ssh minipc "sudo journalctl -u captive-portal -f"
```

Ejemplo de salida durante una sesión:
```
INFO 192.168.30.105 - "GET / HTTP/1.1" 200 -
INFO Authorized: 192.168.30.105
INFO 192.168.30.105 - "GET /accept HTTP/1.1" 302 -
```

---

## Operación y mantenimiento

### Ver clientes autenticados actualmente

```bash
ssh minipc "sudo nft list set inet filter captive_allowed"
```

### Desautorizar un cliente manualmente

```bash
ssh minipc "sudo nft delete element inet filter captive_allowed { 192.168.30.x }"
```

### Desautorizar todos los clientes

```bash
ssh minipc "sudo nft flush set inet filter captive_allowed"
```

### Reiniciar el portal (si la página cambia)

```bash
# 1. Actualizar splash.html desde la RPi
ssh raspberry "base64 /var/www/html/splash.html" \
  | ssh minipc "base64 -d | sudo tee /etc/captive-portal/splash.html > /dev/null"

# 2. Reiniciar el servicio
ssh minipc "sudo systemctl restart captive-portal"
```

### Verificar que nftables persiste tras reinicio

```bash
ssh minipc "sudo systemctl status nftables"
# Expected: Active: active (exited) — loaded from /etc/nftables.conf al boot
```

---

## Notas importantes

- **HTTPS no se intercepta**: Las URLs `https://` no pasan por el portal. Los dispositivos modernos (iOS, Android, Windows) detectan el portal cautivo vía sondas HTTP automáticas al conectarse — estas sondas sí usan HTTP (puerto 80).
- **DNS**: El DNS de los clientes VLAN30 está redirigido a `192.168.10.1` (futuro Pi-hole). Hasta que Pi-hole esté instalado, la resolución DNS puede fallar, pero el portal sigue funcionando porque intercepta HTTP directamente.
- **Timeout**: Las autorizaciones expiran en 8 horas. El valor se puede cambiar editando `/etc/nftables.conf` (campo `timeout` del set) y recargando con `sudo systemctl restart nftables`.
- **Template Ansible**: Las reglas nftables están incluidas en `minipc/router-setup/roles/router/templates/nftables.conf.j2`. Re-ejecutar el playbook no revierte el portal cautivo.
