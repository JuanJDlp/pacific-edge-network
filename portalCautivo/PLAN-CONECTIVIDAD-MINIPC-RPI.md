# Plan de Trabajo — Conectividad Mini PC ↔ Raspberry Pi 5

**Fecha:** 2026-05-10
**Estado:** ✅ COMUNICACIÓN ESTABLECIDA
**Objetivo:** Lograr que la Raspberry Pi se comunique con el Mini PC en VLAN 20.

---

## Diagnóstico realizado (2026-05-10)

### Diagnóstico inicial
| Componente | Estado encontrado |
|------------|------------------|
| `enp171s0` (LAN Mini PC) | **UP** — cable al switch conectado ✓ |
| `enp171s0.20` (VLAN 20) | **UP**, IP `192.168.20.1/24` ✓ |
| `kea-dhcp4-server` | Running, pero **0 leases otorgados** |
| Kea — sockets VLAN | Kea arrancó el 2026-05-08 cuando las VLANs eran `LOWERLAYERDOWN` → nunca abrió socket |
| RPi `eth0` | Link UP (100Mbps), **sin IP** — cliente DHCP sin respuesta |
| RPi `wlan0` | UP, `192.168.131.174/24` — internet y Netbird operativos ✓ |

### Causa raíz descubierta con tcpdump
Los paquetes DHCP de la RPi llegaban a `enp171s0` (sin etiqueta 802.1Q) en lugar de `enp171s0.20` (VLAN 20 tagged). Esto indica que **el switch Catalyst 2960 no tiene aplicada la configuración VLAN** — todos los puertos están en VLAN 1 (default). El tráfico pasa por el switch pero sin etiquetar.

Evidencia: `ssh minipc "sudo nft list ruleset"` → el switch no responde a ping ni Telnet en `192.168.10.2`.

---

## Solución implementada

### En el Mini PC
- **Kea reiniciado** → ahora escucha en `192.168.10.1:67`, `192.168.20.1:67`, `192.168.30.1:67`
- **Ruta host agregada** vía `rpi-route.service` (systemd, habilitado en boot):
  ```
  192.168.20.10/32 dev enp171s0 src 192.168.20.1
  ```
  Esto hace que el tráfico de retorno hacia la RPi salga sin etiquetar por `enp171s0`, compatible con el switch en estado default.

### En la Raspberry Pi
- **IP estática en `eth0`**: `192.168.20.10/24` (netplan permanente)
- **`wlan0` intacto**: `192.168.131.174`, default gateway vía WiFi IASLAB, Netbird activo

---

## Resultados de las pruebas

| Prueba | Resultado |
|--------|-----------|
| Mini PC → RPi: `ping 192.168.20.10` (5 paquetes) | ✅ 0% pérdida, RTT ~0.4ms |
| RPi → Mini PC: `ping 192.168.20.1` (5 paquetes) | ✅ 0% pérdida, RTT ~1ms |
| Mini PC → RPi: TCP puerto 22 (`nc -zv 192.168.20.10 22`) | ✅ Connection succeeded |
| RPi `wlan0` post-cambio | ✅ `192.168.131.174/24`, sin afectación |
| Netbird RPi (`wt0`) | ✅ `100.90.81.168`, intacto |
| Netbird Mini PC (`wt0`) | ✅ `100.90.95.134`, intacto |

---

## Checklist — ✅ Completado

- [x] Kea reiniciado y escuchando en puertos VLAN
- [x] RPi con IP estática `192.168.20.10/24` en `eth0` (netplan permanente)
- [x] Ruta host en Mini PC persistente via `rpi-route.service`
- [x] Ping bidireccional Mini PC ↔ RPi: 0% pérdida
- [x] TCP (SSH) alcanzable de Mini PC a RPi por interfaz LAN
- [x] `wlan0` y Netbird de la RPi sin afectación

---

## Tarea pendiente — Configurar el switch Catalyst 2960 ⚠️

La solución actual es un **workaround**: la RPi está en VLAN 1 (nativa) en lugar de VLAN 20. Funciona porque el Mini PC tiene una ruta específica para `192.168.20.10` sin etiquetar.

**Cuando se pueda acceder físicamente al switch o por consola serial**, aplicar la configuración en `networkDevices/SwitchCerritoBongo/configuration-Catalyst2960.txt`.

Los cambios clave que activan el diseño VLAN completo:

```
! Puerto donde está conectada la RPi (verificar número de puerto real)
interface FastEthernet0/1
 switchport mode access
 switchport access vlan 20
 spanning-tree portfast

! Puerto del Mini PC (verificar número de puerto real)
interface FastEthernet0/24
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30,40
 switchport trunk native vlan 1

! SVI de gestión
interface vlan 10
 ip address 192.168.10.2 255.255.255.0
 no shutdown

ip default-gateway 192.168.10.1
```

Una vez aplicada la config del switch:
1. La RPi recibirá frames etiquetados como VLAN 20
2. El DHCP de Kea funcionará directamente (ya está configurado)
3. Se puede eliminar `rpi-route.service` del Mini PC
4. Se puede volver `eth0` de la RPi a `dhcp4: true` en netplan

---

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `/etc/netplan/50-cloud-init.yaml` (RPi) | `eth0`: de `dhcp4: true` → IP estática `192.168.20.10/24` |
| `/etc/netplan/50-cloud-init.yaml.bak` (RPi) | Backup de la config original |
| `/etc/systemd/system/rpi-route.service` (Mini PC) | Servicio de ruta persistente para la RPi |

---

## Comandos de verificación rápida

```bash
# Estado actual
ssh minipc "ip route show | grep 192.168.20; sudo ss -ulnp | grep 67"
ssh raspberry "ip addr show eth0; ip route show"

# Ping cruzado
ssh minipc "ping -c 3 192.168.20.10"
ssh raspberry "ping -c 3 192.168.20.1"
```
