# Documento técnico

> Especificación técnica formal del stack Matrix Docker.

---

## 1. Resumen ejecutivo

Este documento describe la arquitectura, componentes, flujos y decisiones técnicas del **Matrix Docker Stack v2.0.0**, un sistema de mensajería basado en Matrix Synapse desplegado mediante Docker Compose para entornos LAN aislados.

El stack integra cinco servicios contenerizados (Synapse, PostgreSQL, Redis, Element Web, Nginx) en una topología de dos redes Docker aisladas, con persistencia de datos mediante volúmenes con nombre, secretos externalizados en `.env`, y procedimientos operativos estandarizados para backup, restauración, actualización y migración.

La configuración está optimizada para pequeñas y medianas organizaciones (20-200 usuarios) que requieren mensajería interna privada sin exposición a Internet, con capacidad de migrar entre Docker Desktop (Windows) y Ubuntu Server sin modificaciones estructurales.

---

## 2. Arquitectura del sistema

### 2.1 Diagrama de componentes

```
┌──────────────────────────────────────────────────────────────────────┐
│                            Red LAN (192.168.x.x)                      │
│                                                                       │
│   Clientes (navegadores Element en PCs/tablets)                      │
│         │                                                             │
│         ▼  HTTPS (443)                                                │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Host Docker (Windows Desktop o Ubuntu Server)                │   │
│  │                                                                │   │
│  │  ┌──────────────────────────────────────────────────────┐    │   │
│  │  │  matrix_frontend (red Docker bridge)                  │    │   │
│  │  │                                                        │    │   │
│  │  │   ┌──────────┐    ┌──────────┐    ┌──────────┐       │    │   │
│  │  │   │  Nginx   │    │ Element  │    │ Synapse  │       │    │   │
│  │  │   │ :80 :443 │    │   :80    │    │  :8008   │       │    │   │
│  │  │   └────┬─────┘    └──────────┘    └────┬─────┘       │    │   │
│  │  │        │                                 │             │    │   │
│  │  └────────┼─────────────────────────────────┼─────────────┘    │   │
│  │           │                                 │                   │   │
│  │  ┌────────▼─────────────────────────────────▼─────────────┐   │   │
│  │  │  matrix_internal (red Docker bridge)                     │   │   │
│  │  │                                                            │   │   │
│  │  │   ┌──────────────┐         ┌──────────────┐             │   │   │
│  │  │   │  PostgreSQL  │         │    Redis     │             │   │   │
│  │  │   │    :5432     │         │    :6379     │             │   │   │
│  │  │   └──────────────┘         └──────────────┘             │   │   │
│  │  └────────────────────────────────────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 Componentes

| Componente | Versión | Rol | Recursos default |
|------------|---------|-----|-------------------|
| Nginx | 1.27.2-alpine | Reverse proxy, TLS termination | 64 MB RAM |
| Element Web | v1.11.65 | Cliente web SPA | 64 MB RAM |
| Synapse | v1.118.0 | Servidor Matrix | 2 GB RAM |
| PostgreSQL | 16.4-alpine | Base de datos | 1 GB RAM |
| Redis | 7.4-alpine | Caché y pubsub | 512 MB RAM |

### 2.3 Redes Docker

- **matrix_frontend**: bridge, contiene Nginx + Element + Synapse. Synapse pertenece también a `matrix_internal`.
- **matrix_internal**: bridge, contiene PostgreSQL + Redis + Synapse. Aislada de la frontera.

### 2.4 Volúmenes

| Volumen | Servicio | Path en contenedor | Tipo datos |
|---------|----------|-------------------|------------|
| `matrix_synapse_data` | synapse | `/data` | Media, logs, datos internos |
| `matrix_postgres_data` | postgres | `/var/lib/postgresql/data` | Base de datos |
| `matrix_redis_data` | redis | `/data` | AOF + RDB |
| `matrix_element_cache` | element | `/var/cache/nginx` | Caché Nginx interno |
| `matrix_nginx_logs` | nginx | `/var/log/nginx` | Access + error logs |

### 2.5 Puertos

| Puerto host | Servicio | Puerto contenedor | Protocolo | Acceso |
|-------------|----------|-------------------|-----------|--------|
| 80 | nginx | 80 | TCP | LAN |
| 443 | nginx | 443 | TCP | LAN |
| - | postgres | 5432 | TCP | Solo interno |
| - | redis | 6379 | TCP | Solo interno |
| - | synapse | 8008 | TCP | Solo interno |
| - | element | 80 | TCP | Solo interno |

---

## 3. Servicios detallados

### 3.1 Nginx

**Función**: único punto de entrada desde LAN. Termina TLS, aplica seguridad, enruta a Synapse o Element según Host header.

**Configuración**:
- TLS 1.2/1.3 con ciphersuites modernas.
- HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy.
- Rate limiting por IP (10 req/s general, 2 req/s auth).
- Buffering off para `/sync` (long-polling).
- Catch-all server que rechaza dominios no reconocidos.

**Virtual hosts**:
- `matrix.home.arpa` → proxy a `synapse:8008`
- `element.home.arpa` → proxy a `element:80`

**Certificados**: auto-firmados generados por CA local (10 años validez CA, 1 año certs).

### 3.2 Synapse

**Función**: servidor Matrix. Maneja protocolo Matrix, mensajes, salas, usuarios, dispositivos, media, cifrado E2EE (delegado a clientes).

**Configuración clave**:
- Sin federación (`federation.enabled: false`).
- Sin registro público (`enable_registration: false`).
- PostgreSQL como DB (no SQLite).
- Redis para caché y pubsub.
- SMTP para notificaciones.
- Rate limiting agresivo para auth.
- Política de contraseñas fuerte.

**Signing key**: archivo `synapse/signing.key`, permisos 600, formato `ed25519 <key_id> <base64_seed>`.

### 3.3 PostgreSQL

**Función**: almacenamiento persistente de mensajes, salas, usuarios, dispositivos, eventos.

**Configuración optimizada para Synapse**:
- `shared_buffers`: 25% RAM dedicada.
- `effective_cache_size`: 50-75% RAM total.
- `work_mem`: 16-64 MB.
- `autovacuum` agresivo.
- `wal_buffers`: 16 MB.
- Extensiones: `citext`, `pg_trgm`.

**Seguridad**:
- `pg_hba.conf` restringe a redes Docker internas.
- `scram-sha-256` para auth.
- Sin SSL interno (tráfico entre contenedores).

### 3.4 Redis

**Función**: caché en memoria + pubsub para Synapse.

**Configuración**:
- Contraseña obligatoria.
- Comandos peligrosos deshabilitados.
- `maxmemory` definido, política `allkeys-lru`.
- Persistencia AOF (`appendfsync everysec`) + RDB.
- `appendfsync everysec` para balance durabilidad/performance.

### 3.5 Element Web

**Función**: cliente web Matrix servido via Nginx interno.

**Construcción**: imagen Docker custom sobre `vectorim/element-web:v1.11.65` con `config.json` preconfigurado.

**Configuración**:
- `default_server_config`: apunta a `https://matrix.home.arpa`.
- Features selectivas activadas/deshabilitadas.
- Branding personalizable.
- Tema default: dark.

