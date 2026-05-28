# 07 — Troubleshooting

Guía diagnóstica para problemas comunes. Ordenada por síntoma del usuario.

## Síntoma 1 — biblioteca.tel no carga (HTTPS)

### Diagnóstico

```bash
ssh akasicom@100.90.81.168 '
echo "1. ¿Squid corre y escucha en 443?"
sudo systemctl is-active squid
sudo ss -tlnp | grep ":443\\s"

echo "2. ¿Backend nginx :80 responde?"
curl -s -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1/

echo "3. ¿Cert de biblioteca.tel existe?"
sudo ls -la /etc/squid/ssl/biblioteca.crt /etc/squid/ssl/biblioteca.key

echo "4. Último error en logs:"
sudo tail -5 /var/log/squid/cache.log
'
```

### Causas comunes

| Causa | Solución |
|---|---|
| Squid no corre | `sudo systemctl start squid`. Si falla: `sudo journalctl -u squid -n 50` |
| Squid no escucha en 443 | Verifica `https_port 443 accel` en `/etc/squid/squid.conf`. Si no está → `squid_enable_biblioteca_accel` está en false. |
| nginx :80 no responde | `sudo systemctl restart nginx`. Backend caído. |
| Cert de Squid no readable | `sudo chown proxy:proxy /etc/squid/ssl/biblioteca.*` |
| Config con error | `sudo /usr/sbin/squid -k parse` muestra el FATAL |

---

## Síntoma 2 — biblioteca.tel HTTPS carga pero NO hace cache (siempre TCP_MISS)

### Diagnóstico

```bash
ssh akasicom@100.90.81.168 '
# Hacer 2 requests y ver logs
curl -ks https://biblioteca.tel/index.html -o /dev/null
curl -ks https://biblioteca.tel/index.html -o /dev/null
sudo tail -3 /var/log/squid/access.log
'
```

Si las dos veces aparece `TCP_MISS/200`, no cachea.

### Causas

| Causa | Solución |
|---|---|
| `cache deny` mal configurado | Revisa que `acl cache_allowed dstdomain biblioteca.tel` exista y que `cache deny !cache_allowed` esté declarado |
| Backend devuelve `Cache-Control: no-store` | Verificar headers: `curl -I http://127.0.0.1/index.html`. Si hay `no-store` → nginx lo añade (revisar config nginx). |
| Cache dir lleno | `du -sh /var/lib/biblioteca/squid-cache`. Si está al 100%, Squid empieza a fallar evictions. Limpia. |
| Squid no se reinició tras cambio de cache_dir | `sudo systemctl restart squid` (no `reload` — `cache_dir` cambios requieren restart). |
| `cache_peer` no se está usando | Logs muestran `HIER_DIRECT/...` en lugar de `FIRSTUP_PARENT/127.0.0.1`. Revisa `never_direct allow biblioteca_dom`. |

---

## Síntoma 3 — Cliente VLAN30 ve pornhub/sitio bloqueado SIN problema

### Diagnóstico

```bash
# En la RPi
ssh akasicom@100.90.81.168 '
echo "1. ¿pornhub está en blocklist?"
grep "^pornhub.com$" /etc/squid/blocklists/blocked_domains.txt

echo "2. ¿Squid recibe tráfico HTTPS de clientes?"
sudo tail -20 /var/log/squid/access.log | grep -E "3130|terminate" | head -5
'

# En el Mini PC
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134 '
echo "3. ¿DNAT HTTPS está activo?"
sudo nft list chain ip nat prerouting | grep "3130"
'
```

### Causas

| Causa | Solución |
|---|---|
| DNAT del Mini PC no está | Re-deploy: `ansible-playbook playbook.yml --tags firewall` |
| Cliente NO tiene mark 0x1 | No pasó por el portal cautivo. Sin mark, el DNAT a Squid no aplica → cliente bloqueado en forward chain (drop). Confirmar: `sudo nft list set inet filter captive_allowed_mac` debe incluir su MAC |
| pornhub NO en la lista | Forzar update: `sudo /usr/local/sbin/update-squid-blocklist` |
| Squid en peek+splice pasó algo raro | Revisa logs `ssl::server_name`. Si el cliente usó ECH (encrypted SNI), Squid no puede leerlo y splice por defecto |
| Cliente está usando VPN | Tráfico va cifrado al endpoint VPN. Imposible bloquear sin DPI. Ver [04-CONSIDERACIONES.md § 1.5](04-CONSIDERACIONES.md) |

