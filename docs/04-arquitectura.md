# Arquitectura

> Visión detallada de los componentes, su interacción y los flujos de red.

---

## 1. Visión general

El stack Matrix Docker está compuesto por cinco servicios contenerizados que se comunican mediante dos redes Docker aisladas. El diseño prioriza la seguridad por aislamiento: los servicios de datos (PostgreSQL, Redis) no se exponen al host ni a la LAN; solo Nginx, como único punto de entrada, publica puertos hacia la LAN.

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Red LAN (192.168.x.x)                         │
│                                                                       │
│  Clientes (navegador Element en PCs/tablets)                         │
│       │                                                               │
│       ▼  HTTPS (443)                                                  │
│  ┌────────────────────────────────────────────────────────────┐      │
│  │  Host Docker                                                │      │
│  │                                                              │      │
│  │  ┌──────────────────────────────────────────────────┐      │      │
│  │  │  matrix_frontend (red Docker bridge)             │      │      │
│  │  │                                                    │      │      │
│  │  │   ┌──────────┐    ┌──────────┐    ┌──────────┐  │      │      │
│  │  │   │  Nginx   │    │ Element  │    │ Synapse  │  │      │      │
│  │  │   │ :80 :443 │    │   :80    │    │  :8008   │  │      │      │
│  │  │   └────┬─────┘    └──────────┘    └────┬─────┘  │      │      │
│  │  │        │                                  │       │      │      │
│  │  │        └──────────────┬───────────────────┘       │      │      │
│  │  └────────────────────────┼────────────────────────────┘      │      │
│  │                           │                                    │      │
│  │  ┌────────────────────────▼─────────────────────────────┐    │      │
│  │  │  matrix_internal (red Docker bridge)                  │    │      │
│  │  │                                                        │    │      │
│  │  │   ┌──────────────┐         ┌──────────────┐          │    │      │
│  │  │   │  PostgreSQL  │         │    Redis     │          │    │      │
│  │  │   │    :5432     │         │    :6379     │          │    │      │
│  │  │   └──────────────┘         └──────────────┘          │    │      │
│  │  └────────────────────────────────────────────────────────┘    │      │
│  └────────────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. Componentes

### 2.1 Nginx (Reverse Proxy)

**Imagen**: `nginx:1.27.2-alpine3.20`

**Rol**: Único punto de entrada desde la LAN. Termina TLS, aplica políticas de seguridad, rate limiting, y enruta a Synapse o Element según el hostname.

**Puertos publicados**: 80 (HTTP), 443 (HTTPS) en el host.

**Volúmenes**:
- `./nginx/nginx.conf` (ro): config principal
- `./nginx/conf.d/` (ro): virtual hosts
- `./nginx/certs/` (ro): certificados SSL
- `./nginx/snippets/` (ro): snippets reutilizables
- `./nginx/well-known/` (ro): archivos `.well-known`
- `nginx_logs`: volumen con nombre para logs

**Depende de**: `synapse` (healthy), `element` (healthy)

### 2.2 Matrix Synapse

**Imagen**: `matrixdotorg/synapse:v1.118.0`

**Rol**: Servidor Matrix. Maneja mensajes, salas, usuarios, federación (deshabilitada), media, etc.

**Puerto expuesto (interno)**: 8008 (HTTP plano)

**Volúmenes**:
- `synapse_data`: volumen con nombre para `/data` (media, logs internos, signing key si se generase dentro)
- `./synapse/homeserver.yaml` (ro): configuración principal
- `./synapse/log.config` (ro): configuración de logging
- `./synapse/signing.key` (ro): clave de firma del servidor

**Depende de**: `postgres` (healthy), `redis` (healthy)

### 2.3 PostgreSQL

**Imagen**: `postgres:16.4-alpine3.20`

**Rol**: Base de datos transaccional para Synapse. Almacena mensajes, salas, usuarios, devices, etc.

**Puerto expuesto**: ninguno (solo interno en `matrix_internal`)

**Volúmenes**:
- `postgres_data`: volumen con nombre para `/var/lib/postgresql/data`
- `./postgres/init.sql` (ro): script de inicialización (extensiones)
- `./postgres/postgresql.conf` (ro): configuración
- `./postgres/pg_hba.conf` (ro): reglas de autenticación

### 2.4 Redis

**Imagen**: `redis:7.4-alpine3.20`

**Rol**: Caché en memoria y broker pubsub para Synapse. Mejora el rendimiento de sync y reduce carga en PostgreSQL.

