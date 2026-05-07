# Switch Core - Cerrito Bongo

**Modelo:** Cisco SG350X-24 (24 puertos Gigabit)

### Información General
- **Hostname:** SW-CORE-BONGO
- **IP de Gestión:** 192.168.10.2 /24 (VLAN 10)
- **Rol:** Switch principal del nodo Cerrito Bongo

Por defecto las credenciales son Cisco Cisco

### VLANs Configuradas
| VLAN | Nombre                  | Subred IPv4         | Subred IPv6             | Notas |
|------|-------------------------|---------------------|-------------------------|-------|
| 10   | Gestión                 | 192.168.10.0/24     | 2001:db8:0:10::/64      | Solo equipos de administración |
| 20   | Servidores              | 192.168.20.0/24     | 2001:db8:0:20::/64      | Servicios críticos (DNS, DHCP, NTP) |
| 30   | Clientes Cerrito Bongo  | 192.168.30.0/24     | 2001:db8:0:30::/64      | Red de monitoreo de servicios |
| 40   | Enlace Cocalito         | 192.168.40.0/24     | 2001:db8:0:40::/64      | Enlace hacia nodo Cocalito |

### Mapeo de Puertos

| Puerto              | Descripción                    | Modo     | VLAN |
|---------------------|--------------------------------|----------|------|
| Gi1/0/1             | MiniPC_Core_Services           | Access   | 20   |
| Gi1/0/2             | RPi5_Services                  | Access   | 20   |
| Gi1/0/3             | Radio_Link_900MHz              | Access   | 10   |
| Gi1/0/4             | AP_Pacific_Edge                | Trunk    | 20,100* |
| Gi1/0/24            | Uplink_pfSense                 | Trunk    | 10,20,30,40 |


### Comandos Útiles
```bash
show vlan brief
show interfaces status
show running-config
show ip interface brief