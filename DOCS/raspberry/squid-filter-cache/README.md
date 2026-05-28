# Squid — Filtrado HTTPS + Cache biblioteca.tel

> **Implementado:** 2026-05-27
> **Estado:** En producción
> **Versión Squid:** 6.14 (paquete `squid-openssl` en Ubuntu 24.04)

Este conjunto de documentos describe **completamente** la implementación de filtrado HTTPS por SNI y cache reverse-proxy para `biblioteca.tel` en la Raspberry Pi de la red Pacific Edge.

## Objetivos cumplidos

1. ✅ **Bloquear** páginas prohibidas (porn + apuestas, ~82k dominios) en HTTP y HTTPS para clientes VLAN30 autenticados.
2. ✅ **Cachear** el contenido de `biblioteca.tel` (HTTPS) para reducir carga en los backends (Kiwix, Kolibri, Jellyfin).
3. ✅ **No cachear** ningún contenido de internet (por privacidad y para evitar servir páginas obsoletas).
4. ✅ Todo **replicable vía Ansible** — no hay un solo cambio manual sin un rol que lo encode.
5. ✅ No romper ningún flujo existente (portal cautivo, DNS, DHCP, HTTP intermediary, biblioteca.tel HTTP).

## Mapa de documentos

| # | Documento | ¿Qué encontrarás? |
|---|---|---|
| 1 | [`01-ARQUITECTURA.md`](01-ARQUITECTURA.md) | Diagramas de los 4 flujos finales (HTTP/HTTPS × internet/biblioteca.tel), componentes, puertos. |
| 2 | [`02-DECISIONES.md`](02-DECISIONES.md) | **Cada decisión técnica con su justificación**: alternativas consideradas, trade-offs y por qué se eligió cada cosa. |
| 3 | [`03-IMPLEMENTACION.md`](03-IMPLEMENTACION.md) | Lista detallada archivo por archivo de los cambios: qué cambió, por qué, y dónde está. |
| 4 | [`04-CONSIDERACIONES.md`](04-CONSIDERACIONES.md) | Riesgos, limitaciones, bypass posibles, qué pasa cuando algo cae, impacto en privacidad. |
| 5 | [`05-TESTING.md`](05-TESTING.md) | Cómo probar todo: filtrado, cache, idempotencia Ansible, baselines de performance. |
| 6 | [`06-BLOCKLISTS.md`](06-BLOCKLISTS.md) | Qué páginas están bloqueadas, **cómo añadir/quitar dominios**, cómo cambiar las categorías. |
| 7 | [`07-TROUBLESHOOTING.md`](07-TROUBLESHOOTING.md) | Errores comunes y cómo diagnosticarlos rápido. |

## TL;DR para impacientes

```
                      Cliente VLAN30 (192.168.30.X)
                              │
                ┌─────────────┼──────────────┐
                ▼             ▼              ▼
        biblioteca.tel    internet HTTPS  internet HTTP
              HTTPS         (cualquiera)   (cualquiera)
                │             │              │
                │             │              │ DNAT en Mini PC
                │             │              ▼
                │             │       nginx :8888 (intermediario)
                │             │              │
                │             │ DNAT en      ▼
                │             │ Mini PC    Squid :3129 (forward proxy)
                │             ▼              │  ← bloquea HTTP por blocklist
                │      Squid :3130           │
                │      (peek+splice SNI)     │
                │             │              │
                │      ¿SNI bloqueado?       │
                │       SÍ → terminate       │
                │       NO → splice (TLS)    │
                │             │              │
                ▼             ▼              ▼
        Squid :443       Internet         Internet
        (reverse proxy)   (cifrado E2E)   (HTTP plano)
              │
              ▼
        nginx :80 (loopback)
              │
              ├─ Kiwix    (127.0.0.1:8080)
              ├─ Kolibri  (127.0.0.1:8090)
              └─ Jellyfin (127.0.0.1:8096)
```

## Cómo aplicar todo desde cero

```bash
# Mini PC (firewall nftables)
cd minipc/
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags firewall

# Raspberry Pi (Squid + nginx)
cd ../raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/squid.yml
ansible-playbook -i rpi-setup/inventory.ini services/nginx.yml
```

Todo es idempotente — correr dos veces no cambia nada.

## Cómo verificar que todo funciona

Ver [`05-TESTING.md`](05-TESTING.md) para la batería completa. Versión corta:

```bash
ssh akasicom@100.90.81.168
# Squid escucha en 4 puertos
sudo ss -tlnp | grep -E ':(443|3128|3129|3130)\s'
# Cache de biblioteca.tel funciona (segundo hit = HIT)
curl -ks https://biblioteca.tel/index.html -o /dev/null && \
  curl -ks https://biblioteca.tel/index.html -o /dev/null && \
  sudo tail -2 /var/log/squid/access.log
# Debe verse TCP_MEM_HIT o TCP_HIT
```
