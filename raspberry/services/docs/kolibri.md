# Kolibri — Plataforma Educativa Offline

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/kolibri/`
**Servicio systemd:** `kolibri`
**Puerto interno:** `127.0.0.1:8090`
**Acceso de clientes:** `http://biblioteca.tel/kolibri/`

---

## Qué hace

Kolibri es una plataforma de aprendizaje diseñada para funcionar completamente offline. Sirve contenido educativo estructurado (cursos, videos, ejercicios, evaluaciones) para estudiantes sin acceso a internet. Es desarrollada por Learning Equality y está optimizada para hardware limitado como la Raspberry Pi.

---

## Exposición al exterior

Kolibri escucha en **loopback** (`127.0.0.1:8090`). Los clientes acceden a través de nginx:

```
http://biblioteca.tel/kolibri/
```

nginx proxea el path `/kolibri/` hacia `kolibri_backend` con soporte para WebSockets (usados por Kolibri para actualizaciones de progreso en tiempo real).

---

## Configuración nginx para Kolibri

Kolibri requiere configuración especial en nginx debido a:

- **WebSockets** — para notificaciones en tiempo real durante ejercicios
- **Timeouts largos** — `proxy_read_timeout 600s` para cargas de contenido pesado
- **Body grande** — `client_max_body_size 1G` para importación de canales
- **Buffers grandes** — `proxy_buffer_size 16k` para headers de respuesta de Kolibri

---

## Contenido de Kolibri

Kolibri organiza el contenido en **canales**. Cada canal es un paquete de lecciones, videos o ejercicios agrupados por tema o proveedor.

Canales populares para redes comunitarias:
- Khan Academy (matemáticas, ciencias, historia)
- CK-12 Foundation
- African Storybook Initiative
- Wikipedia for Schools

Los canales se importan desde Kolibri Studio o desde un archivo local. El contenido queda almacenado en `/var/kolibri/content/`.

---

## Gestión de usuarios

Kolibri tiene su propio sistema de usuarios y clases:
- **Admin** — gestiona el servidor, importa canales, crea facilitadores
- **Facilitador** — gestiona una o más clases, ve el progreso de los estudiantes
- **Estudiante** — accede al contenido, completa ejercicios

El progreso de cada estudiante (lecciones completadas, puntajes) se guarda localmente en la RPi.

---

## Flujo de un estudiante usando Kolibri

```
[Estudiante en VLAN30]
    │ GET http://biblioteca.tel/kolibri/
    ▼
[nginx RPi :80]
    │ proxy_pass kolibri_backend :8090
    │ WebSocket upgrade si es necesario
    ▼
[Kolibri :8090]
    │ sirve la app web (Vue.js)
    │ entrega lecciones desde /var/kolibri/content/
    │ guarda progreso en SQLite local
    ▼
[Estudiante navega y completa ejercicios]
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status kolibri

# Ver logs de Kolibri
sudo journalctl -u kolibri -f

# Ver el directorio de contenido
sudo du -sh /var/kolibri/content/

# Gestión desde línea de comandos
sudo -u kolibri kolibri manage listchannels    # listar canales importados
sudo -u kolibri kolibri manage importchannel   # importar canal

# Reiniciar si hay problemas
sudo systemctl restart kolibri
```

---

## Deploy

El rol solo habilita e inicia el servicio (Kolibri se instala por separado con su propio instalador):

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags kolibri
# o:
ansible-playbook services/kolibri.yml -i rpi-setup/inventory.ini
```
