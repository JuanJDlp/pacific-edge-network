# Node Exporter — Métricas del sistema

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/node_exporter/`
**Servicio systemd:** `prometheus-node-exporter`
**Puerto:** `:9100`

---

## Qué hace

Node Exporter expone métricas del sistema operativo de la RPi en formato Prometheus. Prometheus en el Mini PC las recolecta cada 15 segundos y las almacena para visualización en Grafana.

---

## Métricas expuestas

Node Exporter expone cientos de métricas. Las más relevantes para esta red:

| Métrica | Descripción |
|---|---|
| `node_cpu_seconds_total` | Uso de CPU por modo (idle, user, system, iowait) |
| `node_memory_MemAvailable_bytes` | RAM disponible |
| `node_filesystem_avail_bytes` | Espacio libre en disco por partición |
| `node_filesystem_size_bytes` | Tamaño total de cada partición |
| `node_network_receive_bytes_total` | Bytes recibidos por interfaz |
| `node_network_transmit_bytes_total` | Bytes transmitidos por interfaz |
| `node_load1` / `node_load5` | Carga del sistema (1 y 5 minutos) |
| `node_disk_io_time_seconds_total` | Tiempo de I/O en disco |
| `node_temperature_zone_temp` | Temperatura de la RPi (si está disponible) |

---

## Quién la consulta

Prometheus en el Mini PC tiene configurado el scrape job:

```yaml
- job_name: 'rpi_node'
  static_configs:
    - targets: ['192.168.20.10:9100']
  relabel_configs:
    - target_label: instance
      replacement: rpi-servicios
```

Prometheus alcanza `192.168.20.10:9100` directamente por VLAN20 cada 15 segundos.

---

## Acceso

El puerto 9100 no está expuesto públicamente — solo accesible desde la red interna (VLAN20/VLAN10). El firewall del Mini PC limita el acceso a métricas desde VLAN10.

Para ver las métricas en crudo:

```bash
curl http://192.168.20.10:9100/metrics
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status prometheus-node-exporter

# Ver métricas en crudo (desde la RPi)
curl -s http://localhost:9100/metrics | grep -E "node_memory|node_cpu|node_filesystem"

# Temperatura de la RPi
curl -s http://localhost:9100/metrics | grep temperature

# Uso de disco del ZIM y caché
curl -s http://localhost:9100/metrics | grep 'node_filesystem_avail_bytes.*biblioteca'

# Logs
sudo journalctl -u prometheus-node-exporter -f
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags node_exporter
# o:
ansible-playbook services/node_exporter.yml -i rpi-setup/inventory.ini
```
