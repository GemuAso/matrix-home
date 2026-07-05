# Manual del administrador

> Guía práctica para administración diaria del stack Matrix Docker v4.0.0.
>
> **v4.0.0**: La instalación se realiza con un único comando: `./install.sh`. Todos los secretos se generan automáticamente con `openssl rand`. La IP se detecta automáticamente. Si necesitas reinstalar, ejecuta `./install.sh` de nuevo (preguntará antes de sobrescribir el `.env`). Para verificar el estado de los servicios en cualquier momento: `bash scripts/linux/verify.sh`.

---

## Tabla de contenidos

1. [Rol del administrador](#1-rol-del-administrador)
2. [Tareas diarias](#2-tareas-diarias)
3. [Tareas semanales](#3-tareas-semanales)
4. [Tareas mensuales](#4-tareas-mensuales)
5. [Creación y gestión de usuarios](#5-creación-y-gestión-de-usuarios)
6. [Gestión de contraseñas](#6-gestión-de-contraseñas)
7. [Backups y restauración](#7-backups-y-restauración)
8. [Actualizaciones](#8-actualizaciones)
9. [Logs y diagnóstico](#9-logs-y-diagnóstico)
10. [Mantenimiento de almacenamiento](#10-mantenimiento-de-almacenamiento)
11. [Hardening post-instalación](#11-hardening-post-instalación)
12. [Solución de problemas comunes](#12-solución-de-problemas-comunes)
13. [Procedimientos de emergencia](#13-procedimientos-de-emergencia)
14. [Checklist de mantenimiento](#14-checklist-de-mantenimiento)

---

## 1. Rol del administrador

Como administrador del stack Matrix Docker, eres responsable de:

- **Disponibilidad**: que el servicio esté accesible durante el horario acordado.
- **Integridad de datos**: que los mensajes y archivos no se pierdan.
- **Seguridad**: que los accesos no autorizados sean imposibles.
- **Performance**: que la experiencia de usuario sea fluida.
- **Cumplimiento**: que se cumplan las políticas de retención y auditoría.

No necesitas ser experto en Matrix, Docker, PostgreSQL o Nginx individualmente, pero debes entender cómo interactúan y qué hacer cuando algo falla. Este manual te guía paso a paso por cada operación.

---

## 2. Tareas diarias

### 2.1 Verificación matutina (5 minutos)

```bash
# Linux
bash scripts/linux/status.sh

# Windows
.\scripts\windows\status.ps1
```

Verifica:
- Todos los servicios en estado `healthy`.
- Sin contenedores reiniciando (`Restarting (N)`).
- Espacio en disco suficiente (>20% libre).
- Sin errores recientes en logs.

### 2.2 Revisión de logs (5-10 minutos)

```bash
# Ver últimos logs de cada servicio
bash scripts/linux/logs.sh

# Ver errores de Synapse en la última hora
bash scripts/linux/logs.sh synapse --since 1h | grep -i error

# Ver accesos fallidos en Nginx
bash scripts/linux/logs.sh nginx --since 24h | grep " 40[13] \| 50[0-9] "
```

En Windows, equivalente con `.ps1`.

### 2.3 Verificación de backups (1 minuto)

Si tienes cron configurado, verifica que el backup se ejecutó:

```bash
ls -lah backups/ | tail -10
cat backups/cron.log | tail -20
```

---

## 3. Tareas semanales

### 3.1 Backup manual de verificación

```bash
# Linux
bash scripts/linux/backup-db.sh verificacion_semanal

# Windows
.\scripts\windows\backup-db.ps1 verificacion_semanal
```

Verifica que el archivo se generó con tamaño razonable (>1 KB) y que la rotación está funcionando.

### 3.2 Limpieza de imágenes antiguas

```bash
bash scripts/linux/clean-images.sh
```

### 3.3 Revisión de espacio en disco

```bash
df -h
docker system df
```

Si el volumen de Synapse crece excesivamente, considera:
- Revisar `media_store_path` en `homeserver.yaml`.
- Configurar `max_media_upload_size` más restrictivo.
- Ejecutar purga de media antigua (ver documentación Synapse).

### 3.4 Rotación de signing key (cada 6-12 meses)

Por seguridad, rota la signing key del servidor:

1. Genera una nueva key:
   ```bash
   openssl rand -hex 32 | xxd -r -p | base64
   ```
2. Agrega la key vieja a `old_signing_keys` en `homeserver.yaml`.
3. Reemplaza el contenido de `synapse/signing.key`.
4. Reinicia Synapse: `bash scripts/linux/restart.sh synapse`.
5. Verifica que los clientes reconectan.

---

## 4. Tareas mensuales

### 4.1 Actualización de imágenes

```bash
bash scripts/linux/update-images.sh
bash scripts/linux/update-containers.sh
```

Antes de actualizar:
- Lee el [changelog de Synapse](https://github.com/element-hq/synapse/blob/master/CHANGES.md).
- Verifica compatibilidad con Element Web.
- Haz un backup completo.
- Programa ventana de mantenimiento.

### 4.2 Revisión de usuarios

```bash
# Listar usuarios
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, creation_ts, admin FROM users ORDER BY creation_ts;"
```

Verifica:
- Usuarios inactivos (sin login en 90 días).
- Usuarios con permisos admin innecesarios.
- Cuentas huérfanas (para desactivar).

### 4.3 Auditoría de seguridad

Revisa:
- Intentos de login fallidos en logs de Synapse.
- Conexiones rechazadas en PostgreSQL (`pg_hba.conf`).
- Certificados próximos a expirar (1 año de validez).

```bash
# Ver expiración de certs
openssl x509 -enddate -noout -in nginx/certs/matrix.crt
```

### 4.4 Test de restauración

Restaura un backup en un entorno de prueba (NO en producción):

```bash
# En un host de test
bash scripts/linux/restore-db.sh backups/db_YYYYMMDD_HHMMSS.sql.gz
```

Verifica que:
- Las tablas se cargan sin errores.
- Los usuarios existen.
- Los mensajes están accesibles.

---

## 5. Creación y gestión de usuarios

### 5.1 Crear usuario administrador

```bash
# Linux
bash scripts/linux/create-admin.sh <username>

# Windows
.\scripts\windows\create-admin.ps1 <username>
```

El script pide la contraseña interactivamente. El usuario creado tiene permisos de administración sobre el servidor.

### 5.2 Crear usuario normal

```bash
# Linux
bash scripts/linux/create-user.sh <username>

# Windows
.\scripts\windows\create-user.ps1 <username>
```

### 5.3 Listar usuarios existentes

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, to_timestamp(creation_ts) AS created, admin FROM users ORDER BY creation_ts DESC;"
```

### 5.4 Promover usuario a admin

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET admin = 1 WHERE name = '@usuario:home.arpa';"
```

### 5.5 Desactivar usuario

```bash
# Vía API admin
docker compose exec synapse \
    curl -X POST http://localhost:8008/_synapse/admin/v1/deactivate/@usuario:home.arpa \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 5.6 Restablecer contraseña de usuario

```bash
# Generar nueva contraseña aleatoria
NEW_PASS=$(openssl rand -base64 18)
echo "Nueva contraseña: $NEW_PASS"

# Hash con bcrypt (requiere Python passlib)
HASH=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.hash('$NEW_PASS', rounds=12))")

# Actualizar en BD
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET password_hash='$HASH' WHERE name='@usuario:home.arpa';"
```

---

## 6. Gestión de contraseñas

### 6.1 Política de contraseñas

La configuración en `homeserver.yaml` define:

```yaml
password_config:
  policy:
    enabled: true
    minimum_length: 10
    require_digit: true
    require_symbol: true
    require_lowercase: true
    require_uppercase: true
```

Para modificar la política, edita `synapse/homeserver.yaml` y reinicia Synapse.

### 6.2 Cambiar tu propia contraseña (como admin)

1. Inicia sesión en Element.
2. Ve a Ajustes → Cuenta → Cambiar contraseña.

### 6.3 Forzar cambio de contraseña a todos los usuarios

En caso de compromiso:

```bash
# 1. Generar nuevas contraseñas aleatorias por usuario
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name FROM users;" > usuarios.txt

# 2. Para cada usuario, generar y aplicar nueva contraseña (ver 5.6)
# 3. Enviar contraseñas por canal fuera de banda (telefono, email externo)
# 4. Invalidar todas las sesiones activas:
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "DELETE FROM access_tokens;"
```

---

## 7. Backups y restauración

### 7.1 Backup manual

```bash
# Linux
bash scripts/linux/backup-db.sh
# Output: backups/db_YYYYMMDD_HHMMSS.sql.gz + config_*.tar.gz

# Windows
.\scripts\windows\backup-db.ps1
```

### 7.2 Backup automático (Ubuntu)

```bash
sudo cp deployment/matrix-backup.cron /etc/cron.d/matrix-backup
sudo chmod 644 /etc/cron.d/matrix-backup
sudo chown root:root /etc/cron.d/matrix-backup
sudo systemctl reload cron
```

Verifica ejecución:

```bash
sudo tail -f /var/log/syslog | grep CRON
cat backups/cron.log
```

### 7.3 Restauración

```bash
# Linux
bash scripts/linux/restore-db.sh backups/db_YYYYMMDD_HHMMSS.sql.gz

# Windows
.\scripts\windows\restore-db.ps1 backups\db_YYYYMMDD_HHMMSS.sql.gz
```

El script:
1. Hace un backup preventivo (por si acaso).
2. Pide confirmación escrita.
3. Restaura con `pg_restore --clean --if-exists`.
4. Reinicia Synapse para recargar datos.

Ver detalles en [`docs/10-restauracion.md`](docs/10-restauracion.md).

### 7.4 Estrategia de retención recomendada

| Tipo | Retención | Ubicación |
|------|-----------|-----------|
| Diarios | 7 días | Local (server) |
| Semanales | 4 semanas | Local + NAS |
| Mensuales | 12 meses | NAS + offsite |
| Anuales | 5 años | Offsite (cold storage) |

---

## 8. Actualizaciones

### 8.1 Actualización rutinaria (imágenes)

```bash
# 1. Backup antes de actualizar
bash scripts/linux/backup-db.sh pre_update

# 2. Descargar nuevas imágenes
bash scripts/linux/update-images.sh

# 3. Recrear contenedores
bash scripts/linux/update-containers.sh

# 4. Verificar
bash scripts/linux/status.sh
```

### 8.2 Actualización de versiones pinned

Cuando quieras cambiar Synapse o PostgreSQL a una versión mayor:

1. Lee el **changelog** y los **upgrade notes** de la versión.
2. Verifica compatibilidad con Element Web.
3. Programa ventana de mantenimiento (anuncia a usuarios).
4. Haz backup completo.
5. Edita `docker-compose.yml` y cambia el tag de la imagen.
6. Si hay cambios de esquema de BD, sigue el procedimiento de migración específico.
7. Aplica con `update-containers.sh`.
8. Verifica y monitorea logs por 24 horas.

### 8.3 Rollback

Si la actualización falla:

```bash
# 1. Restaurar versión anterior en docker-compose.yml
nano docker-compose.yml  # revertir tag

# 2. Restaurar BD del backup pre-update
bash scripts/linux/restore-db.sh backups/db_pre_update_*.sql.gz

# 3. Reiniciar
bash scripts/linux/restart.sh
```

---

## 9. Logs y diagnóstico

### 9.1 Ubicación de logs

| Servicio | Ubicación | Acceso |
|----------|-----------|--------|
| PostgreSQL | Docker logs | `docker compose logs postgres` |
| Redis | Docker logs | `docker compose logs redis` |
| Synapse | Docker logs + `/data/logs/homeserver.log` | `docker compose logs synapse` |
| Element | Docker logs | `docker compose logs element` |
| Nginx | Docker volume `matrix_nginx_logs` + `./nginx/logs` (si mount) | `docker compose logs nginx` |

### 9.2 Comandos útiles

```bash
# Ver logs en vivo de un servicio
docker compose logs -f synapse

# Últimas 200 líneas
docker compose logs --tail 200 synapse

# Desde una hora atrás
docker compose logs --since 1h synapse

# Rango de tiempo
docker compose logs --since 2026-07-04T10:00:00 --until 2026-07-04T12:00:00 synapse

# Filtrar errores
docker compose logs synapse 2>&1 | grep -i "error\|warning"

# Estadísticas de uso
docker compose stats
```

### 9.3 Logs estructurados

Para analizar logs con herramientas como `jq`:

```bash
docker compose logs --format json synapse | jq 'select(.level=="ERROR")'
```

Más detalles en [`docs/15-logs.md`](docs/15-logs.md).

---

## 10. Mantenimiento de almacenamiento

### 10.1 Verificar espacio

```bash
# Espacio del host
df -h

# Espacio usado por Docker
docker system df -v

# Tamaño de volúmenes
docker volume inspect matrix_synapse_data | grep Mountpoint
sudo du -sh /var/lib/docker/volumes/matrix_synapse_data/_data
```

### 10.2 Limpieza de Docker

```bash
# Limpiar contenedores parados
docker container prune -f

# Limpiar imágenes sin usar
docker image prune -a -f

# Limpiar redes sin usar
docker network prune -f

# Limpiar build cache
docker builder prune -a -f

# O todo a la vez (cuidado con lo que borra)
docker system prune -a -f --volumes  # NO usar en producción
```

### 10.3 Purga de media antigua

Synapse acumula media descargada. Para limpiar:

```bash
# API admin - purge media older than X
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/home.arpa/delete?before_ts=1640000000000" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 10.4 VACUUM PostgreSQL

Para recuperar espacio en la BD:

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "VACUUM FULL ANALYZE;"
```

> **Nota**: `VACUUM FULL` bloquea la tabla. Programa en ventana de mantenimiento.

---

## 11. Hardening post-instalación

### 11.1 Endurecimiento del host (Ubuntu)

```bash
# 1. SSH: deshabilitar login root y password
sudo sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 2. Fail2ban
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# 3. Actualizaciones automáticas de seguridad
sudo dpkg-reconfigure -plow unattended-upgrades

# 4. Firewall (ver deployment/setup-firewall.sh)
sudo bash deployment/setup-firewall.sh 192.168.1.0/24
```

### 11.2 Endurecimiento de Synapse

Edita `synapse/homeserver.yaml`:

```yaml
# Deshabilitar federation explícitamente
federation:
  enabled: false

# Limitar tamaño de uploads
max_upload_size: 50M

# Throttling agresivo para auth
rc_login:
  address:
    per_second: 0.1
    burst_count: 3

# Deshabilitar registration pública
enable_registration: false

# Deshabilitar URL preview (LAN sin Internet)
url_preview_enabled: false
```

### 11.3 Endurecimiento de Nginx

Ya incluido en `nginx/nginx.conf` y `nginx/snippets/security-headers.conf`. Verifica:

```bash
docker compose exec nginx nginx -T | grep -E "ssl_protocols|ssl_ciphers|server_tokens"
```

---

## 12. Solución de problemas comunes

### 12.1 El stack no arranca

```bash
# 1. Ver errores de compose
docker compose config
docker compose up

# 2. Ver logs de cada servicio
docker compose logs

# 3. Verificar que .env existe y tiene valores válidos
cat .env | grep -v "^#"

# 4. Verificar signing key
ls -la synapse/signing.key

# 5. Verificar certs
ls -la nginx/certs/
```

### 12.2 Element no conecta con Matrix

```bash
# 1. Verificar que Synapse responde
curl -k https://matrix.home.arpa/health

# 2. Verificar .well-known
curl -k https://matrix.home.arpa/.well-known/matrix/client

# 3. Verificar DNS local
nslookup matrix.home.arpa
nslookup element.home.arpa

# 4. Verificar que el cliente confía en la CA
# Importar nginx/certs/ca.crt en el navegador
```

### 12.3 PostgreSQL no arranca

```bash
# Logs
docker compose logs postgres

# Verificar permisos del volumen
docker compose exec postgres ls -la /var/lib/postgresql/data

# Si el volumen está corrupto
# (PELIGROSO - solo si tienes backup)
docker volume rm matrix_postgres_data
docker compose up -d postgres
bash scripts/linux/restore-db.sh backups/db_*.sql.gz
```

### 12.4 Redis OOM o lento

```bash
# Verificar uso de memoria
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO memory

# Ajustar maxmemory en redis/redis.conf
# Reiniciar: bash scripts/linux/restart.sh redis
```

Más problemas en [`docs/11-resolucion-problemas.md`](docs/11-resolucion-problemas.md).

---

## 13. Procedimientos de emergencia

### 13.1 Caída del servicio en horario productivo

1. **Verificar estado**: `bash scripts/linux/status.sh`
2. **Reiniciar servicios caídos**: `bash scripts/linux/restart.sh <servicio>`
3. **Si no funciona**: `bash scripts/linux/stop.sh && bash scripts/linux/start.sh`
4. **Si persiste**: revisar logs del servicio afectado.
5. **Comunicar a usuarios**: usar canal alternativo (email, teléfono).

### 13.2 Pérdida de datos (escenario desastre)

1. **Detener el stack**: `bash scripts/linux/stop.sh`
2. **Restaurar último backup**:
   ```bash
   bash scripts/linux/restore-db.sh backups/db_ULTIMO.sql.gz
   ```
3. **Si el volumen está corrupto**:
   ```bash
   docker compose down -v  # ⚠️ borra volúmenes
   docker volume create matrix_synapse_data
   docker volume create matrix_postgres_data
   docker volume create matrix_redis_data
   bash scripts/linux/restore-db.sh backups/db_ULTIMO.sql.gz
   ```
4. **Iniciar**: `bash scripts/linux/start.sh`
5. **Verificar integridad**: `bash scripts/linux/status.sh`
6. **Auditar qué se perdió** entre el último backup y el incidente.

### 13.3 Compromiso de credenciales

1. **Identificar alcance**: qué cuentas/secciones comprometidas.
2. **Desactivar cuentas afectadas** (ver 5.5).
3. **Forzar logout de todas las sesiones**:
   ```bash
   docker compose exec postgres psql -U synapse_user -d synapse \
       -c "DELETE FROM access_tokens;"
   ```
4. **Resetear contraseñas** (ver 5.6).
5. **Rotar secretos** en `.env` y `homeserver.yaml`:
   - `POSTGRES_PASSWORD`
   - `REDIS_PASSWORD`
   - `SYNAPSE_REGISTRATION_SHARED_SECRET`
   - `SYNAPSE_MACAROON_SECRET_KEY`
   - `password_config.pepper` (invalida todos los hashes de password)
6. **Reiniciar stack**: `bash scripts/linux/restart.sh`
7. **Auditar logs** buscando actividad maliciosa.
8. **Documentar incidente**.

### 13.4 Host caído (hardware failure)

1. **Tener backup reciente accesible** (offsite).
2. **Aprovisionar nuevo host** Ubuntu Server.
3. **Instalar Docker**: `bash deployment/install-docker-ubuntu.sh`.
4. **Restaurar proyecto + backups**.
5. **Importar volúmenes**: `bash deployment/migrate-from-windows.sh ...`.
6. **Restaurar BD**: `bash scripts/linux/restore-db.sh ...`.
7. **Actualizar DNS** para apuntar al nuevo host (o usar **Tailscale**).
8. **Verificar acceso**.

---

## 14. Checklist de mantenimiento

### Diario

- [ ] `bash scripts/linux/status.sh` - verificar servicios UP
- [ ] Verificar espacio en disco
- [ ] Revisar logs de errores (5 min)
- [ ] Confirmar backup nocturno

### Semanal

- [ ] Backup manual de verificación
- [ ] `bash scripts/linux/clean-images.sh`
- [ ] Revisar tamaño de volúmenes
- [ ] Auditar accesos fallidos

### Mensual

- [ ] Actualizar imágenes (`update-images.sh` + `update-containers.sh`)
- [ ] Test de restauración en entorno de pruebas
- [ ] Revisar lista de usuarios (inactivos, admins)
- [ ] Verificar expiración de certs
- [ ] `VACUUM ANALYZE` en PostgreSQL

### Trimestral

- [ ] Rotar signing key
- [ ] Auditoría de seguridad completa
- [ ] Revisar política de retención de backups
- [ ] Actualizar documentación con cambios
- [ ] Test de DR (disaster recovery) completo

### Anual

- [ ] Revisar roadmap y planes de mejora
- [ ] Renovar CA local (10 años de validez, pero planificar)
- [ ] Auditar cumplimiento normativo (si aplica)
- [ ] Capacitación refresh del equipo de administración
