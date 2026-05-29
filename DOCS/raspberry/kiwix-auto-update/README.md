# Kiwix — Auto-actualizacion de contenido ZIM

> **Implementado:** 2026-05-29
> **Estado:** En produccion
> **Componente:** `raspberry/rpi-setup/roles/kiwix/`

Sistema automatico que mantiene actualizados los archivos ZIM (Wikipedia, Wikibooks, Wikinews, Wikiversity, Wikivoyage) en la Raspberry Pi sin intervencion manual.

## Problema que resuelve

Los ZIM se publicaban manualmente: alguien debia entrar por SSH a la RPi, descargar el archivo nuevo, actualizar `library.xml`, editar la homepage y reiniciar kiwix-serve. Si nadie lo hacia, los estudiantes navegaban contenido desactualizado indefinidamente.

## Que hace

1. Detecta versiones mas recientes en `download.kiwix.org`
2. Descarga de noche con limite de ancho de banda (2 MB/s)
3. Reemplaza el ZIM viejo atomicamente (sin downtime)
4. Actualiza `library.xml` y los links de la homepage
5. Reinicia kiwix-serve una sola vez al final
6. Elimina el contenido viejo (no se persisten dos versiones)

## Mapa de documentos

| # | Documento | Contenido |
|---|---|---|
| 1 | [`01-ARQUITECTURA.md`](01-ARQUITECTURA.md) | Flujo completo del script, componentes involucrados, diagrama de secuencia. |
| 2 | [`02-CONFIGURACION.md`](02-CONFIGURACION.md) | Variables Ansible, como agregar/quitar ZIMs, ajustar schedule y bandwidth. |
| 3 | [`03-OPERACION.md`](03-OPERACION.md) | Ejecucion manual, logs, monitoreo, troubleshooting. |

## TL;DR

- **Script:** `/usr/local/sbin/update-kiwix-content` (desplegado por Ansible)
- **Cron:** lunes y jueves a las 02:00 (`0 2 * * 1,4`)
- **Logs:** `/var/log/biblioteca/kiwix-update.log` + syslog (`kiwix-update`)
- **Bandwidth:** limitado a 2 MB/s (~7 GB/hora)
- **Fuente:** `https://download.kiwix.org/zim/{category}/`

## Deploy

```bash
cd raspberry/
ansible-playbook -i rpi-setup/inventory.ini services/kiwix.yml
```

## Archivos Ansible

| Archivo | Descripcion |
|---------|-------------|
| `roles/kiwix/templates/update-kiwix-content.sh.j2` | Script principal (template Jinja2) |
| `roles/kiwix/tasks/main.yml` | Tasks de deploy (script + cron + logrotate) |
| `rpi-setup/group_vars/all.yml` | Variable `kiwix_zim_sources` (lista de ZIMs) |
