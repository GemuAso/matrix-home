# Changelog

Todos los cambios notables de este proyecto se documentarán en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/spec/v2.0.0.html).

---

## [4.0.0] - 2026-07-05

### Cambio mayor: Instalación de un solo comando

La instalación ahora requiere un único comando: `./install.sh`. No se necesita editar manualmente ningún archivo. Todos los secretos se generan criptográficamente con `openssl rand`.

### Instalador automático (`install.sh`)

- **Nuevo `install.sh`** en la raíz del proyecto: instalador principal que realiza 10 pasos secuenciales.
- **Nuevo `lib/install-utils.sh`**: biblioteca modular de funciones reutilizables (detección de red, validación de IP, generación de secretos, validación de sistema).
- **Nuevo `scripts/linux/verify.sh`**: verificación de salud de todos los servicios con diagnóstico de errores.
- **Paso 1**: Valida sistema operativo (Ubuntu 20.04+, Debian 11+) y arquitectura (x86_64, ARM64).
- **Paso 2**: Valida recursos (mínimo 5 GB disco, 2 GB RAM).
- **Paso 3**: Verifica e instala dependencias automáticamente (Docker, Compose, OpenSSL, curl, git, iproute2) via `apt-get` si hay permisos de root.
- **Paso 4**: Detecta IP LAN automáticamente con `ip route` (sin servicios HTTP externos). Detecta Tailscale si está instalado. Permite al usuario elegir entre LAN y Tailscale.
- **Paso 5**: Genera `.env` automáticamente con 7 secretos únicos generados con `openssl rand`. Cero valores manuales. Cero valores `cambiar_por`.
- **Paso 6**: Genera signing key de Synapse (método oficial o fallback) y certificados TLS.
- **Paso 7**: Construye imagen de Element Web.
- **Paso 8**: Valida `docker-compose.yml` y ejecuta `docker compose up -d`.
- **Paso 9**: Verifica que los 5 servicios estén healthy (con timeout y diagnóstico).
- **Paso 10**: Muestra resumen final con IPs, accesos, instrucciones DNS y comandos útiles.

### Generación automática de secretos

- **7 secretos generados criptográficamente**: `POSTGRES_PASSWORD` (base64), `REDIS_PASSWORD` (hex 64), `SYNAPSE_REGISTRATION_SHARED_SECRET` (hex 64), `SYNAPSE_MACAROON_SECRET_KEY` (hex 64), `SYNAPSE_ADMIN_API_TOKEN` (hex 64), `SYNAPSE_FORM_SECRET` (hex 64), `SYNAPSE_PASSWORD_PEPPER` (hex 64).
- **Sin valores de ejemplo**: `.env.example` ahora usa `__GENERATE__` como marcador. No existe ningún valor del tipo `cambiar_por...` en el proyecto.
- **Sin intervención manual**: el usuario no necesita editar ningún archivo de configuración.

### Detección automática de red

- **`detect_lan_ip()`**: usa `ip route show default` + `ip addr` para obtener la IP LAN. Sin dependencias externas (no usa ifconfig.me ni similares).
- **`detect_tailscale_ip()`**: usa `tailscale ip -4` si Tailscale está instalado.
- **`validate_ip()`**: verifica que la IP sea IPv4 válida, privada (RFC 1918), no loopback, no multicast, no reservada, no 0.0.0.0.
- **`detect_lan_cidr()`**: deriva el CIDR automáticamente a partir de la IP detectada.
- Si el usuario rechaza la IP detectada, permite ingresar una manualmente con validación en bucle.

### Compatibilidad con Raspberry Pi

- Detección de arquitectura: `check_architecture()` soporta x86_64 y ARM64 (aarch64).
- Las imágenes Docker (`postgres:16.4-alpine3.20`, `redis:7.4-alpine3.20`, `matrixdotorg/synapse:v1.118.0`, `nginx:1.27.2-alpine3.20`) todas tienen soporte multi-arquitectura.

### Instalación de dependencias automática

- Si falta alguna dependencia (Docker, Compose plugin, OpenSSL, curl, git, iproute2), `install.sh` las instala automáticamente con `apt-get install` si se ejecuta con `sudo`.
- Verifica que Docker daemon esté corriendo; si no, ejecuta `systemctl enable --now docker`.

### Seguridad

- `.env` generado con `chmod 600`.
- Permisos de signing key: `chmod 600`.
- Permisos de claves de certificados: `chmod 600`.
- Todos los secretos generados con `openssl rand` (fuente de entropía del kernel).