**Puerto expuesto**: ninguno (solo interno en `matrix_internal`)

**Volúmenes**:
- `redis_data`: volumen con nombre para `/data` (persistencia AOF + RDB)
- `./redis/redis.conf` (ro): configuración

### 2.5 Element Web

**Imagen**: `matrix-element:custom` (construida localmente sobre `vectorim/element-web:v1.11.65`)

**Rol**: Cliente web Matrix servido vía Nginx interno. Los navegadores cargan la SPA desde aquí.

**Puerto expuesto (interno)**: 80 (HTTP)

**Volúmenes**:
- `element_nginx_cache`: volumen con nombre para caché de Nginx interno

**Build**: usa `./element/Dockerfile` que parte de la imagen oficial y copia `config.json` y `nginx.conf` personalizados.

---

## 3. Redes Docker

### 3.1 matrix_frontend

- **Tipo**: bridge
- **Driver**: local
- **Servicios**: `nginx`, `element`, `synapse`
- **Propósito**: servicios accesibles desde la "frontera" del stack. Nginx enruta tráfico entre estos servicios.

### 3.2 matrix_internal

- **Tipo**: bridge
- **Driver**: local
- **Servicios**: `postgres`, `redis`, `synapse`
- **Propósito**: servicios backend. PostgreSQL y Redis NO son accesibles desde Nginx ni desde fuera.

### 3.3 Por qué dos redes

El patrón de dos redes implementa defensa en profundidad:

1. Si un atacante compromete Nginx, no puede llegar a PostgreSQL ni Redis directamente.
2. Synapse está en ambas redes porque necesita tanto servir a Nginx como hablar con PostgreSQL y Redis.
3. PostgreSQL y Redis están aislados: solo Synapse (y los scripts via `docker compose exec`) pueden alcanzarlos.

---

## 4. Volúmenes

### 4.1 Volúmenes con nombre

| Nombre | Servicio | Path en contenedor | Tipo contenido |
|--------|----------|-------------------|----------------|
| `matrix_synapse_data` | synapse | `/data` | Media, logs internos, datos derivados |
| `matrix_postgres_data` | postgres | `/var/lib/postgresql/data` | Base de datos |
| `matrix_redis_data` | redis | `/data` | AOF + RDB snapshots |
| `matrix_element_cache` | element | `/var/cache/nginx` | Caché de Nginx interno |
| `matrix_nginx_logs` | nginx | `/var/log/nginx` | Access + error logs de Nginx |

### 4.2 Bind mounts (archivos de configuración)

| Path host | Path contenedor | Servicio |
|-----------|----------------|----------|
| `./synapse/homeserver.yaml` | `/data/homeserver.yaml` | synapse |
| `./synapse/log.config` | `/data/matrix.home.arpa.log.config` (o `/data/homeserver.log.config` en v2.0.0) | synapse |
| `./synapse/signing.key` | `/data/signing.key` | synapse |
| `./postgres/init.sql` | `/docker-entrypoint-initdb.d/01-init.sql` | postgres |
| `./postgres/postgresql.conf` | `/etc/postgresql/postgresql.conf` | postgres |
| `./postgres/pg_hba.conf` | `/etc/postgresql/pg_hba.conf` | postgres |
| `./redis/redis.conf` | `/usr/local/etc/redis/redis.conf` | redis |
| `./nginx/nginx.conf` | `/etc/nginx/nginx.conf` | nginx |
| `./nginx/conf.d/` | `/etc/nginx/conf.d/` | nginx |
| `./nginx/certs/` | `/etc/nginx/certs/` | nginx |
| `./nginx/snippets/` | `/etc/nginx/snippets/` | nginx |
| `./nginx/well-known/` | `/etc/nginx/well-known/` | nginx |
| `./backups/` | `/backups` (ro) | postgres, synapse |

### 4.3 Por qué volúmenes con nombre en lugar de bind mounts

- **Portabilidad**: los volúmenes con nombre se mueven fácilmente entre hosts (ver scripts de migración).
- **Aislamiento**: Docker gestiona permisos y lifecycle.
- **Performance**: en Windows, los volúmenes con nombre tienen mejor I/O que los bind mounts a filesystem NTFS.
- **Backup consistente**: scripts como `pg_dump` se ejecutan dentro del contenedor sin preocuparse del path del host.

---

## 5. Flujo de una solicitud

### 5.1 Cliente accede a Element Web

