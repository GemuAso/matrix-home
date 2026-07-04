# Migración Windows → Ubuntu

> Procedimiento completo para migrar el stack desde Docker Desktop (Windows) hacia Ubuntu Server.

---

## 1. Panorama general

La migración implica mover:
1. **Archivos del proyecto** (config, scripts, docs).
2. **Volúmenes Docker** (datos de Synapse, PostgreSQL, Redis).
3. **Configuración del host** (DNS, firewall, systemd).
4. **Ajustes de dominios** si la IP del host cambia.

El procedimiento está diseñado para ser **sin modificaciones estructurales** del proyecto: el mismo `docker-compose.yml`, mismas configs, mismos scripts.

### Tiempo estimado

| Paso | Tiempo |
|------|--------|
| Preparación en Windows | 30 min |
| Exportar volúmenes | 5-30 min (según tamaño datos) |
| Transferir al servidor | 10-60 min (según red) |
| Preparar Ubuntu | 30 min |
| Importar volúmenes | 5-30 min |
| Verificación | 30 min |
| **Total** | **2-3 horas** |

### Downtime

El stack estará caído desde el momento del `stop.ps1` en Windows hasta el `start.sh` exitoso en Ubuntu. Asegúrate de planificar la ventana.

---

## 2. Preparación en Windows

### 2.1 Verificar estado del stack

```powershell
# El stack debe estar corriendo y healthy
.\scripts\windows\status.ps1
```

### 2.2 Backup de seguridad

```powershell
# Backup completo antes de migrar
.\scripts\windows\backup-db.ps1 pre_migration
```

Verifica que se generaron los archivos:
- `backups/db_pre_migration_*.sql.gz`
- `backups/config_pre_migration_*.tar.gz`

### 2.3 Verificar signing key

```powershell
# Asegúrate de que la signing key existe y está respaldada
Get-Content synapse\signing.key
```

> **CRÍTICO**: Si pierdes la signing key, el servidor no podrá firmar eventos y los clientes no confiarán en él. Esta key DEBE migrar al nuevo host.

### 2.4 Verificar certificados

```powershell
# Verificar que los certs existen
Get-ChildItem nginx\certs\*.crt, nginx\certs\*.key
```

### 2.5 Detener el stack

```powershell
.\scripts\windows\stop.ps1
```

### 2.6 Exportar volúmenes

```powershell
.\scripts\windows\export-volumes.ps1
# Output: matrix-migration.tar.gz en la raíz del proyecto
```

Este script:
1. Detiene el stack (si no estaba detenido).
2. Copia los archivos del proyecto a un directorio temporal.
3. Exporta cada volumen Docker a un tar.
4. Crea `matrix-migration.tar.gz` con todo.

Verifica el tamaño del archivo:

```powershell
Get-Item matrix-migration.tar.gz | Select-Object Name, @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB, 2)}}
```

### 2.7 Exportar .env y configs críticas (respaldo adicional)

```powershell
# Copiar .env a un lugar seguro
Copy-Item .env C:\temp\matrix-env-backup.env

# Crear tar con configs críticas
tar -czf C:\temp\matrix-configs.tar.gz `
    docker-compose.yml .env `
    synapse\homeserver.yaml synapse\log.config synapse\signing.key `
    postgres\postgresql.conf postgres\pg_hba.conf postgres\init.sql `
    redis\redis.conf `
    element\config.json element\nginx.conf element\Dockerfile `
    nginx\nginx.conf nginx\conf.d nginx\snippets nginx\well-known `
    nginx\certs
```

---

## 3. Preparar servidor Ubuntu

### 3.1 Instalar Ubuntu Server

Instalar Ubuntu Server 22.04 LTS o 24.04 LTS en el servidor destino. Documentación oficial: https://ubuntu.com/server/docs

### 3.2 Configurar red

Asegurar IP estática (recomendado):

```bash
# Ubuntu 22.04+ usa netplan
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

```bash
sudo netplan apply
```

### 3.3 Actualizar sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git nano ufw fail2ban unattended-upgrades
```

### 3.4 Crear usuario deploy

```bash
sudo useradd -m -s /bin/bash deploy
sudo passwd deploy
sudo usermod -aG sudo deploy  # Temporal para instalación, quitar después
```

### 3.5 Instalar Docker

```bash
# Como root o sudo
sudo bash -c 'curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh'