### Cambios en archivos existentes

- **`.env.example`**: eliminados todos los valores de ejemplo. Ahora usa `__GENERATE__` como marcador.
- **`setup.sh` (Linux)**: simplificado. Ahora es un complemento de `install.sh` (genera archivos faltantes sin levantar el stack). Apunta a `install.sh` si no hay `.env`.
- **`_common.sh` (Linux)**: versión actualizada a 4.0.0.
- **`docker-compose.yml`**: versión 4.0.0.
- **`.gitignore`**: agregado `*.srl` y `*.ext` a la lista de archivos de certificados ignorados.

### Flujo de instalación resultante

```
git clone <repo> matrix-docker && cd matrix-docker
sudo ./install.sh
docker compose exec synapse register_new_matrix_user -c http://localhost:8008 -a admin
```

---

## [3.0.0] - 2026-07-05

### Cambio mayor: Instalación completamente automatizada

La instalación ahora requiere únicamente: clonar, configurar `.env`, ejecutar `setup.sh`, y `docker compose up -d`. Ningún archivo adicional debe crearse manualmente. Todas las claves privadas se generan automáticamente y nunca se almacenan en Git.

### Automatización de claves y certificados

- **Generación automática de certificados TLS**: Si no existen `nginx/certs/ca.key`, `ca.crt`, `default.key`, `default.crt` (y los certificados por servicio), se generan automáticamente durante `setup.sh` usando OpenSSL.
- **SAN unificado**: Todos los certificados generados incluyen `matrix.home.arpa`, `element.home.arpa`, `localhost` y `127.0.0.1` en sus Subject Alternative Names. Esto permite que cualquier certificado funcione para cualquier dominio del stack.
- **Generación automática de Signing Key de Synapse**: Si no existe `synapse/signing.key`, se genera automáticamente usando el método oficial de Matrix Synapse (`generate_signing_key`) cuando la imagen Docker está disponible, o mediante generación manual como fallback.
- **Ninguna clave privada en Git**: Todos los archivos `.key`, `.crt`, `.pem`, `.csr` y `signing.key` están en `.gitignore`. Al clonar el repositorio no se descargan; el script de setup los crea.

### Mejoras en scripts de instalación

- **`setup.sh` (Linux)** reescrito con 8 pasos de validación:
  1. Verificación de dependencias (Docker daemon corriendo, Docker Compose, OpenSSL).
  2. Verificación/creación de `.env` desde `.env.example`.
  3. Validación de variables obligatorias (13 variables requeridas).
  4. Detección de valores de ejemplo en contraseñas y secretos.
  5. Verificación de permisos de escritura en carpetas críticas.
  6. Verificación de disponibilidad de puertos 80 y 443.
  7. Generación automática de signing key y certificados TLS.
  8. Validación final, build de Element, y verificación de `docker-compose.yml`.
- **`setup.ps1` (Windows)** reescrito con las mismas 8 validaciones.
- **`_common.sh` (Linux)** ampliado con nuevas funciones:
  - `validate_required_vars()`: verifica 13 variables obligatorias.
  - `check_port()`: verifica que un puerto no esté en uso.
  - `check_all_ports()`: verifica puertos HTTP y HTTPS.
  - `check_permissions()`: verifica permisos de escritura en carpetas críticas.
  - `check_critical_files()`: verifica existencia de .env, signing.key y certificados.
  - `check_docker()` ahora también verifica que el daemon esté corriendo.
  - `validate_env()` ampliado para detectar 6 variables de ejemplo (antes solo 3).
- **`_common.ps1` (Windows)** ampliado con las mismas funciones equivalentes.
- **`generate-certs.sh` (Linux)** reescrito: todos los certificados incluyen SAN unificado con los 3 dominios. El certificado `default` ahora se genera con la CA (antes era self-signed independiente).
- **`generate-certs.ps1` (Windows)** reescrito con los mismos cambios.

### Arquitectura

- **Red `matrix_internal` con `internal: true`**: La red de backend ahora es completamente interna, sin salida a Internet. PostgreSQL y Redis no pueden acceder a la red externa bajo ninguna circunstancia. Synapse, que está en ambas redes, usa `matrix_frontend` para SMTP.
- **Flujo de instalación simplificado**: `git clone → cp .env.example .env → editar .env → ./setup.sh → docker compose up -d`. No se requiere ningún paso manual adicional.

### Validaciones pre-arranque

