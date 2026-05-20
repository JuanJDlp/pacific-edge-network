# Fix: 502 Bad Gateway en /accept después de autenticación — RPi nginx

**Fecha:** 2026-05-20
**Afecta:** RPi (`akasicom2`, 100.90.81.168) — nginx

## Síntoma

Al hacer clic en "Entrar a la biblioteca" en el portal cautivo (`splash.html`), el botón devolvía **502 Bad Gateway** y el cliente quedaba atascado en `http://biblioteca.local/accept`.

El flujo funcionaba solo en el primer clic (mientras el cliente aún no estaba autenticado). En clics subsecuentes (cliente ya con IP en `captive_allowed`) aparecía el 502.

## Causa raíz

El nginx de la RPi tenía un handler legacy para `/accept` que apuntaba a un servicio inexistente:

```nginx
location = /accept {
    proxy_pass http://127.0.0.1:8088/accept;  ← puerto 8088 no existe en la RPi
    ...
}
```

El `captive-accept.py` (handler real de autorización) **solo corre en el Mini PC** en `127.0.0.1:2051`. No existe ningún proceso en el puerto 8088 de la RPi.

**Por qué fallaba intermitentemente:**

- **Primer clic (no autenticado):** nftables DNAT intercepta el HTTP (`meta mark != 0x1`) → redirige a `192.168.30.1:2050` (captive portal nginx en Mini PC) → proxied a `127.0.0.1:2051` (captive-accept.py) → 302. ✅ Nunca llega al nginx de la RPi.

- **Clics siguientes (autenticado, mark=0x1):** DNAT para no-autenticados no aplica. DNAT para autenticados no aplica (`ip daddr != 192.168.20.10` es falso porque `biblioteca.local = 192.168.20.10`). El paquete llega directamente al nginx de la RPi. nginx intenta conectar a `127.0.0.1:8088` → connection refused → **502**. ❌

Confirmado en pcap (Wireshark cliente): `t+100.779s GET /accept → 192.168.20.10:80 → 502 Bad Gateway` mientras que requests previos retornaban 302 desde el Mini PC.

## Fix aplicado

**Archivo:** `raspberry/rpi-setup/roles/nginx/templates/biblioteca.nginx.j2`

```diff
 location = /accept {
-    proxy_pass http://127.0.0.1:8088/accept;
-    proxy_set_header X-Real-IP $remote_addr;
-    proxy_set_header Host $host;
+    return 302 http://192.168.30.1:2050/accept;
 }
```

La RPi redirige `/accept` directamente al captive portal en el Mini PC (`192.168.30.1:2050/accept`), que siempre es accesible desde VLAN30 (nftables permite `tcp dport 2050` en todas las VLANs). `captive-accept.py` es idempotente: si el cliente ya está autorizado, simplemente re-añade la IP al set nftables (sin efecto) y devuelve 302 a `http://biblioteca.local`.

**Deploy:**
```bash
cd raspberry/rpi-setup
ansible rpi -i inventory.ini -m template \
  -a "src=roles/nginx/templates/biblioteca.nginx.j2 dest=/etc/nginx/sites-available/biblioteca owner=root group=root mode=0644" \
  --become -e "@group_vars/all.yml"
ansible rpi -i inventory.ini -m service -a "name=nginx state=reloaded" --become
```

## Verificación

```bash
# Desde la RPi — debe retornar 302 a http://192.168.30.1:2050/accept
ssh akasicom@100.90.81.168 \
  "curl -s -o /dev/null -w '%{http_code} → %{redirect_url}' http://localhost/accept"
# → 302 → http://192.168.30.1:2050/accept ✅
```