# O usando el script del proyecto (necesitas copiarlo primero)
sudo bash deployment/install-docker-ubuntu.sh
```

### 3.6 Configurar firewall

```bash
sudo bash deployment/setup-firewall.sh 192.168.1.0/24
# Reemplaza con tu CIDR LAN
```

### 3.7 Configurar SSH

```bash
sudo nano /etc/ssh/sshd_config
```

Cambiar:
```conf
PermitRootLogin no
PasswordAuthentication yes  # Cambiar a no después de configurar keys
```

```bash
sudo systemctl restart sshd
```

### 3.8 Crear directorio del proyecto

```bash
sudo mkdir -p /opt/matrix-docker
sudo chown deploy:deploy /opt/matrix-docker
```

---

## 4. Transferir archivos al servidor

### 4.1 Opción A: SCP

Desde Windows (PowerShell o Git Bash):

```bash
scp matrix-migration.tar.gz deploy@<ip-servidor>:/tmp/
```

### 4.2 Opción B: rsync (Linux a Linux)

Si tienes WSL en Windows o usas Linux como intermediario:

```bash
rsync -avz --progress matrix-migration.tar.gz deploy@<ip-servidor>:/tmp/
```

### 4.3 Opción C: USB

Si la red es muy lenta o no hay conectividad directa:
1. Copiar `matrix-migration.tar.gz` a USB.
2. Montar USB en el servidor.
3. Copiar a `/tmp/`.

### 4.4 Verificar integridad

```bash
# En el servidor
cd /tmp
sha256sum matrix-migration.tar.gz
# Comparar con el sha256 del archivo original (en Windows: Get-FileHash)
```

---

## 5. Importar en Ubuntu

### 5.1 Como usuario deploy

```bash
sudo su - deploy
cd /opt/matrix-docker
```

### 5.2 Ejecutar script de migración

```bash
# El script requiere sudo para algunas operaciones
sudo bash /tmp/migrate-from-windows.sh /tmp/matrix-migration.tar.gz /opt/matrix-docker
```

Este script:
1. Extrae el tarball.
2. Copia archivos del proyecto a `/opt/matrix-docker`.
3. Crea volúmenes Docker si no existen.
4. Restaura contenido de cada volumen.
5. Ajusta permisos.

### 5.3 Verificar archivos

```bash
ls -la /opt/matrix-docker/
ls -la /opt/matrix-docker/synapse/
ls -la /opt/matrix-docker/nginx/certs/

# Verificar signing key
cat /opt/matrix-docker/synapse/signing.key
```

### 5.4 Verificar volúmenes

```bash
docker volume ls | grep matrix_
# Debe mostrar:
# matrix_synapse_data
# matrix_postgres_data
# matrix_redis_data

