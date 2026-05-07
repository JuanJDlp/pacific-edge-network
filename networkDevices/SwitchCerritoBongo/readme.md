# Switch Core - Cerrito Bongo

**Modelo:** Cisco SG350X-24 (Gigabit)

### Información General
- **Hostname:** SW-CORE-BONGO
- **IP de Gestión:** 192.168.10.2 /24 (VLAN 10)
- **Rol:** Switch principal del nodo Cerrito Bongo

### VLANs Configuradas
| VLAN | Nombre                    | IPv4 Gateway       | Propósito |
|------|---------------------------|--------------------|---------|
| 10   | Gestion                   | 192.168.10.1       | Administración |
| 20   | Servidores                | 192.168.20.1       | Servidores críticos |
| 30   | Clientes_Cerrito_Bongo    | 192.168.30.1       | Clientes locales |
| 40   | Enlace_Cocalito           | 192.168.40.1       | Enlace hacia Cocalito |
| 50   | Services_RPi              | 192.168.50.1       | Servicios Raspberry Pi |
| 100  | Wireless_Clients          | 192.168.100.1      | Clientes WiFi |

### Mapeo de Puertos

| Puerto              | Descripción                    | Modo     | VLANs permitidas / Access |
|---------------------|--------------------------------|----------|---------------------------|
| Gi1/0/1             | MiniPC_Core_Services           | Access   | 20                        |
| Gi1/0/2             | RPi5_Services                  | Access   | 50                        |
| Gi1/0/3             | Radio_Link_900MHz              | Access   | 10                        |
| Gi1/0/4             | AP_Pacific_Edge                | Trunk    | 20,100                    |
| Gi1/0/24            | Uplink_pfSense                 | Trunk    | 10,20,30,40,50,100        |

### Comandos Útiles
```bash
show vlan brief
show interfaces status
show running-config
show ip interface brief