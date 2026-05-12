# DHCP VLAN 20 — Verificado ✅

**Fecha:** 2026-05-11
**Estado:** FUNCIONANDO

---

## Resultado

Con la configuración del switch Catalyst 2960 aplicada, la Raspberry Pi 5 obtiene IP automáticamente por DHCP en VLAN 20.

```
DHCPDISCOVER on eth0 to 255.255.255.255 port 67
DHCPOFFER of 192.168.20.50 from 192.168.20.1
DHCPREQUEST for 192.168.20.50 on eth0
DHCPACK of 192.168.20.50 from 192.168.20.1
bound to 192.168.20.50 -- renewal in 876 seconds
```

- **IP asignada a la RPi:** `192.168.20.50/24`
- **Servidor DHCP (Kea):** `192.168.20.1` (Mini PC, interfaz `enp171s0.20`)
- **Ping Mini PC → RPi:** 0% pérdida, RTT ~0.4 ms
- **Ping RPi → Mini PC:** 0% pérdida, RTT ~0.66 ms

---

## Cambios aplicados

| Dispositivo | Cambio |
|-------------|--------|
| Switch Catalyst 2960 | Config VLAN aplicada: Fa0/1 → VLAN 20 access, Fa0/24 → trunk 10/20/30/40 |
| Raspberry Pi | `eth0` de IP estática → `dhcp4: true` en netplan (permanente) |
| Mini PC | `rpi-route.service` deshabilitado y eliminado (era workaround) |

---

## Flujo de red actual

```
RPi eth0 (DHCP)
    |
    | VLAN 20 (untagged en acceso)
    |
Switch Catalyst 2960 — Fa0/1 (access VLAN 20)
    |
    | VLAN 20 tagged (trunk 802.1Q)
    |
Switch — Fa0/24 → Mini PC enp171s0.20 (192.168.20.1/24)
    |
    Kea DHCP4 → asigna 192.168.20.50/24 a la RPi
```

---

## Configuración de referencia

- Switch: `networkDevices/SwitchCerritoBongo/configuration-Catalyst2960.txt`
- Diagnóstico previo: `portalCautivo/PLAN-CONECTIVIDAD-MINIPC-RPI.md`
