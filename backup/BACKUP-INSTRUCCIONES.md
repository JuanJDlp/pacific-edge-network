# Backup — Pre-implementación Plan de Mejoras
**Fecha:** 2026-05-12
**Contexto:** Backup tomado antes de implementar las mejoras de `toChange/DIAGNOSTICO-Y-PLAN-MEJORAS.md`
**Directorio en cada equipo:** `/opt/backups/pre-mejoras-20260512/`

> ⚠️ El sistema actualmente está en producción como prototipo funcional. Este backup permite revertir cualquier cambio a la versión que funciona.

---

## 1. Cobertura del backup

### 1.1 Mini PC (`100.90.95.134`)

| Archivo en backup | Ruta original | Servicio afectado | Por qué se respalda |
|-------------------|--------------|-------------------|---------------------|
| `nftables.conf` | `/etc/nftables.conf` | nftables | Se agregarán reglas TCP RST :443 y DNAT a Squid |
| `nftables-live-ruleset.conf` | estado en vivo | nftables | Incluye tabla `netdev dhcp_fix` y sets dinámicos no persistidos aún |
| `captive-portal.py` | `/usr/local/bin/captive-portal.py` | captive-portal.service | Se le agregarán handlers para probes del OS |
| `captive-portal.service` | `/etc/systemd/system/captive-portal.service` | captive-portal.service | Puede cambiar si se migra a nginx |
| `kea-dhcp4.conf` | `/etc/kea/kea-dhcp4.conf` | kea-dhcp4-server | Puede cambiar si se actualiza DNS a Pi-hole |
| `kea-leases4.csv` | `/var/lib/kea/kea-leases4.csv` | kea-dhcp4-server | Snapshot de leases activos al momento del backup |
| `resolved.conf` | `/etc/systemd/resolved.conf` | systemd-resolved | Puede cambiar con instalación de Pi-hole |
| `10-vlan-routing.conf` | `/etc/sysctl.d/10-vlan-routing.conf` | kernel rp_filter | Referencia del estado actual |
| `nftables-live-ruleset.conf` | estado en vivo `nft list ruleset` | nftables | Estado real incluyendo reglas añadidas manualmente |
| `nft-sets-live.txt` | estado en vivo `nft list sets` | nftables | IPs autenticadas en `captive_allowed` |
| `ip-addr.txt` | `ip addr show` | red | Referencia de interfaces y direcciones |
| `ip-route.txt` | `ip route show` | red | Referencia de tabla de rutas |
| `services-status.txt` | `systemctl status ...` | todos | Estado de los 4 servicios antes de cambios |

### 1.2 Raspberry Pi (`100.90.81.168`)

| Archivo en backup | Ruta original | Servicio afectado | Por qué se respalda |
|-------------------|--------------|-------------------|---------------------|
| `nginx-biblioteca.conf` | `/etc/nginx/sites-available/biblioteca` | nginx | Se actualizarán rutas de probes del OS |
| `nginx.conf` | `/etc/nginx/nginx.conf` | nginx | Config global de referencia |
| `nginx-full-config.txt` | `nginx -T` | nginx | Config completa compilada (incluye defaults heredados) |
| `squid.conf` | `/etc/squid/squid.conf` | squid | Se cambiará de `offline_mode on` a modo intercept con internet |
| `splash.html` | `/var/www/html/splash.html` | nginx | Página del portal cautivo activa |
| `splash-bundle.html` | `/home/akasicom/ap-bundle/var/www/html/splash.html` | nginx | Copia original del repositorio |
| `ip-addr.txt` | `ip addr show` | red | Referencia de interfaces |
| `ports-listening.txt` | `ss -tlnp` | todos | Puertos en escucha antes de cambios |
| `services-status.txt` | `systemctl status ...` | todos | Estado de nginx, Kiwix, Jellyfin, Kolibri, Squid |

---

## 2. Cómo ejecutar el backup manualmente

Si necesitas tomar un nuevo backup antes de cualquier cambio adicional, usa los siguientes comandos. Cambia el `TIMESTAMP` según la fecha.

### Mini PC

