# Instalación

> Procedimiento detallado de instalación en Windows y Ubuntu.

---

## 1. Requisitos previos

### 1.1 Hardware

Ver [`SPECIFICATIONS.md`](../SPECIFICATIONS.md) para detalles. Resumen:

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB |
| Disco | 20 GB SSD | 100 GB SSD NVMe |
| Red | 100 Mbps LAN | 1 Gbps LAN |

### 1.2 Software base

- **Sistema operativo**:
  - Windows 10/11 con WSL2 habilitado
  - Ubuntu 20.04/22.04/24.04 LTS
- **Docker Engine** 24+ con Compose plugin v2
- **OpenSSL** 1.1.1+ o 3.x
- **Bash** 4+ (Linux) o **PowerShell** 5+ (Windows)
- **tar** (incluido en Windows 10 1803+)

---

## 2. Instalación en Windows (Docker Desktop)

### 2.1 Instalar Docker Desktop

1. Descarga Docker Desktop desde https://www.docker.com/products/docker-desktop/
2. Ejecuta el instalador `Docker Desktop Installer.exe`.
3. Durante la instalación, marca "Use WSL 2 instead of Hyper-V".
4. Reinicia el equipo cuando se solicite.
5. Abre Docker Desktop y completa el tutorial inicial.

### 2.2 Verificar WSL2

```powershell
wsl --status
wsl --list --verbose
```

Debes ver `VERSION` 2 para la distribución por defecto.

Si no está en WSL2:

```powershell
wsl --set-default-version 2
```

### 2.3 Configurar recursos de Docker Desktop

1. Abre Docker Desktop → Settings (engranaje).
2. **Resources → Advanced**:
   - CPUs: 4+
   - Memory: 4 GB mínimo (recomendado 8 GB)
   - Swap: 1 GB
   - Disk image location: deja el default
3. **Resources → Network**: verifica que DNS es `8.8.8.8` o tu DNS local.
4. **Docker Engine**: edita el JSON para añadir:
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "100m",
       "max-file": "5"
     }
   }
   ```
5. Apply & Restart.

### 2.4 Instalar OpenSSL en Windows

OpenSSL viene incluido en Git for Windows y en algunas versiones de Windows 10/11.

```powershell
# Verificar
openssl version

# Si no está, instalar via chocolatey
choco install openssl -y
# O descargar desde https://slproweb.com/products/Win32OpenSSL.html
```

### 2.5 Clonar/descomprimir el proyecto

```powershell
cd C:\
Expand-Archive C:\ruta\a\matrix-docker.zip -DestinationPath C:\docker
cd C:\docker\matrix-docker
```

### 2.6 Continuar con el setup

Salta a la sección [4. Setup del proyecto](#4-setup-del-proyecto) más abajo.

---

## 3. Instalación en Ubuntu Server

### 3.1 Preparar el servidor

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar utilidades básicas
sudo apt install -y curl wget git nano ufw fail2ban unattended-upgrades openssl
```

### 3.2 Instalar Docker (método automático)

El proyecto incluye un script que instala todo:

```bash
sudo bash deployment/install-docker-ubuntu.sh
```

Este script:
1. Actualiza el sistema.
2. Agrega el repositorio oficial de Docker.
3. Instala `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
4. Configura el daemon Docker con log rotation y security defaults.
5. Crea el usuario `deploy` para operar el stack (no-root).

### 3.3 Instalar Docker (método manual)

Si prefieres hacerlo paso a paso:

```bash
# 1. Dependencias
sudo apt install -y ca-certificates curl gnupg lsb-release

# 2. Repo de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3. Instalar
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4. Habilitar servicio
sudo systemctl enable --now docker

# 5. Agregar tu usuario al grupo docker
sudo usermod -aG docker $USER
newgrp docker
```

### 3.4 Verificar instalación

```bash
docker --version
docker compose version
docker run --rm hello-world
```

### 3.5 Configurar firewall

```bash
sudo bash deployment/setup-firewall.sh 192.168.1.0/24
# Reemplaza con tu rango LAN
```

### 3.6 Crear directorio del proyecto

```bash
sudo mkdir -p /opt/matrix-docker
sudo chown deploy:deploy /opt/matrix-docker

# Como usuario deploy
sudo su - deploy
cd /opt/matrix-docker

# Copiar archivos del proyecto aquí (rsync, scp, git clone)
```

---

## 4. Setup del proyecto

### 4.1 Configurar .env

```bash
# Linux
cp .env.example .env
chmod 600 .env
nano .env

# Windows PowerShell
Copy-Item .env.example .env
notepad .env
```

Edita las variables obligatorias (ver [`03-configuracion.md`](03-configuracion.md) para detalle):

```env
POSTGRES_PASSWORD=<password fuerte 32+ chars>
REDIS_PASSWORD=<password fuerte 32+ chars>
SYNAPSE_REGISTRATION_SHARED_SECRET=<64 hex chars>
SYNAPSE_MACAROON_SECRET_KEY=<64 hex chars>
SYNAPSE_ADMIN_API_TOKEN=<64 hex chars>
```

Genera secretos con:

```bash
# Linux / Mac / Git Bash
openssl rand -hex 32        # hex 64 chars
openssl rand -base64 32     # base64 32+ chars

