# Logs

> Ubicación, rotación, consulta y diagnóstico de logs.

---

## 1. Visión general

Cada servicio del stack genera logs mediante el driver `json-file` de Docker. Adicionalmente:
- PostgreSQL loguea a stderr (capturado por Docker).
- Synapse loguea a stdout/stderr + archivo dentro del volumen.
- Nginx loguea a volumen dedicado (`matrix_nginx_logs`).
- Redis loguea a stdout (capturado por Docker).

Todos los logs tienen rotación configurada via `logging.options` en `docker-compose.yml`:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "100m"
    max-file: "5"
```

---

## 2. Ubicación de logs

### 2.1 Logs de Docker (todos los servicios)

Docker almacena logs en `/var/lib/docker/containers/<container_id>/<container_id>-json.log`. No es necesario acceder directamente; usar `docker compose logs`.

### 2.2 Logs internos de Synapse

Synapse escribe adicionalmente a `/data/logs/homeserver.log` dentro del contenedor (volumen `matrix_synapse_data`).

```bash
# Ver desde el contenedor
docker compose exec synapse ls -la /data/logs/
docker compose exec synapse tail -f /data/logs/homeserver.log
```

### 2.3 Logs de Nginx

Nginx escribe a volumen `matrix_nginx_logs`:
- `/var/log/nginx/access.log` - accesos generales.
- `/var/log/nginx/error.log` - errores.
- `/var/log/nginx/matrix-access.log` - accesos a matrix.home.arpa.
- `/var/log/nginx/matrix-error.log` - errores matrix.
- `/var/log/nginx/element-access.log` - accesos a element.home.arpa.
- `/var/log/nginx/element-error.log` - errores element.

```bash
# Ver desde el contenedor
docker compose exec nginx ls -la /var/log/nginx/
docker compose exec nginx tail -f /var/log/nginx/matrix-access.log
```

### 2.4 Logs de PostgreSQL

PostgreSQL loguea a stderr, capturado por Docker. Algunos logs específicos:

- Queries lentas: `log_min_duration_statement = 500` (ms).
- Lock waits: `log_lock_waits = on`.
- Checkpoints: `log_checkpoints = on`.
- Autovacuum: visible en logs generales.

```bash
# Ver logs
docker compose logs postgres

# Filtrar queries lentas
docker compose logs postgres | grep "duration"
```

### 2.5 Logs de Redis

Redis loguea a stdout con nivel `notice`:

```bash
docker compose logs redis

# Ver info específica
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO log

# Slow log
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" SLOWLOG GET 10
```

### 2.6 Logs de Element

Element Web (Nginx interno) loguea a `/var/log/nginx/` dentro del contenedor:

```bash
docker compose exec element ls -la /var/log/nginx/
docker compose exec element tail -f /var/log/nginx/access.log
```

---

## 3. Comandos para ver logs

### 3.1 Script de logs

```bash
# Ver logs de todos los servicios (últimos 20)
bash scripts/linux/logs.sh

# Ver logs de un servicio en follow
bash scripts/linux/logs.sh synapse -f

# Últimas 200 líneas
bash scripts/linux/logs.sh synapse --tail 200

# Desde una hora atrás
bash scripts/linux/logs.sh synapse --since 1h

# Rango de tiempo
bash scripts/linux/logs.sh synapse --since 2026-07-04T10:00:00 --until 2026-07-04T12:00:00

# Windows equivalent
.\scripts\windows\logs.ps1 synapse -f
```

### 3.2 Docker compose directo

```bash
# Seguir logs en vivo
docker compose logs -f synapse

# Últimas N líneas
docker compose logs --tail 100 synapse

# Timestamps
docker compose logs -t synapse

# Solo nuevos logs (desde ahora)
docker compose logs -f --since 0s synapse
```

### 3.3 Filtrar logs

```bash
# Errores y warnings
docker compose logs synapse 2>&1 | grep -iE "error|warn"

# Errores solo
docker compose logs synapse 2>&1 | grep -i "error"

