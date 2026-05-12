# Portal Cautivo — Setup de prueba y reserva DHCP RPi

**Fecha:** 2026-05-11
**Estado:** Listo para pruebas

---

## Cambios realizados

### 1. Native VLAN 30 en Fa0/4 (switch)

**Problema:** La PC de prueba conectada a Fa0/4 enviaba tráfico sin etiqueta 802.1Q. El switch lo trataba como VLAN 1 (native default), que no está permitida en el trunk hacia el Mini PC. Los DHCP Discover nunca llegaban a Kea.

**Solución:** Cambiar la native VLAN de Fa0/4 a 30.

```
SW-CORE-BONGO# configure terminal
SW-CORE-BONGO(config)# interface FastEthernet0/4
SW-CORE-BONGO(config-if)# switchport trunk native vlan 30
SW-CORE-BONGO(config-if)# end
SW-CORE-BONGO# write memory
```

**Config final de Fa0/4:**
```
interface FastEthernet0/4
 description AP_PacificEdge_WiFi
 switchport trunk native vlan 30
 switchport trunk allowed vlan 20,30
 switchport mode trunk
```

**Resultado:** La PC obtuvo IP `192.168.30.100/24` de Kea en VLAN 30.

---

### 2. Reserva DHCP en Kea para la Raspberry Pi

**Problema:** La RPi pasó de IP estática (`192.168.20.10`) a DHCP dinámico. El script del portal cautivo tiene hardcodeado `REDIRECT = 'http://192.168.20.10'` como destino tras la autenticación. Con IP dinámica la redirección podía apuntar a una IP incorrecta.

**Solución:** Agregar una reserva DHCP en Kea para que la RPi siempre obtenga `192.168.20.10` por su MAC.

Archivo modificado: `/etc/kea/kea-dhcp4.conf` en el Mini PC.

```json
{
  "id": 20,
  "subnet": "192.168.20.0/24",
  "pools": [
    { "pool": "192.168.20.50 - 192.168.20.99" }
  ],
  "reservations": [
    {
      "hw-address": "2c:cf:67:d2:f0:98",
      "ip-address": "192.168.20.10",
      "hostname": "rpi5-servicios"
    }
  ],
  ...
}
```

**Resultado:** La RPi siempre obtiene `192.168.20.10` vía DHCP. Verificado con ping desde el Mini PC.

> La IP reservada está fuera del pool dinámico (`50–99`) para evitar conflictos.

---

## Cómo probar el portal cautivo

### Requisitos
- PC conectada físicamente al switch en **Fa0/4**
- Sin etiqueta VLAN (tráfico normal sin configuración especial)

### Paso 1 — Verificar que tienes IP en VLAN 30

```bash
ipconfig getifaddr en8
# Esperado: 192.168.30.100 (o cualquier IP en 192.168.30.100–200)
```

Si no aparece:
```bash
sudo ipconfig set en8 DHCP
```

### Paso 2 — Probar el portal en el navegador

Abre cualquier URL **HTTP** (no HTTPS):
```
http://neverssl.com
http://example.com
```

Deberías ver la página **"Biblioteca Digital Ladrilleros"** (portal cautivo).

### Paso 3 — Autenticarte

Haz click en **"Entrar a la biblioteca"**. El navegador redirige a `http://192.168.20.10` (nginx de la RPi).

### Paso 4 — Verificar autorización en el switch

```bash
ssh minipc "sudo nft list set inet filter captive_allowed"
```

Esperado:
```
elements = { 192.168.30.100 expires 7h59m... }
```

---

## Flujo completo de red

```
Tu PC (en8, sin etiqueta)
    |
    | → VLAN 1 antes ❌  /  → VLAN 30 ahora ✓  (native vlan 30 en Fa0/4)
    |
Switch Fa0/4 → trunk → Fa0/24
    |
    | VLAN 30 tagged (802.1Q)
    |
Mini PC enp171s0.30 (192.168.30.1)
    |
    ├── Kea DHCP → asigna 192.168.30.100/24
    |
    └── nftables DNAT:
        HTTP sin autenticar → 192.168.30.1:2050 (captive-portal.py)
                                      |
                              Click "Entrar"
                                      |
                              nft add element captive_allowed { 192.168.30.100 }
                                      |
                              302 redirect → http://192.168.20.10
                                      |
                              RPi nginx (IP reservada por Kea)
```

---

## Archivos modificados

| Dispositivo | Archivo / Componente | Cambio |
|-------------|----------------------|--------|
| Switch | `interface FastEthernet0/4` | `switchport trunk native vlan 30` agregado |
| Mini PC | `/etc/kea/kea-dhcp4.conf` | Reserva DHCP para RPi MAC `2c:cf:67:d2:f0:98` → `192.168.20.10` |