# Windows PowerShell
[Convert]::ToHexString((1..32 | ForEach-Object {Get-Random -Max 256}))
```

### 4.2 Si cambiaste los dominios

Si en lugar de `home.arpa` quieres usar tu dominio (ej. `midominio.local`), edita también:

1. `synapse/homeserver.yaml`:
   - `server_name`
   - `public_baseurl`
   - `email` (smtp_from, etc.)
2. `element/config.json`:
   - `m.homeserver.base_url`
   - `m.homeserver.server_name`
3. `nginx/conf.d/matrix.home.arpa.conf` → renombra y edita `server_name`
4. `nginx/conf.d/element.home.arpa.conf` → renombra y edita `server_name`
5. `nginx/well-known/matrix/client.json` → actualiza `base_url`
6. `nginx/well-known/matrix/server.json` → actualiza `m.server`

### 4.3 Ejecutar setup

```bash
# Linux
bash scripts/linux/setup.sh

# Windows
.\scripts\windows\setup.ps1
```

El script:
1. Verifica dependencias.
2. Genera signing key de Synapse.
3. Genera certificados SSL (CA + 2 dominios + default).
4. Valida `.env`.
5. Construye imagen personalizada de Element.
6. Valida `docker-compose.yml`.

### 4.4 Iniciar el stack

```bash
# Linux
bash scripts/linux/start.sh

# Windows
.\scripts\windows\start.ps1
```

### 4.5 Verificar

```bash
bash scripts/linux/status.sh
```

Todos los servicios deben estar `healthy`.

### 4.6 Crear usuario admin

```bash
# Linux
bash scripts/linux/create-admin.sh admin

# Windows
.\scripts\windows\create-admin.ps1 admin
```

### 4.7 Configurar DNS y certificados en clientes

Ver [`01-guia-rapida.md`](01-guia-rapida.md) pasos 6 y 7.

---

## 5. Instalación como servicio en Ubuntu (opcional, recomendado)

Para que el stack arranque automáticamente al reiniciar el servidor:

```bash
# Copiar unit file
sudo cp deployment/matrix-docker.service /etc/systemd/system/
sudo systemctl daemon-reload

# Habilitar
sudo systemctl enable matrix-docker

# Probar
sudo systemctl start matrix-docker
sudo systemctl status matrix-docker

# Ver logs del servicio
sudo journalctl -u matrix-docker -f
```

---

## 6. Configurar backups automáticos (Ubuntu)

```bash
# Copiar cron job
sudo cp deployment/matrix-backup.cron /etc/cron.d/matrix-backup
sudo chmod 644 /etc/cron.d/matrix-backup
sudo chown root:root /etc/cron.d/matrix-backup
sudo systemctl reload cron

# Verificar
sudo tail -f /var/log/syslog | grep CRON
```

Esto ejecutará un backup diario a las 02:00 AM.

---

## 7. Configurar logrotate (Ubuntu)

```bash
sudo cp deployment/logrotate-matrix.conf /etc/logrotate.d/matrix-docker

# Probar
sudo logrotate -d /etc/logrotate.d/matrix-docker
```

---

## 8. Post-instalación

### 8.1 Verificación funcional

```bash
# Test API Matrix
curl -k https://matrix.home.arpa/_matrix/static/

# Test health
curl -k https://matrix.home.arpa/health

# Test .well-known
curl -k https://matrix.home.arpa/.well-known/matrix/client
curl -k https://matrix.home.arpa/.well-known/matrix/server

# Test Element
curl -k https://element.home.arpa/
```

### 8.2 Acceder y crear primera sala

1. Abre `https://element.home.arpa` en el navegador.
2. Inicia sesión con `@admin:home.arpa`.
3. Crea una sala de prueba.
4. Verifica que aparece en la BD:
   ```bash
   docker compose exec postgres psql -U synapse_user -d synapse \
       -c "SELECT count(*) FROM rooms;"
   ```

### 8.3 Hardening

Ver [`05-seguridad.md`](05-seguridad.md) para el checklist completo de seguridad post-instalación.

---

## 9. Desinstalación

### 9.1 Eliminar stack (mantiene datos)

```bash
bash scripts/linux/stop.sh
docker compose down
```

### 9.2 Eliminar stack + volúmenes (PELIGROSO - pierde todo)

```bash
bash scripts/linux/stop.sh
docker compose down -v
```

### 9.3 Eliminar imágenes

```bash
docker rmi matrixdotorg/synapse:v1.118.0
docker rmi postgres:16.4-alpine3.20
docker rmi redis:7.4-alpine3.20
docker rmi nginx:1.27.2-alpine3.20
docker rmi vectorim/element-web:v1.11.65
docker rmi matrix-element:custom
```

### 9.4 Eliminar Docker (Ubuntu)

```bash
sudo systemctl stop docker
sudo apt remove --purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /etc/docker /var/lib/containerd
```