# Stack traces
docker compose logs synapse 2>&1 | grep -A 10 "Traceback"

# Login events
docker compose logs synapse 2>&1 | grep -i "login"

# Requests a endpoint específico
docker compose logs synapse 2>&1 | grep "/_matrix/client/v3/login"
```

### 3.4 JSON format para análisis

```bash
# Formato JSON
docker compose logs --format json synapse | jq '.msg' | head

# Solo logs de cierto nivel
docker compose logs --format json synapse | jq 'select(.level=="ERROR")'

# Contar por nivel
docker compose logs --format json synapse | jq -r '.level' | sort | uniq -c
```

---

## 4. Rotación de logs

### 4.1 Rotación Docker (json-file driver)

Configurada en `docker-compose.yml`:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "100m"   # Tamaño máximo por archivo
    max-file: "5"      # Número máximo de archivos
```

| Servicio | max-size | max-file | Espacio máximo |
|----------|----------|----------|----------------|
| postgres | 50m | 5 | 250 MB |
| redis | 20m | 5 | 100 MB |
| synapse | 100m | 7 | 700 MB |
| element | 20m | 3 | 60 MB |
| nginx | 50m | 5 | 250 MB |

Total máximo: ~1.36 GB en logs.

### 4.2 Rotación de Synapse internal log

Configurada en `synapse/log.config`:

```python
'file': {
    'class': 'logging.handlers.RotatingFileHandler',
    'formatter': 'precise',
    'filename': '/data/logs/homeserver.log',
    'maxBytes': 104857600,    # 100 MB
    'backupCount': 5,         # 5 archivos
    'encoding': 'utf8',
}
```

Espacio máximo: 500 MB.

### 4.3 Rotación de Nginx logs (Ubuntu)

Para rotar logs del volumen `matrix_nginx_logs`, usar logrotate:

```bash
sudo cp deployment/logrotate-matrix.conf /etc/logrotate.d/matrix-docker
```

Contenido:

```conf
/var/lib/docker/volumes/matrix_nginx_logs/_data/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 deploy deploy
    sharedscripts
    postrotate
        docker exec matrix-nginx nginx -s reopen 2>/dev/null || true
    endscript
}
```

Probar:

```bash
sudo logrotate -d /etc/logrotate.d/matrix-docker  # Dry run
sudo logrotate -f /etc/logrotate.d/matrix-docker  # Forzar rotación
```

### 4.4 Rotación de Docker daemon (host)

En `/etc/docker/daemon.json` (Ubuntu):

```json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "5"
    }
}
```

Reiniciar Docker: `sudo systemctl restart docker`.

> **Nota**: esto afecta a todos los contenedores, no solo Matrix.

---

## 5. Niveles de log

### 5.1 Synapse

Configurados en `synapse/log.config`:

```python
loggers:
    synapse:
        level: INFO              # General
    synapse.storage.SQL:
        level: WARNING           # SQL queries (INFO = muy verboso)
    synapse.http:
        level: INFO
    synapse.federation:
        level: INFO
    synapse.handlers:
        level: INFO
    synapse.metrics:
        level: WARNING
    twisted:
        level: INFO
    sqlalchemy:
        level: WARNING
```

Cambiar a `DEBUG` para troubleshooting:

```python
synapse:
    level: DEBUG
```

Reiniciar Synapse.

> **Advertencia**: `DEBUG` genera MUCHOS logs. Usar temporalmente.

### 5.2 PostgreSQL

En `postgres/postgresql.conf`:

```conf
log_min_messages = warning
log_min_error_statement = error
log_min_duration_statement = 500  # ms
log_lock_waits = on
log_statement = 'none'  # none | ddl | mod | all
```

Cambiar `log_min_messages = info` o `log_statement = 'all'` para debug.

> **Advertencia**: `log_statement = 'all'` genera logs enormes. Usar solo temporalmente.

### 5.3 Redis

En `redis/redis.conf`:

```conf
loglevel notice    # debug | verbose | notice | warning
```

### 5.4 Nginx