---

## 4. Flujo de datos

### 4.1 Secuencia de login

```
Cliente ─── POST /_matrix/client/v3/login ───► Nginx ───► Synapse
                                                          │
                                                          ▼
                                          ┌──────────────────────────┐
                                          │ Synapse:                 │
                                          │ 1. Lookup user en PG     │
                                          │ 2. Verify bcrypt+pepper  │
                                          │ 3. Generate macaroon     │
                                          │ 4. INSERT access_token   │
                                          │ 5. Cache session en Redis│
                                          └──────────────────────────┘
                                                          │
Cliente ◄─── 200 {access_token} ─── Nginx ◄───────────────┘
```

### 4.2 Secuencia de mensaje

```
Cliente ─── PUT /_matrix/client/v3/rooms/!roomId/send/... ───► Nginx ───► Synapse
                                                                          │
                                                                          ▼
                                          ┌──────────────────────────────┐
                                          │ Synapse:                     │
                                          │ 1. Verify access_token       │
                                          │ 2. Verify membership         │
                                          │ 3. Assign event_id           │
                                          │ 4. Sign event (signing.key)  │
                                          │ 5. INSERT events en PG       │
                                          │ 6. PUBLISH en Redis pubsub   │
                                          └──────────────────────────────┘
                                                                          │
Otros clientes ◄── /sync long-poll ─── Nginx ◄── Synapse ◄───────────────┘
```

### 4.3 Persistencia

- **Mensajes**: tabla `events` en PostgreSQL.
- **Media**: volumen `matrix_synapse_data` (`/data/media`).
- **Usuarios**: tabla `users` en PostgreSQL (con hash bcrypt + pepper).
- **Sesiones**: tabla `access_tokens` en PostgreSQL + caché Redis.
- **Caché**: Redis (presencia, fingerprints, etc.).

---

## 5. Decisiones técnicas

### 5.1 Por qué PostgreSQL sobre SQLite

| Criterio | SQLite | PostgreSQL |
|----------|--------|------------|
| Concurrencia | Bloqueo a nivel BD | MVCC, miles de conexiones |
| Performance | Limitada | Optimizer avanzado |
| Features | Básicas | pg_trgm, citext, JSONB |
| Backup en caliente | Requiere pausa | pg_dump sin bloqueo |
| Recomendación Synapse | Solo testing | Producción |

