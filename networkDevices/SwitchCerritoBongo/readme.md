# Switch Core - Cerrito Bongo

**Modelo:** Cisco Catalyst 2960 (24 puertos FastEthernet)

### Información General
- **Hostname:** SW-CORE-BONGO
- **IP de Gestión:** `192.168.10.2/24` (VLAN 10, accesible desde Mini PC)
- **Rol:** Switch principal del nodo Cerrito Bongo

### Credenciales
| Acceso | Usuario | Contraseña |
|--------|---------|------------|
| Enable (modo privilegiado) | — | `password` |
| SSH / Telnet | `user` | `password` |

### Conectarse por SSH (recomendado)
Desde el Mini PC (conectado por VLAN 10):
```
ssh admin@192.168.10.2
```
O desde cualquier equipo en VLAN 10 (192.168.10.0/24).

Telnet también funciona si SSH no está disponible:
```
telnet 192.168.10.2
```

### VLANs Configuradas
| VLAN | Nombre          | Subred IPv4      | Notas |
|------|-----------------|------------------|-------|
| 10   | Gestion         | 192.168.10.0/24  | Gestión del switch (SVI: 192.168.10.2) y equipos de administración |
| 20   | Servidores      | 192.168.20.0/24  | RPi5, servicios críticos |
| 30   | Clientes        | 192.168.30.0/24  | Clientes WiFi Cerrito Bongo |
| 40   | EnlaceCocalito  | 192.168.40.0/24  | Radio enlace hacia nodo Cocalito |

### Mapeo de Puertos

| Puerto         | Descripción               | Modo   | VLAN(s)      |
|----------------|---------------------------|--------|--------------|
| FastEthernet0/1  | RPi5_Servicios            | Access | 20           |
| FastEthernet0/2  | Servidor_VLAN20           | Access | 20           |
| FastEthernet0/3  | RadioEnlace_900MHz        | Access | 10           |
| FastEthernet0/4  | AP_PacificEdge_WiFi       | Trunk  | 20, 30       |
| FastEthernet0/24 | Uplink_MiniPC_Router      | Trunk  | 10,20,30,40  |

> **Nota:** El Mini PC se conecta en **Fa0/24** (trunk). La RPi5 va en **Fa0/1** (access VLAN 20).

### Comandos Útiles
```
show vlan brief
show interfaces status
show interfaces trunk
show running-config
show ip interface brief
show ssh