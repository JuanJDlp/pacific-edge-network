# DNS — Bind9 (`biblioteca.tel`)

> Actualizado: 2026-06-02
>
> 📚 **¿Quieres entender el porqué, no solo el qué?** La carpeta [`dns/`](../../dns/)
> (raíz del repo) es una master class de DNS/DNSSEC/TSIG con la teoría del protocolo y
> el detalle de esta implementación. Este doc es la referencia operativa rápida.

## Rol Ansible

`minipc/router-setup/roles/dns/`

## Descripcion

Bind9 **v9.18.39** actua como servidor DNS autoritativo para el dominio `biblioteca.tel` y como resolver recursivo con forwarding para dominios externos. Reemplaza la resolucion DNS en las VLANs internas (el stub de systemd-resolved sigue activo en `127.0.0.53` solo para uso local del Mini PC).

## Por qué Bind9 y no systemd-resolved

systemd-resolved no soporta zonas locales autoritativas con múltiples registros A/CNAME. Bind9 permite:
- Definir `biblioteca.tel` con A records por servicio
- Responder en múltiples interfaces (una IP por VLAN)
- Forwarding condicional a DNS externos

## Interfaces donde escucha

Dual-stack (IPv4 + IPv6 ULA), puerto 53 TCP y UDP:

| Interfaz | IPv4 | IPv6 (ULA) | VLANs que lo usan |
|---|---|---|---|
| loopback | 127.0.0.1 | ::1 | Mini PC local |
| enp171s0.10 | 192.168.10.1 | fd00:0:0:10::1 | VLAN10 gestión |
| enp171s0.20 | 192.168.20.1 | fd00:0:0:20::1 | VLAN20 servidores |
| enp171s0.30 | 192.168.30.1 | fd00:0:0:30::1 | VLAN30 clientes |

El nftables ya redirige UDP/TCP 53 desde las VLANs hacia `192.168.10.1:53` (Bind9), así
que en la práctica los clientes siempre pegan al primario aunque escuche en las 3 VLANs.

> **TCP 53 importante:** las transferencias de zona (AXFR/IXFR) y las respuestas grandes
> de DNSSEC van por TCP. El rol elimina el drop-in `lan-stub.conf` de systemd-resolved
> (ocupaba el TCP 53 en las IPs de VLAN y bloqueaba los transfers). Verificar con
> `ss -tulnp 'sport = :53'` que es **named**, no `systemd-resolve`, quien posee el TCP 53.

## DNS64 (NAT64)

`named.conf.options` declara `dns64 64:ff9b::/96`: sintetiza registros AAAA para destinos
externos IPv4-only (que luego Jool traduce vía NAT64 en el rol `router`). Excluye RFC1918
(`mapped`) y preserva las AAAA reales ULA `fd00::/8` (`exclude`). Detalle de NAT64 en el
rol `router`; aquí solo se documenta que esta directiva vive en el DNS.

## Registros del dominio `biblioteca.tel`

### A records

| Nombre | IP | Descripción |
|---|---|---|
| minipc | 192.168.10.1 | Mini PC — gateway |
| ns1 | 192.168.10.1 | Nameserver primario |
| switch | 192.168.10.2 | Switch Catalyst 2960 |
| biblioteca | 192.168.20.10 | RPi — servidor de servicios |
| rpi | 192.168.20.10 | RPi (alias técnico) |

### CNAME (alias → biblioteca)

| Alias | Destino | Servicio |
|---|---|---|
| wikipedia | biblioteca | Kiwix Wikipedia |
| educacion | biblioteca | Kolibri |
| videos | biblioteca | Jellyfin |
| kolibri | biblioteca | Kolibri |
| jellyfin | biblioteca | Jellyfin |
| squid | biblioteca | Squid proxy |
| wiki | biblioteca | Kiwix (alias corto) |
| media | biblioteca | Jellyfin (alias) |

Todos los servicios educativos resuelven a `192.168.20.10` (RPi). El nginx de la RPi los enruta al puerto correcto según el `Host` header.

