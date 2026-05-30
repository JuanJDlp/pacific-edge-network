# Monitoreo — Prometheus + Grafana + node_exporter + snmp_exporter

> Actualizado: 2026-05-30

## Rol Ansible

`minipc/router-setup/roles/monitoring/`

## Descripcion

Stack de monitoreo para la red comunitaria. Prometheus recolecta metricas del Mini PC, la RPi y el switch L2 (via SNMP). node_exporter expone metricas del sistema, snmp_exporter expone metricas SNMP del switch, y Grafana las visualiza en dashboards. Todo corre localmente en el Mini PC.

## Componentes

### Prometheus (puerto 9090)

Servidor de métricas con scraping cada 15 segundos.

**Targets configurados:**
| Job | Target | Instancia |
|---|---|---|
| prometheus | localhost:9090 | self-monitoring |
| minipc_node | localhost:9100 | Mini PC |
| rpi_node | 192.168.20.10:9100 | RPi (akasicom2) |
| switch_snmp | 192.168.10.2 (via snmp_exporter :9116) | Switch Cisco L2 |

### node_exporter (puerto 9100)

Expone métricas del sistema operativo del Mini PC: CPU, memoria, disco, red, procesos.

Paquete: `prometheus-node-exporter` (repositorio oficial de Ubuntu).

### snmp_exporter (puerto 9116)

Expone metricas SNMP del switch Cisco L2 (`192.168.10.2`). Prometheus lo usa como relay: scraping a `localhost:9116` con parametro `target=192.168.10.2`.

### Grafana (puerto 3000) — v13.0.1

Dashboard web de visualizacion. Accesible desde la red de gestion (VLAN10) en `http://192.168.10.1:3000` o via `monitoreo.biblioteca.tel`.

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
| Grafana | http://192.168.10.1:3000 o http://monitoreo.biblioteca.tel | Solo desde VLAN10 |
| node_exporter metrics | http://192.168.10.1:9100/metrics | Raw metrics Mini PC |
| snmp_exporter metrics | http://192.168.10.1:9116/metrics | Raw metrics switch SNMP |

El nftables debe permitir acceso a estos puertos desde VLAN10. Si no están accesibles, agregar reglas de input para los puertos 9090, 9100 y 3000.

## Configurar Grafana — primeros pasos

1. Abrir `http://192.168.10.1:3000` desde VLAN10
2. Login: `admin` / `admin` → cambiar contraseña
3. Agregar datasource: Connections → Data sources → Add → Prometheus
   - URL: `http://localhost:9090`
4. Importar dashboard: `+` → Import → ID `1860` (Node Exporter Full)

## Variables

No hay variables específicas en este rol. Los puertos son los estándar de cada paquete.

## Verificacion

```bash
# Estado de servicios
systemctl status prometheus
systemctl status prometheus-node-exporter
systemctl status grafana-server
systemctl status prometheus-snmp-exporter

# Verificar endpoints
curl -s http://localhost:9090/-/healthy
# -> Prometheus is Healthy.

curl -s http://localhost:9100/metrics | head -5
# -> # HELP go_gc_duration_seconds ...

curl -s http://localhost:3000/api/health
# -> {"commit":"...","database":"ok","version":"13.0.1"}

# Verificar SNMP del switch
curl -s "http://localhost:9116/snmp?target=192.168.10.2" | head -5
```

## Monitoreo de RPi

node_exporter ya esta instalado y activo en la RPi (`192.168.20.10:9100`). Prometheus lo scrapea bajo el job `rpi_node`.