```
1. Navegador -> DNS local resuelve element.home.arpa -> 192.168.1.100
2. Navegador -> HTTPS https://element.home.arpa/ -> Host:443
3. Nginx termina TLS, lee server_name=element.home.arpa
4. Nginx -> proxy_pass http://element_backend (element:80)
5. Element (Nginx interno) sirve index.html + assets estáticos
6. Navegador recibe HTML, JS, CSS
7. JS carga config.json, obtiene homeserver URL: https://matrix.home.arpa
```

### 5.2 Cliente se autentica (login)

```
1. Usuario ingresa @user:home.arpa + password en Element
2. Element -> POST https://matrix.home.arpa/_matrix/client/v3/login
3. Nginx termina TLS, lee server_name=matrix.home.arpa
4. Nginx -> proxy_pass http://synapse_backend (synapse:8008)
5. Synapse recibe la request
6. Synapse -> SELECT user FROM users WHERE name='@user:home.arpa'
7. PostgreSQL responde
8. Synapse verifica password hash (bcrypt + pepper)
9. Synapse genera access_token (macaroon firmado con macaroon_secret_key)
10. Synapse -> INSERT INTO access_tokens (...)
11. Redis cachea la sesión
12. Synapse responde 200 + access_token
13. Nginx -> respuesta al cliente
14. Element guarda access_token en localStorage
```

### 5.3 Cliente envía mensaje

```
1. Usuario escribe mensaje en Element
2. Element -> PUT https://matrix.home.arpa/_matrix/client/v3/rooms/!roomId/send/...
3. Nginx -> proxy_pass a Synapse
4. Synapse:
   a. Verifica access_token (Redis cache)
   b. Verifica permisos del usuario en la sala
   c. Asigna ID al evento
   d. Firma el evento con signing.key
   e. INSERT en events table (PostgreSQL)
   f. Publica evento en canal Redis (pubsub)
5. Otros clientes conectados reciben el evento via /sync (long-polling)
6. Synapse responde 200 + event_id
7. Element muestra mensaje en la sala
```

### 5.4 Cliente sincroniza (long polling)

```
1. Element -> GET https://matrix.home.arpa/_matrix/client/v3/sync?timeout=30000
2. Nginx -> proxy_pass a Synapse (proxy_buffering off, timeout 3600s)
3. Synapse mantiene la conexión abierta hasta:
   - Hay nuevos eventos
   - Timeout del cliente (30s)
   - Cierre de conexión
4. Si hay eventos, Synapse responde con delta
5. Element procesa, renderiza, y abre nuevo /sync
```

---

## 6. Flujo de datos persistente

### 6.1 Mensaje

1. Cliente envía mensaje.
2. Synapse lo procesa y firma.
3. Synapse INSERT en PostgreSQL (`events`, `event_json`, `event_edges`, etc.).
4. Synapse notifica via Redis pubsub.
5. Mensaje queda persistente en PostgreSQL.

### 6.2 Media (archivo adjunto)

1. Cliente sube archivo via `POST /_matrix/media/v3/upload`.
2. Synapse guarda en `/data/media/<sha256>` (volumen `matrix_synapse_data`).
3. Synapse INSERT metadata en PostgreSQL (`local_media_repository`).
4. Synapse genera thumbnails (si es imagen) en `/data/media/thumbnail/`.

### 6.3 Usuario

1. Admin ejecuta `register_new_matrix_user`.
2. Synapse INSERT en `users` (PostgreSQL).
3. Hash de password con bcrypt + pepper.

---

## 7. Dependencias entre servicios

### 7.1 Orden de arranque

```
postgres (sin dependencias)  ──┐
                               │
redis (sin dependencias)    ──┤
                               ├──> synapse (depende postgres + redis healthy)
                               │
element (sin dependencias)  ──┤
                               │
                               ├──> nginx (depende synapse + element healthy)
```

Docker Compose maneja este orden con `depends_on` + `condition: service_healthy`.

### 7.2 Healthchecks

| Servicio | Comando healthcheck | Intervalo | Timeout | Retries | Start period |
|----------|---------------------|-----------|---------|---------|--------------|
| postgres | `pg_isready -U synapse_user -d synapse` | 15s | 5s | 5 | 30s |
| redis | `redis-cli -a $REDIS_PASSWORD ping` | 15s | 5s | 5 | 10s |
| synapse | `curl -fSs http://localhost:8008/health` | 30s | 10s | 5 | 60s |
| element | `wget -q --spider http://localhost/` | 30s | 5s | 3 | 10s |
| nginx | `nginx -t && wget -q --spider http://localhost/healthz` | 30s | 10s | 3 | 10s |