## Zonas inversas (PTR)

- `10.168.192.in-addr.arpa` → VLAN10
- `20.168.192.in-addr.arpa` → VLAN20
- `30.168.192.in-addr.arpa` → VLAN30

## Forwarding externo

Cuando un cliente pide `google.com` u otro dominio externo, Bind9 hace forwarding a:
1. `8.8.8.8` (Google)
2. `8.8.4.4` (Google)
3. `1.1.1.1` (Cloudflare)

## Archivos de configuración desplegados

| Archivo en Mini PC | Template Ansible | Notas |
|---|---|---|
| `/etc/bind/named.conf.options` | `templates/named.conf.options.j2` | opciones globales, DNSSEC, DNS64 |
| `/etc/bind/named.conf.local` | `templates/named.conf.local.j2` | declaración de zonas |
| `/etc/bind/named.conf.tsig` | `templates/named.conf.tsig.j2` | clave TSIG (0640) |
| `/etc/bind/named.conf.trust-anchors` | generado por `tasks/dnssec.yml` | KSK de la zona |
| `/etc/bind/named.conf.rpz` | `.enabled`/`.disabled` (alterna `wan-check.sh`) | política RPZ activa |
| `/var/lib/bind/db.biblioteca.tel` | `templates/db.forward.j2` | **zona directa fuente** (sin firmar) |
| `/var/lib/bind/db.biblioteca.tel.signed` | (genera BIND) | versión firmada — no editar |
| `/var/lib/bind/keys/` | (genera BIND) | claves DNSSEC KSK/ZSK |
| `/etc/bind/zones/db.10.168.192` | `templates/db.reverse.j2` (VLAN10) | inversa, sin firmar |
| `/etc/bind/zones/db.20.168.192` | `templates/db.reverse.j2` (VLAN20) | inversa, sin firmar |
| `/etc/bind/zones/db.30.168.192` | `templates/db.reverse.j2` (VLAN30) | inversa, sin firmar |

> ⚠️ **La zona directa vive en `/var/lib/bind`, NO en `/etc/bind/zones`.** Razón:
> AppArmor (`usr.sbin.named`) deja `/etc/bind` como solo-lectura para `named`; el
> `inline-signing` de DNSSEC necesita escribir el `.signed`, el journal `.jnl` y las
> claves, y solo puede hacerlo bajo `/var/lib/bind` (y `/var/cache/bind`). Las inversas
> no se firman, así que pueden quedarse en `/etc/bind/zones`.

## DNSSEC

La zona `biblioteca.tel` está **firmada con DNSSEC** (solo la directa; las inversas no).
Firmado y rotación de claves **automáticos** vía `dnssec-policy default` + `inline-signing`
(BIND 9.18). Las claves viven en `/var/lib/bind/keys/`.

Como `biblioteca.tel` es un TLD local (no cuelga de la raíz de internet, nadie publica su
`DS`), `tasks/dnssec.yml` extrae la **KSK** de la zona firmada y la publica como **trust
anchor local** en `/etc/bind/named.conf.trust-anchors`, para que el resolver valide y
marque el bit `AD`. `dnssec-validation auto` en `named.conf.options` activa la validación.

```bash
# ¿Firmada?
sudo rndc zonestatus biblioteca.tel | grep -i secure        # → secure: yes
# ¿El resolver valida? (busca el flag "ad")
dig @192.168.10.1 biblioteca.tel +dnssec | grep -i flags
delv @127.0.0.1 biblioteca.tel A                            # → "; fully validated"
```

> Si rotas la KSK, **re-corre el rol DNS** para re-extraer y re-publicar el trust anchor
> (si no, la validación rompe con SERVFAIL). Detalle completo en [`dns/05-dnssec.md`](../../dns/05-dnssec.md).

## TSIG (transferencias master ↔ slave)

Las transferencias de zona hacia el DNS secundario (RPi) están **autenticadas con TSIG**
(clave `ns1-ns2.`, `hmac-sha256`), no por IP. En `named.conf.local`:

