# Guía de Instalación — TVWS Innonet MASTER como AP (VLAN 30)
**Fecha:** 2026-05-13
**Referencia de hardware:** `tvws/Innonet_TVWS_Korean.md`

---

## Objetivo

Integrar el equipo TVWS Innonet MASTER como **punto de acceso WiFi** para la red de clientes (VLAN 30). Los clientes que se conecten por WiFi deben:

- Obtener IP del servidor Kea DHCP del Mini PC (`192.168.30.100–200`)
- Pasar por el portal cautivo antes de acceder a internet
- Ser indistinguibles de un cliente cableado en FA0/4

Para lograrlo, el MASTER debe operar en **modo bridge / AP puro**: la interfaz WiFi y la interfaz LAN quedan en el mismo dominio L2, sin NAT ni DHCP propio. Los broadcasts DHCP del cliente llegan directamente al Mini PC.

---

## Diagrama de integración

```
                    Internet (Starlink)
                          │
                    ┌─────▼──────┐
                    │  Mini PC   │
                    │ 192.168.30.1 (VLAN30 GW + DHCP + Portal)
                    └─────┬──────┘
                          │ trunk 802.1Q (enp171s0 → switch uplink)
                 ┌────────▼──────────┐
                 │  Switch Catalyst  │
                 │  SW-CORE-BONGO    │
                 └────────┬──────────┘
                          │ FA0/4
                          │ trunk, native VLAN 30
                          │ allowed VLANs 20,30
                 ┌────────▼──────────────────────────┐
                 │  TVWS Innonet MASTER               │
                 │  Puerto LAN → conectado a FA0/4    │
                 │  Modo: AP bridge (sin NAT, sin DHCP│
                 │  SSID: Biblioteca_Digital          │
                 └────────┬──────────────────────────┘
                          │ WiFi (2.4/5 GHz)
                   Clientes WiFi
                   IP: 192.168.30.x (asignada por Kea)
                   GW: 192.168.30.1
```

---

## Antes de empezar — Lo que necesitas

| Elemento | Descripción |
|----------|-------------|
| Laptop de configuración | Con puerto Ethernet o adaptador USB-Ethernet |
| Cable Ethernet | Para conectar laptop ↔ puerto LAN del TVWS |
| Acceso al switch | SSH desde Mini PC (`ssh minipc`, luego `pexpect`) |
| IP temporal en laptop | `192.168.100.x/24` para acceder a la interfaz web del TVWS |

> ⚠️ **Configura todo el TVWS ANTES de conectarlo al switch.** Una vez en bridge mode, la IP `192.168.100.1` del dispositivo puede volverse inaccesible desde la red VLAN 30. Reserva el acceso de administración como se detalla en la sección 4.

---

## Paso 1 — Preparar la laptop de configuración

Conecta tu laptop directamente al **puerto LAN** del TVWS MASTER con un cable Ethernet. Asígnale a tu interfaz Ethernet una IP estática:

```
IP:      192.168.100.50
Máscara: 255.255.255.0
Gateway: 192.168.100.1
DNS:     192.168.100.1
```

Verifica que puedas acceder a la interfaz web:

```
http://192.168.100.1
Usuario: root
Contraseña: fts
```

---

## Paso 2 — Configurar el radio TVWS (Network → Wireless/DB)

Aunque en esta etapa solo vamos a usar el MASTER como AP local (sin enlace TVWS a un SLAVE), el radio debe estar configurado correctamente para no causar interferencia y estar en el modo correcto.

| Parámetro | Valor recomendado | Notas |
|-----------|-------------------|-------|
| **Mode** | `MASTER` | Por defecto — no cambiar |
| **Frecuencia central** | `575 MHz` | Verificar ocupación del canal en el sitio |
| **Ancho de banda** | `6 MHz` | Mismo que en la guía de referencia |
| **Potencia TX** | `14 dBm` (mínima) | En laboratorio/pruebas: usar mínima para evitar interferencia |
| **SSID** | Igual al que se use en el SLAVE futuro | Importante si en el futuro se añade el SLAVE |

1. Navega a **Network → Wireless/DB**
2. Configura los valores de la tabla
3. Haz clic en **Save**, luego **Save and Apply**

> Si aparece un warning de "unsaved changes" en la esquina superior derecha (temperatura de operación), haz Save y continúa.

---

## Paso 3 — Configurar el WiFi de clientes (Network → WiFi)

Este es el radio WiFi estándar (2.4 GHz / 5 GHz) al que se conectarán los usuarios. Es **independiente** del radio TVWS de la sección anterior.

| Parámetro | Valor | Notas |
|-----------|-------|-------|
| **SSID** | `Biblioteca Digital Ladrilleros` | O el nombre acordado para la red |
| **Seguridad** | `Ninguna / Open` | El portal cautivo es el mecanismo de control de acceso |
| **Potencia TX WiFi** | Ajustar según cobertura deseada | Empieza con potencia media |
| **DHCP del TVWS** | **Deshabilitar** | Kea (Mini PC) será el único DHCP en VLAN 30 |

