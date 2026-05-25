# Fix: DNS sin respuesta desde VLAN30 — Conflicto UFW + nftables

**Fecha:** 2026-05-20
**Afecta:** Mini PC (`plataformas`, 100.90.95.134)
**Síntoma:** Clientes VLAN30 no reciben respuesta DNS. Wireshark mostraba queries UDP saliendo hacia `192.168.10.1:53` pero ningún reply. El DHCP funcionaba normalmente (los clientes obtenían IP).

---

## Diagnóstico

### Lo que funcionaba correctamente
- `named` corriendo desde hace días, escuchando en `192.168.10.1:53`, `192.168.20.1:53`, `192.168.30.1:53`, `127.0.0.1:53`.
- Todas las interfaces VLAN (`enp171s0.10/20/30`) en estado `UP LOWER_UP`.
- `dig @192.168.10.1 biblioteca.tel` desde el Mini PC respondía correctamente (192.168.20.10).
- DHCP enviando `192.168.10.1` como servidor DNS a todos los subnets.
- nftables `inet filter input` aceptando UDP/TCP 53 desde todas las interfaces VLAN.

### Causa raíz: UFW activo en paralelo con nftables

**UFW estaba activo** (`sudo ufw status: active`) y había registrado sus propias cadenas en nftables:

```
table ip filter {
    chain INPUT {
        type filter hook input priority filter; policy drop;  ← política DROP
        ...
        jump ufw-user-input
    }
}
```

En nftables, múltiples tablas registradas en el mismo hook (`input priority filter`) **se ejecutan de forma independiente**. La aceptación de una tabla no cancela el procesamiento de las demás.

Flujo real de un paquete DNS UDP desde VLAN30:
1. `inet filter input` (Ansible) — **ACCEPT** (regla: `iif enp171s0.30 udp dport 53 accept`)
2. `ip filter INPUT` (UFW) — **DROP** (política: `deny incoming`; `ufw-user-input` solo permite TCP 22, 3000, 9090, 9100)

La cadena UFW tenía evidencia del bloqueo:
```
chain ufw-after-logging-input {
    limit rate 3/minute burst 10 packets counter packets 3982 bytes 326031 log prefix "[UFW BLOCK] "
}
```

### Por qué UFW estaba instalado
El rol de monitoreo (`prometheus`/`grafana`/`node_exporter`) abrió los puertos 3000, 9090 y 9100 en UFW en algún momento de la instalación, dejándolo activo. El rol `router` de Ansible no contemplaba deshabilitar UFW.

### Por qué los puertos de monitoreo no necesitan UFW
La regla `iif "wt0" accept` en nuestro `inet filter` ya acepta **todo** el tráfico entrante desde la interfaz NetBird (`wt0`), incluyendo Grafana (3000), Prometheus (9090) y node_exporter (9100). UFW era completamente redundante.

---

## Fix aplicado

### 1. Modificación Ansible

**Archivo:** `minipc/router-setup/roles/router/tasks/main.yml`

Se agregó la siguiente tarea a continuación de `Enable and start nftables service`, con tag `firewall`:

```yaml
- name: Disable UFW (conflicts with nftables-based firewall)
  ansible.builtin.systemd:
    name: ufw
    enabled: false
    state: stopped
  tags: firewall
```

Detener el servicio `ufw` ejecuta internamente `ufw --force disable`, que cambia las políticas de todas sus cadenas a `ACCEPT` y evita que se recarguen en el arranque.

### 2. Ejecución del playbook

```bash
cd minipc/router-setup
ansible-playbook playbook.yml -i inventory.ini --tags firewall
```

Resultado: `changed: [minipc]` en la tarea `Disable UFW`.

---

## Verificación

```bash
# En el Mini PC
sudo ufw status           # → Status: inactive
sudo nft list tables      # → ip filter e ip6 filter siguen en memoria pero con policy accept (se limpiarán en próximo reinicio)
dig @192.168.10.1 biblioteca.tel +short   # → 192.168.20.10 ✅
dig @192.168.30.1 biblioteca.tel +short   # → 192.168.20.10 ✅
```

Desde un cliente VLAN30: las queries DNS ahora reciben respuesta. `nslookup biblioteca.tel` → `192.168.20.10`.

---

## Nota sobre persistencia

Tras `ufw disable`, las tablas `ip filter` e `ip6 filter` de UFW permanecen en memoria con `policy accept` hasta el próximo reinicio. En el próximo arranque, `nftables.service` cargará únicamente `/etc/nftables.conf` (gestionado por Ansible: `inet filter`, `ip nat`, `netdev dhcp_fix`) y las cadenas UFW desaparecerán definitivamente.
