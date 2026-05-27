# Fix: Firewall role — sincronizar set captive_allowed_mac

**Fecha:** 2026-05-27
**Afecta:** Mini PC (`plataformas`, 100.90.95.134) — nftables firewall role

---

## Sintoma

El portal cautivo **no autenticaba a nadie**. Al dar click en "Entrar a la biblioteca":

1. `captive-accept.py` fallaba con:
   ```
   WARNING nft error para 192.168.30.103 (3c:ab:72:4a:b9:cd):
     Error: No such file or directory; did you mean set 'captive_allowed' in table inet 'filter'?
     add element inet filter captive_allowed_mac { 3c:ab:72:4a:b9:cd }
                             ^^^^^^^^^^^^^^^^^^^
   ```
2. El cliente quedaba permanentemente no autenticado
3. El redirect a `https://biblioteca.tel` entraba en un loop de TLS handshake fallido (15+ intentos/segundo):
   - nftables seguia DNATeando port 443 al portal (mark 0x1 nunca se seteaba)
   - Browser recibía el cert del PORTAL (no de la RPi) → SNI `biblioteca.tel` no coincide → FIN → retry

## Causa raiz

La migracion IP→MAC (documentada en `fix-captive-portal-ip-to-mac-auth.md`) actualizo el **router** role y `captive-accept.py`, pero **no actualizo el firewall role**. Al desplegar con `--tags firewall`, se sobreescribio el ruleset con la version vieja (IP-based):

| Template | Set | Mangle | Forward |
|----------|-----|--------|---------|
| **router** role (correcto) | `captive_allowed_mac` (ether_addr) | `ether saddr @captive_allowed_mac` | `meta mark 0x1` |
| **firewall** role (roto) | `captive_allowed` (ipv4_addr) | `ip saddr @captive_allowed` | `ip saddr @captive_allowed` |

`captive-accept.py` agrega MACs a `captive_allowed_mac`, pero el set desplegado era `captive_allowed` (tipo IP). Incompatibilidad total.

## Fix aplicado

**Archivo:** `minipc/router-setup/roles/firewall/templates/nftables.conf.j2`

### 1. Set: ipv4_addr → ether_addr

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

### 2. Mangle chain: ip saddr → ether saddr

```diff
-    iif "{{ client_iface }}" ip saddr @captive_allowed meta mark set 0x1
+    iif "{{ client_iface }}" ether saddr @captive_allowed_mac meta mark set 0x1
```

### 3. Forward chain: ip saddr → meta mark 0x1

En el hook `forward` el header L2 (Ethernet) ya no esta disponible (paquete entregado a capa IP). Se usa `meta mark 0x1` establecido por el mangle chain (prioridad -150, ejecuta antes que forward).

```diff
-    iif "{{ client_iface }}" oif "{{ wan_interface }}" ip saddr @captive_allowed accept
+    iif "{{ client_iface }}" oif "{{ wan_interface }}" meta mark 0x1 accept

-    iif "{{ client_iface }}" oif "{{ srv_iface }}" ip saddr @captive_allowed accept
+    iif "{{ client_iface }}" oif "{{ srv_iface }}" meta mark 0x1 accept

-    iif "{{ client_iface }}" oif "{{ lan_interface }}" ip saddr @captive_allowed accept
+    iif "{{ client_iface }}" oif "{{ lan_interface }}" meta mark 0x1 accept
```

## Verificacion

```bash
# Set existe con tipo ether_addr
sudo nft list set inet filter captive_allowed_mac
# → type ether_addr

# Mangle usa ether saddr
sudo nft list chain inet filter captive_mangle
# → ether saddr @captive_allowed_mac meta mark set 0x1

# Forward usa meta mark
sudo nft list chain inet filter forward | grep mark
# → meta mark 0x00000001 accept (x3)

# Despues de autenticar un cliente:
sudo nft list set inet filter captive_allowed_mac
# → elements = { 3c:ab:72:4a:b9:cd expires 7h59m... }

# captive-accept.py sin errores:
sudo journalctl -u captive-accept -n 5 --no-pager
# → Authorized: IP=... MAC=...
```

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags firewall
```