El script de setup ahora detiene la instalación si se detecta cualquiera de estos problemas:
- `.env` no existe y no hay `.env.example`
- Variables obligatorias faltantes en `.env` (13 variables)
- Puertos 80/443 en uso por otro proceso
- Sin permisos de escritura en `nginx/certs/`, `synapse/` o `backups/`
- Docker daemon no está corriendo
- Falta OpenSSL en el PATH
- Los certificados o la signing key no se generan correctamente


## [2.0.0] - 2026-07-04

### Cambio mayor: Dominio interno
- **Cambio de dominio**: `example.com` → `home.arpa` (dominio reservado para redes privadas segun RFC 6762)
- Todas las configuraciones, certificados, scripts y documentacion actualizadas al nuevo dominio

### Seguridad
- **Gestion segura de secretos**: Todos los secretos eliminados de archivos de configuracion
  - `homeserver.yaml` convertido en template (`homeserver.yaml.template`) con variables de entorno inyectadas via `envsubst`
  - `redis.conf` convertido en template (`redis.conf.template`) con password inyectado via `sed`
  - Nuevas variables `.env`: `SYNAPSE_FORM_SECRET`, `SYNAPSE_PASSWORD_PEPPER`, `ELEMENT_URL`
  - Entrypoint wrappers creados para Synapse y Redis que generan configs desde templates al inicio
- **Federacion completamente removida**: Eliminados endpoints, configuraciones y recursos de federacion de todos los archivos
- **API key expuesta removida**: Eliminada `map_style_url` con API key publica de config.json de Element
- **URL de tracking removida**: Eliminada `hydration_url` que apuntaba a develop.element.io

### Arquitectura
- **Certificados con nombres fijos**: `matrix.crt`/`matrix.key` y `element.crt`/`element.key` (independientes del dominio)
- **Federation endpoints removidos de Nginx**: No existe ruta `/_matrix/federation/` en la configuracion
- **Tailscale como metodo de acceso remoto**: Documentacion actualizada para acceso VPN

### Correcciones
- Corregido typo en `.env.example`: `SMTP_THROTTLE_PERHour` → `SMTP_THROTTLE_PERHOUR`
- Corregido `form_secret` que tenia el mismo valor que `SYNAPSE_ADMIN_API_TOKEN` (copy-paste)
- Eliminado bloque `listeners_admin_api` no estandar en homeserver.yaml
- Eliminadas lineas duplicadas de `log_config` y `signing_key_path` en homeserver.yaml
- Removidos `rc_federation`, `federation_rr_timeout`, `federation_verify_certificates`, `allow_public_rooms_over_federation`
- `URL previews` deshabilitado por defecto en Element (servidor LAN sin salida a Internet)

### Nuevos archivos
- `synapse/homeserver.yaml.template` - Template con variables de entorno
- `synapse/entrypoint.sh` - Wrapper que genera homeserver.yaml desde template
- `redis/redis.conf.template` - Template con placeholder de password
- `redis/entrypoint.sh` - Wrapper que genera redis.conf desde template
- `IMPLEMENTATION_REPORT.md` - Reporte completo de la auditoria y cambios


## [1.0.0] - 2026-07-04

### Resumen

Versión inicial del stack Matrix Synapse + PostgreSQL + Redis + Element Web + Nginx, listo para producción en LAN.

### Componentes incluidos

| Componente | Versión pinned | Propósito |
|------------|----------------|-----------|
| Matrix Synapse | `v1.118.0` | Servidor de mensajería |
| PostgreSQL | `16.4-alpine3.20` | Base de datos transaccional |
| Redis | `7.4-alpine3.20` | Caché y pubsub |
| Element Web | `v1.11.65` | Cliente web |
| Nginx | `1.27.2-alpine3.20` | Reverse proxy + TLS |

### Decisiones técnicas

- **PostgreSQL en lugar de SQLite**: SQLite no soporta concurrencia real y Synapse lo desaconseja para producción. PostgreSQL 16 ofrece mejoras de rendimiento, extensions (`citext`, `pg_trgm`) y configuración fino-granular.
- **Redis 7 con AOF+RDB**: AOF (`appendfsync everysec`) garantiza durabilidad con bajo overhead; RDB como backup rápido. Política `allkeys-lru` para caché.
- **Nginx en lugar de Traefik/Caddy**: el usuario eligió Nginx tradicional por máxima compatibilidad y control explícito. TLS terminado en Nginx con certs auto-firmados generados por CA local.
- **Docker Compose v2 (Specification)**: sin declaración `version:` obsoleta; se usa `name:` para el proyecto.
- **Dos redes Docker aisladas**: `matrix_internal` (PostgreSQL, Redis) y `matrix_frontend` (Nginx, Element, Synapse). PostgreSQL y Redis no se publican al host.
- **Volúmenes con nombre** en lugar de bind mounts para datos persistentes: mejor portabilidad y manejo por Docker.
- **Federación deshabilitada**: máxima privacidad para LAN. `.well-known/matrix/server.json` se sirve para compatibilidad con clientes. (En v2.0.0 la federación fue completamente removida).
- **Healthchecks en todos los servicios**: permite `depends_on` con `condition: service_healthy` para arranque ordenado.
- **`no-new-privileges`** en todos los contenedores: previene escalada de privilegios.
- **Logging `json-file` con rotación**: cada servicio define `max-size` y `max-file` para evitar llenar disco.

