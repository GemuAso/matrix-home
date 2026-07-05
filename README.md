# Matrix Docker Stack

[![Version: 5.0.0](https://img.shields.io/badge/Version-5.0.0-brightgreen.svg)](CHANGELOG.md)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## Descripción

Stack completo de mensajería **Matrix** para red LAN privada con **Synapse**, **PostgreSQL**, **Redis**, **Element Web** y **Nginx**. Diseñado para acceso exclusivo vía LAN o **Tailscale VPN**. Instalación de un solo comando.

Todos los secretos se generan criptográficamente, la IP se detecta automáticamente, y el stack queda listo para producción sin intervención manual.

---

## Características Principales

- **Instalación de un solo comando** — `sudo ./install.sh` y listo
- **Cero configuración manual** — secretos, certificados, signing key, todo se genera automáticamente
- **Secretos generados criptográficamente** — 7 secretos con `openssl rand` (contraseñas, tokens, pepper)
- **Detección automática de IP LAN y Tailscale** — sin servicios HTTP externos
- **Compatible con Ubuntu 22.04/24.04, Debian 11+, Raspberry Pi OS 64-bit**
- **AMD64 y ARM64** — probado en x86_64 y aarch64 (Raspberry Pi)
- **10 scripts de administración** — start, stop, restart, status, logs, backup, restore, update, healthcheck, uninstall
- **Desinstalador profesional con 5 niveles** — desde contenedores hasta eliminación total con backup previo
- **14 pruebas automáticas post-instalación** — verifican cada servicio y endpoint
- **Healthchecks en todos los servicios** — 5 contenedores con comprobaciones de salud
- **Certificados TLS auto-firmados con CA local** — SAN unificado (matrix.home.arpa, element.home.arpa, localhost)
- **Federación deshabilitada** — máxima privacidad para uso interno

---

## Requisitos

| Requisito | Valor |
|-----------|-------|
| Docker Engine | 20.10+ |
| Docker Compose | v2 (plugin) |
| RAM mínima | 2 GB (4 GB recomendado) |
| Disco | 5 GB |
| Sistema operativo | Ubuntu 22.04/24.04, Debian 11+, Raspberry Pi OS 64-bit |
| Arquitectura | AMD64 (x86_64) o ARM64 (aarch64) |

---

## Instalación Rápida

```bash
git clone <repo> matrix-docker && cd matrix-docker
sudo ./install.sh
docker compose exec synapse register_new_matrix_user -c http://localhost:8008 -a admin
```

El instalador valida el sistema, instala dependencias, detecta la IP, genera todos los secretos y certificados, construye las imágenes, levanta el stack y ejecuta 14 pruebas automáticas.

---

## Arquitectura

El stack está compuesto por **5 servicios** organizados en **2 redes Docker** con **5 volúmenes persistentes**.

**Redes:**

- `matrix_internal` — red aislada (`internal: true`), sin salida a Internet. Conecta PostgreSQL, Redis y Synapse.
- `matrix_frontend` — red bridge accesible desde la LAN/Tailscale. Conecta Synapse, Element Web y Nginx.

**Flujo de tráfico:** Cliente → Nginx (`:80/:443`) → Synapse (`:8008`) / Element Web (`:80`). PostgreSQL y Redis solo son accesibles desde Synapse a través de la red interna.

| Servicio | Imagen | Función |
|----------|--------|---------|
| **Synapse** | `matrix-synapse:custom` (basado en `synapse:v1.118.0`) | Servidor Matrix (homeserver) |
| **PostgreSQL** | `postgres:16.4-alpine3.20` | Base de datos transaccional |
| **Redis** | `redis:7.4-alpine3.20` | Caché y pub/sub para Synapse |
| **Element Web** | `matrix-element:custom` (basado en `vectorim/element-web`) | Cliente web |
| **Nginx** | `nginx:1.27.2-alpine3.20` | Reverse proxy, terminación TLS, rate limiting |

---

## Scripts de Administración

Todos los scripts se encuentran en `scripts/admin/` y se ejecutan desde la raíz del proyecto.

| Script | Comando | Descripción |
|--------|---------|-------------|
| `start.sh` | `sudo ./scripts/admin/start.sh` | Iniciar todos los servicios del stack |
| `stop.sh` | `sudo ./scripts/admin/stop.sh` | Detener todos los servicios (graceful) |
| `restart.sh` | `sudo ./scripts/admin/restart.sh` | Reiniciar un servicio o todo el stack |
| `status.sh` | `sudo ./scripts/admin/status.sh` | Estado, uptime y salud de cada contenedor |
| `logs.sh` | `sudo ./scripts/admin/logs.sh [servicio]` | Ver logs de un servicio o de todos (`-f` para seguimiento) |
| `backup.sh` | `sudo ./scripts/admin/backup.sh` | Respaldo completo (PostgreSQL dump + configuraciones) |
| `restore.sh` | `sudo ./scripts/admin/restore.sh` | Restaurar el stack desde un respaldo |
| `update.sh` | `sudo ./scripts/admin/update.sh` | Actualizar imágenes y reconstruir el stack |
| `healthcheck.sh` | `sudo ./scripts/admin/healthcheck.sh` | Verificación de salud detallada por servicio |
| `uninstall.sh` | `sudo ./scripts/admin/uninstall.sh` | Desinstalador con 5 niveles de eliminación |

> **Nota:** También existe un `uninstall.sh` en la raíz del proyecto (`sudo ./uninstall.sh`) que es un acceso directo al mismo desinstalador.

---

## Desinstalación

```bash
sudo ./uninstall.sh
```

El desinstalador ofrece **5 niveles** con confirmación en cada paso:

1. **Contenedores** — elimina contenedores (datos conservados)
2. **Contenedores + redes** — elimina redes Docker del stack
3. **Contenedores + redes + volúmenes** — eliminación completa de datos
4. **Todo (incluyendo archivos generados)** — `.env`, certificados, claves
5. **Backup + eliminación completa** — crea un respaldo antes de eliminar (nivel 3)

---

## Configuración del Cliente

### DNS

Configura tu servidor DNS local o el archivo `hosts` de cada cliente para resolver los dominios:

```
192.168.x.x  matrix.home.arpa  element.home.arpa
```

Si usas **Tailscale**, resuelve hacia la IP de Tailscale (`100.x.x.x`).

### Certificado CA

Importa la autoridad certificadora local en cada dispositivo cliente para confiar en los certificados TLS auto-firmados:

```bash
# Linux
sudo cp nginx/certs/ca.crt /usr/local/share/ca-certificates/matrix-ca.crt
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain nginx/certs/ca.crt

# Windows
# Importar ca.crt en "Entidades de certificación raíz de confianza" mediante certlm.msc
```

### Acceso

Abre **https://element.home.arpa** en el navegador de cualquier equipo de la LAN o conectado vía Tailscale.

---

## Estructura del Proyecto

```
matrix-docker/
├── docker-compose.yml          # Orquestación de los 5 servicios
├── install.sh                  # Instalador de un solo comando
├── uninstall.sh                # Acceso directo al desinstalador
├── .env.example                # Plantilla de variables de entorno
├── .gitignore                  # Excluye secretos, certificados y backups
├── LICENSE                     # Apache-2.0
├── README.md                   # Este archivo
├── CHANGELOG.md                # Historial de versiones
│
├── scripts/
│   └── admin/                  # 10 scripts de administración
│       ├── start.sh
│       ├── stop.sh
│       ├── restart.sh
│       ├── status.sh
│       ├── logs.sh
│       ├── backup.sh
│       ├── restore.sh
│       ├── update.sh
│       ├── healthcheck.sh
│       └── uninstall.sh
│
├── synapse/
│   ├── Dockerfile              # Imagen personalizada (envsubst)
│   ├── homeserver.yaml.template
│   ├── entrypoint.sh
│   └── log.config
│
├── postgres/
│   ├── init.sql                # Creación de base de datos y usuario
│   ├── postgresql.conf         # Configuración tuneada
│   └── pg_hba.conf             # Autenticación scram-sha-256
│
├── redis/
│   ├── redis.conf.template     # Comandos peligrosos renombrados
│   └── entrypoint.sh
│
├── element/
│   ├── Dockerfile              # Imagen personalizada con config.json
│   ├── config.json
│   └── nginx.conf
│
├── nginx/
│   ├── nginx.conf
│   ├── conf.d/                 # Virtual hosts (matrix + element)
│   ├── snippets/               # Headers de seguridad, proxy params
│   ├── well-known/matrix/      # Delegación de federación
│   └── certs/                  # Certificados TLS (generados, gitignored)
│
├── deployment/                 # systemd, firewall, migración
├── docs/                       # 15 documentos de referencia
├── backups/                    # Respaldos (gitignored)
└── lib/                        # Funciones compartidas de instalación
```

---

## Seguridad

- **`no-new-privileges:true`** en todos los contenedores
- **Red `matrix_internal` aislada** — PostgreSQL y Redis sin salida a Internet (`internal: true`)
- **PostgreSQL con `scram-sha-256`** — `pg_hba.conf` restringe conexiones a la red Docker interna, denegando todo lo demás (`reject 0.0.0.0/0`)
- **Redis con `rename-command`** — `FLUSHALL`, `FLUSHDB`, `CONFIG`, `KEYS`, `DEBUG` deshabilitados; `SHUTDOWN` renombrado
- **`.env` con permisos `chmod 600`** — solo legible por root
- **Claves privadas fuera de Git** — certificados TLS y signing key en `.gitignore`, generados en tiempo de instalación
- **Nginx hardened** — HSTS, CSP, X-Frame-Options, X-Content-Type-Options, rate limiting por IP y endpoint, versión oculta
- **Healthchecks en todos los servicios** — detección temprana de fallos
- **Federación deshabilitada** — el servidor no se comunica con otros homeservers de Matrix
- **Rotación de logs** — límites de tamaño y cantidad por contenedor (`json-file` driver)

---

## Licencia

Este proyecto se distribuye bajo la licencia **Apache License 2.0**.

Ver el archivo [LICENSE](LICENSE) para el texto completo.