# DNS Secundario — Bind9 slave de biblioteca.tel en RPi

> **Ultima actualizacion:** 2026-06-02
> BIND 9.18.39
>
> 📚 Teoría + porqué de master/slave, TSIG y DNSSEC en [`dns/`](../../dns/) (raíz del
> repo), en especial [`dns/04-master-slave-tsig.md`](../../dns/04-master-slave-tsig.md).

## Rol Ansible

`raspberry/rpi-setup/roles/dns_secondary/`

## Descripcion

Bind9 en la RPi actua como DNS secundario (slave) del dominio `biblioteca.tel`. El DNS primario (master) esta en el Mini PC (192.168.10.1). La RPi recibe las zonas via zone transfer automatico y puede responder queries localmente sin depender del Mini PC.

## Arquitectura DNS

```
[Mini PC — master]                       [RPi — 192.168.20.10 — slave]
  Bind9 master                             Bind9 slave
  zona: biblioteca.tel (firmada DNSSEC) ─▶  zona: biblioteca.tel (copia firmada)
  zonas inversas VLAN10/20/30 ───────────▶  zonas inversas (copia)

  AXFR/IXFR + NOTIFY autenticados con TSIG (clave ns1-ns2.)
  La RPi pide al master por su IP en la VLAN20: 192.168.20.1
```

## Zone transfer: Mini PC → RPi (autenticado con TSIG)

Las transferencias están **autenticadas con TSIG** (clave compartida `ns1-ns2.`,
`hmac-sha256`), no por IP. El master autoriza por clave en `named.conf.local.j2`:

```bind
zone "biblioteca.tel" {
    type master;
    allow-transfer { key "ns1-ns2."; };          // solo quien presente la clave
    also-notify { 192.168.20.10; fd00:0:0:20::10; };
    notify yes;
};
```

La RPi declara las zonas como slave, presentando la clave al master:

```bind
zone "biblioteca.tel" {
    type slave;
    masters { 192.168.20.1 key "ns1-ns2."; };    // ← IP del master en la VLAN20
    file "/var/cache/bind/db.biblioteca.tel";
};
```

> **Ojo con la IP del master:** la RPi transfiere desde **`192.168.20.1`** (la IP del
> Mini PC en la VLAN20, mismo segmento que la RPi), no desde `192.168.10.1`. Variable:
> `dns_master_transfer_ip` en `group_vars/all.yml`.

### TSIG y DNSSEC

- **TSIG:** la clave (`tsig_key_name` / `tsig_secret`) está en
  `raspberry/rpi-setup/group_vars/all.yml` y **debe ser idéntica** a la del master
  (`minipc/router-setup/roles/dns/vars/main.yml`). El slave la despliega en
  `/etc/bind/named.conf.tsig` (solo el bloque `key`).
- **DNSSEC:** la zona llega a la RPi **ya firmada** por el master. El slave **no firma**
  (no tiene las claves privadas), solo sirve la copia firmada. Por eso el master hace
  `also-notify` explícito: cuando re-firma la zona (las RRSIG expiran), avisa al slave.

## Zonas replicadas

| Zona | Tipo |
|------|------|
| `biblioteca.tel` | Forward (A + CNAME) |
| `10.168.192.in-addr.arpa` | Reverse VLAN10 |
| `20.168.192.in-addr.arpa` | Reverse VLAN20 |
| `30.168.192.in-addr.arpa` | Reverse VLAN30 |

## Escucha

Solo en interfaces internas:
- `127.0.0.1` (loopback)
- `192.168.20.10` (VLAN20 — servidores)

**No escucha** en `wlan0` (WiFi backup) ni en `wt0` (Netbird) para no exponer DNS publicamente.

## Forwarders

Queries externas se reenvian al Mini PC primero, luego a DNS publico:
```
forward first;
forwarders { 192.168.10.1; 8.8.8.8; 8.8.4.4; };
```

## Advertencia — Netplan RPi

El rol `dns_secondary` **no modifica** ningun archivo de red (`/etc/netplan/`, `/etc/resolv.conf`). La RPi usa el DNS del Mini PC (192.168.10.1) via DHCP para sus propias queries. El Bind9 local solo responde a queries externas (de clientes de la red).

## Verificacion

```bash
# DNS secundario responde
dig @192.168.20.10 biblioteca.tel
# → 192.168.20.10

dig @192.168.20.10 wikipedia.biblioteca.tel
# → CNAME biblioteca.biblioteca.tel → 192.168.20.10

# Zone transfer forzado (desde RPi)
sudo rndc retransfer biblioteca.tel

# Verificar que la zona fue transferida
ls -la /var/cache/bind/db.biblioteca.tel

# Estado de Bind9
systemctl status named
sudo named-checkconf
```

## Archivos desplegados por Ansible

| Template | Destino en RPi |
|----------|----------------|
| `templates/named.conf.options.j2` | `/etc/bind/named.conf.options` |
| `templates/named.conf.tsig.j2` | `/etc/bind/named.conf.tsig` (0640) |
| `templates/named.conf.local.j2` | `/etc/bind/named.conf.local` |

## Zona ajena: `praticasaws.dev` (Matrix/Conduit)

`named.conf.local.j2` del slave también declara `zone "praticasaws.dev" { type master; }`.
**No es parte del DNS de la red comunitaria** (es del homeserver Matrix/Conduit); se
preserva en este template solo para que al regenerar el archivo no se borre. Fuera del
alcance DNS/DNSSEC/TSIG de este doc.

## Verificación de TSIG (extra)

```bash
# Re-transferir desde el master (en la RPi)
sudo rndc retransfer biblioteca.tel
sudo rndc zonestatus biblioteca.tel        # serial == al del master

# Demostrar que TSIG protege: con clave funciona, sin clave es rechazado
dig @192.168.20.1 biblioteca.tel AXFR -y hmac-sha256:ns1-ns2.:<secret>   # OK
dig @192.168.20.1 biblioteca.tel AXFR                                     # REFUSED
```