```bind
zone "biblioteca.tel" {
    type master;
    allow-transfer { key "ns1-ns2."; };          // solo quien presente la clave
    also-notify { 192.168.20.10; fd00:0:0:20::10; };
    notify yes;
};
```

`allow-transfer { none; }` global en `named.conf.options`; cada zona autoriza por clave.
El secret está en `roles/dns/vars/main.yml` (`tsig_secret`) y **debe ser idéntico** al de
`raspberry/rpi-setup/group_vars/all.yml`. Detalle en [`dns/04-master-slave-tsig.md`](../../dns/04-master-slave-tsig.md).

## Variables (`roles/dns/vars/main.yml`)

```yaml
dns_domain: "biblioteca.tel"
dns_primary_ip: "192.168.10.1"
dns_listen_ips: [127.0.0.1, 192.168.10.1, 192.168.20.1, 192.168.30.1]
dns_forwarders: [8.8.8.8, 8.8.4.4, 1.1.1.1]
dns_forward_zone_path: "/var/lib/bind/db.biblioteca.tel"   # zona firmada (AppArmor)
dnssec_policy: "default"
dnssec_key_dir: "/var/lib/bind/keys"
dnssec_trust_anchor_file: "/etc/bind/named.conf.trust-anchors"
tsig_key_name: "ns1-ns2."
tsig_secret: "…"        # mismo valor en group_vars/all.yml de la RPi
```

## Verificación

```bash
# Desde cualquier cliente en VLAN30
dig @192.168.10.1 biblioteca.tel +short
# → 192.168.20.10

dig @192.168.10.1 wikipedia.biblioteca.tel +short
# → biblioteca.biblioteca.tel. (CNAME) → 192.168.20.10

# Estado del servicio en Mini PC
systemctl status named
named-checkconf
named-checkzone biblioteca.tel /var/lib/bind/db.biblioteca.tel
```

## Coexistencia con systemd-resolved

systemd-resolved sigue activo en `127.0.0.53` para resolver consultas locales del Mini PC (ej. actualizaciones apt). No interfiere con Bind9 porque escuchan en IPs distintas. Los clientes DHCP reciben `192.168.10.1` como DNS, apuntando directamente a Bind9.

## RPZ (Response Policy Zone)

Bind9 usa RPZ para dos cosas:

### `rpz.blocklist` — siempre activa (porn + gambling)

Zona master local que carga `/etc/bind/zones/rpz.blocklist.zone`. Cualquier consulta DNS para un dominio en la lista retorna **NXDOMAIN**, bloqueando porn y gambling a nivel DNS (HTTP y HTTPS por igual). `biblioteca.tel` y subdominios son `PASSTHRU` (nunca bloqueados).

- **Script de actualizacion:** `/usr/local/sbin/update-bind-rpz` — descarga StevenBlack/hosts (porn-only + gambling-only), genera la zona, valida con `named-checkzone`, hace `rndc reload`.
- **Timer systemd:** `bind-rpz-update.timer` — domingos 03:00 (±30 min).
- **Bootstrap:** la zona se inicializa al ejecutar el rol Ansible (`/var/lib/bind-rpz-bootstrap.done` marca el primer run).
- **Tamano actual:** ~82 800 dominios.

### `rpz.offline` — activa solo cuando WAN cae

Zona master local que redirige todos los dominios externos a `192.168.30.1`. Activada/desactivada por `wan-check.sh` (timer cada 15s) reemplazando `/etc/bind/named.conf.rpz` con `.enabled` o `.disabled`. `rpz.blocklist` queda activa en ambos casos.

```bash
# Ver dominios bloqueados (live)
dig @192.168.10.1 bet365.com +short   # → NXDOMAIN
dig @192.168.10.1 google.com +short   # → resuelve normal

# Forzar update de la blocklist
sudo systemctl start bind-rpz-update.service

# Ver estado de las zonas RPZ
sudo rndc zonestatus rpz.blocklist
sudo rndc zonestatus rpz.offline
```
