# Configuración

> Detalle de todas las variables y opciones de configuración del stack.

---

## 1. Archivo .env

El archivo `.env` es la fuente de verdad para todos los secretos y parámetros configurables del stack. Está en la raíz del proyecto y NO debe commitearse a Git (ver `.gitignore`).

### 1.1 Secciones del .env

#### Configuración general

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `TZ` | Zona horaria IANA | `America/Bogota` |

Lista completa: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

#### Matrix Synapse - Identidad

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `SYNAPSE_SERVER_NAME` | Nombre del servidor (dominio en user IDs) | `home.arpa` |
| `SYNAPSE_PUBLIC_URL` | URL pública base con protocolo | `https://matrix.home.arpa` |
| `SYNAPSE_REPORT_STATS` | Enviar stats a matrix.org (false recomendado) | `false` |
| `SYNAPSE_LOG_CONFIG` | Ruta del log config dentro del contenedor | `/data/matrix.home.arpa.log.config` |

> **Importante**: cambiar `SYNAPSE_SERVER_NAME` después de crear usuarios rompe sus IDs. Define esto correctamente desde el inicio.

#### Matrix Synapse - Registro de usuarios

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `SYNAPSE_ENABLE_REGISTRATION` | Permitir registro público | `false` |
| `SYNAPSE_REGISTRATION_SHARED_SECRET` | Secret para `register_new_matrix_user` | (aleatorio) |
| `SYNAPSE_MACAROON_SECRET_KEY` | Firma de macaroons (sesiones) | (aleatorio) |
| `SYNAPSE_ADMIN_API_TOKEN` | Token para API admin | (aleatorio) |

#### PostgreSQL

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `POSTGRES_USER` | Usuario dueño de la BD | `synapse_user` |
| `POSTGRES_PASSWORD` | Password del usuario (32+ chars) | (aleatorio) |
| `POSTGRES_DB` | Nombre de la BD | `synapse` |
| `POSTGRES_HOST` | Hostname (interno Docker) | `postgres` |
| `POSTGRES_PORT` | Puerto (interno) | `5432` |

#### Redis

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `REDIS_PASSWORD` | Contraseña Redis (32+ chars) | (aleatorio) |

#### SMTP

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `SMTP_HOST` | Servidor SMTP | `smtp.home.arpa` |
| `SMTP_PORT` | Puerto SMTP (587 STARTTLS, 465 SSL) | `587` |
| `SMTP_USER` | Usuario SMTP (normalmente email) | `noresponder@home.arpa` |
| `SMTP_PASS` | Contraseña SMTP | (tu password) |
| `SMTP_FROM` | Email remitente | `noresponder@home.arpa` |
| `SMTP_FROM_NAME` | Nombre a mostrar | `Matrix Notificaciones` |
| `SMTP_TLS` | Forzar STARTTLS | `true` |
| `SMTP_REQUIRE_TLS` | Verificar certificado SMTP | `true` |

#### Nginx

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `NGINX_HTTP_PORT` | Puerto HTTP en el host | `80` |
| `NGINX_HTTPS_PORT` | Puerto HTTPS en el host | `443` |
| `NGINX_MATRIX_DOMAIN` | Dominio para Synapse | `matrix.home.arpa` |
| `NGINX_ELEMENT_DOMAIN` | Dominio para Element | `element.home.arpa` |

#### Backups

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `BACKUP_RETENTION_DAYS` | Días a conservar backups | `7` |
| `BACKUP_DIR` | Directorio de backups | `./backups` |

#### Red LAN

| Variable | Descripción | Default ejemplo |
|----------|-------------|-----------------|
| `LAN_CIDR` | Rango CIDR de la LAN | `192.168.1.0/24` |
| `HOST_IP` | IP del host Docker | `192.168.1.100` |

---

## 2. Configuración de Synapse

Archivo: `synapse/homeserver.yaml`

### 2.1 Parámetros críticos

