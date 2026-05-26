# Kiwix — Biblioteca Offline

**Dispositivo:** Raspberry Pi (`akasicom2`, 192.168.20.10)
**Rol Ansible:** `raspberry/rpi-setup/roles/kiwix/`
**Servicio systemd:** `kiwix-serve`
**Puerto interno:** `127.0.0.1:8080`
**Acceso de clientes:** `http://biblioteca.tel/wikipedia/`

---

## Qué hace

Kiwix sirve contenido enciclopédico y educativo offline desde archivos ZIM (formato comprimido de Wikipedia y otros proyectos wiki). Los clientes acceden a Wikipedia, Wikicionario u otros recursos sin conexión a internet, desde cualquier dispositivo en la red.

---

## Cómo funciona ZIM

Un archivo `.zim` es un paquete comprimido que contiene artículos, imágenes y recursos de un sitio web completo (ej: toda la Wikipedia en español). `kiwix-serve` lee el archivo ZIM y lo sirve como sitio web HTTP.

La biblioteca de archivos ZIM se declara en:
```
/var/lib/biblioteca/zim/library.xml
```

Este archivo XML lista los ZIM disponibles. `kiwix-serve` lo lee al iniciar y sirve todos los ZIM declarados.

---

## Exposición al exterior

Kiwix escucha **solo en loopback** (`127.0.0.1:8080`). Los clientes **nunca acceden directamente** a Kiwix — siempre pasan por nginx en `:80`.

nginx recibe el path `/wikipedia/` y lo reenvía a `kiwix_backend` con rewrite:

```nginx
location /wikipedia/ {
    rewrite ^/wikipedia/(.*)$ /$1 break;
    proxy_pass http://kiwix_backend;
}
```

Otros paths de Kiwix (`/content/`, `/catalog/`, `/skin/`, `/search`, etc.) también se proxean.

---

## Hardening del servicio

El systemd unit incluye restricciones de seguridad:

| Restricción | Efecto |
|---|---|
| `NoNewPrivileges=true` | No puede elevar privilegios |
| `ProtectSystem=strict` | Sistema de archivos solo lectura (excepto rutas explícitas) |
| `ProtectHome=true` | Sin acceso a `/home` |
| `PrivateTmp=true` | `/tmp` privado |
| `ReadOnlyPaths` | Solo lectura en el directorio ZIM |
| `MemoryMax=1G` | Límite de RAM a 1 GB |
| `CPUQuota=200%` | Máximo 2 cores de CPU |

Corre con usuario sin shell (`kiwix`, `nologin`).

---

## Condición de inicio

```
ConditionPathExists=/var/lib/biblioteca/zim/library.xml
```

El servicio **no inicia** si `library.xml` no existe. Esto evita errores confusos si los ZIM no han sido descargados aún.

---

## Agregar contenido ZIM

1. Descargar el archivo `.zim` desde https://download.kiwix.org/zim/
2. Copiarlo a `/var/lib/biblioteca/zim/` en la RPi
3. Agregar la entrada al `library.xml`:

```bash
sudo kiwix-manage /var/lib/biblioteca/zim/library.xml add /var/lib/biblioteca/zim/archivo.zim
sudo systemctl restart kiwix-serve
```

---

## Flujo de una búsqueda de Wikipedia

```
[Cliente en VLAN30]
    │ GET http://biblioteca.tel/wikipedia/Albert_Einstein
    ▼
[nginx RPi :80]
    │ rewrite /wikipedia/Albert_Einstein → /Albert_Einstein
    │ proxy_pass kiwix_backend
    ▼
[kiwix-serve :8080]
    │ busca "Albert_Einstein" en el ZIM de Wikipedia
    │ devuelve el artículo HTML comprimido
    ▼
[nginx → cliente]
```

---

## Comandos útiles

```bash
# Estado del servicio
sudo systemctl status kiwix-serve

# Ver qué ZIM están disponibles
cat /var/lib/biblioteca/zim/library.xml

# Ver el tamaño del directorio ZIM
sudo du -sh /var/lib/biblioteca/zim/

# Agregar un ZIM nuevo a la biblioteca
sudo kiwix-manage /var/lib/biblioteca/zim/library.xml add /ruta/al/nuevo.zim

# Logs del servicio
sudo journalctl -u kiwix-serve -f
sudo tail -f /var/log/biblioteca/kiwix.log
```

---

## Deploy

```bash
cd raspberry/
ansible-playbook rpi-setup/playbook.yml -i rpi-setup/inventory.ini --tags kiwix
# o:
ansible-playbook services/kiwix.yml -i rpi-setup/inventory.ini
```
