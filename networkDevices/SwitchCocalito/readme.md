# Switch Core - Cocalito

**Modelo:** Cisco (Pendiente de especificar modelo exacto)

### Información General
- **Hostname:** SW-CORE-COCALITO
- **IP de Gestión:** 192.168.10.3 /24 (VLAN 10)
- **Rol:** Switch secundario del nodo Cocalito
- **Conexión principal:** Radio Enlace hacia Raisecom (Cerrito Bongo)

### VLANs Configuradas
| VLAN | Nombre                    | IPv4 Gateway       | Propósito |
|------|---------------------------|--------------------|---------|
| 10   | Gestion                   | 192.168.10.3       | Administración |
| 20   | Servidores                | 192.168.20.3       | Servidores críticos |
| 30   | Clientes_Cerrito_Bongo    | 192.168.30.3       | Clientes locales |
| 40   | Enlace_Cocalito           | 192.168.40.3       | Red local Cocalito |
| 50   | Services_RPi              | 192.168.50.3       | Servicios |
| 100  | Wireless_Clients          | 192.168.100.3      | Clientes WiFi |

### Mapeo de Puertos

| Puerto              | Descripción                    | Modo     | VLANs permitidas / Access |
|---------------------|--------------------------------|----------|---------------------------|
| Gi1/0/24            | Radio_Enlace_a_Raisecom_Bongo  | Trunk    | 10,20,30,40,50,100        |
| Gi1/0/1             | AP-Cocalito-1                  | Trunk    | 20,100                    |
| Gi1/0/2             | AP-Cocalito-2                  | Trunk    | 20,100                    |
| Gi1/0/3             | AP-Cocalito-3                  | Trunk    | 20,100                    |
| Gi1/0/4             | AP-Cocalito-4                  | Trunk    | 20,100                    |

### Notas Importantes
- El puerto **Gi1/0/24** es el trunk principal hacia el radio enlace.
- Todos los Access Points están configurados en modo **trunk** (VLAN 20 para gestión y 100 para clientes WiFi).
- El tráfico hacia Bongo viaja por el radio enlace a través del trunk en VLANs permitidas.

### Comandos Útiles
```bash
show vlan brief
show interfaces trunk
show interfaces status
show running-config