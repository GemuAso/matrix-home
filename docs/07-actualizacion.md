# Actualización

> Procedimientos para mantener el stack actualizado de forma segura.

---

## 1. Filosofía de actualización

Las actualizaciones son críticas para seguridad y estabilidad, pero conllevan riesgo. Este documento describe el procedimiento para actualizar minimizando el riesgo de downtime o pérdida de datos.

### Principios

1. **Backup antes de actualizar**: SIEMPRE.
2. **Probar en entorno de staging primero**: si es posible.
3. **Ventana de mantenimiento**: anunciar a usuarios.
4. **Versiones pinned**: cambiar tags deliberadamente, no usar `latest`.
5. **Rollback plan**: saber cómo revertir si algo falla.
6. **Monitoreo post-actualización**: verificar logs 24h después.

---

## 2. Tipos de actualización

### 2.1 Actualización de patch (1.118.0 → 1.118.1)

Bajo riesgo. Generalmente bug fixes y security patches.

### 2.2 Actualización de minor (1.118 → 1.119)

Riesgo medio. Nuevas features, posible cambios en config.

### 2.3 Actualización de major (1.x → 2.x)

Riesgo alto. Cambios breaking posibles. Requiere leer upgrade notes.

### 2.4 Cambio de versión de PostgreSQL (14 → 16)

Riesgo alto. Requiere dump + restore de la BD.

---

## 3. Procedimiento estándar de actualización

### 3.1 Preparación

```bash
# 1. Anunciar ventana de mantenimiento (al menos 30 min)

# 2. Backup completo
bash scripts/linux/backup-db.sh pre_update_$(date +%Y%m%d)

# 3. Verificar que el backup se generó
ls -lh backups/*pre_update*

# 4. Verificar espacio en disco (al menos 5 GB libres)
df -h

# 5. Leer changelog de la versión a actualizar
# Synapse: https://github.com/element-hq/synapse/blob/master/CHANGES.md
# PostgreSQL: https://www.postgresql.org/docs/release/
```

### 3.2 Descargar nuevas imágenes

```bash
bash scripts/linux/update-images.sh
```

Esto hace `docker compose pull` para todas las imágenes y reconstruye Element.

### 3.3 Aplicar actualización

```bash
# Opción A: Recrear contenedores con nuevas imágenes
bash scripts/linux/update-containers.sh

# Opción B: Si quieres ver los cambios antes
docker compose up -d --no-deps --build synapse
```

### 3.4 Verificación post-actualización

```bash
# 1. Estado
bash scripts/linux/status.sh

# 2. Verificar versiones
docker compose exec synapse curl -s http://localhost:8008/_synapse/admin/v1/server_version
docker compose exec postgres psql -V
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO server | grep redis_version

# 3. Logs (mirar 5 min)
bash scripts/linux/logs.sh --since 5m

# 4. Test funcional
curl -k https://matrix.home.arpa/health
curl -k https://element.home.arpa/

# 5. Login de prueba desde Element
```

### 3.5 Comunicar fin de mantenimiento

```bash
# Server notice a usuarios
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/send_server_notice" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "@admin:home.arpa",
        "content": {
            "msgtype": "m.text",
            "body": "Mantenimiento completado. Servicio operativo."
        }
    }'
```

---

## 4. Actualización de versiones pinned

Cuando quieras cambiar Synapse o PostgreSQL a una versión mayor:

### 4.1 Cambiar tag en docker-compose.yml

```yaml
# Antes
synapse:
  image: matrixdotorg/synapse:v1.118.0

# Después
synapse:
  image: matrixdotorg/synapse:v1.119.0
```

### 4.2 Leer upgrade notes

Synapse publica upgrade notes para versiones mayores. Lee:
- https://matrix-org.github.io/synapse/latest/upgrade.html

Verificar:
- Cambios en config schema
- Migraciones automáticas de BD
- Breaking changes

### 4.3 Aplicar

```bash
# 1. Backup
bash scripts/linux/backup-db.sh pre_major_upgrade

# 2. Pull nueva imagen
docker compose pull synapse

# 3. Recrear
docker compose up -d synapse

# 4. Monitorear logs (migraciones pueden tardar)
docker compose logs -f synapse
```

### 4.4 Verificar migraciones

Synapse ejecuta migraciones automáticas al arrancar. Ver:

```bash
docker compose logs synapse | grep -i "migrat\|upgrade"
```

Si hay error de migración, NO continuar. Ver procedimiento de rollback.

---

## 5. Actualización de PostgreSQL (major version)

Cambiar de PostgreSQL 15 a 16 requiere dump + restore.

### 5.1 Procedimiento

```bash
# 1. Backup completo (formato custom)
bash scripts/linux/backup-db.sh pre_pg_upgrade

# 2. Detener stack
bash scripts/linux/stop.sh

# 3. Eliminar volumen de PostgreSQL (PELIGROSO - perderás datos)
# Solo si tienes backup confiable
docker volume rm matrix_postgres_data

# 4. Cambiar tag en docker-compose.yml
# image: postgres:16.4-alpine3.20

# 5. Iniciar solo PostgreSQL
docker compose up -d postgres

# 6. Esperar a que esté healthy
sleep 30

# 7. Restaurar backup
bash scripts/linux/restore-db.sh backups/db_pre_pg_upgrade_*.sql.gz

# 8. Iniciar el resto del stack
bash scripts/linux/start.sh
```

### 5.2 Verificar

