# node_exporter — Metricas del sistema RPi para Prometheus

> **Ultima actualizacion:** 2026-05-30
> **Estado actual: INACTIVO** — El servicio existe pero no esta corriendo.

## Rol Ansible

`raspberry/rpi-setup/roles/node_exporter/`

## Descripcion

`prometheus-node-exporter` expone metricas del sistema (CPU, RAM, disco, red) de la RPi en el puerto 9100. Prometheus en el Mini PC scrapes estas metricas cada 15 segundos y Grafana las visualiza.

**Nota:** Actualmente el servicio `prometheus-node-exporter` esta **inactivo** en la RPi. Prometheus en el Mini PC no recibe metricas de la RPi hasta que se reactive.

Para reactivar:
```bash
sudo systemctl start prometheus-node-exporter
sudo systemctl enable prometheus-node-exporter
```

## Integracion con Prometheus (Mini PC)

El job `rpi_node` fue habilitado en `minipc/router-setup/roles/monitoring/templates/prometheus.yml.j2`:

```yaml
- job_name: 'rpi_node'
  static_configs:
    - targets: ['192.168.20.10:9100']
  relabel_configs:
    - target_label: instance
      replacement: rpi-servicios
```

Prometheus en el Mini PC (192.168.10.1:9090) puede acceder a 192.168.20.10:9100 via la VLAN20 de servidores.

## Metricas disponibles (cuando el servicio este activo)

```
node_cpu_seconds_total          # uso de CPU por nucleo
node_memory_MemAvailable_bytes  # RAM disponible
node_filesystem_avail_bytes     # espacio en disco libre
node_network_receive_bytes_total # bytes recibidos por interfaz
node_load1, node_load5, node_load15  # load average
node_disk_io_time_seconds_total # I/O de disco
```

## Acceso al endpoint

```bash
# Desde Mini PC (VLAN20 directa) — solo si el servicio esta activo
curl http://192.168.20.10:9100/metrics | grep node_load1

# Desde la misma RPi
curl http://localhost:9100/metrics
```

## Dashboards en Grafana

En Grafana (Mini PC, puerto 3000), importar el dashboard estandar de node_exporter:
- **Dashboard ID**: 1860 (Node Exporter Full)
- Seleccionar datasource: Prometheus
- Filtrar por instance: `rpi-servicios`

## Verificacion

```bash
# En RPi — verificar estado del servicio (actualmente inactivo)
systemctl status prometheus-node-exporter

# Reactivar si es necesario
sudo systemctl start prometheus-node-exporter
sudo systemctl enable prometheus-node-exporter

# En Mini PC — Prometheus recibe metricas
curl http://localhost:9090/api/v1/targets | \
  python3 -c "import sys,json; [print(t['labels']['instance'], t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"

# En Mini PC — query de metricas
curl -s 'http://localhost:9090/api/v1/query?query=node_load1{instance="rpi-servicios"}' | python3 -m json.tool
```
