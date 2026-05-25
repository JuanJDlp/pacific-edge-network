# DNS Secundario — Bind9 slave de biblioteca.tel en RPi

## Rol Ansible

`raspberry/rpi-setup/roles/dns_secondary/`

## Descripción

Bind9 en la RPi actúa como DNS secundario (slave) del dominio `biblioteca.tel`. El DNS primario (master) está en el Mini PC (192.168.10.1). La RPi recibe las zonas vía zone transfer automático y puede responder queries localmente sin depender del Mini PC.

## Arquitectura DNS

```
[Mini PC — 192.168.10.1]         [RPi — 192.168.20.10]
  Bind9 master                      Bind9 slave
  zona: biblioteca.tel    ──→     zona: biblioteca.tel (copia)
  zonas inversas VLAN10/20/30 ──→  zonas inversas (copia)

  AXFR zone transfer
  (allow-transfer { 192.168.20.10; })
```

## Zone transfer: Mini PC → RPi

El Mini PC fue actualizado para permitir transfers a la RPi en `named.conf.local.j2`:

```bind
zone "biblioteca.tel" {
    type master;
    allow-transfer { 192.168.20.10; };  // RPi DNS secundario
};
```

La RPi declara las zonas como slave:

```bind
zone "biblioteca.tel" {
    type slave;
    masters { 192.168.10.1; };
    file "/var/cache/bind/db.biblioteca.tel";
};
```

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

**No escucha** en `wlan0` (WiFi backup) ni en `wt0` (Netbird) para no exponer DNS públicamente.

## Forwarders

Queries externas se reenvían al Mini PC primero, luego a DNS público:
```
forward first;
forwarders { 192.168.10.1; 8.8.8.8; 8.8.4.4; };
```

## Advertencia — Netplan RPi

El rol `dns_secondary` **no modifica** ningún archivo de red (`/etc/netplan/`, `/etc/resolv.conf`). La RPi usa el DNS del Mini PC (192.168.10.1) vía DHCP para sus propias queries. El Bind9 local solo responde a queries externas (de clientes de la red).

## Verificación

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
| `templates/named.conf.local.j2` | `/etc/bind/named.conf.local` |
