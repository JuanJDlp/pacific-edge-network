# Monitoreo — Prometheus + Grafana + exporters + nginx

> Actualizado: 2026-06-02

## Playbooks y roles Ansible

| Recurso | Ruta |
|---------|------|
| Playbook dedicado | `minipc/router-setup/playbook-monitoring.yml` |
| Playbook de servicio | `minipc/services/monitoring.yml` |
| Variables compartidas | `minipc/router-setup/group_vars/minipc/monitoring.yml` |

### Roles (bajo `minipc/router-setup/roles/`)

| Rol | Función |
|-----|---------|
| `prometheus` | Servidor Prometheus, almacenamiento local, scrape 15s |
| `node_exporter` | Métricas del Mini PC en `:9100` |
| `snmp_exporter` | Relay SNMP del switch Cisco en `127.0.0.1:9116` |
| `grafana` | Grafana en loopback `:3000`, datasource Prometheus |
| `nginx_monitor` | Vhost `monitor.biblioteca.tel` → Grafana + `/prometheus` |
| `bind9_dns` | Zona `biblioteca.tel` con registro `monitor` (vía rol `dns`) |
| `nftables` | Re-despliega firewall (acceso por HTTP :80, no :3000/:9090) |

## Despliegue

```bash
cd minipc/

# Solo monitoreo
ansible-playbook -i router-setup/inventory.ini router-setup/playbook-monitoring.yml

# Con verificación
ansible-playbook -i router-setup/inventory.ini router-setup/playbook-monitoring.yml --tags verify

# Playbook completo del Mini PC (incluye monitoreo)
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags monitoring
```

## Arquitectura

```
VLAN10 (gestión) / otras VLANs con DNS
        │
        ▼
 monitor.biblioteca.tel  →  192.168.10.1:80  (nginx)
        │
        ├── /              →  Grafana 127.0.0.1:3000
        └── /prometheus/   →  Prometheus 127.0.0.1:9090

Prometheus (scrape cada 15s)
        ├── localhost:9090        (prometheus)
        ├── localhost:9100        (minipc_node)
        ├── 192.168.20.10:9100    (rpi_node)
        └── snmp_exporter:9116 → 192.168.10.2 (switch_snmp, if_mib)
```

## Targets Prometheus

| Job | Target | instance |
|-----|--------|----------|
| prometheus | localhost:9090 | — |
| minipc_node | localhost:9100 | minipc |
| rpi_node | 192.168.20.10:9100 | rpi-servicios |
| switch_snmp | 192.168.10.2 vía localhost:9116 | 192.168.10.2 |

SNMP: comunidad `MONITOR_RO`, módulo `if_mib`, auth `public_v2`.

## DNS

Registro en `roles/dns/vars/main.yml`:

```yaml
- { name: "monitor", ip: "192.168.10.1", ipv6: "fd00:0:0:10::1", vlan_octet: "10" }
```

Zona en el servidor: `/etc/bind/zones/db.biblioteca.tel` (firmada → `.signed`).

## Acceso

| URL | Notas |
|-----|-------|
| http://monitor.biblioteca.tel/ | Grafana (desde red interna) |
| http://monitor.biblioteca.tel/prometheus/ | UI Prometheus |
| Grafana directo | Solo `127.0.0.1:3000` (no expuesto a la red) |

Credenciales Grafana por defecto: `admin` / `admin`.

## Verificación manual

```bash
systemctl status prometheus prometheus-node-exporter prometheus-snmp-exporter grafana-server nginx named

dig @192.168.10.1 monitor.biblioteca.tel +short
# → 192.168.10.1

curl -sI http://monitor.biblioteca.tel/login
curl -s http://127.0.0.1:9090/prometheus/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'
```

**Requisitos externos:** `node_exporter` en la RPi (`raspberry/services/node_exporter.yml`) y SNMP habilitado en el switch (`192.168.10.2`, comunidad `MONITOR_RO`).

## Archivos desplegados (Mini PC)

| Destino | Template |
|---------|----------|
| `/etc/prometheus/prometheus.yml` | `prometheus/templates/prometheus.yml.j2` |
| `/etc/default/prometheus` | `prometheus/templates/prometheus.default.j2` |
| `/etc/prometheus/snmp.yml` | `snmp_exporter/templates/snmp.yml.j2` |
| `/etc/nginx/sites-available/monitor` | `nginx_monitor/templates/monitor.nginx.j2` |
| `/etc/grafana/provisioning/datasources/prometheus.yml` | `grafana/templates/datasource-prometheus.yml.j2` |
| `/etc/bind/zones/db.biblioteca.tel` | `dns/templates/db.forward.j2` |