1. Navega a **Network → WiFi**
2. Edita la red WiFi existente
3. Cambia el SSID
4. **Desactiva el servidor DHCP interno** del dispositivo (busca "DHCP Server" en las opciones de la interfaz LAN y ponlo en `disabled`)
5. Configura la red como **abierta** (sin contraseña WPA) — el portal cautivo reemplaza la autenticación
6. Haz clic en **Save**, **Save and Apply**, y luego **Reboot**

---

## Paso 4 — Configurar el puerto LAN en modo bridge (sin NAT)

Este es el paso más crítico. Necesitamos que el TVWS no haga NAT entre WiFi y su puerto LAN, sino que **puentee** ambas interfaces en L2.

### 4.1 Deshabilitar NAT / modo router

Navega a **Network → Interface** (o equivalente en el menú):

- Interfaz **LAN**:
  - IP: `192.168.100.1/24` (mantener para acceso de administración)
  - DHCP Server: **Disabled**
  - **Bridge con WiFi**: Activar (busca "Bridge interfaces" o "br-lan" que incluya la interfaz WiFi)

- Interfaz **WAN**:
  - **No configurar** — el uplink de internet viene del Mini PC a través del switch, no directamente al WAN del TVWS

### 4.2 Verificar que el bridge esté activo

Si el dispositivo corre OpenWRT (probable), el bridge se verifica vía SSH o en la interfaz web bajo **Network → Switch** o **Network → Interfaces → br-lan**. Debes ver la interfaz WiFi y el puerto LAN en el mismo bridge.

```
br-lan
  ├── eth0     (puerto LAN físico)
  └── wlan0    (radio WiFi clientes)
```

Con este bridge activo:
- Un DHCP Discover de un cliente WiFi sale por `eth0` hacia el switch
- El switch (FA0/4, VLAN 30 nativa) lo entrega al Mini PC
- Kea responde con una IP en `192.168.30.100–200`
- El cliente queda en VLAN 30 como si estuviera cableado

### 4.3 Acceso de administración post-integración

Una vez el TVWS esté conectado al switch y en bridge mode, su IP de administración `192.168.100.1` ya **no será alcanzable directamente desde VLAN 30** (diferente subred).

**Opciones para administración futura:**

| Opción | Método |
|--------|--------|
| Laptop directa | Conectar laptop al puerto LAN del TVWS con IP `192.168.100.50/24` |
| Ruta estática en Mini PC | `sudo ip route add 192.168.100.0/24 via 192.168.30.X dev enp171s0.30` (donde X es la IP del TVWS en VLAN 30 si tiene una) |
| Cambiar IP de admin | Reconfigurar el TVWS con IP en `192.168.30.240` (fuera del pool DHCP) para acceso desde VLAN 30 |

> **Recomendado:** Antes de conectar al switch, añade una IP adicional en el rango VLAN 30 a la interfaz de administración del TVWS (`192.168.30.240/24`). Así puedes acceder desde el Mini PC via SSH o navegador después de la integración.

---

## Paso 5 — Conectar al switch (FA0/4)

Una vez terminada la configuración del TVWS:

1. **Desconecta** la laptop del puerto LAN del TVWS
2. **Conecta** el puerto LAN del TVWS al puerto **FA0/4** del switch con un cable Ethernet
3. Verifica el LED de link en el switch y en el TVWS

### Estado actual de FA0/4

El puerto ya está configurado correctamente. No se requieren cambios en el switch:

```
interface FastEthernet0/4
 description AP_PacificEdge_WiFi
 switchport trunk native vlan 30
 switchport trunk allowed vlan 20,30
 switchport mode trunk
 spanning-tree portfast trunk
```

- **Native VLAN 30**: los frames sin tag del TVWS entran a VLAN 30 automáticamente ✓
- **Portfast trunk**: el puerto pasa a Forwarding inmediatamente al conectar (sin esperar STP) ✓
- **Allowed VLANs 20,30**: VLAN 30 (clientes) y VLAN 20 (servidores) están habilitadas ✓

> Si el TVWS solo maneja tráfico untagged (modo bridge simple), el trunk con native VLAN 30 funciona perfectamente. Los frames del TVWS salen sin tag y el switch los pone en VLAN 30.

---

## Paso 6 — Verificación post-instalación

### 6.1 Desde el switch (via Mini PC)

```bash
ssh minipc "python3 -c \"
import pexpect
child = pexpect.spawn(
    'ssh -o StrictHostKeyChecking=no '
    '-o KexAlgorithms=diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 '
    '-o HostKeyAlgorithms=ssh-rsa '
    '-o Ciphers=aes128-cbc,3des-cbc,aes256-cbc '
    'user@192.168.10.2', timeout=15)
i = child.expect(['Password:', '#'])
if i == 0:
    child.sendline('password')
    child.expect('#')
child.sendline('terminal length 0')
child.expect('#')
child.sendline('show interfaces FastEthernet0/4 status')
child.expect('#')
print(child.before.decode())
child.sendline('show mac address-table interface FastEthernet0/4')
child.expect('#')
print(child.before.decode())
\""
```

Debes ver:
- `Fa0/4` en estado `connected`
- MACs del TVWS y de los clientes WiFi en VLAN 30