---

## Síntoma 4 — Squid no levanta tras cambio de config

### Diagnóstico inmediato

```bash
ssh akasicom@100.90.81.168 'sudo /usr/sbin/squid -k parse 2>&1 | tail -20'
```

Busca líneas que digan `FATAL:` o `ERROR:`. Te dice EXACTAMENTE qué línea está mal.

### Errores comunes

| Mensaje | Significado | Solución |
|---|---|---|
| `Bungled config line N: ssl_bump peek step1` | `step1` ACL no declarado | Añadir `acl step1 at_step SslBump1` ANTES de `ssl_bump` |
| `'.biblioteca.tel' is a subdomain of 'biblioteca.tel'` | dstdomain con ambos sintaxis redundantes | Usa solo uno (preferimos exacto: `biblioteca.tel`) |
| `unable to open '/etc/squid/ssl/bump-ca.crt'` | Cert no existe o permisos mal | Re-deploy del rol squid (regenera) |
| `Cannot find a cache_peer named 'X'` | cache_peer_access usa nombre mal | Verifica que `cache_peer ... name=X` coincida con `cache_peer_access X allow ...` |

### Rollback rápido

Si tras un cambio Squid no levanta y necesitas restaurar:

```bash
ssh akasicom@100.90.81.168 '
sudo ls /etc/squid/squid.conf.bak.*  # ver backups (Ansible deja con backup: true)
sudo cp /etc/squid/squid.conf.bak.YYYYMMDD-HHMMSS /etc/squid/squid.conf
sudo systemctl restart squid
'
```

---

## Síntoma 5 — Cron de blocklist nunca corre o falla

### Diagnóstico

```bash
ssh akasicom@100.90.81.168 '
echo "1. ¿Cron instalado?"
sudo crontab -l | grep blocklist

echo "2. ¿Logs?"
sudo tail -30 /var/log/squid-blocklist.log

echo "3. ¿Última modificación del archivo?"
sudo ls -la /etc/squid/blocklists/blocked_domains.txt

echo "4. Forzar run manual y ver salida:"
sudo /usr/local/sbin/update-squid-blocklist
'
```

### Causas

| Causa | Solución |
|---|---|
| Cron no instalado | Re-deploy rol squid |
| Sin conectividad a GitHub | `curl -I https://raw.githubusercontent.com/StevenBlack/hosts/...` desde la RPi. Si falla, problema de WAN |
| Sanity-check abortó | Log dice "sanity-check failed". Probablemente las listas remotas vinieron corruptas. Esperar a próximo intento |
| `squid -k reconfigure` falló | Probablemente config inválida posterior al script. Verificar último cambio |

---

## Síntoma 6 — Ansible reporta `changed=N` en una corrida que debería ser idempotente

### Causas

| Causa | Solución |
|---|---|
| Cambios manuales en la RPi/Mini PC | Reconciliar: o revertir el cambio manual, o incorporarlo al rol |
| Template Jinja2 tiene espacio en blanco diferente | Comparar template renderizado vs archivo en vivo |
| Cert se está regenerando | El task `creates:` debería evitarlo. Si pasa, `ls -la` el cert para ver si existe |
| Cron `cron:` module añade comentario nuevo | Cosmetic, ignorar primera vez |

Para ver QUÉ cambió:

```bash
ansible-playbook ... --check --diff
```

El `--diff` muestra el contenido exacto que diferiría.

---

## Síntoma 7 — Performance degradada

### Síntomas

- Páginas tardan >2s en cargar (deberían ser <500ms para cached, <1s para no-cached).
- RPi con CPU >70% sostenido en `squid`.
- Latencia visible al navegar biblioteca.tel.

### Diagnóstico

```bash
ssh akasicom@100.90.81.168 '
echo "1. Conexiones activas:"
sudo ss -tn | grep -E ":443\\s|:3130\\s" | wc -l

echo "2. Carga del sistema:"
uptime

echo "3. Procesos top:"
ps aux | sort -rk 3 | head -5

echo "4. Tamaño cache:"
du -sh /var/lib/biblioteca/squid-cache

echo "5. File descriptors:"
sudo lsof -p $(pidof squid | awk "{print \$1}") 2>/dev/null | wc -l
'
```

### Soluciones por causa