### Funcionalidades

#### Core
- Stack completo en `docker-compose.yml` con 5 servicios, 2 redes, 5 volúmenes.
- Healthchecks para PostgreSQL (`pg_isready`), Redis (`redis-cli ping`), Synapse (`/health` HTTP), Element (wget), Nginx (`nginx -t`).
- `depends_on` con `condition: service_healthy` para arranque ordenado.
- Restart policy `unless-stopped` en todos los servicios.

#### Seguridad
- `.env` externaliza todos los secretos.
- `pg_hba.conf` restringe conexiones a rangos Docker internos.
- `redis.conf` con contraseña y comandos peligrosos renombrados/deshabilitados.
- Nginx con headers HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy.
- Rate limiting por IP y por endpoint en Nginx.
- Certificados auto-firmados con CA local importable en clientes.

#### Operaciones
- 16 scripts Linux (.sh) y 16 scripts Windows (.ps1) para administración.
- Script `setup.sh/ps1` que orquesta el setup inicial completo.
- Scripts de backup con dump PostgreSQL + tar de configs, con rotación automática.
- Script de restauración con backup preventivo y confirmación.
- Script de migración de volúmenes Windows → Ubuntu.

#### Documentación
- README.md principal con tabla de contenidos, arquitectura, instalación.
- 15 documentos en `docs/` cubriendo todos los aspectos operativos.
- Diagramas Mermaid en `docs/diagrams/mermaid-diagrams.md`.
- SPECIFICATIONS.md con requisitos funcionales y no funcionales.
- ADMIN_GUIDE.md con tareas diarias del administrador.

### Mejoras futuras (no incluidas en 1.0.0)

- **Workers de Synapse**: separar `federation_sender`, `media_repository`, `synchrotron` en contenedores distintos para escalar horizontalmente.
- **Monitoring stack**: integrar Prometheus + Grafana para métricas.
- **Logs centralizados**: Loki + Promtail para agregación.
- **OIDC/SAML**: integración con Keycloak o Authentik para SSO empresarial.
- **Cifrado de backups**: usar `gpg` o `age` para cifrar backups antes de almacenarlos fuera del host.
- **Snapshots programados de volúmenes**: usar `restic` o `borg` para snapshots incrementales.
- **Alta disponibilidad**:架构 multi-nodo con PostgreSQL replicado y Synapse workers.
- **Migración a certs públicos**: cuando el servidor se exponga a Internet, integrar Let's Encrypt via certbot.
- **Federación opcional**: flag en `.env` para habilitar federación sin reescribir config.
- **Mobile apps**: guía para configurar Element iOS/Android apuntando al servidor.
- **Bridges**: integración con puentes a Signal, Telegram, WhatsApp (opcional).
- **Audit log**: hook para enviar eventos críticos a SIEM externo.

### Cambios pendientes de revisión

- Validar funcionamiento de `register_new_matrix_user` con shared secret en Synapse 1.118.
- Probar migración de volúmenes en Docker Desktop con WSL2 backend.
- Verificar que Element Web `v1.11.65` sea compatible con Synapse `v1.118.0` (matriz de compatibilidad).

---

## Convenciones de versionado

- **MAJOR**: cambios incompatibles en la API/estructura del proyecto.
- **MINOR**: nuevas funcionalidades backward-compatible.
- **PATCH**: fixes backward-compatible.

---

## Enlaces

- [Matrix Specification](https://spec.matrix.org/)
- [Synapse Documentation](https://matrix-org.github.io/synapse/latest/)
- [Element Web](https://github.com/element-hq/element-web)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)
- [PostgreSQL 16 Docs](https://www.postgresql.org/docs/16/)
- [Redis 7 Docs](https://redis.io/docs/latest/)
- [Nginx Docs](https://nginx.org/en/docs/)