### 6.2 Desde el Mini PC — verificar clientes WiFi en VLAN 30

```bash
# Ver leases activos en Kea — deben aparecer las MACs de los clientes WiFi
ssh minipc "sudo cat /var/lib/kea/kea-leases4.csv | grep '192\.168\.30\.' | tail -10"

# Verificar que los clientes responden ping
ssh minipc "ping -c 2 192.168.30.101"
```

### 6.3 Desde un cliente WiFi

1. Conectar al SSID `Biblioteca Digital Ladrilleros`
2. Verificar que obtiene IP en `192.168.30.100–200`:
   - macOS/Linux: `ip addr` o `ifconfig`
   - Windows: `ipconfig`
3. Abrir un browser y navegar a cualquier URL HTTP (ej. `http://neverssl.com`)
4. Debe aparecer la splash page del portal cautivo
5. Hacer clic en "Entrar a la biblioteca" → debe redirigir a `http://192.168.20.10`

### 6.4 Verificar probe automático del OS

Al conectar el dispositivo al WiFi, el sistema operativo debe mostrar automáticamente el popup del portal cautivo:

| OS | Comportamiento esperado |
|----|------------------------|
| iOS / macOS | Popup "Iniciar sesión en la red Biblioteca Digital Ladrilleros" |
| Android | Notificación "Iniciar sesión en la red Wi-Fi" |
| Windows | Popup "Se requiere inicio de sesión adicional" |

Si el popup no aparece, abrir el browser manualmente e ir a cualquier URL HTTP.

---

## Paso 7 — Solución de problemas comunes

### El cliente WiFi no obtiene IP (queda en APIPA `169.254.x.x`)

**Causa probable:** El TVWS aún tiene su DHCP interno activo y compite con Kea, o el bridge no está correctamente configurado.

```bash
# En el Mini PC, ver si llegan Discovers de la MAC del cliente
ssh minipc "sudo journalctl -u kea-dhcp4-server --no-pager -n 30 | grep -i 'discover\|offer\|alloc'"
```

- Si no aparece ningún `DHCPDISCOVER` con la MAC del cliente → el bridge no está pasando los broadcasts → revisar configuración del bridge en el TVWS
- Si aparece `DHCP4_LEASE_ADVERT` pero nunca `DHCP4_LEASE_ALLOC` → el Offer no llega al cliente → posible filtrado en el TVWS o problema de broadcast (ver fix `netdev egress` ya aplicado para macOS)

### El portal cautivo no aparece

Verificar que el nftables DNAT de puerto 80 esté activo:

```bash
ssh minipc "sudo nft list chain ip nat prerouting | grep 2050"
# Debe mostrar:
# iif "enp171s0.30" meta mark != 0x00000001 tcp dport 80 dnat to 192.168.30.1:2050
```

### No hay internet después de aceptar el portal

Verificar que la IP del cliente esté en el set `captive_allowed`:

```bash
ssh minipc "sudo nft list set inet filter captive_allowed"
```

### No se puede acceder a la interfaz web del TVWS (192.168.100.1) desde VLAN 30

Conectar laptop directamente al puerto LAN del TVWS con IP estática `192.168.100.50/24`, o agregar una ruta temporal desde el Mini PC:

```bash
ssh minipc "sudo ip route add 192.168.100.0/24 via 192.168.30.X"
# Reemplazar X por la IP que el TVWS obtuvo de Kea si tiene una configurada en VLAN 30
```

---

## Resumen de configuraciones en el TVWS

| Sección | Parámetro | Valor |
|---------|-----------|-------|
| Network → Wireless/DB | Mode | `MASTER` |
| Network → Wireless/DB | Frecuencia | `575 MHz` |
| Network → Wireless/DB | Ancho de banda | `6 MHz` |
| Network → Wireless/DB | Potencia TX | `14 dBm` |
| Network → WiFi | SSID | `Biblioteca Digital Ladrilleros` |
| Network → WiFi | Seguridad | `Open (sin contraseña)` |
| Network → Interface → LAN | DHCP Server | `Disabled` |
| Network → Interface → LAN | Bridge WiFi | `Enabled (br-lan incluye wlan0)` |
| Network → Interface → WAN | Estado | `No configurar` |

---

## Notas importantes

- **No configurar la interfaz WAN del TVWS.** El uplink de internet lo provee el Mini PC a través del switch. Configurar la WAN del TVWS podría crear un loop de routing o conflictos de gateway.
- **El SSID debe ser abierto.** El portal cautivo reemplaza la contraseña WiFi. Una contraseña WPA requeriría que los usuarios la compartan, eliminando el control del portal.
- **Sin SLAVE por ahora.** El radio TVWS del MASTER (575 MHz) no tiene un receptor activo. Esto es correcto para la etapa actual — el enlace de radio se habilita cuando se agregue el SLAVE en campo.
- **TVWS no es el AP WiFi del SLAVE.** En el futuro con el SLAVE conectado, el SLAVE servirá los clientes WiFi del sitio remoto (192.168.25.0/24 según la guía original). El MASTER solo necesita su WiFi local activo para clientes cercanos.
