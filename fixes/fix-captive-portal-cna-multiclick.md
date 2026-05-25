# Fix: Portal cautivo requiere múltiples clicks — macOS/iOS CNA no detecta éxito

**Fecha:** 2026-05-20
**Afecta:** Mini PC (`plataformas`) — captive-accept.py + nginx:8888

## Síntoma

Al hacer clic en "Entrar a la biblioteca" en el portal cautivo, el usuario debía dar 3+ clics y esperar 30-60 segundos antes de que la autenticación funcionara. En los logs, `captive-accept.py` registraba autorizaciones múltiples para la misma IP en intervalos de ~750ms-2s durante casi 2 minutos.

## Causa raíz

El handler `captive-accept.py` respondía con `302 Location: http://biblioteca.local`. El nft add element es instantáneo y la RPi respondía en < 1ms — el cuello de botella NO era el handler.

El problema real era el **Captive Network Assistant (CNA)** de macOS/iOS:

1. OS abre popup CNA con splash.html
2. Usuario hace clic → `/accept` → IP agregada → `302 http://biblioteca.local`
3. CNA carga `http://biblioteca.local` (RPi sirve 200 en < 1ms) ✓
4. CNA **re-verifica** conectividad haciendo GET a `captive.apple.com/hotspot-detect.html`
5. Cliente autenticado (mark=0x1) → proxy DNAT → nginx:8888 → Squid → **intenta alcanzar internet** ❌
6. Red sin internet ("sin internet") → Squid falla → CNA nunca recibe confirmación → sigue mostrando el popup
7. Usuario re-clic → repite el ciclo hasta que el CNA da timeout y el usuario intenta desde el browser principal

## Fixes aplicados

### 1. `captive-accept.py` — responder 200 en lugar de 302

**Archivo:** `minipc/router-setup/roles/captive_portal/files/captive-accept.py`

El CNA de macOS/iOS cierra el popup cuando recibe una respuesta `200` con `<TITLE>Success</TITLE>` en la respuesta a `/accept`. El HTML incluye meta-refresh + JS para redirigir al browser a `http://biblioteca.local`.

```diff
-self.send_response(302)
-self.send_header('Location', REDIRECT)
-self.send_header('Content-Length', '0')
-self.end_headers()
+self.send_response(200)
+self.send_header('Content-Type', 'text/html; charset=utf-8')
+self.send_header('Content-Length', str(len(SUCCESS_HTML)))
+self.end_headers()
+self.wfile.write(SUCCESS_HTML)
```

Donde `SUCCESS_HTML` contiene `<TITLE>Success</TITLE>` y una redirección JS/meta-refresh a `http://biblioteca.local`.

### 2. `http-proxy.nginx.j2` — interceptar probes de conectividad del OS

**Archivo:** `minipc/router-setup/roles/captive_portal/templates/http-proxy.nginx.j2`

Agrega 4 bloques `server` con `server_name` específicos ANTES del catch-all `server_name _`, que responden localmente sin tocar Squid/internet:

| Host | Respuesta |
|------|-----------|
| `captive.apple.com` | `200 <HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>` |
| `connectivitycheck.gstatic.com` / `connectivitycheck.android.com` | `204 No Content` |
| `www.msftconnecttest.com` | `200 Microsoft Connect Test` |
| `www.msftncsi.com` | `200 Microsoft NCSI` |

## Verificación

```bash
# captive-accept.py retorna 200 con Success HTML
ssh minipc "curl -s -H 'X-Real-IP: 192.168.30.99' http://127.0.0.1:2051/" \
  | grep -o '<TITLE>Success</TITLE>'
# → <TITLE>Success</TITLE> ✅

# Apple probe interceptada localmente
ssh minipc "curl -s -H 'Host: captive.apple.com' http://127.0.0.1:8888/hotspot-detect.html"
# → <HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML> ✅

# Android probe interceptada localmente
ssh minipc "curl -s -o /dev/null -w '%{http_code}' -H 'Host: connectivitycheck.gstatic.com' http://127.0.0.1:8888/generate_204"
# → 204 ✅
```

## Deploy

```bash
cd minipc/router-setup
ansible-playbook playbook.yml -i inventory.ini --tags captive_portal
```