### 5.2 Por qué Nginx sobre Traefik/Caddy

| Criterio | Nginx | Traefik | Caddy |
|----------|-------|---------|-------|
| Configuración | Explícita, granular | Labels en compose | Caddyfile simple |
| Performance | Excelente | Buena | Buena |
| Compatibilidad | Universal | Docker nativo | Moderno |
| Certs auto-firmados | Directo | Asume Let's Encrypt | Asume Let's Encrypt |
| Madurez | 20+ años | 10 años | 8 años |
| Documentación | Muy extensa | Buena | Media |

Para LAN con self-signed, Nginx es más directo.

### 5.3 Por qué dos redes Docker

Defensa en profundidad:

- Si Nginx se compromete, no puede acceder a PostgreSQL/Redis.
- Si Synapse se compromete, solo puede llegar a PostgreSQL y Redis (ya las necesita).
- PostgreSQL y Redis están totalmente aislados de la frontera.

### 5.4 Por qué volúmenes con nombre sobre bind mounts

| Criterio | Volúmenes con nombre | Bind mounts |
|----------|---------------------|-------------|
| Portabilidad Windows/Linux | Excelente | Problemática (paths) |
| Performance en Windows | Buena | Pobre (NTFS) |
| Backup | Vía `docker run` + tar | Directo |
| Permisos | Docker gestiona | Manual |
| Migración | Export/import consistente | Copia manual |

### 5.5 Por qué federación deshabilitada

- LAN aislada: no hay necesidad de federar.
- **v2.0.0**: La federación fue completamente removida del proyecto.
- Reduce superficie de ataque (sin conexiones entrantes externas).
- Simplifica configuración (sin `.well-known` público, sin puerto 8448).
- Cumple principio de menor privilegio.

### 5.6 Por qué versiones pinned

- **Reproducibilidad**: mismo comportamiento entre deploys.
- **Auditable**: se sabe exactamente qué versión se ejecuta.
- **Control**: actualizaciones son deliberadas, no sorpresivas.
- **Rollback**: fácil revertir a versión anterior.

---

## 6. Modelos de despliegue

### 6.1 Escenario A: Docker Desktop Windows (desarrollo/pruebas)

- Host: PC Windows 10/11.
- Docker Desktop con WSL2.
- Stack accesible desde la LAN del PC.
- Volúmenes en filesystem WSL2.

### 6.2 Escenario B: Ubuntu Server (producción)

- Host: servidor dedicado o VM Ubuntu 22.04/24.04 LTS.
- Docker Engine nativo.
- Stack accesible desde LAN corporativa.
- systemd service para auto-arranque.
- UFW firewall.
- Backups automáticos via cron.

### 6.3 Escenario C: Migración A → B

Procedimiento documentado en [`08-migracion-windows-ubuntu.md`](08-migracion-windows-ubuntu.md):
1. Exportar volúmenes en Windows.
2. Transferir tarball a Ubuntu.
3. Importar volúmenes en Ubuntu.
4. Ajustar `.env` y dominios si cambiaron.
5. Iniciar en Ubuntu.

### 6.4 Escenario D: Disaster recovery

Procedimiento documentado en [`10-restauracion.md`](10-restauracion.md):
1. Aprovisionar nuevo host Ubuntu.
2. Instalar Docker + proyecto.
3. Restaurar volúmenes desde backup.
4. Restaurar BD desde backup.
5. Verificar funcionalidad.

---

## 7. Escenarios de mantenimiento

### 7.1 Actualización rutinaria

1. Backup previo.
2. `update-images.sh` (descargar).
3. `update-containers.sh` (aplicar).
4. Verificar 24h.

### 7.2 Cambio de dominios

1. Backup previo.
2. Editar `.env`, `homeserver.yaml`, `config.json`, `nginx/conf.d/*`.
3. Regenerar certs.
4. Reconstruir Element.
5. Reiniciar stack.

### 7.3 Rotación de signing key

1. Generar nueva key.
2. Agregar vieja a `old_signing_keys` en `homeserver.yaml`.
3. Reemplazar `synapse/signing.key`.
4. Reiniciar Synapse.
5. Verificar que clientes reconectan.

### 7.4 Migración de PostgreSQL (major version)

1. Backup completo.
2. Detener stack.
3. Eliminar volumen PostgreSQL.
4. Cambiar tag en `docker-compose.yml`.
5. Iniciar solo PostgreSQL.
6. Restaurar BD desde backup.
7. Iniciar stack completo.

---

## 8. Escenarios de recuperación

### 8.1 Pérdida de datos (RPO)

- Backup diario → RPO máximo 24h.
- Para RPO menor: replicación streaming (no incluido en 1.0.0).

### 8.2 Tiempo de recuperación (RTO)

