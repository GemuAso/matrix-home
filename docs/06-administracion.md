# Administración

> Tareas y procedimientos de administración del stack Matrix Docker.

> Para el manual completo del administrador con checklist diario/semanal/mensual, ver [`ADMIN_GUIDE.md`](../ADMIN_GUIDE.md) en la raíz del proyecto. Este documento complementa con tareas específicas.

---

## 1. Operaciones diarias

### 1.1 Verificación de salud

Cada mañana, ejecuta:

```bash
bash scripts/linux/status.sh
```

Verifica:
- Los 5 contenedores en estado `Up (healthy)`.
- Sin reinicios recientes en `Restart (N)` column.
- Espacio en disco suficiente (>20% libre).
- Sin errores en logs de las últimas 24 horas.

### 1.2 Revisión de logs

```bash
# Ver logs de las últimas 24 horas con errores
bash scripts/linux/logs.sh --since 24h 2>&1 | grep -iE "error|warn|fatal" | head -50

# Verificar intentos de login fallidos
bash scripts/linux/logs.sh synapse --since 24h 2>&1 | grep -i "login" | grep -v "200"
```

### 1.3 Verificación de backup

```bash
# Verificar que el último backup tiene tamaño razonable
ls -lh backups/ | tail -10
```

---

## 2. Gestión de usuarios

### 2.1 Crear usuario administrador

```bash
bash scripts/linux/create-admin.sh <username>
```

### 2.2 Crear usuario normal

```bash
bash scripts/linux/create-user.sh <username>
```

### 2.3 Listar usuarios

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, to_timestamp(creation_ts) AS created, admin FROM users ORDER BY creation_ts DESC;"
```

### 2.4 Promover/despromover admin

```bash
# Promover
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET admin=1 WHERE name='@usuario:home.arpa';"

# Despromover
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET admin=0 WHERE name='@usuario:home.arpa';"
```

### 2.5 Resetear contraseña

```bash
# Generar nueva password
NEW_PASS=$(openssl rand -base64 18)
echo "Nueva contraseña: $NEW_PASS"

# Hash con Python passlib
HASH=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.hash('$NEW_PASS', rounds=12))")

# Actualizar en BD
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET password_hash='$HASH' WHERE name='@usuario:home.arpa';"
```

### 2.6 Desactivar usuario

```bash
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/deactivate/@usuario:home.arpa" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 2.7 Invalidar todas las sesiones de un usuario

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "DELETE FROM access_tokens WHERE user_id='@usuario:home.arpa';"
```

---

## 3. Gestión de salas

### 3.1 Listar salas

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT room_id, name, join_rules FROM rooms r LEFT JOIN room_stats_state s ON r.room_id = s.room_id LIMIT 50;"
```

### 3.2 Ver miembros de una sala

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT user_id FROM current_state_events WHERE room_id='!roomid:home.arpa' AND membership='join';"
```

### 3.3 Eliminar sala (cuidado)

```bash
docker compose exec synapse curl -X DELETE \
    "http://localhost:8008/_synapse/admin/v1/rooms/!roomid:home.arpa" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"new_room_user_id": "@admin:home.arpa", "message": "Sala eliminada por admin", "block": true, "purge": true}'
```

### 3.4 Estadísticas de salas

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) AS total_rooms, sum(current_state_events) AS total_events FROM room_stats_current;"
```

---

## 4. Gestión de media

### 4.1 Ver tamaño de media

```bash
docker compose exec synapse du -sh /data/media
```

### 4.2 Listar media reciente

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT media_id, media_type, media_length, to_timestamp(created_ts/1000) AS created FROM local_media_repository ORDER BY created_ts DESC LIMIT 20;"
```

### 4.3 Purgar media antigua

```bash
# Media anterior a 90 días (timestamp en ms)
TS_90_DAYS_AGO=$(( ( $(date +%s) - 90*24*60*60 ) * 1000 ))

docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/home.arpa/delete?before_ts=$TS_90_DAYS_AGO" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 4.4 Cuarentena de media

Si detectas contenido inapropiado:

```bash
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/quarantine/home.arpa/<media_id>" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

---

## 5. Operaciones con la base de datos

### 5.1 Conectar a PostgreSQL

```bash
docker compose exec postgres psql -U synapse_user -d synapse
```

### 5.2 Ver tamaño de tablas

```sql
SELECT schemaname AS schema, relname AS table, pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;
```

### 5.3 VACUUM y ANALYZE

```bash
# VACUUM normal (no bloquea)
docker compose exec postgres psql -U synapse_user -d synapse -c "VACUUM ANALYZE;"