```yaml
# Identidad del servidor - NO cambiar después del primer arranque
server_name: "home.arpa"
public_baseurl: "https://matrix.home.arpa/"

# Stats - mantener false para privacidad
report_stats: false

# Federación - deshabilitada para LAN aislada
federation:
  enabled: false
```

### 2.2 Base de datos

```yaml
database:
  name: psycopg2
  args:
    user: "synapse_user"
    password: "${POSTGRES_PASSWORD}"  # Inyectado desde .env via envsubst (v2.0.0)
    database: "synapse"
    host: "postgres"
    port: 5432
    cp_min: 5      # Conexiones mínimas del pool
    cp_max: 20     # Conexiones máximas del pool
```

Ajusta `cp_max` si tienes más usuarios (50+ usuarios → `cp_max: 50`).

### 2.3 Redis

```yaml
redis:
  enabled: true
  host: "redis"
  port: 6379
  password: "${REDIS_PASSWORD}"  # Inyectado desde .env via envsubst (v2.0.0)
```

### 2.4 Registro de usuarios

```yaml
# Registro público - mantener false en producción
enable_registration: false

# Si lo activas, requiere email verification
registration_requires_token: false
registrations_require_3pid:
  - email

# Shared secret para el script register_new_matrix_user
registration_shared_secret: "${SYNAPSE_REGISTRATION_SHARED_SECRET}"  # Inyectado desde .env (v2.0.0)
```

### 2.5 Email

```yaml
email:
  smtp_host: "smtp.home.arpa"
  smtp_port: 587
  smtp_user: "noresponder@home.arpa"
  smtp_pass: "<SMTP_PASS>"
  require_transport_security: true
  enable_tls: true
  notif_from: "Matrix <noresponder@home.arpa>"
  app_name: "Matrix"
  enable_notifs: true
  invite_client_location: "https://element.home.arpa/"
```

### 2.6 Media

```yaml
media_store_path: "/data/media"
max_media_upload_size: 50M      # Ajusta según necesidad
max_image_pixels: 32M           # Máximo para auto-thumbnail

# Proveedor de almacenamiento
media_storage_providers:
  - module: file_system
    store_local: true
    store_remote: true
    store_synchronous: true
    config:
      directory: "/data/media"
```

### 2.7 Rate limiting

```yaml
rc_messages:
  per_second: 0.2
  burst_count: 10

rc_login:
  address:
    per_second: 0.17   # ~10 intentos/minuto por IP
    burst_count: 5
  account:
    per_second: 0.17
    burst_count: 5
  failed_attempts:
    per_second: 0.17
    burst_count: 5
```

### 2.8 Política de contraseñas

```yaml
password_config:
  enabled: true
  localdb_enabled: true
  pepper: "${SYNAPSE_PASSWORD_PEPPER}"  # Inyectado desde .env via envsubst (v2.0.0)
  policy:
    enabled: true
    minimum_length: 10
    require_digit: true
    require_symbol: true
    require_lowercase: true
    require_uppercase: true
```

### 2.9 Logging

Ver `synapse/log.config` para la configuración de loggers. Niveles:

- `DEBUG`: muy verboso, solo para troubleshooting
- `INFO`: default, balance
- `WARNING`: solo warnings y errores
- `ERROR`: solo errores

Para producción: `INFO` en `synapse`, `WARNING` en `synapse.storage.SQL`.

---

## 3. Configuración de PostgreSQL

### 3.1 postgresql.conf

Archivo: `postgres/postgresql.conf`

Parámetros clave ajustados para Synapse:

```conf
# Conexiones (Synapse usa pool, no necesita muchas)
max_connections = 100

# Memoria - ajustar según RAM del host
shared_buffers = 512MB        # 25% de RAM dedicada a PG
effective_cache_size = 2GB    # 50-75% de RAM total
work_mem = 16MB
maintenance_work_mem = 256MB

# WAL
wal_buffers = 16MB
checkpoint_timeout = 5min
max_wal_size = 1GB

# Autovacuum (crítico para Synapse - muchas escrituras)
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 30s

# Logging
log_min_duration_statement = 500  # ms - log queries >500ms
log_lock_waits = on
```

