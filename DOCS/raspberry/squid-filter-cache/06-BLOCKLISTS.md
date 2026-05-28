# 06 — Blocklists: qué se bloquea, cómo añadir / quitar / personalizar

## ¿Qué está bloqueado HOY?

**Cantidad actual:** ~82 803 dominios.

**Categorías incluidas:**
- **Porn / adultos**: ~76 700 dominios (de `StevenBlack/hosts/alternates/porn-only/hosts`).
- **Gambling / apuestas**: ~6 100 dominios (de `StevenBlack/hosts/alternates/gambling-only/hosts`).

**Ejemplos de dominios bloqueados** (no exhaustivo):

```
pornhub.com, xvideos.com, xnxx.com, redtube.com, youporn.com, ...
bet365.com, 1xbet.com, betway.com, gambling.com, pokerstars.com, ...
```

**Cómo verificar si un dominio está bloqueado:**

```bash
ssh akasicom@100.90.81.168 'grep -E "^DOMINIO$" /etc/squid/blocklists/blocked_domains.txt'
# Ejemplo:
ssh akasicom@100.90.81.168 'grep -E "^bet365.com$" /etc/squid/blocklists/blocked_domains.txt'
# Si imprime "bet365.com" → está bloqueado.
# Si no imprime nada → no está en la lista.
```

## Dónde vive todo

```
group_vars/all.yml
  ├── squid_blocklist_sources: [...URLs de hosts files...]
  └── squid_blocklist_path: /etc/squid/blocklists/blocked_domains.txt

raspberry/rpi-setup/roles/squid/templates/update-squid-blocklist.sh.j2
  └── Script que descarga, combina y deduplica las URLs

raspberry/rpi-setup/roles/squid/templates/squid.conf.j2
  └── ACLs que usan el archivo:
      acl blocked_domains   dstdomain        "{{ squid_blocklist_path }}"
      acl blocked_sni       ssl::server_name "{{ squid_blocklist_path }}"

En la RPi (después de deploy):
  /usr/local/sbin/update-squid-blocklist    # Script ejecutable
  /etc/squid/blocklists/blocked_domains.txt # Archivo de dominios
  /var/log/squid-blocklist.log               # Log de actualizaciones
  /etc/crontab → cron job semanal           # Trigger
```

## Casos de uso

---

### A. Añadir una categoría nueva (e.g., social media)

**Pasos:**

1. **Encuentra una URL** con la lista en formato hosts (`0.0.0.0 dominio.com`). StevenBlack tiene varias:
   - `https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts`
   - `https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-only/hosts`

2. **Edita** `raspberry/rpi-setup/group_vars/all.yml`:

   ```yaml
   squid_blocklist_sources:
     - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
     - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
     - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/social-only/hosts"   # ← NUEVA
   ```

3. **Re-deploy** el rol squid:

   ```bash
   cd raspberry/
   ansible-playbook -i rpi-setup/inventory.ini services/squid.yml
   ```

4. **Forzar update inmediato** (el cron es semanal):

   ```bash
   ssh akasicom@100.90.81.168 'sudo /usr/local/sbin/update-squid-blocklist'
   ```

5. **Verificar**:

   ```bash
   ssh akasicom@100.90.81.168 'grep -c "^facebook.com$" /etc/squid/blocklists/blocked_domains.txt'
   # Debe imprimir 1
   ```

---

### B. Quitar una categoría

Inverso del caso A: elimina la URL del array `squid_blocklist_sources`, re-deploy, fuerza update.

---

### C. Añadir un dominio individual (custom)

**Caso típico**: una página específica que StevenBlack no cubre.

**Opción 1 (recomendada): añadir a una lista custom**

1. **Crear un archivo de custom blocks** en la RPi:

   ```bash
   ssh akasicom@100.90.81.168 '
   sudo tee /etc/squid/blocklists/custom_blocks.txt << EOF
   sitio-malo-1.com
   sitio-malo-2.org
   subdominio.peligroso.net
   EOF
   '
   ```

2. **Editar** `raspberry/rpi-setup/roles/squid/templates/squid.conf.j2` para añadir ACL:

   ```squid
   acl blocked_domains   dstdomain        "/etc/squid/blocklists/blocked_domains.txt"
   acl blocked_sni       ssl::server_name "/etc/squid/blocklists/blocked_domains.txt"
   # NUEVAS — custom blocks
   acl custom_blocked    dstdomain        "/etc/squid/blocklists/custom_blocks.txt"
   acl custom_blocked_sni ssl::server_name "/etc/squid/blocklists/custom_blocks.txt"
   ```