| Causa | Solución |
|---|---|
| Demasiadas conexiones concurrentes (>200) | Identificar quién está saturando. Considerar rate-limit por src IP. |
| Cache lleno → mucho eviction | Aumentar `cache_dir`. Restart Squid después. |
| Disco lento (SD card vieja) | Migrar cache a SSD/USB-stick |
| Memoria insuficiente | Reducir `cache_mem` |
| FD limit alcanzado | `ulimit -n 65536` ya configurado en systemd. Verificar `cat /proc/$(pidof squid)/limits` |

---

## Síntoma 8 — Cliente reporta "este sitio no se puede alcanzar" en sitios normales

### Diagnóstico rápido

```bash
# Desde el cliente:
curl -v https://www.google.com 2>&1 | head -30
```

Observar:
- `Connection refused` → DNAT rompiendo algo, o Squid no escucha
- `SSL handshake failed` → Squid bumpeando cuando no debería
- Timeout → Squid no responde, WAN caído

### Causas

| Síntoma | Causa | Solución |
|---|---|---|
| TODOS los HTTPS fallan desde VLAN30 | Squid:3130 caído | `systemctl restart squid` |
| Algunos sitios fallan | SNI específico falsamente en blocklist | Whitelist (ver [06](06-BLOCKLISTS.md)) |
| `SSL_ERROR_NO_CYPHER_OVERLAP` | TLS 1.3 issue | Squid 6 + OpenSSL 3 debería ir. Re-verificar paquete `squid-openssl` |
| Funciona desde HTTP pero no HTTPS | DNAT HTTPS roto | Ver [Síntoma 3](#síntoma-3) |

---

## Comandos diagnósticos master

```bash
# === En la RPi ===
ssh akasicom@100.90.81.168 '
# Status global
sudo systemctl status squid --no-pager
sudo ss -tlnp | grep -E ":(443|3128|3129|3130|8443)\\s"

# Logs en tiempo real
sudo tail -f /var/log/squid/access.log /var/log/squid/cache.log

# Reload sin downtime
sudo /usr/sbin/squid -k reconfigure

# Restart completo (si reconfigure no basta)
sudo systemctl restart squid

# Verificar config
sudo /usr/sbin/squid -k parse

# Stats — entries en cache, hit rate
sudo /usr/sbin/squid -k debug=ALL,1 2>&1 | head -20  # nivel debug temporal

# Cache info
sudo du -sh /var/lib/biblioteca/squid-cache
sudo find /var/lib/biblioteca/squid-cache -type f | wc -l
'

# === En el Mini PC ===
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134 '
# Reglas nftables
sudo nft list ruleset | grep -A2 "tcp dport 443"

# Conntrack
sudo conntrack -L | grep "dst=192.168.20.10" | head -10

# Clientes autenticados
sudo nft list set inet filter captive_allowed_mac
'
```

## Limpiezas que pueden ayudar

```bash
# Limpiar cache de Squid (si está corrupto)
ssh akasicom@100.90.81.168 '
sudo systemctl stop squid
sudo rm -rf /var/lib/biblioteca/squid-cache/*
sudo squid -z              # inicializa estructura nueva
sudo systemctl start squid
'

# Limpiar SSL cert DB (si security_file_certgen se corrompió)
ssh akasicom@100.90.81.168 '
sudo systemctl stop squid
sudo rm -rf /var/lib/squid/ssl_db/*
sudo /usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 20MB
sudo chown -R proxy:proxy /var/lib/squid/ssl_db
sudo systemctl start squid
'

# Limpiar conntrack (si DNAT ata conexiones colgadas)
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134 '
sudo conntrack -F                 # flushea todo
sudo conntrack -F -p tcp --dport 443  # solo HTTPS
'
```

## Cuándo pedir ayuda

Si después de revisar logs, parse-check, restart de servicios, y los tests del documento [05-TESTING.md](05-TESTING.md) siguen fallando:

1. **Captura el estado completo**:
   ```bash
   ssh akasicom@100.90.81.168 '
   sudo systemctl status squid > /tmp/diag.txt
   sudo cat /etc/squid/squid.conf >> /tmp/diag.txt
   sudo tail -100 /var/log/squid/cache.log >> /tmp/diag.txt
   sudo tail -50 /var/log/squid/access.log >> /tmp/diag.txt
   '
   scp akasicom@100.90.81.168:/tmp/diag.txt .
   ```
2. **Indicar qué cambió antes del problema** (git log, deploy reciente).
3. **Adjuntar el contenido del diag.txt** + descripción del síntoma.
