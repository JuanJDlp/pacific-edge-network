# Firewall — nftables mejorado

El rol `firewall` reemplaza el ruleset básico del rol `router` con reglas más robustas. Usa nftables con tablas `inet filter`, `ip nat` y `netdev`.

## Resumen de políticas

| Tráfico | Política |
|---------|----------|
| WAN → Mini PC | DROP (excepto conexiones establecidas) |
| VLAN10/20 → WAN | PERMITIDO |
| VLAN30 → WAN | Solo clientes autenticados en portal cautivo |
| VLAN30 → VLAN20 | Solo clientes autenticados |
| VLAN20 → VLAN30 | BLOQUEADO (aislamiento) |
| VLAN10 → VLAN30 | BLOQUEADO (aislamiento) |
| DNS cualquier VLAN | Forzado a Pi-hole (DNAT) |
| SSH | Rate limiting + auto-ban por fuerza bruta |

## Protecciones activas

### Anti-fuerza-bruta SSH
- Máximo 5 intentos/minuto por IP
- IPs que superan el límite se agregan al set `ssh_bruteforce` y se bloquean 1 hora automáticamente
- El ban es dinámico (nftables set con timeout), no requiere reiniciar el firewall

```bash
# Ver IPs actualmente baneadas
sudo nft list set inet filter ssh_bruteforce

# Desbanear una IP manualmente
sudo nft delete element inet filter ssh_bruteforce { 1.2.3.4 }
```

### Rate limiting DNS
- Máximo 30 consultas/segundo por cliente (burst de 50)
- Protege contra ataques de amplificación DNS

### Rate limiting ICMP
- Máximo 10 pings/segundo (burst de 20)
- Protege contra ping floods

### Bloqueo de puertos WAN
Los siguientes puertos se bloquean explícitamente desde internet:

| Puerto | Servicio |
|--------|----------|
| 23 | Telnet |
| 135, 137-139, 445 | NetBIOS / SMB |
| 1433 | MSSQL |
| 3306 | MySQL |
| 3389 | RDP |
| 5900 | VNC |

### Anti-spoofing
Paquetes que llegan desde WAN con IP origen privada (10.x, 172.16.x, 192.168.x) se descartan inmediatamente.

### Aislamiento de VLANs
- VLAN20 (servidores) no puede iniciar conexiones hacia VLAN30 (clientes)
- VLAN10 (gestión) no puede llegar directamente a VLAN30
- Los servicios de gestión (Prometheus :9090, Grafana :3000, Pi-hole :8080) solo son accesibles desde VLAN10

## Logging

Los drops se registran en el kernel log con el prefijo `NFT DROP:`. Para verlos:

```bash
# Ver drops en tiempo real
sudo journalctl -k -f | grep "NFT DROP"

# Ver drops de las últimas 24h
sudo journalctl -k --since "24 hours ago" | grep "NFT DROP"

# Contar drops por tipo
sudo journalctl -k --since "1 hour ago" | grep "NFT DROP" | awk '{print $NF}' | sort | uniq -c | sort -rn
```

Para deshabilitar el logging (producción con mucho tráfico), cambiar en `roles/firewall/vars/main.yml`:
```yaml
enable_drop_logging: false
```

## DNS forzado (anti-bypass)

El DNAT en nftables redirige **todo** el tráfico al puerto 53 de cualquier VLAN hacia Pi-hole en `192.168.10.1:53`. Esto significa que aunque un cliente configure manualmente `8.8.8.8` como DNS, sus consultas igual llegan a Pi-hole.

```bash
# Verificar regla DNAT DNS
sudo nft list chain ip nat prerouting | grep "dport 53"
```

## Comandos útiles

```bash
# Ver ruleset completo
sudo nft list ruleset

# Ver solo la chain input
sudo nft list chain inet filter input

# Ver clientes autenticados en portal cautivo
sudo nft list set inet filter captive_allowed

# Ver IPs baneadas por SSH
sudo nft list set inet filter ssh_bruteforce

# Recargar firewall (sin perder conexiones establecidas)
sudo systemctl reload nftables

# Verificar sintaxis antes de aplicar
sudo nft -c -f /etc/nftables.conf
```

## Despliegue con Ansible

```bash
# Solo firewall
ansible-playbook -i inventory.ini playbook.yml --tags firewall

# Firewall + Pi-hole
ansible-playbook -i inventory.ini playbook.yml --tags firewall,pihole
```