```bash
ssh minipc "
BACKUP_DIR=/opt/backups/pre-mejoras-\$(date +%Y%m%d_%H%M%S)
sudo mkdir -p \$BACKUP_DIR

sudo cp /etc/nftables.conf                          \$BACKUP_DIR/nftables.conf
sudo cp /usr/local/bin/captive-portal.py            \$BACKUP_DIR/captive-portal.py
sudo cp /etc/systemd/system/captive-portal.service  \$BACKUP_DIR/captive-portal.service
sudo cp /etc/kea/kea-dhcp4.conf                     \$BACKUP_DIR/kea-dhcp4.conf
sudo cp /etc/sysctl.d/10-vlan-routing.conf          \$BACKUP_DIR/10-vlan-routing.conf
sudo cp /etc/systemd/resolved.conf                  \$BACKUP_DIR/resolved.conf
sudo cp /var/lib/kea/kea-leases4.csv                \$BACKUP_DIR/kea-leases4.csv 2>/dev/null || true
sudo nft list ruleset > /tmp/nft-ruleset.txt && sudo mv /tmp/nft-ruleset.txt \$BACKUP_DIR/nftables-live-ruleset.conf
sudo nft list sets    > /tmp/nft-sets.txt    && sudo mv /tmp/nft-sets.txt    \$BACKUP_DIR/nft-sets-live.txt
ip addr show   > /tmp/ip-addr.txt  && sudo mv /tmp/ip-addr.txt  \$BACKUP_DIR/ip-addr.txt
ip route show  > /tmp/ip-route.txt && sudo mv /tmp/ip-route.txt \$BACKUP_DIR/ip-route.txt
systemctl status captive-portal kea-dhcp4-server nftables systemd-resolved \
  --no-pager -l > /tmp/svc.txt && sudo mv /tmp/svc.txt \$BACKUP_DIR/services-status.txt

sudo ls -lh \$BACKUP_DIR
echo \"Backup completado en \$BACKUP_DIR\"
"
```

### Raspberry Pi

```bash
ssh raspberry "
BACKUP_DIR=/opt/backups/pre-mejoras-\$(date +%Y%m%d_%H%M%S)
echo '4k4s1c0m' | sudo -S mkdir -p \$BACKUP_DIR

echo '4k4s1c0m' | sudo -S cp /etc/nginx/sites-available/biblioteca             \$BACKUP_DIR/nginx-biblioteca.conf
echo '4k4s1c0m' | sudo -S cp /etc/nginx/nginx.conf                             \$BACKUP_DIR/nginx.conf
echo '4k4s1c0m' | sudo -S cp /etc/squid/squid.conf                             \$BACKUP_DIR/squid.conf
echo '4k4s1c0m' | sudo -S cp /var/www/html/splash.html                          \$BACKUP_DIR/splash.html 2>/dev/null || true
echo '4k4s1c0m' | sudo -S cp /home/akasicom/ap-bundle/var/www/html/splash.html  \$BACKUP_DIR/splash-bundle.html 2>/dev/null || true
nginx -T 2>/dev/null > /tmp/nginx-full.txt && echo '4k4s1c0m' | sudo -S mv /tmp/nginx-full.txt \$BACKUP_DIR/nginx-full-config.txt
systemctl status nginx kiwix-serve jellyfin kolibri squid --no-pager -l > /tmp/svc.txt
echo '4k4s1c0m' | sudo -S mv /tmp/svc.txt \$BACKUP_DIR/services-status.txt
ip addr show > /tmp/ip-addr.txt && echo '4k4s1c0m' | sudo -S mv /tmp/ip-addr.txt \$BACKUP_DIR/ip-addr.txt
ss -tlnp     > /tmp/ports.txt   && echo '4k4s1c0m' | sudo -S mv /tmp/ports.txt   \$BACKUP_DIR/ports-listening.txt

echo '4k4s1c0m' | sudo -S ls -lh \$BACKUP_DIR
echo \"Backup completado en \$BACKUP_DIR\"
"
```

---

## 3. Cómo restaurar cada servicio

### 3.1 Restaurar nftables (Mini PC)

```bash
# Restaurar config persistida y recargar
ssh minipc "
  sudo cp /opt/backups/pre-mejoras-20260512/nftables.conf /etc/nftables.conf
  sudo nft -f /etc/nftables.conf
  sudo systemctl restart nftables
  sudo nft list ruleset | head -20
"
```

> ⚠️ Si el estado en vivo tenía reglas adicionales (tabla `netdev dhcp_fix`, etc.) que no estaban en el archivo persistido, usa `nftables-live-ruleset.conf` en su lugar:
> ```bash
> ssh minipc "sudo nft flush ruleset && sudo nft -f /opt/backups/pre-mejoras-20260512/nftables-live-ruleset.conf"
> ```

---

### 3.2 Restaurar captive-portal.py (Mini PC)

```bash
ssh minipc "
  sudo cp /opt/backups/pre-mejoras-20260512/captive-portal.py /usr/local/bin/captive-portal.py
  sudo systemctl restart captive-portal
  sudo systemctl status captive-portal --no-pager
"
```

---

### 3.3 Restaurar Kea DHCP (Mini PC)

