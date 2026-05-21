# Fix: Portal cautivo — autenticación por MAC en lugar de IP

**Fecha:** 2026-05-21
**Afecta:** Mini PC (`plataformas`) — nftables + captive-accept.py

## Síntoma

Si el dispositivo A se autentica en el portal cautivo y obtiene la IP `192.168.30.101`, luego se desconecta y el DHCP le asigna esa misma IP al dispositivo B (dentro de la ventana de 8h del set nftables), el dispositivo B entra a la red **sin pasar por el portal cautivo**.

## Causa raíz

El set nftables `captive_allowed` era de tipo `ipv4_addr`. El tracking de autenticación era por IP, no por dispositivo. Cualquier dispositivo que obtuviera una IP ya autorizada heredaba el acceso automáticamente.

```nftables
# ANTES (vulnerable)
set captive_allowed {
    type ipv4_addr       ← solo rastreable por IP
    flags dynamic, timeout
    timeout 8h
}
```

La vida útil del set (8h) es independiente del tiempo de arrendamiento DHCP. Un dispositivo puede desconectarse, el DHCP reasignar su IP en minutos, y la IP seguir autorizada en nftables.

## Fix aplicado

### 1. `minipc/router-setup/roles/router/templates/nftables.conf.j2`

**Set:** cambio de `ipv4_addr` a `ether_addr`, renombrado a `captive_allowed_mac`.

```diff
-    set captive_allowed {
-        type ipv4_addr
-        flags dynamic, timeout
-        timeout 8h
-        comment "Clientes VLAN30 autenticados via portal cautivo"
-    }
+    set captive_allowed_mac {
+        type ether_addr
+        flags dynamic, timeout
+        timeout 8h
+        comment "Clientes VLAN30 autenticados via portal cautivo (MAC)"
+    }
```

**Mangle chain:** match por MAC en lugar de IP.

En el hook `prerouting priority mangle` (-150), el frame Ethernet está íntegro y `ether saddr` es accesible en la familia `inet`.

```diff
-    iif "{{ client_iface }}" ip saddr @captive_allowed meta mark set 0x1
+    iif "{{ client_iface }}" ether saddr @captive_allowed_mac meta mark set 0x1
```

**Forward chain:** uso de `meta mark 0x1` en lugar de `ip saddr @captive_allowed`.

En el hook `forward`, el header L2 ya no está presente (el paquete fue entregado a la capa IP). Se usa el mark establecido por el mangle anterior.

```diff
-    iif "{{ client_iface }}" oif "{{ wan_interface }}" ip saddr @captive_allowed accept
-    iif "{{ client_iface }}" oif "{{ lan_interface }}.20" ip saddr @captive_allowed accept
-    iif "{{ client_iface }}" oif "{{ lan_interface }}" ip saddr @captive_allowed accept
+    iif "{{ client_iface }}" oif "{{ wan_interface }}" meta mark 0x1 accept
+    iif "{{ client_iface }}" oif "{{ lan_interface }}.20" meta mark 0x1 accept
+    iif "{{ client_iface }}" oif "{{ lan_interface }}" meta mark 0x1 accept
```

### 2. `minipc/router-setup/roles/captive_portal/files/captive-accept.py`

Se agrega la función `lookup_mac_for_ip()` que consulta la tabla ARP del kernel. La entrada ARP existe con certeza al momento de procesar `/accept` — el kernel ya resolvió la MAC al recibir el SYN del cliente.

```python
NFT_SET_NAME = 'captive_allowed_mac'
VLAN30_IFACE = 'enp171s0.30'
MAC_RE       = re.compile(r'lladdr\s+([0-9a-f]{2}(?::[0-9a-f]{2}){5})', re.IGNORECASE)

def lookup_mac_for_ip(client_ip):
    try:
        result = subprocess.run(
            ['ip', 'neigh', 'show', client_ip, 'dev', VLAN30_IFACE],
            check=True, capture_output=True, text=True, timeout=2
        )
        m = MAC_RE.search(result.stdout)
        if m:
            return m.group(1).lower()
        ...
```

En `do_GET()`, en lugar de agregar la IP al set, se resuelve la MAC y se agrega ella:

```python
mac = lookup_mac_for_ip(client_ip)
if mac:
    subprocess.run(['nft', 'add', 'element', 'inet', 'filter',
                    'captive_allowed_mac', '{ ' + mac + ' }'], ...)
    logging.info('Authorized: IP=%s MAC=%s', client_ip, mac)
```

### 3. `minipc/router-setup/playbook.yml`

Tarea de verificación actualizada para el nuevo nombre del set:

```diff
-    - name: Verificar set captive_allowed
-      command: nft list set inet filter captive_allowed
+    - name: Verificar set captive_allowed_mac
+      command: nft list set inet filter captive_allowed_mac
```

## Verificación

```bash
# Set existe con tipo ether_addr
ssh minipc "sudo nft list set inet filter captive_allowed_mac"
# → type ether_addr ✅

# Mangle usa ether saddr
ssh minipc "sudo nft list chain inet filter captive_mangle"
# → ether saddr @captive_allowed_mac meta mark set 0x1 ✅

# Forward usa meta mark
ssh minipc "sudo nft list chain inet filter forward | grep mark"
# → meta mark 0x00000001 accept ✅

# Después de autenticar un dispositivo, verificar que aparece su MAC (no la IP):
ssh minipc "sudo nft list set inet filter captive_allowed_mac"
# → elements = { aa:bb:cc:dd:ee:ff expires 7h59m... } ✅
```

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags captive_portal
```

## Nota sobre MAC spoofing

Esta solución protege contra la reasignación accidental de IPs por DHCP (el caso de uso normal). No protege contra un atacante que deliberadamente configure su MAC para que coincida con la de un dispositivo ya autorizado. Para ese nivel de protección se requiere 802.1X/EAP, que está fuera del alcance de esta red comunitaria.
