# Monitoreo — Prometheus + Grafana + node_exporter

## Rol Ansible

`minipc/router-setup/roles/monitoring/`

## Descripción

Stack de monitoreo para el Mini PC. Prometheus recolecta métricas del sistema, node_exporter las expone, y Grafana las visualiza en dashboards. Todo corre localmente en el Mini PC.

## Componentes

### Prometheus (puerto 9090)

Servidor de métricas con scraping cada 15 segundos.

**Targets configurados:**
| Job | Target | Instancia |
|---|---|---|
| prometheus | localhost:9090 | self-monitoring |
| minipc_node | localhost:9100 | minipc |

**Futuro:** El target de RPi (`192.168.20.10:9100`) está comentado en el template. Se activa cuando node_exporter esté instalado en la RPi.

### node_exporter (puerto 9100)

Expone métricas del sistema operativo del Mini PC: CPU, memoria, disco, red, procesos.

Paquete: `prometheus-node-exporter` (repositorio oficial de Ubuntu).

### Grafana (puerto 3000)

Dashboard web de visualización. Accesible desde la red de gestión (VLAN10) en `http://192.168.10.1:3000`.

**Credenciales por defecto:** `admin` / `admin` (cambiar al primer login).

Repositorio Grafana APT: `deb https://apt.grafana.com stable main`

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible |
|---|---|
| `/etc/prometheus/prometheus.yml` | `templates/prometheus.yml.j2` |

La configuración de Grafana (datasources, dashboards) se gestiona desde la UI web, no vía Ansible.

## Acceso

| Servicio | URL | Nota |
|---|---|---|
| Prometheus | http://192.168.10.1:9090 | Solo desde VLAN10 |
| Grafana | http://192.168.10.1:3000 | Solo desde VLAN10 |
| node_exporter metrics | http://192.168.10.1:9100/metrics | Raw metrics |

El nftables debe permitir acceso a estos puertos desde VLAN10. Si no están accesibles, agregar reglas de input para los puertos 9090, 9100 y 3000.

## Configurar Grafana — primeros pasos

1. Abrir `http://192.168.10.1:3000` desde VLAN10
2. Login: `admin` / `admin` → cambiar contraseña
3. Agregar datasource: Connections → Data sources → Add → Prometheus
   - URL: `http://localhost:9090`
4. Importar dashboard: `+` → Import → ID `1860` (Node Exporter Full)

## Variables

No hay variables específicas en este rol. Los puertos son los estándar de cada paquete.

## Verificación

```bash
# Estado de servicios
systemctl status prometheus
systemctl status prometheus-node-exporter
systemctl status grafana-server

# Verificar endpoints
curl -s http://localhost:9090/-/healthy
# → Prometheus is Healthy.

curl -s http://localhost:9100/metrics | head -5
# → # HELP go_gc_duration_seconds ...

curl -s http://localhost:3000/api/health
# → {"commit":"...","database":"ok","version":"..."}
```

## Agregar monitoreo de RPi (futuro)

1. Instalar node_exporter en RPi:
   ```bash
   sudo apt install prometheus-node-exporter
   ```
2. Descomentar en `templates/prometheus.yml.j2`:
   ```yaml
   - job_name: 'rpi_node'
     static_configs:
       - targets: ['192.168.20.10:9100']
     relabel_configs:
       - target_label: instance
         replacement: rpi5-servicios
   ```
3. Ejecutar playbook con tag `monitoring`:
   ```bash
   ansible-playbook -i inventory.ini playbook.yml --tags monitoring
   ```