# Verificar contenido
docker run --rm -v matrix_synapse_data:/data alpine ls -la /data
docker run --rm -v matrix_postgres_data:/data alpine ls -la /data
```

---

## 6. Ajustes post-migración

### 6.1 Actualizar .env

```bash
cd /opt/matrix-docker
nano .env
```

Cambiar al menos:
- `HOST_IP`: nueva IP del servidor Ubuntu
- `LAN_CIDR`: si cambió la red
- `SMTP_PASS`: si usas otro SMTP
- Secretos: rotar si es política (opcional)

### 6.2 Si cambiaron los dominios

Editar:
- `synapse/homeserver.yaml`: `server_name`, `public_baseurl`
- `element/config.json`: `m.homeserver.base_url`
- `nginx/conf.d/matrix.home.arpa.conf`: `server_name`, `ssl_certificate`
- `nginx/conf.d/element.home.arpa.conf`: `server_name`, `ssl_certificate`
- `nginx/well-known/matrix/client.json`: `base_url`
- `nginx/well-known/matrix/server.json`: `m.server`

### 6.3 Regenerar certs (solo si cambiaron dominios)

```bash
rm -f nginx/certs/*.crt nginx/certs/*.key nginx/certs/*.srl
bash scripts/linux/generate-certs.sh
```

### 6.4 Reconstruir imagen de Element

```bash
docker compose build element
```

### 6.5 Validar docker-compose

```bash
docker compose config --quiet
```

---

## 7. Configurar DNS

En el servidor DNS de la LAN (router, dnsmasq, bind9):

```
matrix.home.arpa.    IN A 192.168.1.100
element.home.arpa.   IN A 192.168.1.100
```

Si no hay DNS, configurar `/etc/hosts` (o usar **Tailscale** MagicDNS para acceso remoto) (Linux) o `C:\Windows\System32\drivers\etc\hosts` (Windows) en cada cliente:

```
192.168.1.100  matrix.home.arpa  element.home.arpa
```

---

## 8. Iniciar el stack en Ubuntu

### 8.1 Primer arranque

```bash
cd /opt/matrix-docker
bash scripts/linux/start.sh
```

El primer arranque:
- Recrea redes Docker (si no existen).
- Levanta los 5 servicios.
- Espera healthchecks.

### 8.2 Verificar

```bash
bash scripts/linux/status.sh

# Test desde el propio servidor
curl -k https://matrix.home.arpa/health
curl -k https://element.home.arpa/
```

### 8.3 Test desde un cliente

Desde un PC en la LAN:
1. Verificar que resuelve DNS: `nslookup matrix.home.arpa`
2. Acceder a `https://element.home.arpa`
3. Login con un usuario existente (los usuarios migraron desde la BD)
4. Verificar mensajes antiguos visibles
5. Enviar un mensaje de prueba

---

## 9. Configurar systemd para auto-arranque

```bash
sudo cp /opt/matrix-docker/deployment/matrix-docker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable matrix-docker

# Test
sudo systemctl start matrix-docker
sudo systemctl status matrix-docker

# Ver logs del servicio
sudo journalctl -u matrix-docker -f
```

Verificar que el servicio arranque automáticamente tras reinicio:

```bash
sudo reboot
# Después del reboot:
sudo systemctl status matrix-docker
```

---

## 10. Configurar backups automáticos

```bash
sudo cp /opt/matrix-docker/deployment/matrix-backup.cron /etc/cron.d/matrix-backup
sudo chmod 644 /etc/cron.d/matrix-backup
sudo chown root:root /etc/cron.d/matrix-backup
sudo systemctl reload cron
```

Verificar:

```bash
# Ver crontab activo
cat /etc/cron.d/matrix-backup

# Esperar al día siguiente y verificar
ls -la /opt/matrix-docker/backups/
cat /opt/matrix-docker/backups/cron.log
```

---

## 11. Hardening post-migración

Ver [`05-seguridad.md`](05-seguridad.md) sección 4 para el checklist completo. Resumen:

- [ ] SSH deshabilita root y password auth (configurar keys)
- [ ] Fail2ban activo
- [ ] Actualizaciones automáticas de seguridad
- [ ] UFW firewall con reglas LAN-only
- [ ] Auditd instalado
- [ ] Logrotate configurado
- [ ] Monitoreo de espacio en disco

---

## 12. Desactivar el stack en Windows

Una vez verificado que Ubuntu funciona correctamente:

1. **Esperar 1-2 semanas** de operación estable en Ubuntu.
2. **Detener el stack en Windows**:
   ```powershell
   .\scripts\windows\stop.ps1
   docker compose down
   ```
3. **Backup final de Windows** (por si acaso):
   ```powershell
   .\scripts\windows\backup-db.ps1 windows_final
   ```
4. **Desinstalar Docker Desktop** (opcional, libera recursos).
5. **Reutilizar el hardware** de Windows para otros fines.

---

## 13. Troubleshooting de migración

### 13.1 Los volúmenes no se restauran

```bash
# Verificar que los volúmenes existen
docker volume ls | grep matrix_

# Verificar contenido
docker run --rm -v matrix_postgres_data:/data alpine ls -la /data

# Si están vacíos, re-importar manualmente:
docker run --rm \
    -v matrix_postgres_data:/data \
    -v /tmp/volumes:/backup:ro \
    alpine sh -c "cd /data && tar -xf /backup/matrix_postgres_data.tar"
```

### 13.2 PostgreSQL no arranca tras migración

```bash
# Ver logs
docker compose logs postgres

# Si hay errores de permisos
docker run --rm -v matrix_postgres_data:/data alpine chown -R 70:70 /data

# Si la BD está corrupta (raro), restaurar del backup
docker volume rm matrix_postgres_data
docker volume create matrix_postgres_data
docker compose up -d postgres
sleep 30
bash scripts/linux/restore-db.sh backups/db_pre_migration_*.sql.gz
```

### 13.3 Synapse no responde

```bash
# Ver logs
docker compose logs synapse

# Errores comunes:
# - signing key no encontrada: verificar synapse/signing.key existe
# - BD no conecta: verificar postgres está healthy
# - Redis no conecta: verificar redis está healthy y password correcta
```

### 13.4 Nginx no termina TLS

```bash
# Verificar que los certs existen
docker compose exec nginx ls -la /etc/nginx/certs/

# Verificar config
docker compose exec nginx nginx -t

# Si los certs no están, copiarlos manualmente
cp -r nginx/certs /opt/matrix-docker/nginx/
```

### 13.5 Los clientes no conectan

```bash
# 1. Verificar DNS desde cliente
nslookup matrix.home.arpa
# Debe resolver a la IP del nuevo servidor

# 2. Verificar firewall en Ubuntu
sudo ufw status

# 3. Verificar que el servidor escucha en 443
sudo ss -tlnp | grep :443

# 4. Importar CA en cliente si es nuevo
# nginx/certs/ca.crt
```

---

## 14. Rollback de migración

Si la migración falla y necesitas volver a Windows:

```powershell
# 1. En Windows, restaurar el stack desde el backup final
.\scripts\windows\start.ps1

# 2. Si perdiste datos entre el último backup y la migración,
#    exportar la BD migrada desde Ubuntu y restaurar en Windows:
# En Ubuntu:
# bash scripts/linux/backup-db.sh post_failed_migration

# En Windows:
# .\scripts\windows\restore-db.ps1 backups\db_post_failed_migration_*.sql.gz
```

---

## 15. Checklist completo de migración

### Pre-migración
- [ ] Backup completo del stack en Windows
- [ ] Verificar signing key respaldada
- [ ] Verificar certs respaldados
- [ ] Anunciar ventana de mantenimiento a usuarios
- [ ] Servidor Ubuntu preparado (IP estática, Docker instalado)
- [ ] Firewall Ubuntu configurado
- [ ] Usuario deploy creado

### Migración
- [ ] Stack detenido en Windows
- [ ] Volúmenes exportados en Windows
- [ ] Tarball transferido a Ubuntu (con verificación SHA256)
- [ ] Volúmenes importados en Ubuntu
- [ ] .env actualizado con nueva IP/host
- [ ] Dominios actualizados si cambiaron
- [ ] Certs regenerados si cambiaron dominios
- [ ] Imagen Element reconstruida
- [ ] docker-compose validado

### Post-migración
- [ ] Stack arrancado en Ubuntu
- [ ] Healthchecks pasando
- [ ] Test desde navegador en LAN
- [ ] Login con usuario existente
- [ ] Mensajes antiguos visibles
- [ ] Mensaje nuevo enviado/recibido
- [ ] Backup automático configurado (cron)
- [ ] Servicio systemd habilitado
- [ ] Test de reboot (stack auto-arranca)
- [ ] Hardening aplicado
- [ ] Stack detenido en Windows (después de 1-2 semanas estable)

---

## 16. Migración inversa (Ubuntu → Windows)

El procedimiento es análogo usando:

```bash
# En Ubuntu
bash scripts/linux/export-volumes.sh
# Genera matrix-migration.tar.gz

# Transferir a Windows

# En Windows
# No hay script directo, pero se puede hacer manualmente:
# 1. docker volume create matrix_synapse_data
# 2. docker run --rm -v matrix_synapse_data:/data -v ./:/backup alpine tar -xf /backup/matrix_synapse_data.tar -C /data
# 3. Repetir para postgres y redis
# 4. .\scripts\windows\start.ps1
```

La migración Ubuntu → Windows es menos común pero posible.
