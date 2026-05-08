# Documentación — Servidor DHCP4 con ISC Kea

**Proyecto:** Red Comunitaria Cerrito Bongo & Cocalito — Universidad ICESI  
**Software:** ISC Kea DHCPv4 v2.4.1  
**Host:** Mini PC Ubuntu Server 24.04 — `100.90.95.134` (Netbird VPN)

---

## Estado actual del servicio

```
● kea-dhcp4-server.service - Kea IPv4 DHCP daemon
   Estado:   active (running)
   Habilitado en boot: sí
   Puerto:   UDP 67
   Config:   /etc/kea/kea-dhcp4.conf
   Leases:   /var/lib/kea/kea-leases4.csv
   Logs:     /var/log/kea/kea-dhcp4.log
```

### ¿Por qué Kea solo escucha en 2 interfaces ahora?

Kea está configurado con `"interfaces": ["*"]` (todas las interfaces), pero actualmente **solo escucha en `enp170s0` (WAN) y `wt0` (Netbird)** porque las interfaces VLAN (`enp171s0.10/20/30`) están en estado `LOWERLAYERDOWN` — el puerto LAN del Mini PC no tiene cable físico al switch todavía.

En cuanto se conecte el cable al switch, esas interfaces pasarán a estado `UP` y Kea necesita ser **reiniciado una vez** para que las detecte:

```bash
sudo systemctl restart kea-dhcp4-server
```

A partir de ahí, Kea servirá leases normalmente en las 3 VLANs.

---

## Subredes configuradas

| VLAN | Red | Pool asignable | Gateway | DNS |
|------|-----|----------------|---------|-----|
| VLAN 10 — Gestión | `192.168.10.0/24` | `.50` → `.99` (50 IPs) | `192.168.10.1` | `192.168.10.1` |
| VLAN 20 — Servidores | `192.168.20.0/24` | `.50` → `.99` (50 IPs) | `192.168.20.1` | `192.168.10.1` |
| VLAN 30 — Clientes WiFi | `192.168.30.0/24` | `.100` → `.200` (101 IPs) | `192.168.30.1` | `192.168.10.1` |

**Dominio de búsqueda entregado a clientes:** `comunitaria.local`

> El DNS `192.168.10.1` es la IP reservada para Pi-hole (aún no instalado). Hasta que Pi-hole esté activo, los clientes recibirán esa IP como DNS pero no podrá resolver — esto es intencional: el DNS forzado en nftables intercepta todo el puerto 53 y lo redirige a `192.168.10.1:53`, así cuando Pi-hole esté, funciona sin cambiar nada.

### Rangos reservados (fuera del pool)

Cada subred tiene IPs deliberadamente fuera del pool DHCP para asignarlas de forma estática a dispositivos fijos:

| VLAN | Rango estático | Uso previsto |
|------|----------------|-------------|
| VLAN 10 | `192.168.10.1` – `.49` | Gateway (`.1`), Pi-hole (`.1`), infraestructura |
| VLAN 20 | `192.168.20.1` – `.49` | Gateway (`.1`), Raspberry Pi (`.10` estática) |
| VLAN 30 | `192.168.30.1` – `.99` | Gateway (`.1`), Access Point (IP fija si se necesita) |

---

## Parámetros de lease

| Parámetro | Valor | Significado |
|-----------|-------|-------------|
| `valid-lifetime` | 4000 s (~66 min) | Tiempo total del lease |
| `renew-timer` (T1) | 1000 s (~16 min) | El cliente pide renovación al servidor original |
| `rebind-timer` (T2) | 2000 s (~33 min) | El cliente hace broadcast buscando cualquier servidor |
| `lfc-interval` | 3600 s (1 hora) | Frecuencia de limpieza del archivo de leases |

---

## Cómo funciona el playbook

El playbook principal es `provision/dhcp4.yml`. Se ejecuta desde `dhcp/dhcp4_role/provision/`:

```bash
ansible-playbook -i ../inventory.yml dhcp4.yml
```

### Estructura de archivos

```
dhcp/
└── dhcp4_role/             ← el rol Ansible completo
    ├── inventory.yml       ← apunta al Mini PC vía Netbird
    ├── provision/
    │   ├── ansible.cfg     ← configura roles_path para encontrar el rol
    │   ├── dhcp4.yml       ← playbook principal
    │   └── setup_ssh.yml   ← copia llave SSH (uso único)
    ├── tasks/
    │   ├── main.yml        ← punto de entrada, importa los demás
    │   ├── install.yml     ← instala kea-dhcp4-server
    │   ├── directories.yml ← crea /var/lib/kea y /var/log/kea
    │   ├── configure.yml   ← despliega kea-dhcp4.conf desde template
    │   ├── service.yml     ← habilita y arranca el servicio
    │   └── verify.yml      ← comprueba que el puerto 67 está activo
    ├── templates/
    │   └── kea-dhcp4.conf.j2   ← config de Kea en Jinja2
    └── vars/
        ├── main.yml        ← IPs, subredes, timers (editar aquí)
        └── Debian.yml      ← nombres de paquetes/servicio para Ubuntu
```

### Secuencia de ejecución