3. **Modificar reglas para que cubran ambas listas**:

   ```squid
   http_access deny blocked_domains
   http_access deny custom_blocked

   ssl_bump terminate blocked_sni
   ssl_bump terminate custom_blocked_sni
   ssl_bump splice all
   ```

4. **Re-deploy**:

   ```bash
   ansible-playbook -i rpi-setup/inventory.ini services/squid.yml
   ```

**Opción 2 (rápida, no persistente): añadir directo al archivo principal**

```bash
ssh akasicom@100.90.81.168 '
echo "sitio-malo.com" | sudo tee -a /etc/squid/blocklists/blocked_domains.txt
sudo /usr/sbin/squid -k reconfigure
'
```

⚠️ **Esto NO persiste**: el siguiente cron de actualización (domingos 03:30) reescribe el archivo con solo lo que viene de las URLs configuradas, perdiendo tus adiciones. Usa la Opción 1 si quieres persistencia.

---

### D. Whitelist: permitir un dominio que está bloqueado por error

**Caso**: un sitio legítimo está incluido en StevenBlack por error, o la categoría es demasiado amplia.

**Pasos:**

1. **Crear archivo de whitelist** en la RPi:

   ```bash
   ssh akasicom@100.90.81.168 '
   sudo tee /etc/squid/blocklists/whitelist.txt << EOF
   sitio-bueno.com
   educativo-erotico.com
   EOF
   '
   ```

2. **Editar** `squid.conf.j2`:

   ```squid
   acl blocked_domains   dstdomain        "/etc/squid/blocklists/blocked_domains.txt"
   acl blocked_sni       ssl::server_name "/etc/squid/blocklists/blocked_domains.txt"
   # NUEVA — whitelist (excepciones)
   acl whitelisted       dstdomain        "/etc/squid/blocklists/whitelist.txt"
   acl whitelisted_sni   ssl::server_name "/etc/squid/blocklists/whitelist.txt"
   ```

3. **Modificar reglas** para que `whitelisted` gane sobre `blocked`:

   ```squid
   # Whitelist GANA — debe estar ANTES del deny
   http_access allow whitelisted
   http_access deny blocked_domains

   # SNI — whitelist también primero
   ssl_bump splice whitelisted_sni
   ssl_bump terminate blocked_sni
   ssl_bump splice all
   ```

4. **Re-deploy**.

---

### E. Quitar TODO el bloqueo temporalmente

**Caso**: para debugging o evento especial.

```yaml
# group_vars/all.yml
squid_enable_https_filter: false
```

```bash
# Re-deploy
ansible-playbook -i rpi-setup/inventory.ini services/squid.yml
# Y también firewall (para quitar el DNAT)
ansible-playbook -i router-setup/inventory.ini router-setup/playbook.yml --tags firewall
```

Tras el re-deploy:
- nftables ya no DNATtea HTTPS a Squid:3130.
- Squid no escucha en :3130 (no se renderiza el bloque).
- HTTP filter (`http_access deny blocked_domains`) tampoco se renderiza.

Para reactivar: `squid_enable_https_filter: true` y re-deploy.

---

### F. Solo bloquear porn (no gambling)

```yaml
squid_blocklist_sources:
  - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
  # gambling comentado:
  # - "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
```

Re-deploy + `update-squid-blocklist`. La lista se rehace solo con porn.

---

### G. Cambiar la frecuencia del cron

Por defecto: domingos 03:30.

Edita `raspberry/rpi-setup/roles/squid/tasks/main.yml`, busca el bloque del cron:

```yaml
- name: Cron semanal — actualizar blocklist los domingos 03:30
  cron:
    name: "update-squid-blocklist"
    weekday: "0"      # 0 = domingo
    hour: "3"
    minute: "30"
```

Cambia a, e.g., diario a las 4:00 AM:

```yaml
    minute: "0"
    hour: "4"
    # quita weekday para que sea daily
```

Re-deploy.

---

## Anatomía del archivo blocked_domains.txt

Una entrada por línea, dominio plano:

```
0.oldgyhogola.com
007angels.com
1080pornhub.com
...
zzzzporn.com
```

**Match en Squid**:
- `acl blocked_domains dstdomain "archivo.txt"` → busca exact match del hostname del request.
- `acl blocked_sni ssl::server_name "archivo.txt"` → busca exact match del SNI.

**No usamos prefijo `.`** (subdomain match) en el archivo. Razón: las listas de StevenBlack ya incluyen subdominios explícitos cuando aplica. Si añadiéramos `.example.com` también matchearía `www.example.com`, `sub.example.com`, etc. — pero la lista vendría con esos subdominios ya enumerados.

**Si quieres cambiar a subdomain match**: edita el script `update-squid-blocklist.sh.j2` para que prefije `.` a cada dominio. Cuidado con falsos positivos (`.com` bloquearía todo).

## Anatomía del script `update-squid-blocklist`

```bash
SOURCES=(
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts"
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
)

# 1. Descargar TODO o nada (si falla 1, aborta sin tocar la lista vigente)
for url in "${SOURCES[@]}"; do
  curl -fsSL --max-time 60 -o "$TMP_DIR/srcN.txt" "$url" || abort
done

# 2. Combinar: extraer dominios (columna 2 de las líneas que empiezan en 0.0.0.0)
awk '/^0\.0\.0\.0/ {print $2}' "$TMP_DIR"/src*.txt \
  | grep -Ev '^(0\.0\.0\.0|localhost|broadcasthost|ip6-)' \
  | sort -u > combined.txt

# 3. Sanity-check
[ $(wc -l < combined.txt) -ge 1000 ] || abort

# 4. Comparar con la lista actual — si idéntica, no toques nada
cmp -s combined.txt /etc/squid/blocklists/blocked_domains.txt && exit 0

# 5. Instalar + reconfigure
install ... && squid -k reconfigure
```

## Auditoría de bloqueos

**Ver qué se está bloqueando AHORA mismo (en tiempo real)**:

```bash
ssh akasicom@100.90.81.168 '
sudo tail -f /var/log/squid/access.log | grep -E "TCP_DENIED|terminate"
'
```

**Conteo de bloqueos por dominio (último log)**:

```bash
ssh akasicom@100.90.81.168 '
sudo grep TCP_DENIED /var/log/squid/access.log \
  | awk "{print \$8}" \
  | sort | uniq -c | sort -rn | head -20
'
```

**¿Hay clientes con muchos bloqueos? (posible mal actor)**:

```bash
ssh akasicom@100.90.81.168 '
sudo grep TCP_DENIED /var/log/squid/access.log \
  | awk "{print \$4}" \
  | sort | uniq -c | sort -rn | head -10
'
```

## Limpieza periódica recomendada

Sin intervención, la lista crece (cada release de StevenBlack añade nuevos dominios). Esto:
- **NO degrada performance** (Squid maneja millones).
- **SÍ ocupa espacio** (cada entry ~30 bytes; 1M = 30 MB).

Si en 5 años la lista es absurdamente grande, considera filtrar al deduplicar — pero hoy 82k es trivial.

## Origen y licencias de las listas

### StevenBlack/hosts (MIT License)

- **Repo**: https://github.com/StevenBlack/hosts
- **Licencia**: MIT (libre uso comercial, atribución opcional).
- **Curado por**: Steven Black + comunidad GitHub. ~80 contribuidores activos.
- **Actualización**: semanal o más frecuente.
- **Auditoría**: cualquier dominio incluido tiene un commit GitHub asociado donde se puede ver quién y por qué.

**Pros**: open, auditable, gratis, activo.
**Contras**: cobertura comparable pero no idéntica a fuentes comerciales; no incluye categorías exóticas.

### Alternativas comerciales (no usadas hoy)

| Proveedor | Cobertura | Precio aprox. | Notas |
|---|---|---|---|
| Cisco Umbrella | millones, categorizada finamente | $$$$ | Estándar empresarial |
| NextDNS Block lists | varias categorías | gratis hasta cuota | API friendly |
| OISD (oisd.nl) | dominios maliciosos | gratis | DNS-based, no hosts format |

Si en el futuro la red comunitaria se vuelve grande y necesita mejor curación, vale la pena considerar OISD (gratis, formato compatible).
