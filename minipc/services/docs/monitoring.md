# Monitoreo — Prometheus + Grafana + Node Exporter

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/monitoring/`
**Servicios systemd:** `prometheus`, `grafana-server`, `prometheus-node-exporter`

---

## Qué hace

Stack de monitoreo completo para observar el estado del Mini PC y la Raspberry Pi. Prometheus recolecta métricas, Node Exporter las expone desde cada host, y Grafana las visualiza en dashboards.

---

## Componentes

### Prometheus (`:9090`)

Scraper de métricas. Se instala desde los repos de Ubuntu (`apt`). Configuración en `/etc/prometheus/prometheus.yml`.

**Jobs configurados:**

| Job | Target | Instancia |
|---|---|---|
| `prometheus` | `localhost:9090` | (métricas propias) |
| `minipc_node` | `localhost:9100` | `minipc` |
| `rpi_node` | `192.168.20.10:9100` | `rpi-servicios` |

Scrape interval: **15 segundos**.

Prometheus alcanza la RPi directamente por VLAN20 (`192.168.20.10:9100`). La RPi corre su propio `node_exporter` (ver `raspberry/services/docs/node-exporter.md`).

### Node Exporter (`:9100`)

Expone métricas del sistema operativo del Mini PC: CPU, RAM, disco, red, procesos, etc. Se instala como `prometheus-node-exporter` desde apt.

### Grafana (`:3000`)

Dashboard web. Se instala desde el repositorio oficial de Grafana. Solo accesible desde **VLAN10 (gestión)** — nftables bloquea el puerto 3000 desde VLAN30.

Acceso: `http://192.168.10.1:3000` (desde VLAN10 o VPN NetBird)

Credenciales por defecto: `admin` / `admin` (cambiar en el primer login).

---

## Acceso a los servicios

| Servicio | Puerto | Acceso permitido |
|---|---|---|
| Prometheus | `:9090` | Solo VLAN10 |
| Grafana | `:3000` | Solo VLAN10 |
| Node Exporter | `:9100` | Solo VLAN10 |

El firewall (nftables) permite estos puertos solo desde `enp171s0.10`:
```
iif "enp171s0.10" tcp dport { 9090, 3000, 9100 } accept
```

---

## Flujo de datos

```
[Mini PC — node_exporter :9100] ──────────────────┐
                                                   │
[RPi — node_exporter :9100] ──────────────────────┤
                                                   │ scrape cada 15s
                                                   ▼
                                         [Prometheus :9090]
                                                   │
                                                   ▼
                                         [Grafana :3000]
                                                   │
                                                   ▼
                                    [Administrador en VLAN10]
```

---

## Comandos útiles

```bash
# Estado de los servicios
sudo systemctl status prometheus grafana-server prometheus-node-exporter

# Ver targets que Prometheus está scrapeando
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E "job|health"

# Ver métricas del Mini PC directamente
curl -s http://localhost:9100/metrics | grep node_cpu

# Logs
sudo journalctl -u prometheus -f
sudo journalctl -u grafana-server -f
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags monitoring
# o:
ansible-playbook services/monitoring.yml -i router-setup/inventory.ini
```
