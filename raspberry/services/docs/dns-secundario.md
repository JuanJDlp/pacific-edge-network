# DNS Secundario — Bind9 Slave

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/dns_secondary/`
**Servicio systemd:** `named`
**Puerto:** `:53`

---

## Qué hace

Bind9 en la RPi actúa como servidor DNS secundario (slave) del dominio `biblioteca.tel`. Mantiene copias sincronizadas de todas las zonas del Mini PC y puede responder queries si el Mini PC está temporalmente inaccesible.

---

## Dónde escucha

| Interfaz | IPv4 | IPv6 |
|---|---|---|
| Loopback | `127.0.0.1:53` | `::1:53` |
| VLAN20 | `192.168.20.10:53` | `fd00:0:0:20::10:53` |

---

## Zonas replicadas (slave)

| Zona | Tipo | Master |
|---|---|---|
| `biblioteca.tel` | slave | `192.168.20.1` (Mini PC vía VLAN20) |
| `10.168.192.in-addr.arpa` | slave | `192.168.20.1` |
| `20.168.192.in-addr.arpa` | slave | `192.168.20.1` |
| `30.168.192.in-addr.arpa` | slave | `192.168.20.1` |

> El master es `192.168.20.1` (gateway VLAN20 del Mini PC) en lugar de `192.168.10.1` porque la RPi está en VLAN20 y tiene accesibilidad directa a través de ese gateway.

Las zonas se guardan en caché local en `/var/cache/bind/`. Cuando Bind9 en la RPi inicia, verifica si la zona local está desactualizada y hace un zone transfer (AXFR) al master.

---

## Sincronización de zonas

El Mini PC (Bind9 primario) permite zone transfers hacia la RPi:

```
allow-transfer { 192.168.20.10; fd00:0:0:20::10; 192.168.20.1; 127.0.0.1; };
```

Cuando el admin actualiza un registro en el primario y recarga Bind9, el número de serie de la zona aumenta. El secundario detecta el cambio (via NOTIFY o polling SOA) y solicita un AXFR para sincronizar.

---

## Forwarders del secundario

Para dominios externos (no locales), el secundario reenvía al primario:

```
forwarders {
    192.168.10.1;       # Mini PC (primario)
    fd00:0:0:10::1;     # Mini PC IPv6
    8.8.8.8;            # Google DNS (fallback)
    8.8.4.4;
};
forward first;
```

`forward first` — intenta el forwarder primero; si no responde, recurre a resolución iterativa.

---

## DNSSEC

El secundario tiene `dnssec-validation auto` (a diferencia del primario que lo tiene deshabilitado). Esto valida las firmas DNSSEC de los dominios externos que pasen por el secundario.

---

## Clientes que pueden usar el secundario

```
allow-recursion {
    127.0.0.1;
    192.168.0.0/16;      # todas las VLANs internas
    100.64.0.0/10;       # NetBird CGNAT
    ::1;
    fd00::/8;            # ULA (todas las VLANs IPv6)
};
```

---

## Flujo de query durante falla del primario

```
[Cliente VLAN20/30]
    │ query → 192.168.10.1:53 (primario via DNAT)
    │ primario no responde (timeout)
    ▼
[Bind9 RPi :53 — secundario]
    │ tiene copia local de biblioteca.tel
    │ responde con los registros cacheados
    ▼
[Cliente recibe respuesta]
```

> En la configuración actual, el DNAT de nftables fuerza todas las queries al Mini PC (`192.168.10.1:53`). El secundario actúa como fallback solo si los clientes lo tienen configurado manualmente o si el DNAT falla. Para usarlo activamente como HA, se debería agregar la IP del secundario como segundo DNS en Kea.

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status named

# Verificar zona replicada
dig @192.168.20.10 biblioteca.tel SOA

# Forzar sincronización de zona
sudo rndc refresh biblioteca.tel

# Ver estado de las zonas
sudo rndc zonestatus biblioteca.tel

# Ver si hay diferencia de serial con el primario
dig @192.168.10.1 biblioteca.tel SOA +short   # serial del primario
dig @192.168.20.10 biblioteca.tel SOA +short  # serial del secundario

# Logs de Bind9
sudo journalctl -u named -f
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags dns_secondary
# o:
ansible-playbook services/dns_secondary.yml -i rpi-setup/inventory.ini
```