```
Gathering Facts
    │
    ▼
[always] Cargar vars/Debian.yml según OS
    │
    ▼
[install] apt install kea-dhcp4-server
    │
    ▼
[config] Crear /var/lib/kea/ y /var/log/kea/
    │
    ▼
[config] Desplegar /etc/kea/kea-dhcp4.conf desde template
    │       └─ si cambió → notify: "Reiniciar Kea DHCPv4"
    ▼
[config] Validar sintaxis: sudo -u _kea kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
    │
    ▼
[service] systemctl enable --now kea-dhcp4-server
    │
    ▼
[verify] ss -tuln | grep :67  →  assert puerto activo
    │
    ▼
[verify] systemctl status kea-dhcp4-server  →  imprimir en pantalla
    │
    ▼
HANDLER (si config cambió): systemctl restart kea-dhcp4-server
```

### Tags disponibles

```bash
# Solo instalar el paquete
ansible-playbook -i ../inventory.yml dhcp4.yml --tags install

# Solo redesplegar la config (sin reinstalar)
ansible-playbook -i ../inventory.yml dhcp4.yml --tags config

# Solo reiniciar/habilitar el servicio
ansible-playbook -i ../inventory.yml dhcp4.yml --tags service

# Solo verificar que funciona
ansible-playbook -i ../inventory.yml dhcp4.yml --tags verify
```

---

## Variables que se deben editar para cambiar la config

Todo está en `vars/main.yml`. No hay valores hardcodeados en tasks ni templates.

```yaml
kea_listen_interface: "*"          # interfaces de escucha ("*" = todas)
kea_valid_lifetime: 4000           # duración del lease en segundos
kea_dns_servers: "192.168.10.1"    # DNS entregado a clientes

kea_subnets:
  - id: 30
    subnet: "192.168.30.0/24"
    pool_start: "192.168.30.100"
    pool_end:   "192.168.30.200"
    gateway:    "192.168.30.1"
```

Después de editar, re-ejecutar el playbook. Si la config cambia, el handler reinicia Kea automáticamente.

---

## Cómo verificar que DHCP funciona

### Verificación inmediata (sin switch conectado)

```bash
# Conectarse al Mini PC
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134

# 1. Confirmar que el servicio está corriendo
systemctl status kea-dhcp4-server --no-pager

# 2. Confirmar que el puerto 67 está abierto
ss -tuln | grep 67

# 3. Ver las subnets que Kea cargó al arrancar
sudo journalctl -u kea-dhcp4-server --no-pager | grep -E 'SUBNET|STARTED|WARN'

# 4. Ver el archivo de leases (vacío hasta que haya clientes)
cat /var/lib/kea/kea-leases4.csv
```

### Verificación con clientes reales (después de conectar el switch)

```bash
# Reiniciar Kea para que detecte las interfaces VLAN recién activas
sudo systemctl restart kea-dhcp4-server

# Desde el Mini PC: ver leases asignados en tiempo real
sudo tail -f /var/lib/kea/kea-leases4.csv

# Desde un cliente en VLAN 30: verificar que recibió IP en el rango correcto
ip addr show          # debe mostrar 192.168.30.100-200
ip route show         # gateway debe ser 192.168.30.1
cat /etc/resolv.conf  # DNS debe ser 192.168.10.1
```

### Prueba manual de DHCP desde línea de comandos (en un cliente Linux)

```bash
# Solicitar lease manualmente en una interfaz (sin afectar la config permanente)
sudo dhclient -v -1 eth0

# Liberar el lease
sudo dhclient -r eth0
```

---

## Consideraciones importantes

### 1. AppArmor restringe kea-dhcp4 como root
El binario `kea-dhcp4` está bajo un perfil AppArmor en Ubuntu 24.04 que impide que se ejecute con permisos de root para leer archivos de config. Por eso la validación del playbook usa `sudo -u _kea kea-dhcp4 -t ...` en vez del módulo `validate:` de Ansible.

### 2. Kea no detecta interfaces que suben después de su arranque
Si las VLANs estaban `LOWERLAYERDOWN` cuando Kea arrancó, no se ató a ellas. Después de conectar el cable al switch hay que hacer `systemctl restart kea-dhcp4-server` una vez para que las detecte.

### 3. El DNS que Kea entrega aún no responde
`192.168.10.1` (Pi-hole) no está instalado todavía. Los clientes recibirán esa IP como DNS server pero las consultas no resolverán. Instalar Pi-hole en `192.168.10.1` es el siguiente paso.

### 4. Kea escucha también en WAN y Netbird
Con `"interfaces": ["*"]`, Kea escucha en **todas** las interfaces activas, incluidas `enp170s0` (WAN) y `wt0` (Netbird). Esto es inofensivo porque:
- En WAN, el router externo no reenvía paquetes DHCP hacia el Mini PC
- En Netbird, solo hay tráfico de gestión

Si en algún momento se quiere restringir solo a las VLANs, cambiar en `vars/main.yml`:
```yaml
kea_listen_interface: "enp171s0.10 enp171s0.20 enp171s0.30"
```

### 5. El playbook es idempotente
Correrlo múltiples veces no genera cambios si la config ya está aplicada. El servicio solo se reinicia cuando el template de config cambia efectivamente.
