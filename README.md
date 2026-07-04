# Matrix Docker Stack

> Despliegue completo de **Matrix Synapse** + **PostgreSQL** + **Redis** + **Element Web** + **Nginx** mediante Docker Compose, listo para producción en entornos **LAN 100%**.
>
> **v3.0.0**: Instalación completamente automatizada. Clona, configura `.env`, ejecuta `setup.sh`, y listo. Ninguna clave privada se almacena en Git; todo se genera automáticamente durante la instalación.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Synapse v1.118.0](https://img.shields.io/badge/Synapse-v1.118.0-green.svg)](https://github.com/element-hq/synapse)
[![PostgreSQL 16.4](https://img.shields.io/badge/PostgreSQL-16.4-blue.svg)](https://www.postgresql.org/)
[![Redis 7.4](https://img.shields.io/badge/Redis-7.4-red.svg)](https://redis.io/)
[![Nginx 1.27](https://img.shields.io/badge/Nginx-1.27-green.svg)](https://nginx.org/)

---

## Tabla de contenidos

- [Descripción](#descripción)
- [Características principales](#características-principales)
- [Arquitectura](#arquitectura)
- [Requisitos del sistema](#requisitos-del-sistema)
- [Instalación rápida](#instalación-rápida)
- [Uso diario](#uso-diario)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Documentación completa](#documentación-completa)
- [Migración Windows → Ubuntu](#migración-windows--ubuntu)
- [Seguridad](#seguridad)
- [Soporte y contribución](#soporte-y-contribución)
- [Licencia](#licencia)

---

## Descripción

Este proyecto permite desplegar un servidor de mensajería **Matrix Synapse** completamente funcional en una red de área local (LAN), sin exponer servicios a Internet pública (para acceso remoto, usar **Tailscale** como VPN). Está diseñado para equipos u organizaciones que requieren comunicaciones internas privadas, seguras y autosuficientes, manteniendo la flexibilidad de migrar entre entornos (Docker Desktop en Windows → Ubuntu Server) sin modificaciones estructurales.

El stack incluye todos los componentes necesarios para una instancia productiva: el servidor **Synapse** como núcleo de mensajería, **PostgreSQL 16** como base de datos transaccional de alto rendimiento (en lugar de SQLite, inadecuado para producción), **Redis 7** como capa de caché y pub/sub interno, el cliente web **Element Web** para acceso desde navegadores, y **Nginx** como reverse proxy que termina TLS y aplica políticas de seguridad.

La configuración está preparada para funcionar inicialmente en **Docker Desktop sobre Windows 10/11**, y puede migrarse sin alteraciones a un **Ubuntu Server 20.04/22.04/24.04 LTS** mediante los scripts de migración incluidos. Todos los secretos están externalizados en un archivo `.env`, los volúmenes son persistentes, los healthchecks verifican la salud de cada servicio, y los logs siguen una política de rotación configurable.

---

## Características principales

- **Stack completo en Docker Compose v2**: orquestación declarativa con redes, volúmenes, restart policies y healthchecks por servicio.
- **Aislamiento LAN 100%**: red `matrix_internal` con `internal: true` (sin salida a Internet); solo Nginx expone puertos a la LAN.
- **Sin SQLite**: PostgreSQL 16 con configuración tuneada (shared_buffers, autovacuum, pg_trgm, citext).
- **Redis 7 con persistencia AOF+RDB**: caché en memoria y pubsub para Synapse.
- **TLS auto-firmado con CA local y SAN unificado**: certificados generados automáticamente por `setup.sh`, incluyen `matrix.home.arpa`, `element.home.arpa`, `localhost` y `127.0.0.1` en todos los certificados. Nunca se almacenan en Git.
- **Signing key de Synapse generada automáticamente**: usa el método oficial de Synapse si la imagen Docker está disponible, o generación manual como fallback.
- **Validaciones pre-instalación completas**: puertos libres, permisos de carpetas, variables obligatorias, detección de valores de ejemplo.
- **Element Web personalizado**: imagen Docker con `config.json` preconfigurado para tu servidor.
- **Nginx hardened**: HSTS, CSP, rate limiting, headers de seguridad, sin exponer versión.
- **Federación deshabilitada por defecto**: máxima privacidad para uso interno.
- **SMTP completo**: notificaciones por correo, restablecimiento de contraseña.
- **Scripts PowerShell + Bash**: 12 operaciones administrativas (start, stop, backup, restore, create-user, etc.).
- **Backups automáticos**: dump de PostgreSQL + tar de configuraciones, con rotación.
- **Migración Docker Desktop → Ubuntu**: scripts de exportación/importación de volúmenes + servicio systemd.
- **Documentación exhaustiva**: 15 documentos en español cubriendo instalación, seguridad, administración, troubleshooting.

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                      Red LAN (192.168.x.x)                       │
│                                                                  │
│   Cliente (Element Web en navegador)                            │
│              │                                                   │
│              ▼                                                   │
│   ┌──────────────────────────────────────────────────────┐      │
│   │  Host Docker (Windows Desktop o Ubuntu Server)       │      │
│   │                                                       │      │
│   │   ┌──────────────────────────────────────────┐       │      │
│   │   │  matrix_frontend (red Docker bridge)     │       │      │
│   │   │                                            │       │      │
│   │   │  ┌─────────┐         ┌──────────────┐    │       │      │
│   │   │  │ Nginx   │ ──────► │ Element Web  │    │       │      │
│   │   │  │ :80 :443│         │ (nginx:80)   │    │       │      │
│   │   │  └────┬─────┘         └──────────────┘    │       │      │
│   │   │       │                                  │       │      │
│   │   │       ▼ (proxy_pass)                     │       │      │
│   │   │  ┌──────────────┐                        │       │      │
│   │   │  │ Synapse      │                        │       │      │
│   │   │  │ :8008        │                        │       │      │
│   │   │  └──────┬───────┘                        │       │      │
│   │   └─────────┼────────────────────────────────┘       │      │
│   │   ┌─────────▼────────────────────────────────┐       │      │
│   │   │  matrix_internal (red Docker bridge)     │       │      │
│   │   │                                            │       │      │
│   │   │  ┌──────────────┐    ┌──────────────┐    │       │      │
│   │   │  │ PostgreSQL   │    │ Redis        │    │       │      │
│   │   │  │ :5432        │    │ :6379        │    │       │      │
│   │   │  └──────────────┘    └──────────────┘    │       │      │
│   │   └────────────────────────────────────────┘       │      │
│   └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

Diagramas detallados en formato Mermaid en [`docs/diagrams/mermaid-diagrams.md`](docs/diagrams/mermaid-diagrams.md).

---

## Requisitos del sistema

### Mínimos

| Recurso | Valor mínimo |
|---------|--------------|
| CPU | 2 núcleos (x86_64) |
| RAM | 4 GB |
| Almacenamiento | 20 GB SSD |
| Red | LAN con DHCP o IP estática |
| Sistema operativo | Windows 10/11 con Docker Desktop, o Ubuntu 20.04+ LTS |
| Docker | Docker Engine 24+ con Compose v2 |
| OpenSSL | Para generación de certificados |

### Recomendados

| Recurso | Valor recomendado |
|---------|-------------------|
| CPU | 4+ núcleos |
| RAM | 8 GB |
| Almacenamiento | 100 GB SSD |
| Red | LAN con DNS local para los subdominios |
| Sistema operativo | Ubuntu Server 22.04/24.04 LTS |

---

## Instalación rápida

### 1. Prerrequisitos

- Docker Engine + Compose plugin v2 (Linux) o Docker Desktop (Windows) instalado y corriendo.
- OpenSSL disponible en el PATH.
- Permisos de administrador/sudo en el host.

### 2. Clonar el proyecto

```bash
# Linux
cd /opt
git clone <repositorio> matrix-docker
cd matrix-docker
```

> **Nota**: Al clonar, los archivos `signing.key`, `nginx/certs/*.key` y `nginx/certs/*.crt` **no se descargan** porque están en `.gitignore`. No te preocupes, el script de setup los genera automáticamente.

### 3. Configurar variables de entorno

```bash
cp .env.example .env
nano .env   # edita contraseñas y dominios
```

Cambia **obligatoriamente**:
- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `SYNAPSE_REGISTRATION_SHARED_SECRET`
- `SYNAPSE_MACAROON_SECRET_KEY`
- `SYNAPSE_ADMIN_API_TOKEN`
- `SYNAPSE_FORM_SECRET`
- `SYNAPSE_PASSWORD_PEPPER`
- `SMTP_PASS` (si usas SMTP)

### 4. Setup inicial (único comando necesario)

```bash
# Linux
bash scripts/linux/setup.sh

# Windows (PowerShell)
.\scripts\windows\setup.ps1
```

Este script realiza **todo** de forma automática:

1. Verifica que Docker, Docker Compose y OpenSSL estén instalados y funcionando.
2. Verifica que `.env` exista (lo crea desde `.env.example` si falta).
3. Valida las variables obligatorias (detecta valores de ejemplo).
4. Verifica que los puertos 80 y 443 estén libres.
5. Verifica permisos de escritura en carpetas críticas.
6. **Genera automáticamente la signing key de Synapse** (usando el método oficial si la imagen Docker existe, o generación manual como fallback).
7. **Genera automáticamente todos los certificados TLS** (CA raíz + certificados para matrix, element y default, todos con SAN unificado que incluye `matrix.home.arpa`, `element.home.arpa` y `localhost`).
8. Construye la imagen personalizada de Element Web.
9. Valida `docker-compose.yml`.
10. Realiza validación final de que todos los archivos críticos existen.

> **Ninguna clave privada se almacena jamás en Git.** Todas se generan localmente durante la instalación y son ignoradas por `.gitignore`.

### 5. Iniciar el stack

```bash
docker compose up -d
```

El comando descarga imágenes, crea volúmenes, levanta los servicios y espera a que todos los healthchecks pasen (tarda 2-5 minutos en el primer arranque).

### 6. Crear el primer usuario administrador

```bash
# Linux
bash scripts/linux/create-admin.sh admin

# Windows
.\scripts\windows\create-admin.ps1 admin
```

### 7. Acceder a Element

Abre en el navegador (de un equipo de la LAN o vía Tailscale):

```
https://element.home.arpa
```

> **Importante**: Debes configurar DNS local o el archivo `hosts` del cliente para que `matrix.home.arpa` y `element.home.arpa` apunten a la IP del host Docker. Importa el certificado `nginx/certs/ca.crt` en el trust store del cliente para evitar warnings del navegador.

---

## Uso diario

### Operaciones frecuentes

| Operación | Linux | Windows |
|-----------|-------|---------|
| Iniciar stack | `bash scripts/linux/start.sh` | `.\scripts\windows\start.ps1` |
| Detener stack | `bash scripts/linux/stop.sh` | `.\scripts\windows\stop.ps1` |
| Reiniciar todo | `bash scripts/linux/restart.sh` | `.\scripts\windows\restart.ps1` |
| Estado | `bash scripts/linux/status.sh` | `.\scripts\windows\status.ps1` |
| Ver logs | `bash scripts/linux/logs.sh synapse -f` | `.\scripts\windows\logs.ps1 synapse -f` |
| Crear usuario | `bash scripts/linux/create-user.sh juan` | `.\scripts\windows\create-user.ps1 juan` |
| Backup BD | `bash scripts/linux/backup-db.sh` | `.\scripts\windows\backup-db.ps1` |
| Restaurar BD | `bash scripts/linux/restore-db.sh archivo.sql.gz` | `.\scripts\windows\restore-db.ps1 archivo.sql.gz` |
| Actualizar imágenes | `bash scripts/linux/update-images.sh` | `.\scripts\windows\update-images.ps1` |
| Actualizar contenedores | `bash scripts/linux/update-containers.sh` | `.\scripts\windows\update-containers.ps1` |
| Limpiar imágenes | `bash scripts/linux/clean-images.sh` | `.\scripts\windows\clean-images.ps1` |

### Operaciones avanzadas con Docker Compose directo

```bash
# Ver servicios
docker compose ps

# Reiniciar solo un servicio
docker compose restart synapse

# Ver logs en vivo de un servicio
docker compose logs -f synapse

# Entrar a un contenedor
docker compose exec postgres psql -U synapse_user -d synapse

# Detener y eliminar contenedores (mantiene volúmenes)
docker compose down

# Detener y eliminar todo incluyendo volúmenes (PELIGROSO)
docker compose down -v
```

---

## Estructura del proyecto

```
matrix-docker/
├── docker-compose.yml         # Orquestación de servicios
├── .env.example               # Plantilla de variables
├── .env                       # Variables reales (no commitear)
├── .gitignore                 # Ignora secretos, backups, certs
├── README.md                  # Este archivo
├── CHANGELOG.md               # Historial de cambios
├── SPECIFICATIONS.md          # Especificaciones técnicas
├── ADMIN_GUIDE.md             # Manual del administrador
├── LICENSE                    # Apache 2.0
│
├── docs/                      # Documentación detallada
│   ├── 01-guia-rapida.md
│   ├── 02-instalacion.md
│   ├── 03-configuracion.md
│   ├── 04-arquitectura.md
│   ├── 05-seguridad.md
│   ├── 06-administracion.md
│   ├── 07-actualizacion.md
│   ├── 08-migracion-windows-ubuntu.md
│   ├── 09-backups.md
│   ├── 10-restauracion.md
│   ├── 11-resolucion-problemas.md
│   ├── 12-faq.md
│   ├── 13-buenas-practicas.md
│   ├── 14-documento-tecnico.md
│   ├── 15-logs.md
│   └── diagrams/
│       └── mermaid-diagrams.md
│
├── deployment/                # Migración Ubuntu / systemd / firewall
│   ├── install-docker-ubuntu.sh
│   ├── setup-firewall.sh
│   ├── matrix-docker.service
│   ├── matrix-backup.cron
│   ├── logrotate-matrix.conf
│   └── migrate-from-windows.sh
│
├── scripts/                   # Scripts de administración
│   ├── linux/                 # 16 scripts .sh
│   └── windows/               # 16 scripts .ps1
│
├── backups/                   # Backups generados (gitignored)
│
├── config/                    # Config compartida (vacío por defecto)
│
├── synapse/                   # Config Synapse
│   ├── homeserver.yaml.template
│   ├── entrypoint.sh
│   ├── log.config
│   └── signing.key
│
├── postgres/                  # Config PostgreSQL
│   ├── init.sql
│   ├── postgresql.conf
│   └── pg_hba.conf
│
├── redis/                     # Config Redis
│   ├── redis.conf.template
│   └── entrypoint.sh
│
├── element/                   # Element Web
│   ├── Dockerfile
│   ├── config.json
│   └── nginx.conf
│
└── nginx/                     # Nginx reverse proxy
    ├── nginx.conf
    ├── conf.d/
    │   ├── 00-default.conf
    │   ├── matrix.home.arpa.conf
    │   └── element.home.arpa.conf
    ├── snippets/
    │   ├── security-headers.conf
    │   └── proxy-params.conf
    ├── well-known/
    │   └── matrix/
    │       ├── client.json
    │       └── server.json
    └── certs/                 # Certs generados (gitignored)
```

---

## Documentación completa

Toda la documentación está en la carpeta [`docs/`](docs/) y se organiza en 15 documentos temáticos más un anexo de diagramas Mermaid. Para una visión general rápida, empieza por [`docs/01-guia-rapida.md`](docs/01-guia-rapida.md).

| Documento | Contenido |
|-----------|-----------|
| [01-guia-rapida](docs/01-guia-rapida.md) | Checklist de puesta en marcha en 10 minutos |
| [02-instalacion](docs/02-instalacion.md) | Instalación detallada en Windows y Ubuntu |
| [03-configuracion](docs/03-configuracion.md) | Variables, dominios, SMTP, branding |
| [04-arquitectura](docs/04-arquitectura.md) | Componentes, redes, volúmenes, dependencias |
| [05-seguridad](docs/05-seguridad.md) | Modelo de amenazas y mitigaciones |
| [06-administracion](docs/06-administracion.md) | Tareas diarias del administrador |
| [07-actualizacion](docs/07-actualizacion.md) | Procedimiento de actualización de imágenes |
| [08-migracion-windows-ubuntu](docs/08-migracion-windows-ubuntu.md) | Migración paso a paso |
| [09-backups](docs/09-backups.md) | Estrategia y scripts de respaldo |
| [10-restauracion](docs/10-restauracion.md) | Restauración ante desastres |
| [11-resolucion-problemas](docs/11-resolucion-problemas.md) | Diagnóstico y solución de problemas |
| [12-faq](docs/12-faq.md) | Preguntas frecuentes |
| [13-buenas-practicas](docs/13-buenas-practicas.md) | Recomendaciones operativas |
| [14-documento-tecnico](docs/14-documento-tecnico.md) | Especificación técnica formal |
| [15-logs](docs/15-logs.md) | Logs, rotación, diagnóstico |
| [diagrams/mermaid-diagrams](docs/diagrams/mermaid-diagrams.md) | Diagramas lógicos y de flujo |

---

## Migración Windows → Ubuntu

El proyecto está diseñado para migrar sin modificaciones estructurales entre Docker Desktop (Windows) y Ubuntu Server. El procedimiento completo está documentado en [`docs/08-migracion-windows-ubuntu.md`](docs/08-migracion-windows-ubuntu.md).

Resumen del flujo:

1. **En Windows**: detener el stack y exportar volúmenes con `scripts/windows/export-volumes.ps1`.
2. **Transferir**: copiar el tarball + proyecto al servidor Ubuntu (scp, rsync, USB).
3. **En Ubuntu**: instalar Docker con `deployment/install-docker-ubuntu.sh`.
4. **Importar**: ejecutar `sudo bash deployment/migrate-from-windows.sh matrix-migration.tar.gz /opt/matrix-docker`.
5. **Ajustar**: actualizar `.env` (IPs del host), DNS local, firewall.
6. **Iniciar**: `bash scripts/linux/start.sh`.
7. **Systemd**: instalar el servicio para auto-arranque en boot.

---

## Seguridad

Las decisiones de seguridad están documentadas en [`docs/05-seguridad.md`](docs/05-seguridad.md). Aspectos clave:

- **Sin exposición a Internet**: los puertos 80/443 se publican solo para LAN; los demás servicios no se publican.
- **Secretos externalizados**: contraseñas y tokens en `.env` (gitignored). Claves privadas (certificados, signing key) **nunca en Git**; se generan automáticamente durante `setup.sh`.
- **Red aislada**: `matrix_internal` con `internal: true` — PostgreSQL y Redis sin salida a Internet. Synapse usa `matrix_frontend` para SMTP.
- **PostgreSQL con scram-sha-256** y `pg_hba.conf` que solo permite conexiones desde la red Docker interna.
- **Redis con contraseña** y comandos peligrosos deshabilitados (`FLUSHALL`, `CONFIG`, `KEYS`, `DEBUG`).
- **Contenedores con `no-new-privileges`** y `security_opt`.
- **Nginx con headers HSTS, CSP, X-Frame-Options, X-Content-Type-Options**, sin exponer versión.
- **Rate limiting** en Nginx por IP y por endpoint (auth, sync, media).
- **Logging estructurado** con rotación para auditoría.
- **Federación deshabilitada** por defecto para máxima privacidad.

---

## Soporte y contribución

### Reportar problemas

Si encuentras un bug o tienes una solicitud de mejora:

1. Verifica [`docs/11-resolucion-problemas.md`](docs/11-resolucion-problemas.md) y [`docs/12-faq.md`](docs/12-faq.md).
2. Recopila logs relevantes con `scripts/linux/logs.sh <servicio>`.
3. Adjunta salida de `scripts/linux/status.sh`.

### Contribuir

1. Fork el repositorio.
2. Crea una rama: `git checkout -b feature/nueva-funcionalidad`.
3. Realiza cambios siguiendo las buenas prácticas de [`docs/13-buenas-practicas.md`](docs/13-buenas-practicas.md).
4. Verifica que `docker compose config --quiet` no arroje errores.
5. Envía un Pull Request describiendo los cambios.

---

## Licencia

Este proyecto se distribuye bajo la licencia **Apache License 2.0**. Ver el archivo [LICENSE](LICENSE) para el texto completo.

Copyright 2026 Matrix Docker Project.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