```bash
docker compose exec postgres psql -U synapse_user -d synapse -c "SELECT version();"
# Debe mostrar PostgreSQL 16.x

# Verificar que las tablas están
docker compose exec postgres psql -U synapse_user -d synapse -c "\dt"
```

---

## 6. Rollback

Si la actualización falla:

### 6.1 Rollback de imagen

```bash
# 1. Revertir docker-compose.yml al tag anterior
nano docker-compose.yml
# Cambiar image: matrixdotorg/synapse:v1.119.0
# a image: matrixdotorg/synapse:v1.118.0

# 2. Pull imagen anterior
docker compose pull synapse

# 3. Recrear
docker compose up -d --force-recreate synapse
```

### 6.2 Rollback de base de datos

Si la migración de BD falló:

```bash
# 1. Detener Synapse
docker compose stop synapse

# 2. Restaurar BD del backup pre-update
bash scripts/linux/restore-db.sh backups/db_pre_update_*.sql.gz

# 3. Reiniciar con imagen anterior
docker compose up -d synapse
```

### 6.3 Rollback completo (escenario worst case)

```bash
# 1. Detener todo
bash scripts/linux/stop.sh

# 2. Eliminar contenedores
docker compose down

# 3. Restaurar docker-compose.yml de Git
git checkout docker-compose.yml

# 4. Restaurar configs de backup
tar -xzf backups/config_pre_update_*.tar.gz -C ./

# 5. Restaurar BD
docker compose up -d postgres
sleep 30
bash scripts/linux/restore-db.sh backups/db_pre_update_*.sql.gz

# 6. Iniciar
bash scripts/linux/start.sh
```

---

## 7. Actualización automática (no recomendado)

Para entornos no críticos, se puede configurar Watchtower para auto-actualizar contenedores:

```yaml
# Añadir al docker-compose.yml
watchtower:
  image: containrrr/watchtower:latest
  container_name: matrix-watchtower
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  environment:
    - WATCHTOWER_CLEANUP=true
    - WATCHTOWER_SCHEDULE=0 0 4 * * *  # Diario a las 4 AM
  restart: unless-stopped
```

> **No recomendado para producción**. Las actualizaciones automáticas pueden romper el stack si hay breaking changes. Mejor actualizar manualmente con procedimiento.

---

## 8. Matriz de compatibilidad

Antes de actualizar, verificar compatibilidad:

| Synapse | Element Web | PostgreSQL | Redis |
|---------|-------------|------------|-------|
| 1.118 | 1.11.65+ | 12-16 | 6-7 |
| 1.117 | 1.11.60+ | 12-16 | 6-7 |
| 1.116 | 1.11.55+ | 12-16 | 6-7 |

Consultar:
- [Synapse changelog](https://github.com/element-hq/synapse/blob/master/CHANGES.md)
- [Element releases](https://github.com/element-hq/element-web/releases)
- [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/)

---

## 9. Calendario de actualizaciones

### Recomendado

| Tipo | Frecuencia | Ventana |
|------|------------|---------|
| Security patches | Inmediata | Cualquiera |
| Bug fixes | Mensual | Fin de semana |
| Minor releases | Trimestral | Fin de semana |
| Major releases | Semestral | Ventana larga (2h) |
| PostgreSQL upgrades | Anual | Ventana larga (4h) |

### Notificar usuarios

Con al menos 48 horas de anticipación:
- Fecha y hora
- Duración estimada
- Impacto (servicio caído, degradado, etc.)
- Canal alternativo (email, teléfono)

---

## 10. Post-actualización: verificación 24h

Después de 24 horas de la actualización:

```bash
# 1. Verificar que no hay errores en logs
bash scripts/linux/logs.sh --since 24h 2>&1 | grep -iE "error|fatal" | head -20

# 2. Verificar usuarios activos (comparar con pre-update)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(DISTINCT user_id) FROM user_ips WHERE last_seen > NOW() - INTERVAL '24 hours';"

# 3. Verificar performance (latencia de sync)
# Ver logs de Synapse para `request_times`
docker compose logs synapse --since 24h 2>&1 | grep "request_times" | tail -50

# 4. Verificar tamaño de BD (no debe crecer anormalmente)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT pg_size_pretty(pg_database_size('synapse'));"

# 5. Documentar en CHANGELOG.md
nano CHANGELOG.md
```

---

## 11. Vulnerabilidades de seguridad críticas

Si se publica una vulnerabilidad crítica (CVE) en Synapse, PostgreSQL, Redis o Nginx:

1. **Evaluar impacto**: ¿afecta a nuestro stack?
2. **Aplicar patch urgente**:
   ```bash
   bash scripts/linux/backup-db.sh pre_security_patch
   bash scripts/linux/update-images.sh
   bash scripts/linux/update-containers.sh
   ```
3. **Verificar**: ver procedimiento post-actualización.
4. **Documentar**: agregar entrada a `CHANGELOG.md` con referencia al CVE.
5. **Auditar logs**: verificar que no hay signos de explotación previa.

---

## 12. Mantener el sistema operativo del host

No olvidar actualizar el host:

### Ubuntu

```bash
# Actualizaciones de seguridad automáticas
sudo unattended-upgrades --dry-run

# Actualización manual
sudo apt update && sudo apt upgrade -y

# Reiniciar si es necesario
sudo reboot
```

### Docker

```bash
# Verificar versión
docker version

# Actualizar Docker Engine
sudo apt update
sudo apt install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
