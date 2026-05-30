# Pi-hole — Bloqueo de publicidad DNS

> **Estado: NO DESPLEGADO** — Pi-hole esta documentado como plan pero nunca fue activado.
> Docker esta instalado en el Mini PC pero el contenedor Pi-hole no esta corriendo.
> El bloqueo de contenido se realiza actualmente via Squid (blocklists en la RPi).

**Dispositivo:** Mini PC (`plataformas`)
**Rol Ansible:** `minipc/router-setup/roles/pihole/`
**Servicio systemd:** `pihole` (wrapper sobre Docker Compose)
**Imagen Docker:** `pihole/pihole:2024.07.0`

---

## Arquitectura propuesta (no implementada)

Pi-hole correria como contenedor Docker en el Mini PC y actuaria como resolvedor DNS con bloqueo de publicidad, rastreadores y contenido no deseado para toda la red. Tomaria el puerto 53 en `192.168.10.1`, desplazando a Bind9 al puerto 5353.

```
[Clientes VLANs 10/20/30]
    | cualquier DNS (nftables DNAT fuerza a 192.168.10.1:53)
    v
[Pi-hole :53 en 192.168.10.1]
    | dominio en blocklist? → NXDOMAIN (bloqueado)
    | biblioteca.tel? → reenvio a Bind9 en :5353 (mismo host)
    | dominio externo? → reenvio a Quad9 (9.9.9.9)
    v
[Respuesta al cliente]
```

---

## Estado actual alternativo

El filtrado de contenido se maneja via:
- **Squid** en la RPi (`:3128`/`:3130`) con blocklists de StevenBlack (porn + gambling)
- **nftables** DNAT forzando HTTPS de VLAN30 a Squid SNI filter (`:3130`)

Ver `DOCS/raspberry/squid-filter-cache/` para documentacion completa del sistema de filtrado actual.
