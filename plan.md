# Plan de Despliegue y Validación — Pacific Edge Network

> Documento vivo. Actualizar a medida que se completan tareas o se descubren nuevos issues.
> Última revisión: 2026-05-20

---

## Estado general

La mayoría de piezas están escritas en Ansible y documentadas. El objetivo es tenerlas funcionando **end-to-end** y validar el flujo completo de usuario.

| Componente | Rol Ansible | Estado |
|---|---|---|
| Router / VLANs / nftables | `minipc/roles/router` | ✅ Escrito, pendiente validar en vivo |
| DHCP (Kea) | `minipc/roles/dhcp` | ✅ Escrito, pendiente validar |
| DNS primario (Bind9) | `minipc/roles/dns` | ✅ Escrito, pendiente validar |
| Portal cautivo (nginx + captive-accept.py) | `minipc/roles/captive_portal` | ✅ Escrito, bug en template (ver §3.1) |
| HTTP proxy intermediario (nginx → Squid) | `minipc/roles/captive_portal` | ✅ Escrito |
| NTP (Chrony) | `minipc/roles/ntp` | ✅ Escrito |
| Monitoring (Prometheus + Grafana) | `minipc/roles/monitoring` | ✅ Escrito |
| nginx RPi (proxy servicios) | `raspberry/roles/nginx` | ✅ Escrito |
| Squid (proxy-cache) | `raspberry/roles/squid` | ✅ Escrito |
| Kiwix | `raspberry/roles/kiwix` | ✅ Escrito |
| Kolibri | `raspberry/roles/kolibri` | ✅ Escrito |
| Jellyfin | `raspberry/roles/jellyfin` | ✅ Escrito |
| DNS secundario RPi (Bind9 slave) | `raspberry/roles/dns_secondary` | ✅ Escrito |

---

## Flujo de usuario — lo que queremos validar

```
Usuario conecta cable/WiFi al switch (puerto VLAN 30)
        │
        ▼
[1] DHCP: obtiene IP 192.168.30.x, GW 192.168.30.1, DNS 192.168.10.1
        │
        ▼
[2] Abre browser → HTTP a cualquier sitio
    nftables DNAT: mark≠0x1, dport 80 → 192.168.30.1:2050
        │
        ▼
[3] nginx :2050 → splash.html (portal cautivo)
    También responde OS probes (iOS, Android, Windows) → popup automático
        │
        ▼
[4] Usuario hace clic "Entrar"
    GET /accept → nginx proxy_pass → captive-accept.py :2051
    captive-accept.py: nft add element captive_allowed { IP } (timeout 8h)
    302 → http://biblioteca.local
        │
        ├─── CON internet ──────────────────────────────────────────────────────
        │    Bind9 resuelve cualquier dominio → forwarders (8.8.8.8)
        │    HTTP autenticado → DNAT → nginx :8888 → Squid RPi :3129 → internet
        │    HTTPS autenticado → forward directo → MASQUERADE → internet
        │
        └─── SIN internet ───────────────────────────────────────────────────────
             Bind9 resuelve biblioteca.local → 192.168.20.10 (RPi) ✓
             CNAMEs: wikipedia/kolibri/jellyfin/wiki → biblioteca.local → RPi ✓
             HTTP a RPi (192.168.20.10): no pasa por proxy (excluido en DNAT) ✓
             Servicios accesibles: Kiwix :8080, Kolibri :8090, Jellyfin :8096
             (todos expuestos vía nginx RPi en puerto 80)
```

---

## Bugs e inconsistencias identificadas

### 3.1 `nftables.conf.j2` — HTTPS sin autenticar usa `drop` en vez de `reject`

**Archivo:** `minipc/router-setup/roles/router/templates/nftables.conf.j2`, línea 75

**Problema:** El template dice:
```nft
iif "{{ client_iface }}" meta mark != 0x1 tcp dport 443 drop
```
Pero el comentario inmediatamente anterior dice "RST inmediato evitaba que macOS/Chrome reintentara con HTTP" — y el estado actual documentado en `DOCS/red/ESTADO_ACTUAL_RED.md` muestra que la configuración viva usa `reject with tcp reset`.

`drop` causa un timeout de ~30s antes de que el browser reintente con HTTP.
`reject with tcp reset` hace que el browser reintente con HTTP en < 1ms.

**Fix:** Cambiar `drop` → `reject with tcp reset` en el template.

**Estado:** ⬜ Pendiente

---

### 3.2 RPi nginx — ruta `/accept` legada apunta a puerto inexistente

**Archivo:** `raspberry/rpi-setup/roles/nginx/templates/biblioteca.nginx.j2`, línea 57

**Problema:**
```nginx
location = /accept {
    proxy_pass http://127.0.0.1:8088/accept;   # puerto 8088 no existe
```
Este es código legado de cuando el portal corría en la RPi. El portal ahora vive enteramente en el Mini PC. La ruta no se llama en el flujo actual pero puede causar confusión.

**Fix:** Eliminar el bloque `/accept` y `/splash` del nginx de la RPi (son legacy).

**Estado:** ⬜ Pendiente (no bloquea el flujo, pero limpia deuda técnica)

---

### 3.3 `captive-portal.service` vs `nginx.service` — posible conflicto de PID

**Archivo:** `minipc/router-setup/roles/captive_portal/templates/captive-portal.service.j2`

**Problema:** `captive-portal.service` lanza nginx directamente (`ExecStart=/usr/sbin/nginx`). Si `nginx.service` (el instalado por apt) también está habilitado y activo, ambos intentan manejar el mismo proceso/PID file → conflicto.