# VACUUM FULL (bloquea - ventana de mantenimiento)
docker compose exec postgres psql -U synapse_user -d synapse -c "VACUUM FULL ANALYZE;"
```

### 5.4 Ver conexiones activas

```sql
SELECT pid, usename, datname, client_addr, state, query
FROM pg_stat_activity
WHERE datname = 'synapse';
```

### 5.5 Matar query colgada

```sql
SELECT pg_cancel_backend(<pid>);   -- Cancela
SELECT pg_terminate_backend(<pid>); -- Termina
```

### 5.6 Reindexar

```bash
# En ventana de mantenimiento
docker compose exec postgres psql -U synapse_user -d synapse -c "REINDEX DATABASE synapse;"
```

---

## 6. Operaciones con Redis

### 6.1 Conectar a Redis CLI

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD"
```

### 6.2 Ver info de Redis

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO
```

### 6.3 Ver keys activas

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" DBSIZE
```

> **Nota**: el comando `KEYS` está deshabilitado por seguridad. Usa `SCAN` en su lugar.

### 6.4 Flush de caché (cuidado)

```bash
# El comando FLUSHALL está deshabilitado por seguridad.
# Para limpiar cache, reinicia Redis:
bash scripts/linux/restart.sh redis
```

---

## 7. Operaciones con Synapse

### 7.1 Ver estado de Synapse

```bash
# Health
curl -k https://matrix.home.arpa/health

# Versión
docker compose exec synapse curl -s http://localhost:8008/_synapse/admin/v1/server_version \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 7.2 Recargar configuración sin reiniciar

Algunos parámetros se pueden recargar via API:

```bash
docker compose exec synapse curl -X POST \
    http://localhost:8008/_synapse/admin/v1/reload \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 7.3 Regenerar signing key

Ver [`ADMIN_GUIDE.md` sección 3.4](../ADMIN_GUIDE.md).

### 7.4 Exportar eventos de una sala

```bash
docker compose exec synapse curl \
    "http://localhost:8008/_synapse/admin/v1/rooms/!roomid:home.arpa/export" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

---

## 8. Operaciones con Nginx

### 8.1 Recargar configuración

```bash
docker compose exec nginx nginx -s reload
```

### 8.2 Verificar configuración

```bash
docker compose exec nginx nginx -t
```

### 8.3 Ver access log en vivo

```bash
docker compose exec nginx tail -f /var/log/nginx/matrix-access.log
```

### 8.4 Ver stats de Nginx

```bash
docker compose exec nginx nginx -V 2>&1 | head -3
```

### 8.5 Reemplazar certificado

Si renuevas certs:

```bash
# 1. Reemplazar archivos en nginx/certs/
# 2. Verificar
docker compose exec nginx nginx -t
# 3. Recargar
docker compose exec nginx nginx -s reload
```

---

## 9. Monitoreo proactivo

### 9.1 Espacio en disco

Configurar alerta:

```bash
# Script simple (añadir a cron)
THRESHOLD=80
USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ $USAGE -gt $THRESHOLD ]; then
    echo "ALERTA: Disco al $USAGE%" | mail -s "Matrix Disk Alert" admin@home.arpa
fi
```

### 9.2 Healthcheck externo

```bash
# Script simple para verificar desde otro host
curl -k --max-time 5 https://matrix.home.arpa/health || \
    echo "ALERTA: Matrix no responde"
```

### 9.3 Conteo de usuarios activos

```sql
-- Usuarios que hicieron login en las últimas 24 horas
SELECT count(DISTINCT user_id)
FROM user_ips
WHERE last_seen > NOW() - INTERVAL '24 hours';
```

### 9.4 Latencia de mensajes

```bash
# Métricas de Synapse (si enable_metrics: true)
curl -k https://matrix.home.arpa/_synapse/metrics | grep synapse_http
```

---

## 10. Comunicación con usuarios

### 10.1 Anunciar mantenimiento

Usa el sistema de server notices (configurado en `homeserver.yaml`):

```bash
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/send_server_notice" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "@usuario:home.arpa",
        "content": {
            "msgtype": "m.text",
            "body": "Mantenimiento programado: 04:00-04:30 AM. El servicio estará intermitente."
        }
    }'
```

### 10.2 Broadcast a todos los usuarios

Crear una sala de anuncios y agregar a todos los usuarios. Ver [`ADMIN_GUIDE.md` sección 5](../ADMIN_GUIDE.md).

---

## 11. Auditoría

### 11.1 Quién creó qué sala

```sql
SELECT r.room_id, cs.creator, to_timestamp cs.creation_ts
FROM rooms r
JOIN current_state_events cs ON r.room_id = cs.room_id
WHERE cs.type = 'm.room.create'
ORDER BY cs.creation_ts DESC
LIMIT 20;
```

### 11.2 Login por IP

```sql
SELECT user_id, ip, last_seen
FROM user_ips
ORDER BY last_seen DESC
LIMIT 50;
```

### 11.3 Admins activos

```sql
SELECT name, to_timestamp(admin) AS is_admin
FROM users
WHERE admin = 1;
```

### 11.4 Eventos admin recientes

```bash
docker compose logs synapse --since 24h 2>&1 | grep -i "admin_api"
```