En `nginx/nginx.conf`:

```conf
error_log  /var/log/nginx/error.log warn;  # debug | info | notice | warn | error | crit
```

Para debug de un problema específico:

```nginx
error_log  /var/log/nginx/error.log debug;
```

> **Advertencia**: `debug` genera logs enormes.

---

## 6. Diagnóstico con logs

### 6.1 Identificar errores frecuentes

```bash
# Top errores de Synapse (última hora)
docker compose logs synapse --since 1h 2>&1 | \
    grep "ERROR" | \
    awk -F'ERROR ' '{print $2}' | \
    sort | uniq -c | sort -rn | head -20

# Top errores de PostgreSQL
docker compose logs postgres --since 24h 2>&1 | \
    grep "ERROR" | \
    awk -F'ERROR: ' '{print $2}' | \
    sort | uniq -c | sort -rn | head -20
```

### 6.2 Detectar ataques

```bash
# Intentos de login fallidos (últimas 24h)
docker compose logs synapse --since 24h 2>&1 | \
    grep "login" | grep -i "fail\|denied\|invalid"

# 403 Forbidden en Nginx
docker compose exec nginx cat /var/log/nginx/matrix-access.log | \
    awk '$9 == 403 {print $1}' | sort | uniq -c | sort -rn | head

# IPs con más requests (posible DDoS)
docker compose exec nginx cat /var/log/nginx/matrix-access.log | \
    awk '{print $1}' | sort | uniq -c | sort -rn | head -20
```

### 6.3 Detectar problemas de performance

```bash
# Queries lentas de PostgreSQL (>500ms)
docker compose logs postgres --since 1h 2>&1 | \
    grep "duration:" | \
    awk -F'duration: ' '{print $2}' | sort -rn | head

# Requests lentas de Synapse
docker compose logs synapse --since 1h 2>&1 | \
    grep "request_times" | \
    grep -oP '"\d+\.\d+"' | sort -rn | head

# 50x errors en Nginx
docker compose exec nginx cat /var/log/nginx/matrix-access.log | \
    awk '$9 ~ /^50/ {print $0}' | tail -20
```

### 6.4 Trazar un evento específico

```bash
# Login de un usuario específico
docker compose logs synapse 2>&1 | \
    grep "@usuario:home.arpa" | grep -i "login"

# Mensajes en una sala específica
docker compose logs synapse 2>&1 | \
    grep "!roomid:home.arpa"

# Requests de una IP específica
docker compose exec nginx cat /var/log/nginx/matrix-access.log | \
    grep "192.168.1.50"
```

---

## 7. Retención de logs

### 7.1 Política recomendada

| Tipo de log | Retención | Justificación |
|-------------|-----------|---------------|
| Docker json logs | 5 archivos x 100 MB | Configurado por servicio |
| Synapse internal | 5 archivos x 100 MB | Configurado en log.config |
| Nginx access | 14 días | Suficiente para auditoría |
| Nginx error | 14 días | Suficiente para diagnóstico |
| PostgreSQL | 5 archivos x 50 MB | Queries lentas y errores |
| Redis | 5 archivos x 20 MB | Pocos logs |

### 7.2 Compliance (si aplica)

Para auditoría/regulatorio:

- **Logs de acceso**: retención mínima 90 días (algunas normas 1 año).
- **Logs de admin actions**: retención mínima 1 año.
- **Logs de seguridad**: retención mínima 1 año (PCI-DSS, ISO 27001).

Para implementar retención larga, enviar logs a sistema externo:
- Loki + Grafana
- Elasticsearch + Kibana
- Syslog server
- S3 con lifecycle policy

---

## 8. Centralización de logs (futuro)

### 8.1 Loki + Promtail

Para centralizar logs (no incluido en 1.0.0):

```yaml
# docker-compose.monitoring.yml
loki:
  image: grafana/loki:latest
  container_name: matrix-loki
  ports:
    - "3100:3100"
  volumes:
    - loki_data:/loki

promtail:
  image: grafana/promtail:latest
  container_name: matrix-promtail
  volumes:
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  command: -config.file=/etc/promtail/config.yml

grafana:
  image: grafana/grafana:latest
  container_name: matrix-grafana
  ports:
    - "3000:3000"
```

