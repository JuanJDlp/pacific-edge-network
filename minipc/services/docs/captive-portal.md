# Portal Cautivo

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/captive_portal/`
**Servicios systemd:** `nginx` (puertos 80, 2050 y 8888), `captive-accept`
**Aplica a:** VLAN30 (clientes, `192.168.30.0/24`)

---

## Qué hace

Intercepta el tráfico HTTP **y HTTPS** de clientes VLAN30 no autenticados y los redirige a una página de bienvenida (splash page) servida por HTTPS. Al hacer clic en "Entrar a la biblioteca", el sistema registra la MAC del dispositivo y le permite acceder a los servicios locales y a internet. El redirect post-autenticación va a `https://biblioteca.tel`.

---

## Componentes

| Componente | Archivo | Puerto | Función |
|---|---|---|---|
| nginx HTTP redirect | `captive-portal.nginx.j2` | `:80` | Redirige cualquier request HTTP a `https://192.168.30.1:2050` |
| nginx splash HTTPS | `captive-portal.nginx.j2` | `:2050` (SSL) | Sirve el splash page con cert autofirmado; proxy hacia captive-accept |
| captive-accept | `captive-accept.py` | `127.0.0.1:2051` | Handler Python: resuelve MAC, autoriza en nftables |
| nginx http-proxy | `http-proxy.nginx.j2` | `:8888` | Reenvía HTTP autenticado hacia Squid en RPi; sirve `offline.html` si WAN cae |

---

## Flujo completo de un cliente nuevo

### Cliente HTTP (puerto 80)

```
1. [Cliente conecta a VLAN30]
   → DHCP le asigna IP 192.168.30.X

2. [Cliente abre http://ejemplo.com]
   → nftables: mark != 0x1 (no autenticado)
   → DNAT puerto 80 → 192.168.30.1:2050 (puerto SSL de nginx)
   → nginx recibe HTTP en puerto SSL → devuelve código 497
   → error_page 497 → redirect a https://192.168.30.1:2050/

3. [Browser abre https://192.168.30.1:2050]
   → nginx sirve splash.html con advertencia de cert autofirmado
```

### Cliente HTTPS (puerto 443)

```
2. [Cliente abre https://ejemplo.com]
   → nftables: mark != 0x1 (no autenticado)
   → DNAT puerto 443 → 192.168.30.1:2050 (SSL nginx)
   → SSL handshake con cert del portal (autofirmado)
   → browser muestra "Tu conexión no es privada"
   → usuario hace clic "Continuar" → ve splash HTTPS
```

### Aceptación y acceso

```
4. [Usuario hace clic en "Entrar a la biblioteca"]
   → GET /accept

5. [nginx :2050 → captive-accept.py :2051]
   → captive-accept recibe X-Real-IP del cliente
   → ip neigh show <IP> dev enp171s0.30  → obtiene MAC
   → nft add element inet filter captive_allowed_mac { <MAC> }
   → conntrack -D -s <IP>  (limpia entradas DNAT cacheadas)
   → responde 200 con <TITLE>Success</TITLE> + meta-refresh a https://biblioteca.tel

6. [nginx cierra TCP] (keepalive_timeout 0 en /accept)
   → browser abre NUEVA conexión TCP

7. [Nueva conexión a https://biblioteca.tel]
   → nftables captive_mangle: MAC en captive_allowed_mac → mark=0x1
   → nftables: mark=0x1 → acceso permitido → va directo a RPi:443
```

---

## Autenticación por MAC (no por IP)

El set nftables usa `type ether_addr` (MAC) en lugar de `type ipv4_addr` (IP). Esto evita que un segundo dispositivo herede acceso al obtener la misma IP que ya estaba autorizada.

La MAC se resuelve desde la ARP table del kernel:

```python
ip neigh show <client_ip> dev enp171s0.30
# → 192.168.30.101 dev enp171s0.30 lladdr aa:bb:cc:dd:ee:ff REACHABLE
```

El kernel ya resolvió la MAC al procesar el SYN del cliente, por lo que la entrada ARP siempre está disponible.

La autenticación tiene un timeout de 8 horas. Al expirar, el cliente debe pasar de nuevo por el splash.

---

## Fix múltiples clicks (keepalive + conntrack)

**Problema:** HTTP/1.1 usa keep-alive. El browser reutilizaba la misma conexión TCP (que ya tenía el DNAT a `:2050` cacheado en conntrack) para ejecutar el meta-refresh, volviendo al splash en lugar de ir a biblioteca.tel.