| Escenario | RTO estimado |
|-----------|--------------|
| Reinicio de servicio | 2-5 min |
| Restore BD desde backup local | 10-15 min |
| Restore BD desde backup offsite | 30-60 min |
| Migración a nuevo host | 2-3 horas |

### 8.3 Fallo de hardware

1. Aprovisionar nuevo host.
2. Instalar Docker + proyecto + **Tailscale**.
3. Restaurar desde último backup offsite.
4. Verificar.
5. Actualizar DNS si IP cambió.
6. Verificar acceso remoto via Tailscale.

### 8.4 Compromiso de credenciales

1. Identificar alcance.
2. Desactivar cuentas comprometidas.
3. Resetear passwords afectadas.
4. Rotar secretos del stack.
5. Invalidar todas las sesiones.
6. Auditar logs.
7. Documentar incidente.

### 8.5 Fallo de BD corrupta

1. Detener Synapse.
2. Intentar `pg_resetwal` (si WAL corrupto).
3. Si no funciona, restaurar desde backup.
4. Reiniciar.

---

## 9. Métricas y monitoreo

### 9.1 Métricas técnicas

- **CPU/MEM/Disco** por contenedor (`docker stats`).
- **Conexiones PostgreSQL** (`pg_stat_activity`).
- **Hit rate Redis** (`INFO stats`).
- **Requests por segundo Nginx** (access log).
- **Latencia Synapse** (`request_times` en logs).

### 9.2 Métricas de negocio

- **Usuarios activos diarios** (DAU).
- **Mensajes por día**.
- **Salas activas**.
- **Media subida**.

### 9.3 Alertas recomendadas

- Disco >80%.
- Alguna servicio no healthy.
- Backup no generado en 25h.
- Errores en logs >threshold.
- Conexiones PostgreSQL >80% max.

---

## 10. Limitaciones conocidas

1. **Single-node**: sin HA. Caída del host = servicio caído.
2. **Sin push notifications móviles** (requiere Sygnal).
3. **Federación deshabilitada** por defecto.
4. **TLS con CA self-signed** (requiere import en clientes).
5. **Sin OIDC/SAML/LDAP activo** (configuración existe pero comentada).
6. **Sin cifrado de backups** automático (debe hacerse manualmente).
7. **Sin auto-actualización** (deliberado, requiere procedimiento).
8. **Sin WAF** en Nginx.
9. **Máximo ~200 usuarios** con config por defecto.
10. **Sin monitorización Prometheus/Grafana** integrada.

---

## 11. Roadmap futuro

### 11.1 Mejoras planificadas

- **Workers de Synapse** para escalar horizontalmente.
- **Monitoring stack**: Prometheus + Grafana.
- **Logs centralizados**: Loki + Promtail.
- **OIDC integration** con Keycloak/Authentik.
- **Backup cifrado automático** con age o gpg.
- **Snapshots programados** con restic.
- **Sygnal** para push notifications.
- **Element Call** self-hosted para videollamadas grandes.
- **Bridges** a Signal/Telegram (opcional).

### 11.2 Versiones futuras

- **v1.1.0**: integración monitoring + alerts.
- **v1.2.0**: workers Synapse.
- **v1.3.0**: OIDC opcional.
- **v3.0.0**: workers Synapse + alta disponibilidad.

---

## 12. Referencias

- [Matrix Specification](https://spec.matrix.org/)
- [Synapse Documentation](https://matrix-org.github.io/synapse/latest/)
- [Element Web](https://github.com/element-hq/element-web)
- [PostgreSQL 16 Docs](https://www.postgresql.org/docs/16/)
- [Redis 7 Docs](https://redis.io/docs/latest/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)
- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [NIST SP 800-190](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

---

## 13. Glosario

- **Homeserver**: servidor Matrix donde residen las cuentas de usuarios.
- **Federación**: capacidad de servidores Matrix distintos de comunicarse.
- **E2EE**: cifrado de extremo a extremo.
- **Signing key**: clave privada que firma los eventos del servidor.
- **Macaroon**: token de autorización bearer usado por Synapse.
- **Worker**: proceso separado de Synapse para una función específica.
- **PUBSUB**: patrón publish/subscribe para notificaciones entre procesos.
- **AOF**: Append Only File, formato de persistencia de Redis.
- **RDB**: Redis Database, formato de snapshot de Redis.
- **VACUUM**: operación de PostgreSQL que reclama espacio.
- **SCRAM**: Salted Challenge Response Authentication Mechanism.
- **HSTS**: HTTP Strict Transport Security.
- **CSP**: Content Security Policy.
- **MFA**: Multi-Factor Authentication.
- **RPO**: Recovery Point Objective.
- **RTO**: Recovery Time Objective.
- **DR**: Disaster Recovery.
- **DPIA**: Data Protection Impact Assessment (GDPR).