### 8.2 Docker logging drivers alternativos

Para enviar logs a syslog externo:

```yaml
# En docker-compose.yml
services:
  synapse:
    logging:
      driver: syslog
      options:
        syslog-address: "tcp://192.168.1.10:514"
        syslog-facility: daemon
        tag: "matrix-synapse"
```

---

## 9. Backup de logs

### 9.1 Backup periódico de logs críticos

```bash
# Backup semanal de logs de Nginx
docker compose exec nginx tar -czf - /var/log/nginx/ > \
    backups/nginx_logs_$(date +%Y%m%d).tar.gz

# Backup de logs de Synapse
docker compose exec synapse tar -czf - /data/logs/ > \
    backups/synapse_logs_$(date +%Y%m%d).tar.gz
```

### 9.2 Logs a considerar críticos

- Access logs de Nginx (auditoría de accesos).
- Login events de Synapse (auditoría de auth).
- Admin API calls de Synapse (auditoría de admin actions).
- Error logs de todos los servicios (diagnóstico).

---

## 10. Troubleshooting con logs

### 10.1 Stack no arranca

```bash
# Ver logs de cada servicio en orden
docker compose logs postgres | tail -50
docker compose logs redis | tail -20
docker compose logs synapse | tail -50
docker compose logs element | tail -20
docker compose logs nginx | tail -50
```

### 10.2 Servicio no healthy

```bash
# Verificar healthcheck en logs
docker inspect matrix-synapse --format='{{json .State.Health}}' | jq

# Ver últimos logs
docker compose logs synapse --tail 100
```

### 10.3 Performance degradada

```bash
# PostgreSQL slow queries
docker compose logs postgres --since 1h | grep "duration" | sort -t: -k2 -rn | head

# Synapse request times
docker compose logs synapse --since 1h | grep "request_times" | head -20

# Redis slow log
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" SLOWLOG GET 10
```

### 10.4 Errores intermitentes

```bash
# Capturar errores en vivo
docker compose logs -f synapse 2>&1 | grep --line-buffered "ERROR" >> /tmp/synapse_errors.log &

# Esperar 1h
sleep 3600

# Ver errores capturados
cat /tmp/synapse_errors.log
```

---

## 11. Monitoreo de logs

### 11.1 Alerta si aparecen errores

Script simple:

```bash
#!/usr/bin/env bash
# /opt/matrix-docker/scripts/linux/check-logs.sh
ERRORS=$(docker compose logs synapse --since 1h 2>&1 | grep -c "ERROR")
if [ "$ERRORS" -gt 10 ]; then
    echo "ALERTA: $ERRORS errores en Synapse en la última hora" | \
    mail -s "Matrix: errors in Synapse" admin@home.arpa
fi
```

Añadir a cron:

```cron
0 * * * * deploy /opt/matrix-docker/scripts/linux/check-logs.sh
```

### 11.2 Watch de error patterns

```bash
# Watch en tiempo real
docker compose logs -f synapse 2>&1 | \
    grep --line-buffered -E "ERROR|FATAL" | \
    while read line; do
        echo "[$(date)] $line"
        # Aquí se podría enviar a Slack, email, etc.
    done
```

---

## 12. Logs vs métricas

### Logs vs métricas

- **Logs**: eventos discretos con contexto. Útiles para diagnóstico.
- **Métricas**: agregados numéricos en series temporales. Útiles para alertas y tendencias.

Para este stack, los logs son la fuente principal de observabilidad. Las métricas (Prometheus/Grafana) son una mejora futura.

### Cuándo usar logs

- Diagnóstico de errores.
- Auditoría de accesos.
- Trazado de eventos.
- Debugging.

### Cuándo usar métricas

- Alertas de performance.
- Tendencias de uso.
- Capacidad planning.
- Detección de anomalías.
