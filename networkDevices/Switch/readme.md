Este repositorio contiene la arquitectura de Infraestructura como Código (IaC) para la gestión del switch core de fibra **Raisecom RAX721** en el proyecto Pacific Edge.

## Justificación Técnica

### Desafío de Hardware
El **Raisecom RAX721** es un switch Carrier Ethernet de 24 puertos SFP. Al no contar con una colección de Ansible oficial (como `cisco.ios` o `arista.eos`), se ha implementado una estrategia de **abstracción mediante módulos agnósticos**.

### Decisiones de Diseño
1.  **Emulación de Terminal:** Se utiliza `ansible_network_os: cisco.ios` en el inventario. Esto permite que Ansible reconozca los prompts de comandos (`>`, `#`) y el manejo de privilegios (`enable`), ya que el sistema operativo de Raisecom (ROS) es compatible con la sintaxis de terminal de Cisco.
2.  **Módulos Netcommon:** Se migró de módulos específicos de Cisco a `ansible.netcommon.cli_config`. Esto asegura que los comandos se envíen de forma literal, evitando errores de validación que ocurren cuando los módulos de Cisco intentan ejecutar comandos de comprobación no soportados por Raisecom.
3.  **Idempotencia Manual:** Aunque se usan comandos crudos, la estructura de `parents` en las tareas asegura que la configuración se aplique específicamente en los contextos correctos (interfaces, vlans).

---

## Segmentación de Red (VLANs)

El diseño de red de Pacific Edge utiliza un esquema de stack dual (IPv4/IPv6) segmentado por servicios y ubicaciones geográficas:

| VLAN | Nombre | IPv4 (GW) | IPv6 (GW) | Propósito / Notas |
| :--- | :--- | :--- | :--- | :--- |
| **10** | Gestión | 192.168.10.1 | 2001:db8:0:10::1 | Administración exclusiva de equipos de red. |
| **20** | Servidores | 192.168.20.1 | 2001:db8:0:20::1 | Servicios críticos (DNS, DHCP, NTP). |
| **30** | Clientes Cerrito Bongo | 192.168.30.1 | 2001:db8:0:30::1 | Red de monitoreo de servicios. |
| **40** | Enlace Cocalito | 192.168.40.1 | 2001:db8:0:40::1 | Red donde reside el nodo CDN. |

---

## Mapeo Físico de Puertos (Raisecom RAX721)

Basado en la infraestructura actual, los puertos del switch se distribuyen así:

*   **Puerto 1/1/1:** Radio Enlace (VLAN 10 - Gestión)[cite: 2].
*   **Puerto 1/1/2:** Raspberry Pi 5 (VLAN 40 - CDN/Enlace Cocalito)[cite: 2].
*   **Puerto 1/1/3:** Mini PC (VLAN 20 - Servidores Críticos)[cite: 2].
*   **Puerto 1/1/4:** Access Point (Trunk VLAN 20, 30)[cite: 2].
*   **Puerto 1/1/24:** Uplink pfSense (Trunk All)[cite: 2].

---

## Estructura del Proyecto

```text
└── pacific-edge-network
    └── networkDevices
        └── Switch
            ├── playbooks/       # Playbooks de orquestación (Backups, VLANs, Interfaces)
            ├── tasks/           # Definiciones atómicas de configuración
            ├── vars/            # Variables de red (VLANs, IPs, IDs)
            ├── ansible.cfg      # Parámetros globales de Ansible
            ├── ansible.sh       # Script wrapper para ejecución simplificada
            ├── inventory.yml    # Definición de hosts y credenciales
            └── ordenAejecutar   # Guía rápida de comandos