```bash
ssh minipc "
  sudo cp /opt/backups/pre-mejoras-20260512/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf
  sudo systemctl restart kea-dhcp4-server
  sudo systemctl status kea-dhcp4-server --no-pager
"
```

---

### 3.4 Restaurar nginx (Raspberry Pi)

```bash
ssh raspberry "
  echo '4k4s1c0m' | sudo -S cp /opt/backups/pre-mejoras-20260512/nginx-biblioteca.conf \
    /etc/nginx/sites-available/biblioteca
  echo '4k4s1c0m' | sudo -S nginx -t
  echo '4k4s1c0m' | sudo -S systemctl reload nginx
  echo '4k4s1c0m' | sudo -S systemctl status nginx --no-pager
"
```

---

### 3.5 Restaurar Squid (Raspberry Pi)

```bash
ssh raspberry "
  echo '4k4s1c0m' | sudo -S cp /opt/backups/pre-mejoras-20260512/squid.conf \
    /etc/squid/squid.conf
  echo '4k4s1c0m' | sudo -S systemctl restart squid
  echo '4k4s1c0m' | sudo -S systemctl status squid --no-pager
"
```

---

### 3.6 Restaurar splash.html (Raspberry Pi)

```bash
ssh raspberry "
  echo '4k4s1c0m' | sudo -S cp /opt/backups/pre-mejoras-20260512/splash.html \
    /var/www/html/splash.html
"
```

---

### 3.7 Restaurar todo en caso de emergencia

Si múltiples cosas fallan al mismo tiempo, restaurar en este orden:

```bash
# 1. Primero nftables (firewall + portal cautivo)
ssh minipc "sudo nft flush ruleset && sudo nft -f /opt/backups/pre-mejoras-20260512/nftables-live-ruleset.conf"

# 2. Captive portal Python
ssh minipc "sudo cp /opt/backups/pre-mejoras-20260512/captive-portal.py /usr/local/bin/captive-portal.py && sudo systemctl restart captive-portal"

# 3. Kea DHCP
ssh minipc "sudo cp /opt/backups/pre-mejoras-20260512/kea-dhcp4.conf /etc/kea/kea-dhcp4.conf && sudo systemctl restart kea-dhcp4-server"

# 4. nginx RPi
ssh raspberry "echo '4k4s1c0m' | sudo -S cp /opt/backups/pre-mejoras-20260512/nginx-biblioteca.conf /etc/nginx/sites-available/biblioteca && echo '4k4s1c0m' | sudo -S systemctl reload nginx"

# 5. Squid RPi
ssh raspberry "echo '4k4s1c0m' | sudo -S cp /opt/backups/pre-mejoras-20260512/squid.conf /etc/squid/squid.conf && echo '4k4s1c0m' | sudo -S systemctl restart squid"
```

---

## 4. Verificar que el sistema está operativo tras restaurar

```bash
# Desde tu Mac — verificar servicios Mini PC
ssh minipc "
  sudo systemctl is-active captive-portal kea-dhcp4-server nftables systemd-resolved
  curl -s -o /dev/null -w '%{http_code}' http://192.168.30.1:2050/ && echo ' portal ok'
"

# Verificar servicios Raspberry Pi
ssh raspberry "
  systemctl is-active nginx squid kiwix-serve jellyfin kolibri
  curl -s -o /dev/null -w '%{http_code}' http://192.168.20.10/ && echo ' nginx ok'
"

# Verificar conectividad entre equipos
ssh minipc "ping -c 2 192.168.20.10 && echo 'RPi alcanzable desde Mini PC'"
```

---

## 5. Listado de backups disponibles

```bash
# Ver todos los backups en Mini PC
ssh minipc "sudo ls -lt /opt/backups/"

# Ver todos los backups en Raspberry Pi
ssh raspberry "echo '4k4s1c0m' | sudo -S ls -lt /opt/backups/"
```

---

## 6. Notas importantes

- Los leases de Kea (`kea-leases4.csv`) son un snapshot del momento del backup. Si se restauran, los clientes que obtuvieron IPs después no serán reconocidos — Kea les asignará nuevas IPs al reconectar, lo cual es aceptable.
- El archivo `nftables-live-ruleset.conf` contiene el estado **en vivo** al momento del backup, incluyendo la tabla `netdev dhcp_fix` (DHCP broadcast fix para macOS) que fue añadida manualmente y aún no está en el `nftables.conf` persistido. **Usar este archivo para restaurar el estado real del sistema**, no el `nftables.conf`.
- El set `captive_allowed` (IPs autenticadas) es dinámico y no se restaura — los usuarios deberán aceptar el portal de nuevo tras un restore, lo cual es el comportamiento esperado.
