# Fix: DHCP lento y Portal Cautivo sin funcionar

**Fecha:** 2026-05-12
**Estado:** Aplicado ✅

---

## Problema 1 — DHCP tardaba 30-50 segundos en asignar IP

### Síntoma
Al conectar un dispositivo nuevo al switch por Fa0/4, el DHCP tardaba hasta 50 segundos en entregar una IP. En algunos casos nunca la entregaba dentro de la ventana de espera. Al segundo equipo conectado tampoco le llegaba IP sin forzarla manualmente.

### Causa raíz
`Fa0/4` (puerto trunk del AP y PCs de prueba) no tenía `spanning-tree portfast trunk` configurado. Al conectar un cable, el puerto pasaba por el ciclo STP normal:

```
Blocking → Listening (15s) → Learning (15s) → Forwarding
```

Con **Rapid PVST** el tiempo baja a ~1-2 segundos, pero era suficiente para que la primera **DHCP Discover** se perdiera mientras el puerto convergía. El cliente DHCP entonces esperaba el retry con backoff exponencial:

```
1er intento → perdido (STP convergiendo)
2do intento → 4s después → perdido o recibido tarde
3er intento → 8s
4to intento → 16s
...
Total: fácilmente 30-50s antes de obtener IP
```

### Fix aplicado en el switch

```
SW-CORE-BONGO# configure terminal
SW-CORE-BONGO(config)# interface FastEthernet0/4
SW-CORE-BONGO(config-if)# spanning-tree portfast trunk
SW-CORE-BONGO(config-if)# end
SW-CORE-BONGO# write memory
```

Con `portfast trunk` el puerto entra **directamente a estado Forwarding** al detectar un cable. La primera DHCP Discover llega a Kea sin demora → IP asignada en < 5 segundos.

> **Nota:** `portfast trunk` se usa en puertos trunk conectados a dispositivos finales (APs, PCs de prueba), no a otros switches. En este caso es correcto porque Fa0/4 conecta a un AP o a una PC, no a otro switch.

---

## Problema 2 — Portal cautivo no interceptaba HTTP

### Síntoma
Al conectar una PC a Fa0/4 (con WiFi desactivado) e intentar acceder a `http://neverssl.com`, el navegador se quedaba cargando indefinidamente. Era como si el dominio no resolviera. El portal cautivo nunca aparecía.

### Causa raíz A — DNS mal configurado (causa principal)

Kea le entregaba a los clientes VLAN 30 el DNS `192.168.10.1` (perteneciente a VLAN 10, otra subred). El cliente enviaba la consulta DNS a `192.168.10.1` a través de su gateway (`192.168.30.1`).

El problema ocurría en la **respuesta DNS**: el Mini PC respondía con `src=192.168.10.1` saliendo por `enp171s0.30` (VLAN 30). Con `rp_filter=2` (modo strict), el kernel verificaba:

> *"¿La mejor ruta para llegar a 192.168.10.1 pasa por enp171s0.30?"*
> Respuesta: **No** — 192.168.10.0/24 está en enp171s0.10.
> Resultado: **paquete descartado.**

Sin respuesta DNS → el navegador no resolvía el dominio → nunca se enviaba el HTTP → el DNAT del portal cautivo nunca se activaba.

### Causa raíz B — rp_filter en modo strict (modo 2)

Todas las interfaces VLAN tenían `rp_filter=2`. Este modo es correcto para hosts finales, pero en un router que maneja múltiples VLANs genera falsos positivos y descarta tráfico legítimo que cruza interfaces.

### Fixes aplicados

#### Fix A — DNS de VLAN 30 apunta a 192.168.30.1 (misma subred)

Archivo modificado: `/etc/kea/kea-dhcp4.conf` en el Mini PC.

```json
{
  "id": 30,
  "subnet": "192.168.30.0/24",
  "option-data": [
    {
      "name": "domain-name-servers",
      "data": "192.168.30.1"
    }
  ]
}
```

Antes era `192.168.10.1`. Ahora los clientes consultan `192.168.30.1:53` — misma subred, no necesitan routing inter-VLAN. El DNAT transparente maneja la respuesta con conntrack correctamente.

#### Fix B — rp_filter modo 1 (loose) en interfaces VLAN

Aplicado en vivo:
```bash
sysctl -w net.ipv4.conf.enp171s0.rp_filter=1
sysctl -w net.ipv4.conf.enp171s0/10.rp_filter=1
sysctl -w net.ipv4.conf.enp171s0/20.rp_filter=1
sysctl -w net.ipv4.conf.enp171s0/30.rp_filter=1
```

Persistido en `/etc/sysctl.d/10-vlan-routing.conf`:
```ini
net.ipv4.conf.enp171s0.rp_filter = 1
net.ipv4.conf.enp171s0/10.rp_filter = 1
net.ipv4.conf.enp171s0/20.rp_filter = 1
net.ipv4.conf.enp171s0/30.rp_filter = 1
```

| Modo | Comportamiento |
|------|---------------|
| `0` | Sin filtro |
| `1` (loose) | Acepta si existe cualquier ruta hacia el origen ✅ correcto para router |
| `2` (strict) | Solo acepta si la mejor ruta al origen pasa por la misma interfaz ❌ descarta tráfico inter-VLAN legítimo |

---

## Estado final del sistema

| Componente | Antes | Después |
|------------|-------|---------|
| Fa0/4 STP | Sin portfast — convergencia 1-30s | `portfast trunk` — forwarding inmediato |
| DNS VLAN 30 | `192.168.10.1` (otra VLAN) | `192.168.30.1` (misma subred) |
| rp_filter VLANs | `2` (strict) | `1` (loose) |
| Tiempo DHCP nueva PC | 30-50 segundos | < 5 segundos |
| Portal cautivo | No aparecía (DNS timeout) | Intercepta HTTP correctamente |

---

## Flujo correcto del portal cautivo (post-fix)

```
PC conectada a Fa0/4 (sin WiFi)
    │
    │  Cable detectado → portfast trunk → Forwarding inmediato
    ▼
Kea DHCP → asigna 192.168.30.x/24
           DNS: 192.168.30.1 (misma subred)
    │
    │  Navegador: http://neverssl.com
    ▼
DNS query → 192.168.30.1:53
    │  (DNAT transparente → 192.168.10.1:53 → systemd-resolved)
    │  rp_filter=1 → respuesta pasa ✓
    ▼
IP resuelta: 34.223.124.45
    │
    │  TCP SYN → 34.223.124.45:80, llegando por enp171s0.30
    ▼
nftables DNAT: tcp dport 80 → 192.168.30.1:2050
    │
    ▼
captive-portal.py → sirve splash.html (Biblioteca Digital Ladrilleros)
    │
    │  Click "Entrar a la biblioteca"
    ▼
GET /accept → nft add element captive_allowed { 192.168.30.x }
    │
    │  302 redirect → http://192.168.20.10 (RPi nginx)
    ▼
Navegación libre durante 8 horas
```

---

## Archivos modificados

| Dispositivo | Archivo / Componente | Cambio |
|-------------|----------------------|--------|
| Switch | `interface FastEthernet0/4` | `spanning-tree portfast trunk` agregado |
| Switch | `interface FastEthernet0/1` | `spanning-tree portfast` confirmado (ya estaba) |
| Mini PC | `/etc/kea/kea-dhcp4.conf` | `domain-name-servers` VLAN30: `192.168.10.1` → `192.168.30.1` |
| Mini PC | `/etc/sysctl.d/10-vlan-routing.conf` | Archivo nuevo — `rp_filter=1` para todas las interfaces VLAN |