Para ajustar según RAM del host:

| RAM host | shared_buffers | effective_cache_size | work_mem |
|----------|----------------|----------------------|----------|
| 4 GB | 512MB | 2GB | 16MB |
| 8 GB | 1GB | 5GB | 32MB |
| 16 GB | 2GB | 10GB | 64MB |
| 32 GB | 4GB | 22GB | 128MB |

### 3.2 pg_hba.conf

Archivo: `postgres/pg_hba.conf`

Define quién puede conectar. Por defecto solo permite conexiones desde la red Docker interna:

```conf
# Solo el usuario synapse_user puede acceder, solo a la DB synapse
host    synapse    synapse_user    172.16.0.0/12    scram-sha-256
host    synapse    synapse_user    192.168.0.0/16   scram-sha-256
host    synapse    synapse_user    10.0.0.0/8       scram-sha-256

# Reject todo lo demás
host    all    all    0.0.0.0/0    reject
host    all    all    ::/0         reject
```

### 3.3 init.sql

Archivo: `postgres/init.sql`

Se ejecuta solo en el primer arranque (cuando el directorio de datos está vacío):

```sql
CREATE EXTENSION IF NOT EXISTS citext;     -- Case-insensitive text
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- Búsqueda fuzzy
```

---

## 4. Configuración de Redis

Archivo: `redis/redis.conf`

```conf
# Seguridad
requirepass <REDIS_PASSWORD>

# Renombrar comandos peligrosos
rename-command FLUSHALL ""
rename-command CONFIG ""

# Persistencia
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Memoria
maxmemory 512mb               # Ajustar según RAM
maxmemory-policy allkeys-lru
```

Ajusta `maxmemory` según RAM del host:

| RAM host | maxmemory Redis |
|----------|-----------------|
| 4 GB | 256MB |
| 8 GB | 512MB |
| 16 GB | 1GB |
| 32 GB | 2GB |

---

## 5. Configuración de Element Web

Archivo: `element/config.json`

### 5.1 Homeserver

```json
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://matrix.home.arpa",
            "server_name": "home.arpa"
        }
    }
}
```

Cambia `base_url` y `server_name` si usas otro dominio.

### 5.2 Branding

```json
{
    "brand": "Element",
    "branding": {
        "authHeaderLogoUrl": "themes/element/img/logos/element-logo.svg",
        "authFooterLinks": [
            { "text": "Privacidad", "url": "https://home.arpa/privacy" },
            { "text": "Términos", "url": "https://home.arpa/terms" }
        ]
    }
}
```

### 5.3 Features habilitadas/deshabilitadas

```json
{
    "features": {
        "feature_video_rooms": "enable",
        "feature_group_calls": "enable"
    },
    "settingDefaults": {
        "UIFeature.registration": false,        // Sin registro desde Element
        "UIFeature.thirdPartyIdentities": false, // Sin 3PID
        "UIFeature.identityServer": false,
        "UIFeature.feedback": false
    }
}
```

### 5.4 Tema default

```json
{
    "default_theme": "dark"  // dark | light
}
```

---

## 6. Configuración de Nginx

### 6.1 nginx.conf (principal)

Archivo: `nginx/nginx.conf`

Define parámetros globales: worker processes, MIME types, gzip, SSL, rate limiting zones, upstreams.

### 6.2 conf.d/

- `00-default.conf`: catch-all para dominios no reconocidos.
- `matrix.home.arpa.conf`: virtual host para Synapse.
- `element.home.arpa.conf`: virtual host para Element.

### 6.3 snippets/

- `security-headers.conf`: headers HSTS, CSP, X-Frame-Options, etc.
- `proxy-params.conf`: parámetros comunes de proxy reverso.

### 6.4 well-known/

Archivos servidos en `/.well-known/matrix/`:

- `client.json`: información del homeserver para clientes.
- `server.json`: información del servidor para federación (incluso si está deshabilitada, sirve para compatibilidad).

### 6.5 certs/

Certificados SSL generados por `scripts/linux/generate-certs.sh`:

- `ca.crt` + `ca.key`: CA local (importable en clientes).
- `matrix.crt` + `.key`: cert para Synapse (nombre fijo desde v2.0.0).
- `element.crt` + `.key`: cert para Element (nombre fijo desde v2.0.0).
- `default.crt` + `.key`: cert para catch-all.

---

## 7. Cambio de dominios

Si quieres usar dominios distintos a `home.arpa`:

### 7.1 Editar archivos

1. `.env`:
   ```
   SYNAPSE_SERVER_NAME=tudominio.com
   SYNAPSE_PUBLIC_URL=https://matrix.tudominio.com
   NGINX_MATRIX_DOMAIN=matrix.tudominio.com
   NGINX_ELEMENT_DOMAIN=element.tudominio.com
   ```

2. `synapse/homeserver.yaml`: reemplazar `home.arpa` por `tudominio.com`.

3. `element/config.json`: actualizar `base_url` y `server_name`.

4. `nginx/conf.d/`: renombrar archivos y actualizar `server_name` y `ssl_certificate` paths.

5. `nginx/well-known/matrix/`: actualizar JSONs.

6. `synapse/log.config`: el nombre del log config cambia según el dominio. Renombrar archivo `synapse/log.config` a `synapse/matrix.tudominio.com.log.config` y actualizar referencia en `homeserver.yaml` y `docker-compose.yml`.

### 7.2 Regenerar certs

```bash
# Linux
rm -f nginx/certs/*.crt nginx/certs/*.key nginx/certs/*.srl
bash scripts/linux/generate-certs.sh

# Windows
Remove-Item nginx\certs\*.crt, nginx\certs\*.key, nginx\certs\*.srl
.\scripts\windows\generate-certs.ps1
```

### 7.3 Reiniciar

```bash
bash scripts/linux/restart.sh
```

---

## 8. Habilitar federación (opcional, no recomendado para LAN)

> **Nota v2.0.0**: A partir de la versión 2.0.0, la federación fue completamente removida del proyecto. Los endpoints de federación en Nginx, las configuraciones de federación en homeserver.yaml, y los recursos relacionados han sido eliminados. Esta sección se conserva únicamente como referencia histórica.

Si en el futuro quieres federar con otros servidores Matrix:

1. Editar `synapse/homeserver.yaml`:
   ```yaml
   federation:
     enabled: true
   ```

2. Exponer puerto 8448 en `docker-compose.yml`:
   ```yaml
   nginx:
     ports:
       - "80:80"
       - "443:443"
       - "8448:8448"
   ```

3. Actualizar `nginx/conf.d/matrix.home.arpa.conf` para manejar `:8448` y la ruta `/_matrix/federation/*`.

4. Actualizar `nginx/well-known/matrix/server.json`:
   ```json
   { "m.server": "matrix.home.arpa:443" }
   ```

5. Configurar DNS público para el dominio.
6. Cambiar certs self-signed por Let's Encrypt o CA pública.

Ver [federation docs de Matrix](https://matrix-org.github.io/synapse/latest/federate.html) para más detalles.

---

## 9. Backup de la configuración

La configuración está compuesta por:
- `.env` (con secretos)
- `synapse/` (homeserver, log.config, signing.key)
- `postgres/` (postgresql.conf, pg_hba.conf, init.sql)
- `redis/redis.conf`
- `element/` (config.json, nginx.conf, Dockerfile)
- `nginx/` (todos los conf y certs)
- `docker-compose.yml`

El script `backup-db.sh` genera un tar.gz con todos estos archivos automáticamente. Ver [`09-backups.md`](09-backups.md).

---

## 10. Validación de configuración

Después de cualquier cambio:

```bash
# Validar docker-compose
docker compose config --quiet

# Validar nginx
docker compose exec nginx nginx -t

# Validar PostgreSQL
docker compose exec postgres psql -U synapse_user -d synapse -c "SELECT 1;"

# Validar Redis
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping

# Validar Synapse
docker compose exec synapse curl -sf http://localhost:8008/health
```
