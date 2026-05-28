# 05 — Cómo probar todo

Batería completa de tests, desde sanity-check hasta validación end-to-end. Cada test indica qué esperas ver y qué significa si falla.

## Tabla de tests

| # | Qué prueba | Dónde se ejecuta | Tiempo |
|---|---|---|---|
| [1](#test-1) | Squid corriendo con OpenSSL | RPi | <1s |
| [2](#test-2) | 4 puertos Squid + nginx en 8443 | RPi | <1s |
| [3](#test-3) | Blocklist cargada (~82k entries) | RPi | <1s |
| [4](#test-4) | Cron blocklist instalado | RPi | <1s |
| [5](#test-5) | biblioteca.tel HTTPS sirve + cachea | RPi | ~2s |
| [6](#test-6) | Filtro HTTPS bloquea SNI prohibido | RPi (simulado) | ~10s |
| [7](#test-7) | Filtro HTTPS permite SNI normal | RPi (simulado) | ~10s |
| [8](#test-8) | Internet HTTP no se cachea | RPi | ~2s |
| [9](#test-9) | biblioteca.tel HTTP sigue funcionando | RPi | <1s |
| [10](#test-10) | DNAT en Mini PC presente | Mini PC | <1s |
| [11](#test-11) | Idempotencia Ansible (dry-run) | Local | ~30s |
| [12](#test-12) | Resiliencia tras restart de Squid | RPi | ~5s |
| [13](#test-13) | Test desde cliente VLAN30 real | Cliente | manual |

---

## Test 1 — Squid corriendo con OpenSSL

```bash
ssh akasicom@100.90.81.168 "squid -v 2>&1 | grep -oE -- '--with-openssl|--enable-ssl-crtd'"
```

**Esperado**:
```
--enable-ssl-crtd
--with-openssl
```

**Si falla** → el paquete equivocado está instalado. Resuelve con `sudo apt install squid-openssl` o re-run el playbook.

---

## Test 2 — Listeners

```bash
ssh akasicom@100.90.81.168 'sudo ss -tlnp | grep -E ":(443|3128|3129|3130|8443)\\s"'
```

**Esperado** (5 líneas):
```
LISTEN 0 511 127.0.0.1:8443  ... users:(("nginx",...))
LISTEN 0 256 *:3130          ... users:(("squid",...))
LISTEN 0 256 *:3129          ... users:(("squid",...))
LISTEN 0 256 *:3128          ... users:(("squid",...))
LISTEN 0 256 *:443           ... users:(("squid",...))
```

**Si falla**:
- Si `:443` está en nginx en lugar de squid → playbook nginx no se aplicó con `nginx_serve_https: false`. Re-deploy.
- Si `:3130` no aparece → `squid_enable_https_filter` está en false o config no se aplicó.
- Si `:8443` no aparece → nginx HTTPS interno no se levantó. Verifica `nginx -t`.

---

## Test 3 — Blocklist cargada

```bash
ssh akasicom@100.90.81.168 'wc -l /etc/squid/blocklists/blocked_domains.txt'
```

**Esperado**: ≥ 80 000 (típicamente 82 000–85 000, varía con cada update de StevenBlack).

**Si falla**:
- Archivo no existe → el script no ha corrido. Forzar: `sudo /usr/local/sbin/update-squid-blocklist`.
- Muy pocas líneas (< 1000) → el script abortó por sanity-check; revisar `/var/log/squid-blocklist.log`.

---

## Test 4 — Cron instalado

```bash
ssh akasicom@100.90.81.168 'sudo crontab -l | grep -i blocklist'
```

**Esperado**:
```
#Ansible: update-squid-blocklist
30 3 * * 0 /usr/local/sbin/update-squid-blocklist >> /var/log/squid-blocklist.log 2>&1
```

**Si falla** → re-deploy del rol squid.

---

## Test 5 — biblioteca.tel HTTPS con cache

```bash
ssh akasicom@100.90.81.168 '
echo "1st hit:"
curl -ks -o /dev/null -w "  HTTP=%{http_code} time=%{time_total}s\n" https://biblioteca.tel/index.html
echo "2nd hit:"
curl -ks -o /dev/null -w "  HTTP=%{http_code} time=%{time_total}s\n" https://biblioteca.tel/index.html
echo "Squid log:"
sudo tail -2 /var/log/squid/access.log | awk "{print \$5, \$7, \$8}"
'
```

**Esperado**:
```
1st hit:
  HTTP=200 time=0.012s
2nd hit:
  HTTP=200 time=0.010s
Squid log:
  TCP_MISS/200  GET https://biblioteca.tel/index.html
  TCP_MEM_HIT/200  GET https://biblioteca.tel/index.html
```

**Lo crítico**: la segunda línea debe ser `TCP_MEM_HIT` o `TCP_HIT` (HIT desde RAM o disco).

**Si falla**:
- Ambos hits `TCP_MISS/200` → cache no se activa. Revisa `cache deny !cache_allowed` en squid.conf, y que `cache_allowed` ACL esté correcta.
- `TCP_MISS_ABORTED/503` → backend (nginx :80) no responde. `sudo systemctl status nginx`.

---

## Test 6 — Filtro HTTPS BLOQUEA dominio prohibido

```bash
ssh akasicom@100.90.81.168 '
EXAMPLE_IP=$(dig +short example.com | head -1)
sudo nft add table ip squid_test 2>/dev/null
sudo nft "add chain ip squid_test output { type nat hook output priority -100; }" 2>/dev/null
sudo nft "add rule ip squid_test output ip daddr $EXAMPLE_IP tcp dport 443 dnat to 127.0.0.1:3130"

echo "pornhub.com via DNAT (en blocklist):"
timeout 6 curl -ks --resolve pornhub.com:443:$EXAMPLE_IP --connect-timeout 3 \
    -o /dev/null -w "  HTTP=%{http_code} (esperado: 000)\n" https://pornhub.com/

sudo nft delete table ip squid_test
'
```

**Esperado**:
```
pornhub.com via DNAT (en blocklist):
  HTTP=000 (esperado: 000)
```

`HTTP=000` significa "no se recibió respuesta HTTP" → la conexión fue cortada por Squid (terminate). Es el comportamiento correcto.

**Si falla**:
- `HTTP=200` → Squid NO bloqueó. Revisa: dominio está en blocklist (`grep ^pornhub.com$ /etc/squid/blocklists/blocked_domains.txt`); ACL `blocked_sni` referencia el archivo correcto; `ssl_bump terminate blocked_sni` está en la config.

---

## Test 7 — Filtro HTTPS PERMITE dominio normal

```bash
ssh akasicom@100.90.81.168 '
EXAMPLE_IP=$(dig +short example.com | head -1)
sudo nft add table ip squid_test 2>/dev/null
sudo nft "add chain ip squid_test output { type nat hook output priority -100; }" 2>/dev/null
sudo nft "add rule ip squid_test output ip daddr $EXAMPLE_IP tcp dport 443 dnat to 127.0.0.1:3130"

echo "example.com via DNAT (NO en blocklist):"
sudo tail -3 /var/log/squid/access.log > /tmp/before.log
timeout 15 curl -ks --connect-timeout 5 -o /tmp/example.html \
    -w "  HTTP=%{http_code} bytes=%{size_download}\n" \
    https://example.com/
echo "Squid logs nuevos:"
sudo tail -3 /var/log/squid/access.log

sudo nft delete table ip squid_test
'
```

**Esperado**:
```
example.com via DNAT (NO en blocklist):
  HTTP=200 bytes=1256
Squid logs nuevos:
  ... TCP_TUNNEL/200 ... CONNECT example.com:443 ... ORIGINAL_DST/...
```

`TCP_TUNNEL/200` = Squid hizo splice exitoso → conexión TLS pasó intacta.

**Si falla**:
- `HTTP=000` con `TCP_TUNNEL/200` en logs → Squid splice OK pero curl tuvo timeout. Es problema de routing/WAN, no del filtro.
- `NONE_NONE/000` en logs → Squid no logueó el splice — probablemente blocked accidentalmente. Revisa el SNI vs blocklist.

---

## Test 8 — Internet HTTP NO se cachea

```bash
ssh akasicom@100.90.81.168 '
echo "1st hit:"
curl -s --proxy http://127.0.0.1:3129 -o /dev/null -w "  HTTP=%{http_code}\n" http://example.com/
echo "2nd hit (debe seguir siendo MISS):"
curl -s --proxy http://127.0.0.1:3129 -o /dev/null -w "  HTTP=%{http_code}\n" http://example.com/
sudo tail -2 /var/log/squid/access.log | awk "{print \$5}"
'
```

**Esperado**:
```
1st hit:
  HTTP=200
2nd hit (debe seguir siendo MISS):
  HTTP=200
TCP_MISS/200
TCP_MISS/200
```

Las DOS líneas deben ser `TCP_MISS/200`. Si la segunda es `TCP_HIT` → internet se está cacheando (mal).

---

## Test 9 — biblioteca.tel HTTP sigue funcionando

```bash
ssh akasicom@100.90.81.168 'curl -s -o /dev/null -w "HTTP=%{http_code}\n" http://biblioteca.tel/'
```

**Esperado**: `HTTP=200`

**Si falla** → nginx :80 caído. `sudo systemctl status nginx`.

---

## Test 10 — DNAT en Mini PC

```bash
ssh -i ~/.ssh/plats_mini_pc user@100.90.95.134 \
  'sudo nft list chain ip nat prerouting | grep "tcp dport 443"'
```

**Esperado** (dos líneas):
```
iif "enp171s0.30" meta mark != 0x00000001 tcp dport 443 dnat to 192.168.30.1:2050
iif "enp171s0.30" meta mark 0x00000001 ip daddr != 192.168.20.10 tcp dport 443 dnat to 192.168.20.10:3130
```

La primera redirige clientes NO autenticados al portal (existía antes). La segunda — añadida en esta iteración — redirige autenticados al filtro de Squid.

**Si la segunda no aparece** → re-deploy del rol firewall.

---

## Test 11 — Idempotencia Ansible

Desde tu máquina local:

```bash
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/squid.yml --check
# Espera: changed=0

ansible-playbook -i rpi-setup/inventory.ini services/nginx.yml --check
# Espera: changed=0

cd ../minipc/
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags firewall --check
# Espera: changed=0
```

**Esperado** en cada uno:
```
rpi : ok=N changed=0 unreachable=0 failed=0 ...
```

**Si hay `changed>0`** → el sistema en vivo difiere del código git. Investigar qué cambió manualmente y reconciliar (preferir el código git).

---

## Test 12 — Resiliencia: restart Squid

```bash
ssh akasicom@100.90.81.168 '
sudo systemctl restart squid
sleep 3
sudo systemctl is-active squid
sudo ss -tlnp | grep -E ":(443|3128|3129|3130)\\s" | wc -l
curl -ks -o /dev/null -w "biblioteca.tel: HTTP=%{http_code}\n" https://biblioteca.tel/
'
```

**Esperado**:
```
active
4
biblioteca.tel: HTTP=200
```

(4 listeners, biblioteca.tel responde, todo OK).

**Lo crítico**: el cache se preserva tras restart (porque vive en disco). El segundo curl a una URL ya vista debe ser HIT inmediato.

---

## Test 13 — Desde un cliente VLAN30 real

Conectado a la WiFi de la red comunitaria (VLAN30):

```bash
# 1. Confirmar IP y gateway
ip addr | grep inet
ip route | grep default
# Esperado: IP en 192.168.30.x, gateway 192.168.30.1

# 2. Pasar el portal cautivo
# Abrir http://example.com en un navegador → debe redirigir a http://192.168.30.1:2050/
# Aceptar términos. Tu MAC queda autorizada.

# 3. Verificar que un dominio normal funciona
curl -v https://example.com/ -o /dev/null
# Esperado: HTTP/2 200, sin warnings de cert

# 4. Verificar que un dominio bloqueado NO funciona
curl -v https://pornhub.com/ -o /dev/null
# Esperado: SSL_ERROR_SYSCALL, connection reset

# 5. Verificar biblioteca.tel
curl -k https://biblioteca.tel/ -o /dev/null
# Esperado: HTTP 200 (warning de cert autofirmado, ignorar)

# 6. Comprobar cache de biblioteca.tel (lado servidor)
# Desde la RPi (ssh aparte):
sudo tail -f /var/log/squid/access.log | grep "$(my-IP)"
# Cuando navegues a https://biblioteca.tel/, deberías ver TCP_MISS la primera vez
# y TCP_MEM_HIT en visitas siguientes a la misma URL
```

**Si falla** algún punto:
- Punto 2 (no aparece portal): DNS no se está forzando o nftables DNAT roto. `sudo nft list table ip nat`.
- Punto 3 (example.com no carga): el filtro está bloqueando incorrectamente. Revisar SNI en blocklist.
- Punto 4 (pornhub carga): el filtro no está bloqueando. Verificar [Test 6](#test-6) en servidor.
- Punto 5 (biblioteca.tel falla): Squid o nginx down. `systemctl status squid nginx` en RPi.

## Tests de stress (opcional)

### Concurrencia

```bash
# Desde la RPi — 50 requests concurrentes a biblioteca.tel
seq 1 50 | xargs -P 50 -I{} curl -ks -o /dev/null https://biblioteca.tel/

# Ver estadísticas
sudo tail -50 /var/log/squid/access.log | awk '{print $5}' | sort | uniq -c
# Esperado: muchos TCP_MEM_HIT (cache calentado)
```

### Cache hit rate

```bash
ssh akasicom@100.90.81.168 '
sudo awk "
  /TCP_MEM_HIT|TCP_HIT/ { hits++ }
  /TCP_MISS/ { misses++ }
  END {
    total = hits + misses
    if (total > 0) printf \"Hits: %d / Total: %d (%.1f%%)\n\", hits, total, hits/total*100
  }
" /var/log/squid/access.log
'
```

Una red sana con clientes navegando debería tener >40% hit rate para biblioteca.tel después de unas horas. Internet (no cacheable) siempre será 0% hits.

## Tests de regresión: flujos existentes

Estos verifican que NO se rompió nada del setup anterior:

```bash
ssh akasicom@100.90.81.168 '
echo "1. nginx HTTP biblioteca.tel:"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" http://biblioteca.tel/

echo "2. Kiwix vía HTTP:"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" http://biblioteca.tel/wikipedia/

echo "3. Kolibri vía HTTP:"
curl -s -o /dev/null -w "  HTTP=%{http_code}\n" http://biblioteca.tel/kolibri/
# 302 es OK (redirect a /kolibri/user/)

echo "4. Squid forward proxy HTTP:"
curl -s --proxy http://127.0.0.1:3129 -o /dev/null -w "  HTTP=%{http_code}\n" http://example.com/

echo "5. DNS local:"
dig @127.0.0.1 biblioteca.tel +short
'
```

Si TODOS los puntos pasan = setup anterior intacto + nuevas features funcionan.