---

## 8. Decisiones de diseño

### 8.1 Por qué Nginx en lugar de Traefik o Caddy

- **Control explícito**: Nginx permite configuración granular de cada aspecto (rate limiting, headers, buffering, timeouts).
- **Compatibilidad**: ampliamente soportado, documentación extensa.
- **Performance**: bajo overhead, excelente para serving estático + proxy.
- **Certificados**: para LAN con self-signed, Nginx es más directo que Traefik (que asume Let's Encrypt).

### 8.2 Por qué PostgreSQL en lugar de SQLite

- **Concurrencia**: SQLite bloquea la BD entera en writes; PostgreSQL maneja miles de conexiones concurrentes.
- **Performance**: índices más eficientes, query planner más avanzado.
- **Features**: `pg_trgm` para búsqueda fuzzy, `citext` para case-insensitive.
- **Backup en caliente**: `pg_dump` no bloquea; SQLite requiere pausa.
- **Recomendación oficial de Synapse**: PostgreSQL es lo recomendado para producción.

### 8.3 Por qué Redis en lugar de solo PostgreSQL

- **Caché**: Redis cachea fingerprints de devices, presence, etc. reduce queries a PostgreSQL.
- **Pubsub**: notificaciones entre requests de Synapse (sync long-polling).
- **Performance**: latencia sub-ms para reads cacheados.
- **Opcional pero recomendado**: Synapse funciona sin Redis, pero con peor performance.

### 8.4 Por qué dos redes

- Defensa en profundidad: aislar servicios backend de frontend.
- Si Nginx se compromete, no llega a PostgreSQL/Redis.
- Principio de menor privilegio.

### 8.5 Por qué volúmenes con nombre en lugar de bind mounts

- Portabilidad entre Windows y Linux.
- Performance en Windows (NTFS es lento para muchos archivos pequeños).
- Backup consistente via scripts Docker.

### 8.6 Por qué federación deshabilitada

- LAN aislada: máxima privacidad.
- Reduce superficie de ataque (no hay conexiones entrantes de otros servidores).
- Simplifica configuración (no requiere `.well-known` público, puerto 8448, etc.).
- **v2.0.0**: La federación fue completamente removida (no solo deshabilitada).
- Reversible: ver `docs/03-configuracion.md` sección 8.
- **v2.0.0**: Federation endpoints completamente removidos de Nginx. No existe ruta `/_matrix/federation/` en la configuración.

---

## 9. Escalabilidad

La arquitectura actual es single-node. Para acceso remoto (fuera de la LAN), se recomienda **Tailscale** como método de acceso VPN.

Para escalar:

### 9.1 Vertical (más recursos en el mismo host)

- Aumentar `max_connections` en PostgreSQL.
- Aumentar `cp_max` en Synapse homeserver.yaml.
- Aumentar `maxmemory` en Redis.
- Más RAM/CPU en el host.

### 9.2 Horizontal (múltiples nodos)

Requiere cambios mayores:

- **Workers de Synapse**: separar `synchrotron`, `federation_sender`, `media_repository` en contenedores distintos. Redis coordina.
- **PostgreSQL replicado**: streaming replication con Patroni o stolon.
- **Redis HA**: Redis Sentinel o Redis Cluster.
- **Load balancer**: HAProxy o Nginx frente a múltiples Synapse workers.

Este escenario está fuera del alcance de la versión 2.0.0 pero está documentado como mejora futura en el CHANGELOG.

---

## 10. Modelo de amenazas y mitigaciones

Ver [`05-seguridad.md`](05-seguridad.md) para el análisis completo de amenazas y mitigaciones.

Resumen:

| Amenaza | Mitigación |
|---------|------------|
| Atacante externo desde Internet | Sin exposición pública (solo LAN) |
| Atacante en LAN intenta acceder a BD | pg_hba.conf restringe a red Docker interna |
| Atacante en LAN intenta brute force | Rate limiting en Nginx + fail2ban opcional |
| Compromiso de Nginx | Aislado en red frontend, no llega a BD |
| Compromiso de Synapse | `no-new-privileges`, secretos en .env |
| Robo de backups | Permisos de archivo 600 + recomendación de cifrado |
| Pérdida de datos | Backups diarios + test de restauración |
| Fallo de hardware | Migración + restore en nuevo host |
