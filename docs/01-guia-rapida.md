# Guía rápida

> Puesta en marcha del stack Matrix Docker en 10 minutos (si ya tienes Docker instalado).

---

## Prerrequisitos

Antes de empezar, verifica que tienes:

- [ ] Docker Engine 24+ con Compose v2 instalado
- [ ] OpenSSL en el PATH
- [ ] 4 GB de RAM disponibles
- [ ] 20 GB de espacio en disco
- [ ] Permisos de administrador en el host
- [ ] Acceso a la LAN donde se usará el servicio

Verifica Docker:

```bash
# Linux / macOS / Git Bash
docker --version
docker compose version
openssl version

# Windows PowerShell
docker --version
docker compose version
openssl version
```

Si alguno falla, instala Docker Desktop (Windows/Mac) o Docker Engine (Linux) antes de continuar.

---

## Paso 1: Descomprimir el proyecto

```bash
# Linux
cd /opt
unzip matrix-docker.zip
cd matrix-docker

# Windows PowerShell
cd C:\docker
Expand-Archive matrix-docker.zip .
cd matrix-docker
```

---

## Paso 2: Configurar variables de entorno

```bash
# Linux
cp .env.example .env
nano .env

# Windows
Copy-Item .env.example .env
notepad .env
```

**Variables que DEBES cambiar obligatoriamente**:

```env
POSTGRES_PASSWORD=<genera con: openssl rand -base64 32>
REDIS_PASSWORD=<genera con: openssl rand -hex 32>
SYNAPSE_REGISTRATION_SHARED_SECRET=<genera con: openssl rand -hex 32>
SYNAPSE_MACAROON_SECRET_KEY=<genera con: openssl rand -hex 32>
SYNAPSE_ADMIN_API_TOKEN=<genera con: openssl rand -hex 32>
SMTP_PASS=<tu_contraseña_smtp>
```

---

## Paso 3: Setup inicial

```bash
# Linux
bash scripts/linux/setup.sh

# Windows
.\scripts\windows\setup.ps1
```

Este script:
1. Verifica Docker y OpenSSL.
2. Genera la signing key de Synapse (`synapse/signing.key`).
3. Genera certificados SSL auto-firmados (`nginx/certs/`).
4. Construye la imagen personalizada de Element.
5. Valida `docker-compose.yml`.

Tarda 2-3 minutos la primera vez.

---

## Paso 4: Iniciar el stack

```bash
# Linux
bash scripts/linux/start.sh

# Windows
.\scripts\windows\start.ps1
```

Esto:
1. Descarga todas las imágenes (~1 GB) la primera vez.
2. Crea redes y volúmenes Docker.
3. Levanta los 5 servicios.
4. Espera a que todos los healthchecks pasen.

Primer arranque: 5-10 minutos. Arranques subsiguientes: 1-2 minutos.

---

## Paso 5: Crear usuario administrador

```bash
# Linux
bash scripts/linux/create-admin.sh admin

# Windows
.\scripts\windows\create-admin.ps1 admin
```

Te pedirá la contraseña interactivamente (no se ve mientras escribes).

---

## Paso 6: Configurar DNS local

En cada cliente que va a usar Element, agrega al archivo hosts:

- **Linux/Mac**: `/etc/hosts`
- **Windows**: `C:\Windows\System32\drivers\etc\hosts` (ejecuta Notepad como administrador)

```
192.168.1.100  matrix.home.arpa  element.home.arpa
```

Reemplaza `192.168.1.100` con la IP del host Docker.

Alternativa: configurar DNS local en el router (dnsmasq, bind9).

---

## Paso 7: Importar CA en clientes

Para evitar el warning de certificado no confiable:

1. Copia `nginx/certs/ca.crt` al cliente.
2. **Windows**: doble clic → "Instalar certificado" → "Equipo local" → "Entidades de certificación raíz de confianza".
3. **Linux**: 
   ```bash
   sudo cp ca.crt /usr/local/share/ca-certificates/matrix-ca.crt
   sudo update-ca-certificates
   ```
4. **macOS**: abrir Llavero → Arrastrar ca.crt → Marcar como "Confiar siempre".

Para navegadores basados en Chromium/Firefox, normalmente basta con importar en el sistema operativo.

---

## Paso 8: Acceder a Element

Abre en el navegador:

```
https://element.home.arpa
```

1. Click en "Iniciar sesión".
2. Servidor: `https://matrix.home.arpa` (debería venir preconfigurado).
3. Usuario: `@admin:home.arpa` (el que creaste en el paso 5).
4. Contraseña: la que definiste.

¡Listo! Ya puedes crear salas, invitar usuarios, etc.

---

## Verificación final

```bash
# Estado del stack
bash scripts/linux/status.sh

# Debes ver algo como:
# NAME              STATUS                    PORTS
# matrix-postgres   Up (healthy)              5432/tcp
# matrix-redis      Up (healthy)              6379/tcp
# matrix-synapse    Up (healthy)              8008/tcp
# matrix-element    Up (healthy)              80/tcp
# matrix-nginx      Up (healthy)              0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

Si todos los servicios están `healthy`, el stack está 100% operativo.

---

## Próximos pasos

- **Crear usuarios**: `bash scripts/linux/create-user.sh juan.perez`
- **Configurar backups automáticos**: ver [`09-backups.md`](09-backups.md)
- **Hardening**: ver [`05-seguridad.md`](05-seguridad.md)
- **Configurar SMTP**: ver [`03-configuracion.md`](03-configuracion.md)
- **Migrar a Ubuntu**: ver [`08-migracion-windows-ubuntu.md`](08-migracion-windows-ubuntu.md)

---

## Comandos esenciales para recordar

| Acción | Comando Linux | Comando Windows |
|--------|---------------|-----------------|
| Iniciar | `bash scripts/linux/start.sh` | `.\scripts\windows\start.ps1` |
| Detener | `bash scripts/linux/stop.sh` | `.\scripts\windows\stop.ps1` |
| Reiniciar | `bash scripts/linux/restart.sh` | `.\scripts\windows\restart.ps1` |
| Estado | `bash scripts/linux/status.sh` | `.\scripts\windows\status.ps1` |
| Logs | `bash scripts/linux/logs.sh <svc> -f` | `.\scripts\windows\logs.ps1 <svc> -f` |
| Backup | `bash scripts/linux/backup-db.sh` | `.\scripts\windows\backup-db.ps1` |
| Crear user | `bash scripts/linux/create-user.sh <name>` | `.\scripts\windows\create-user.ps1 <name>` |