**Fix necesario:** Verificar en el Mini PC que `nginx.service` está **deshabilitado** y solo corre `captive-portal.service`.
```bash
systemctl is-enabled nginx.service    # debe decir: disabled o masked
systemctl is-active captive-portal    # debe decir: active
```
Si está habilitado, agregarlo al role como `systemd: name=nginx enabled=false state=stopped`.

**Estado:** ⬜ Pendiente verificar en vivo

---

### 3.4 DNS con `forward only` — sin internet no resuelven dominios externos

**Archivo:** `minipc/router-setup/roles/dns/templates/named.conf.options.j2`, línea 13

**Comportamiento:** `forward only` significa que si los forwarders (8.8.8.8 etc.) no están disponibles, Bind9 retorna SERVFAIL para cualquier dominio externo. Esto es correcto — el plan es que sin internet el usuario use solo los servicios internos.

**Consideración:** El splash.html y el portal de la RPi deben orientar al usuario hacia los servicios internos (`biblioteca.local`, `wikipedia.biblioteca.local`, etc.) y no hacia internet, especialmente para el caso sin conectividad.

**Estado:** ✅ Comportamiento esperado y documentado — no requiere cambio en código

---

## Tareas por hacer

### Fase 1 — Fixes pendientes (validados en vivo 2026-05-20)

- [x] **Fix 3.1**: `reject with tcp reset` aplicado en vivo — confirmado ✓
- [x] **Fix 3.2**: Rutas legacy `/accept`/`/splash` eliminadas del nginx RPi — aplicando vía Ansible
- [x] **Fix 3.3**: `nginx.service` (apt) inactivo — sin conflicto, confirmado ✓
- [x] **Fix 3.6**: `node_exporter` en Ansible role RPi ya usa `prometheus-node-exporter` — correcto ✓
- [ ] **Fix 3.5**: DNS zone transfers timeout — investigar conectividad switch VLAN20 ↔ RPi

### Fase 2 — Despliegue Ansible

Orden de ejecución (desde `minipc/`):
```bash
# Mini PC — todo en uno
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml

# O por servicio individual:
ansible-playbook -i router-setup/inventory.ini services/router.yml
ansible-playbook -i router-setup/inventory.ini services/dns.yml
ansible-playbook -i router-setup/inventory.ini services/dhcp.yml
ansible-playbook -i router-setup/inventory.ini services/captive_portal.yml
ansible-playbook -i router-setup/inventory.ini services/ntp.yml
```

Desde `raspberry/`:
```bash
ansible-playbook -i rpi-setup/inventory.ini rpi-setup/playbook.yml
```

### Fase 3 — Validación en vivo

Checklist de validación (ejecutar en orden):

**Mini PC — servicios:**
```bash
systemctl status named kea-dhcp4-server captive-portal captive-accept nginx nftables
```

**DHCP:**
```bash
# Desde un cliente en VLAN30, verificar que obtiene IP en 192.168.30.100-200
# En el Mini PC, ver leases activos:
cat /var/lib/kea/kea-leases4.csv
```

**DNS — resolución interna:**
```bash
# Desde Mini PC o cliente VLAN30:
dig @192.168.10.1 biblioteca.local          # → 192.168.20.10
dig @192.168.10.1 wikipedia.biblioteca.local # → CNAME → 192.168.20.10
dig @192.168.10.1 google.com                 # → IP pública (requiere internet)
```

**nftables — reglas activas:**
```bash
nft list ruleset | grep -A5 captive_allowed
# Verificar que el set existe y tiene timeout 8h
```

**Portal cautivo — acceso:**
```bash
# Simular request HTTP no autenticado desde VLAN30:
curl -v http://192.168.30.1:2050/
# → debe servir splash.html

# Simular OS probe de macOS:
curl -I http://192.168.30.1:2050/hotspot-detect.html
# → HTTP/1.1 302, Location: http://192.168.30.1:2050/

# Verificar que captive-accept.py agrega la IP:
curl -H "X-Real-IP: 192.168.30.50" http://127.0.0.1:2051/accept
nft list set inet filter captive_allowed
# → debe aparecer 192.168.30.50
```

**Conflicto nginx.service (fix 3.3):**
```bash
systemctl is-enabled nginx.service   # debe ser disabled
systemctl is-active captive-portal   # debe ser active
```

**RPi — servicios:**
```bash
# Desde RPi:
systemctl status nginx squid kiwix-serve kolibri jellyfin named
curl -s http://127.0.0.1:8080/catalog/root.xml | head -5  # Kiwix
curl -s http://127.0.0.1:8090/en/learn/                   # Kolibri
curl -s http://127.0.0.1:8096/health                      # Jellyfin
```

**Flujo completo — cliente VLAN30:**
1. Conectar dispositivo al puerto del switch asignado a VLAN 30
2. Verificar que obtiene IP `192.168.30.x`
3. Abrir `http://neverssl.com` → debe aparecer splash page
4. Hacer clic en "Entrar" → debe redirigir a `http://biblioteca.local`
5. Verificar acceso a Kiwix en `http://biblioteca.local/wikipedia/`
6. Con internet: verificar que `http://example.com` carga (vía Squid)

---

## Comandos de despliegue rápido

```bash
# Aplicar solo un fix específico (por tag):
ansible-playbook -i router-setup/inventory.ini services/router.yml --tags firewall

# Check mode (no aplica cambios, solo muestra diffs):
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --check --diff

# Forzar re-despliegue de portal cautivo:
ansible-playbook -i router-setup/inventory.ini services/captive_portal.yml
```

---

## Pendiente / Ideas futuras

- Pi-hole como DNS primario (filtrado de ads, DNSSEC): ver `DOCS/red/ESTADO_ACTUAL_RED.md §8`
- TSIG para zone transfers Mini PC → RPi
- DHCPv6 (Kea ya lo soporta, solo falta configurar)
- Servidor Matrix para chat interno sin internet
