# Credenciales SSH — Pacific Edge Network

> ⚠️ Documento sensible. No subir a repositorios públicos.

---

## Mini PC (Router)

| Campo | Valor |
|-------|-------|
| Host (Netbird) | `100.90.95.134` |
| Usuario | `user` |
| Contraseña | `password` |
| Sudo | Sin contraseña (`NOPASSWD`) |

```bash
ssh user@100.90.95.134
```

---

## Raspberry Pi 5

| Campo | Valor |
|-------|-------|
| Host (Netbird) | `100.90.81.168` |
| Host (LAN VLAN 20) | `192.168.20.10` |
| Usuario | `akasicom` |
| Contraseña | `4k4s1c0m` |
| Sudo | Con contraseña (usar `-S`) |

```bash
ssh akasicom@100.90.81.168
```

Para comandos con sudo desde scripts (sin TTY):
```bash
ssh akasicom@100.90.81.168 "echo '4k4s1c0m' | sudo -S <comando>"
```

---

## Switch Catalyst 2960 — Cerrito Bongo

> Solo accesible desde la LAN (VLAN 10). Debe hacerse SSH desde el Mini PC o la RPi, **no directamente desde internet**.

| Campo | Valor |
|-------|-------|
| IP (SVI VLAN 10) | `192.168.10.2` |
| Usuario | `user` |
| Contraseña | `password` |
| Privilegio | 15 (prompt `#`, ya en modo enable) |

El switch usa IOS antiguo con algoritmos SSH legacy. Requiere flags adicionales:

```bash
# Desde el Mini PC o la RPi:
ssh -o StrictHostKeyChecking=no \
    -o KexAlgorithms=diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 \
    -o HostKeyAlgorithms=ssh-rsa \
    -o Ciphers=aes128-cbc,3des-cbc,aes256-cbc \
    user@192.168.10.2
```

### Acceso desde el Mini PC (recomendado)

```bash
# 1. Conectar al Mini PC
ssh user@100.90.95.134

# 2. Desde el Mini PC, conectar al switch
ssh -o StrictHostKeyChecking=no \
    -o KexAlgorithms=diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 \
    -o HostKeyAlgorithms=ssh-rsa \
    -o Ciphers=aes128-cbc,3des-cbc,aes256-cbc \
    user@192.168.10.2
```

### Acceso desde la Raspberry Pi

```bash
# 1. Conectar a la RPi
ssh akasicom@100.90.81.168

# 2. Desde la RPi, conectar al switch
ssh -o StrictHostKeyChecking=no \
    -o KexAlgorithms=diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 \
    -o HostKeyAlgorithms=ssh-rsa \
    -o Ciphers=aes128-cbc,3des-cbc,aes256-cbc \
    user@192.168.10.2
```

### Acceso automatizado desde el Mini PC (con pexpect)

Para scripts que necesiten enviar comandos al switch:

```python
import pexpect

child = pexpect.spawn(
    'ssh -o StrictHostKeyChecking=no '
    '-o KexAlgorithms=diffie-hellman-group14-sha1,diffie-hellman-group1-sha1 '
    '-o HostKeyAlgorithms=ssh-rsa '
    '-o Ciphers=aes128-cbc,3des-cbc,aes256-cbc '
    'user@192.168.10.2',
    timeout=20
)
i = child.expect(['Password:', 'SW-CORE-BONGO'])
if i == 0:
    child.sendline('password')
    child.expect('SW-CORE-BONGO')
child.expect('#')
child.sendline('terminal length 0')
child.expect('#')
# Aquí van los comandos
child.sendline('show interfaces status')
child.expect('#')
print(child.before.decode())
child.sendline('exit')
```

---

## Resumen rápido

| Dispositivo | Acceso directo | Usuario | Contraseña |
|-------------|---------------|---------|------------|
| Mini PC | `ssh user@100.90.95.134` | `user` | `password` |
| Raspberry Pi | `ssh akasicom@100.90.81.168` | `akasicom` | `4k4s1c0m` |
| Switch | Solo desde Mini PC o RPi → `ssh user@192.168.10.2` + flags legacy | `user` | `password` |
