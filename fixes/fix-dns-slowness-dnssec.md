# Fix: DNS lento 7-10 segundos — dnssec-validation conflicto con forward only

**Fecha:** 2026-05-20
**Afecta:** Mini PC (`plataformas`, 100.90.95.134) — Bind9

## Síntoma

Algunas queries DNS (principalmente dominios de Apple iCloud / iCloud Private Relay) tardaban entre 7 y 10 segundos en resolverse. El resto de dominios respondía en 1–200ms.

Dominios afectados confirmados por pcap Wireshark:
- `mask.apple-dns.net` → RTT **6989ms**
- `mask.icloud.com` → RTT **8989ms**
- `mask-h2.icloud.com` → RTT **9590ms**

El cliente enviaba la misma query hasta 3–4 veces mientras esperaba respuesta.

## Causa raíz

Conflicto entre dos opciones de Bind9:
- `forward only` — Bind9 **no hace recursión propia**, solo reenvía a 8.8.8.8 / 8.8.4.4 / 1.1.1.1
- `dnssec-validation auto` — Bind9 **valida la cadena DNSSEC** de las respuestas recibidas

Con `forward only`, Bind9 depende de que los forwarders incluyan todos los registros RRSIG necesarios. Los dominios de Apple iCloud Private Relay tienen cadenas DNSSEC incompletas desde Colombia: los forwarders devuelven la respuesta sin los registros DS/RRSIG intermedios. Bind9 no puede validar, reintenta con cada forwarder y espera hasta el `resolver-query-timeout` (10 segundos por defecto) antes de responder SERVFAIL o aceptar sin validar.

Evidencia en los logs del servicio:
```
named: no valid RRSIG resolving '168.192.in-addr.arpa/DS/IN': 1.1.1.1#53
named: no valid RRSIG resolving '168.192.in-addr.arpa/DS/IN': 8.8.8.8#53
named: broken trust chain resolving 'lb._dns-sd._udp.0.100.168.192.in-addr.arpa/PTR/IN': 8.8.4.4#53
```

## Fix aplicado

**Archivo:** `minipc/router-setup/roles/dns/templates/named.conf.options.j2`

```diff
-    // DNSSEC: auto (valida cuando sea posible)
-    dnssec-validation auto;
+    // DNSSEC: deshabilitado — forward only + validación rompe cadenas de Apple/iCloud (7-10s timeout)
+    dnssec-validation no;
```

**Justificación:** Este DNS es un resolver interno en modo `forward only`. Los forwarders públicos (Google, Cloudflare) ya realizan validación DNSSEC en su extremo. Deshabilitar la validación local es correcto y seguro para este caso de uso.

**Deploy:**
```bash
cd minipc/router-setup
ansible-playbook playbook.yml -i inventory.ini --tags dns
```

## Verificación

```bash
ssh minipc "time dig @192.168.10.1 mask.icloud.com +short"
# Antes: ~9 segundos
# Después: 0.116s ✅

ssh minipc "time dig @192.168.10.1 mask.apple-dns.net +short"
# Después: 0.023s ✅

ssh minipc "time dig @192.168.10.1 biblioteca.local +short"
# Después: 0.024s → 192.168.20.10 ✅
```