**Solución aplicada:**
1. `keepalive_timeout 0` en la location `/accept` de nginx → fuerza `Connection: close`, el browser cierra el TCP y abre uno nuevo
2. `conntrack -D -s <client_ip>` en captive-accept.py → limpia cualquier otra conexión DNAT cacheada en paralelo

---

## Intercepción de probes del OS

macOS, iOS, Android y Windows verifican conectividad en background enviando HTTP a dominios propios (`captive.apple.com`, `connectivitycheck.gstatic.com`, etc.). Sin respuestas locales, el OS nunca marca la red como "con internet" y sigue mostrando el popup del portal.

nginx en `:8888` intercepta estos dominios localmente:

| Host | Respuesta |
|---|---|
| `captive.apple.com` | `200 <TITLE>Success</TITLE>` |
| `connectivitycheck.gstatic.com` | `204 No Content` |
| `connectivitycheck.android.com` | `204 No Content` |
| `www.msftconnecttest.com` | `200 Microsoft Connect Test` |
| `www.msftncsi.com` | `200 Microsoft NCSI` |

---

## nginx como proxy HTTP intermediario

Para clientes autenticados (mark=0x1), el tráfico HTTP pasa por:

```
Cliente → DNAT a :8888 → nginx http-proxy → Squid RPi:3129
```

El motivo para usar nginx como intermediario (en lugar de DNAT directo a Squid) es el problema `SO_ORIGINAL_DST`: Squid en modo `intercept` usa `SO_ORIGINAL_DST` para conocer el destino original, pero cuando el DNAT cruza máquinas (Mini PC → RPi), la syscall devuelve la IP de la propia RPi, causando un loop detection y error 403.

nginx recibe el request, reconstruye la petición con el `Host` header correcto y se lo envía a Squid en modo **forward proxy** (puerto 3129), donde Squid usa el Host header para conectar al destino real — sin depender de `SO_ORIGINAL_DST`.

---

## Certificado SSL del portal

El rol genera un certificado autofirmado en `/etc/nginx/ssl/captive.crt` para el servidor HTTPS en puerto 2050. Se genera solo si no existe (`creates:` en Ansible):

```
CN: portal.pacificedge.local
Ubicación: /etc/nginx/ssl/captive.crt + captive.key
```

Los browsers mostrarán una advertencia de cert porque no coincide con el dominio que el usuario intentaba visitar — este es el comportamiento estándar de todos los captive portals HTTPS.

---

## Página offline (sin WAN)

Cuando el Mini PC no tiene conexión WAN, los clientes autenticados que intentan navegar por HTTP ven una página amigable en lugar de un error de Squid.

**Flujo:**
```
Cliente HTTP autenticado → nginx:8888 → Squid:3129
  Squid no puede conectar al origen (WAN caído, ~15s timeout)
  → Squid devuelve 503
  → nginx intercepta (proxy_intercept_errors on)
  → sirve /etc/captive-portal/offline.html (HTTP 200)
  → browser muestra "Sin conexión a internet" con botón a https://biblioteca.tel
```

La biblioteca local (`https://biblioteca.tel`) siempre está disponible aunque WAN esté caído, porque el nftables excluye la IP de la RPi del DNAT hacia el proxy.

> **Limitación:** HTTPS autenticado va directo al WAN sin pasar por el proxy — no es posible interceptarlo sin SSL bumping. El browser mostrará `ERR_CONNECTION_TIMED_OUT`.

---

## Comandos útiles

```bash
# Ver MACs autorizadas actualmente
sudo nft list set inet filter captive_allowed_mac

# Limpiar todas las MACs (re-probar el portal desde cero)
sudo nft flush set inet filter captive_allowed_mac

# Logs del handler captive-accept
sudo journalctl -u captive-accept -f

# Logs de nginx (acceso al splash y proxy)
sudo tail -f /var/log/nginx/access.log

# Probar que captive-accept responde
curl -v -H 'X-Real-IP: 192.168.30.101' http://127.0.0.1:2051/

# Verificar cert SSL del portal
openssl x509 -in /etc/nginx/ssl/captive.crt -noout -subject -dates

# Simular respuesta offline (desde la RPi o Mini PC en VLAN20)
curl -s http://192.168.30.1:8888/ --header 'Host: google.com'
# Con WAN caído debería retornar el HTML de offline.html
```

---

## Deploy

```bash
cd minipc/
ansible-playbook router-setup/playbook.yml -i router-setup/inventory.ini --tags captive_portal
# o:
ansible-playbook services/captive_portal.yml -i router-setup/inventory.ini
```
