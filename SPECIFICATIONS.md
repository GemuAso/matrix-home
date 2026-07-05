# Especificaciones técnicas

> Documento formal de especificaciones del proyecto **Matrix Docker Stack** versión 5.0.0.

---

## 1. Objetivos

### 1.1 Objetivo principal

Desplegar un servidor de mensajería instantánea **Matrix Synapse** completamente funcional en un entorno de red de área local (LAN), mediante contenedores Docker orquestados con Docker Compose, listo para uso productivo sin requerir exposición a Internet pública. A partir de la versión 5.0.0, Synapse se construye desde un **Dockerfile personalizado** que permite personalizar dependencias, optimizar la imagen para producción y garantizar reproducibilidad en cada despliegue.

### 1.2 Objetivos específicos

1. Proveer un stack completo (Synapse + PostgreSQL + Redis + Element Web + Nginx) operable con un único comando.
2. Garantizar persistencia de datos mediante volúmenes Docker con nombre.
3. Aislar todos los servicios salvo los estrictamente necesarios para acceso desde la LAN.
4. Externalizar secretos en archivo `.env` no commiteado a control de versiones.
5. **Generar automáticamente todas las claves privadas** (certificados TLS, signing key de Synapse) durante la instalación, sin almacenarlas jamás en Git.
6. Validar completamente el entorno antes del primer arranque (dependencias, puertos, permisos, variables).
7. Proveer scripts administrativos en Bash organizados en `scripts/admin/` con cobertura completa de operaciones.
8. Construir Synapse desde un Dockerfile personalizado para control total de la imagen.
9. Ejecutar **14 pruebas automatizadas** post-instalación que validan la integridad del despliegue.
10. Proveer un script de desinstalación (`uninstall.sh`) para eliminación limpia y completa del stack.
11. Documentar exhaustivamente cada componente, decisión y procedimiento operativo.

---

## 2. Alcance

### 2.1 Incluido

- Configuración de Synapse con PostgreSQL, Redis, SMTP, sin federación, sin SQLite.
- **Dockerfile personalizado de Synapse** con dependencias optimizadas para producción y soporte multi-arquitectura (AMD64/ARM64).
- Imagen Docker personalizada de Element Web con `config.json` preconfigurado.
- Nginx reverse proxy con TLS auto-firmado, headers de seguridad y rate limiting.
- Scripts administrativos organizados en `scripts/admin/`: `backup-db.sh`, `clean-images.sh`, `create-admin.sh`, `create-user.sh`, `healthcheck.sh`, `logs.sh`, `restore-db.sh`, `restart.sh`, `start.sh`, `status.sh`, `stop.sh`, `update.sh`, `verify.sh` y más.
- Script `uninstall.sh` en la raíz del proyecto para desinstalación limpia.
- Sistema de backups con rotación y restauración con backup preventivo.
- Servicio systemd para auto-arranque en Ubuntu.
- Configuración de firewall UFW para acceso solo desde LAN.
- Documentación completa en español (15 documentos + diagramas Mermaid).

### 2.2 No incluido

- Federación con otros servidores Matrix (completamente removida en v2.0.0).
- Alta disponibilidad multi-nodo.
- Bridging a otras plataformas (Signal, Telegram, etc.).
- Monitorización con Prometheus/Grafana.
- Logs centralizados con Loki/ELK.
- Cifrado de backups en reposo (solo se documenta como recomendación).
- Mobile push notifications (requiere servidor push adicional).
- Integración con SSO externo (OIDC/SAML/LDAP) - preconfigurado pero deshabilitado.
- Certificados públicos Let's Encrypt (la configuración es LAN-only con self-signed).
- **Acceso remoto**: usar **Tailscale** VPN para acceso desde fuera de la LAN.

---

## 3. Arquitectura del sistema

### 3.1 Servicios (5 contenedores)

| Servicio | Imagen/Build | Puerto interno | Redes | Función |
|----------|-------------|----------------|-------|---------|
| **PostgreSQL** | `postgres:16.4-alpine3.20` | 5432 | `matrix_internal` | Base de datos principal de Synapse |
| **Redis** | `redis:7.4-alpine3.20` | 6379 | `matrix_internal` | Caché persistente y colas de Synapse |
| **Synapse** | Build desde `synapse/Dockerfile` | 8008 | `matrix_internal` + `matrix_frontend` | Servidor Matrix homeserver |
| **Element Web** | `vectorim/element-web:v1.11.65` | 80 | `matrix_frontend` | Cliente web Matrix |
| **Nginx** | `nginx:1.27.2-alpine3.20` | 80, 443 | `matrix_frontend` | Reverse proxy TLS + cache estático |

### 3.2 Redes Docker (2)

| Red | Tipo | `internal` | Servicios conectados | Salida a Internet |
|-----|------|------------|---------------------|-------------------|
| `matrix_internal` | bridge | **true** | PostgreSQL, Redis, Synapse | No (completamente aislada) |
| `matrix_frontend` | bridge | false | Nginx, Element, Synapse | Sí (Synapse para SMTP) |

> **Nota v5.0.0**: `matrix_internal` tiene `internal: true`, lo que impide cualquier tráfico hacia o desde Internet. Synapse pertenece a ambas redes y utiliza exclusivamente `matrix_frontend` para conexiones SMTP salientes. Esto aísla completamente a PostgreSQL y Redis de cualquier comunicación externa, cumpliendo el principio de defensa en profundidad.

### 3.3 Volúmenes Docker (5)

| Volumen | Montaje en | Contenido | Tamaño inicial estimado |
|---------|-----------|-----------|------------------------|
| `synapse_data` | `/data` (Synapse) | Mensajes, media, signing key, logs internos | 100 MB |
| `postgres_data` | `/var/lib/postgresql/data` (PostgreSQL) | Base de datos relacional | 100 MB |
| `redis_data` | `/data` (Redis) | Caché persistente | 10 MB |
| `element_nginx_cache` | `/var/cache/nginx` (Nginx) | Cache estático de Element Web | 10 MB |
| `nginx_logs` | `/var/log/nginx` (Nginx) | Access logs + error logs de Nginx | 10 MB |

### 3.4 Límites de memoria por servicio

| Servicio | Límite de memoria | Notas |
|----------|------------------|-------|
| PostgreSQL | 1 GB | `deploy.resources.limits.memory` en docker-compose |
| Redis | 512 MB | `maxmemory 512mb` en redis.conf + limite Docker |
| Synapse | 2 GB | `deploy.resources.limits.memory` en docker-compose |
| Nginx | 256 MB | `deploy.resources.limits.memory` en docker-compose |
| Element Web | Sin límite explícito | Contenedor estático, consumo mínimo (~32-64 MB) |

---

## 4. Requisitos funcionales

| ID | Requisito | Prioridad | Estado |
|----|-----------|-----------|--------|
| RF-01 | El sistema debe permitir enviar y recibir mensajes en tiempo real entre usuarios | Alta | ✅ |
| RF-02 | El sistema debe soportar salas de chat grupales con permisos | Alta | ✅ |
| RF-03 | El sistema debe permitir llamadas de voz y video vía WebRTC | Media | ✅ |
| RF-04 | El sistema debe permitir compartir archivos adjuntos hasta 50 MB | Alta | ✅ |
| RF-05 | El sistema debe enviar notificaciones por email | Media | ✅ |
| RF-06 | El sistema debe permitir restablecer contraseña vía email | Media | ✅ |
| RF-07 | El administrador debe poder crear usuarios desde script | Alta | ✅ |
| RF-08 | El administrador debe poder crear administradores desde script | Alta | ✅ |
| RF-09 | El sistema debe mantener datos persistentes tras reinicios | Alta | ✅ |
| RF-10 | El sistema debe reiniciar servicios automáticamente tras fallos | Alta | ✅ |
| RF-11 | El sistema debe permitir respaldos en caliente de la base de datos | Alta | ✅ |
| RF-12 | El sistema debe permitir restauración de respaldos | Alta | ✅ |
| RF-13 | El sistema debe exponer el cliente web por HTTPS | Alta | ✅ |
| RF-14 | El sistema debe permitir acceso desde la LAN sin Internet | Alta | ✅ |
| RF-15 | El sistema debe permitir migración entre hosts sin pérdida de datos | Alta | ✅ |
| RF-16 | El sistema debe permitir visualizar logs por servicio | Media | ✅ |
| RF-17 | El sistema debe permitir cifrado E2EE de mensajes | Alta | ✅ (nativo Synapse) |
| RF-18 | El sistema debe permitir verificación de dispositivos cruzados | Media | ✅ (nativo Element) |
| RF-19 | La instalación debe poder realizarse con un único comando (`./install.sh`) | Alta | ✅ (v5.0.0) |
| RF-20 | El instalador debe ejecutar 14 pruebas automatizadas post-instalación | Alta | ✅ (v5.0.0) |
| RF-21 | El sistema debe poder desinstalarse completamente con un script | Alta | ✅ (v5.0.0) |
| RF-22 | El sistema debe proveer un script de healthcheck unificado | Media | ✅ (v5.0.0) |
| RF-23 | El sistema debe construir Synapse desde Dockerfile personalizado | Alta | ✅ (v5.0.0) |

---

## 5. Requisitos no funcionales

### 5.1 Rendimiento

| ID | Requisito | Métrica |
|----|-----------|---------|
| RNF-01 | Latencia de mensaje enviado/recibido | < 500 ms en LAN |
| RNF-02 | Tiempo de arranque del stack completo | < 5 minutos |
| RNF-03 | Soporte de usuarios concurrentes | ≥ 100 usuarios activos |
| RNF-04 | Throughput de mensajes | ≥ 50 msg/s sostenidos |
| RNF-05 | Tamaño máximo de archivo adjunto | 50 MB configurable |
| RNF-06 | Tiempo de backup de BD | < 30 segundos para 1 GB |

### 5.2 Disponibilidad

| ID | Requisito | Métrica |
|----|-----------|---------|
| RNF-07 | Uptime objetivo | 99.5% (mensual) |
| RNF-08 | Tiempo de recuperación (RTO) | < 15 minutos |
| RNF-09 | Punto de recuperación (RPO) | ≤ 24 horas |
| RNF-10 | Reinicio automático tras fallo | Sí (restart: unless-stopped) |

### 5.3 Seguridad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-11 | Cifrado en tránsito | TLS 1.2/1.3 con Nginx |
| RNF-12 | Cifrado en reposo de mensajes | E2EE nativo de Matrix |
| RNF-13 | Autenticación de usuarios | Password con política + pepper |
| RNF-14 | Secretos externalizados | `.env` con permisos 600 |
| RNF-15 | Aislamiento de red | Dos redes Docker, `matrix_internal` con `internal: true` |
| RNF-16 | Rate limiting | Por IP y endpoint en Nginx |
| RNF-17 | Hardening de contenedores | `no-new-privileges`, sin root cuando posible |
| RNF-18 | Auditoría de logs | Logs estructurados con retención |
| RNF-19 | Sin exposición innecesaria | Solo puertos 80/443 al host |
| RNF-20 | Contraseñas hasheadas | SCRAM-SHA-256 en PostgreSQL |

### 5.4 Mantenibilidad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-21 | Versiones pinned | Tags inmutables en docker-compose (excepto Synapse que se construye) |
| RNF-22 | Documentación completa | 15 documentos + diagramas |
| RNF-23 | Scripts idempotentes | Verifican estado antes de actuar |
| RNF-24 | Estructura modular | Carpetas por servicio + `scripts/admin/` centralizado |
| RNF-25 | Backups automáticos | Cron job configurable |
| RNF-26 | Pruebas automatizadas | 14 tests post-instalación en `install.sh` |
| RNF-27 | Desinstalación limpia | Script `uninstall.sh` en raíz del proyecto |

### 5.5 Portabilidad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-28 | Multi-arquitectura | AMD64 y ARM64 (Dockerfile con soporte multi-platform) |
| RNF-29 | Migración sin reconfiguración | Scripts de export/import de volúmenes |
| RNF-30 | Mínimas dependencias del host | Solo Docker + openssl + bash |

---

## 6. Instalador (`install.sh`)

### 6.1 Resumen

El instalador (`install.sh`) ejecuta **14 pasos secuenciales** que configuran, validan y despliegan el stack completo:

| Paso | Descripción |
|------|-------------|
| 1 | Comprobación de requisitos del sistema (Docker, openssl, bash) |
| 2 | Detección automática de la IP del host |
| 3 | Generación del archivo `.env` con todos los secretos (o preservación si ya existe) |
| 4 | Generación de certificados TLS auto-firmados (CA + certificado del servidor) |
| 5 | Generación de la signing key de Synapse |
| 6 | Creación de los 5 volúmenes Docker |
| 7 | Construcción de la imagen personalizada de Synapse desde el Dockerfile |
| 8 | Descarga de las imágenes Docker restantes |
| 9 | Generación de configuraciones de Synapse (`homeserver.yaml`, `log.config`) |
| 10 | Generación de configuración de Redis (`redis.conf`) |
| 11 | Generación de configuración de Nginx (`nginx.conf`, snippets de seguridad) |
| 12 | Generación de `config.json` personalizado para Element Web |
| 13 | Arranque del stack completo con `docker compose up -d` |
| 14 | Ejecución de 14 pruebas automatizadas de verificación |

### 6.2 Pruebas automatizadas post-instalación (14 tests)

Tras completar los 14 pasos de instalación, el instalador ejecuta automáticamente 14 pruebas que validan la integridad del despliegue:

| # | Prueba | Valida |
|---|--------|--------|
| 1 | Contenedores ejecutándose | Los 5 servicios están en estado `running` |
| 2 | Volúmenes montados | Los 5 volúmenes existen y están montados |
| 3 | Redes creadas | `matrix_internal` y `matrix_frontend` existen |
| 4 | Aislamiento de red interna | `matrix_internal` tiene `internal: true` |
| 5 | Healthcheck de PostgreSQL | Responde a `pg_isready` |
| 6 | Healthcheck de Redis | Responde a `redis-cli ping` |
| 7 | Healthcheck de Synapse | Endpoint `/health` devuelve 200 |
| 8 | TLS funcional | Certificado válido en puerto 443 |
| 9 | Redirección HTTP→HTTPS | Puerto 80 redirige a 443 |
| 10 | Element Web accesible | `https://element.home.arpa` devuelve HTML |
| 11 | `.well-known` configurado | Client config accesible vía HTTPS |
| 12 | Archivo `.env` presente | Variables de entorno cargadas |
| 13 | Signing key existe | `synapse/signing.key` presente en volumen |
| 14 | Espacio en disco | Mínimo 5 GB libres en el host |

---

## 7. Hardware recomendado

### 7.1 Hardware mínimo

| Componente | Mínimo | Notas |
|------------|--------|-------|
| CPU | 2 núcleos (AMD64 o ARM64) | 1.5 GHz mínimo |
| RAM | 4 GB | Docker + 5 contenedores |
| Almacenamiento | 20 GB SSD | Imágenes + datos + logs |
| Red | 100 Mbps | LAN |
| Storage tipo | SSD recomendado | HDD afecta rendimiento PostgreSQL |

### 7.2 Hardware recomendado

| Componente | Recomendado | Para |
|------------|-------------|------|
| CPU | 4+ núcleos (AMD64 o ARM64) | 50+ usuarios concurrentes |
| RAM | 8 GB | Synapse + PostgreSQL cache |
| Almacenamiento | 100 GB SSD NVMe | Histórico de mensajes + media |
| Red | 1 Gbps | Videollamadas + media |
| Backup storage | 50 GB externo | Rotación 7 días |

### 7.3 Hardware para alta carga (200+ usuarios)

| Componente | Recomendado |
|------------|-------------|
| CPU | 8+ núcleos |
| RAM | 16-32 GB |
| Almacenamiento | 500 GB SSD NVMe + 1 TB HDD para backups |
| Red | 10 Gbps |

### 7.4 Desglose de RAM por servicio

| Servicio | Mínimo | Límite Docker (v5.0.0) | Pico |
|----------|--------|------------------------|------|
| PostgreSQL | 256 MB | **1 GB** | 2 GB |
| Redis | 64 MB | **512 MB** | 1 GB |
| Synapse | 512 MB | **2 GB** | 4 GB |
| Element | 32 MB | Sin límite | 128 MB |
| Nginx | 32 MB | **256 MB** | 512 MB |
| **Total** | **896 MB** | **~3.8 GB** | **7.6 GB** |

---

## 8. Almacenamiento

### 8.1 Volúmenes Docker

| Volumen | Tamaño inicial estimado | Crecimiento | Tipo |
|---------|-------------------------|-------------|------|
| `synapse_data` | 100 MB | 1-10 GB | Mensajes, media, logs internos |
| `postgres_data` | 100 MB | 1-5 GB | Base de datos |
| `redis_data` | 10 MB | 100 MB | Caché persistente |
| `element_nginx_cache` | 10 MB | 100 MB | Cache nginx Element |
| `nginx_logs` | 10 MB | 500 MB | Access + error logs |

### 8.2 Estimación de crecimiento

Para 50 usuarios activos con uso moderado (100 mensajes/día + 5 MB media/día):
- Mensajes: ~50 KB/día → 18 MB/año
- Media: 250 MB/día → 91 GB/año
- Logs: 5 MB/día → 1.8 GB/año

**Recomendación**: dimensionar 50 GB/año de crecimiento para 50 usuarios activos.

---

## 9. Red

### 9.1 Puertos expuestos al host

| Puerto | Servicio | Propósito |
|--------|----------|-----------|
| 80 (TCP) | Nginx | HTTP - redirige a HTTPS |
| 443 (TCP) | Nginx | HTTPS - acceso cliente |

### 9.2 Puertos internos (no publicados)

| Puerto | Servicio | Accesible por |
|--------|----------|---------------|
| 5432 | PostgreSQL | Solo contenedores en `matrix_internal` |
| 6379 | Redis | Solo contenedores en `matrix_internal` |
| 8008 | Synapse | Solo contenedores en `matrix_internal` + `matrix_frontend` |
| 80 | Element | Solo contenedores en `matrix_frontend` |

### 9.3 Redes Docker

| Red | Tipo | `internal` | Servicios | Salida a Internet |
|-----|------|------------|-----------|-------------------|
| `matrix_internal` | bridge | **true** | PostgreSQL, Redis, Synapse | No (aislado) |
| `matrix_frontend` | bridge | false | Nginx, Element, Synapse | Sí (Synapse para SMTP) |

> **Nota v5.0.0**: `matrix_internal` tiene `internal: true`, lo que significa que los contenedores en esta red no tienen gateway a Internet. Synapse, que pertenece a ambas redes, utiliza `matrix_frontend` para conexiones SMTP salientes. Esto aísla completamente a PostgreSQL y Redis de cualquier comunicación externa.

### 9.4 Resolución DNS

Los clientes deben resolver los siguientes nombres a la IP del host Docker:

| Hostname | Resuelve a |
|----------|-----------|
| `matrix.home.arpa` | IP del host Docker |
| `element.home.arpa` | IP del host Docker |

Métodos:
- DNS local (bind9, dnsmasq, router).
- Archivo `hosts` en cada cliente:
  - Linux: `/etc/hosts`
  - Windows: `C:\Windows\System32\drivers\etc\hosts`
  - macOS: `/etc/hosts`

---

## 10. Compatibilidad

### 10.1 Sistemas operativos del host

| OS | Versión | Soporte | Notas |
|----|---------|---------|-------|
| Ubuntu Server | 22.04 LTS | ✅ Recomendado | Docker Engine nativo, plataforma principal |
| Ubuntu Server | 24.04 LTS | ✅ Recomendado | Docker Engine nativo, plataforma principal |
| Debian | 11+ | ✅ | Docker Engine nativo |
| Raspberry Pi OS | 64-bit (ARM64) | ✅ | Soporte completo multi-arquitectura |
| Ubuntu Server | 20.04 LTS | ❌ Deprecado | Ya no se prueba activamente |

### 10.2 Arquitecturas soportadas

| Arquitectura | Estado | Notas |
|-------------|--------|-------|
| **AMD64** (x86_64) | ✅ Plena | Plataforma principal, todas las imágenes y el Dockerfile soportan AMD64 |
| **ARM64** (aarch64) | ✅ Plena | Raspberry Pi 4/5, servidores ARM, el Dockerfile de Synapse se construye nativamente en ARM64 |

> **Nota v5.0.0**: Todas las imágenes base utilizadas (postgres, redis, nginx, element-web) tienen variantes oficiales multi-arquitectura. El Dockerfile personalizado de Synapse utiliza imágenes base con soporte AMD64 y ARM64, por lo que el stack completo funciona de forma nativa en ambas arquitecturas sin emulación.

### 10.3 Navegadores soportados (cliente Element)

- Chrome 100+ (recomendado)
- Firefox 100+ (recomendado)
- Edge 100+
- Safari 15+ (parcial - algunas features de videollamada pueden no funcionar)

### 10.4 Clientes móviles

- Element Android: configurable manualmente, requiere acceso a la URL del servidor.
- Element iOS: configurable manualmente, requiere confianza del certificado CA.

---

## 11. Scripts administrativos

### 11.1 Ubicación

Todos los scripts administrativos residen en `scripts/admin/`:

| Script | Función |
|--------|---------|
| `backup-db.sh` | Backup de la base de datos PostgreSQL |
| `clean-images.sh` | Limpieza de imágenes Docker huérfanas |
| `create-admin.sh` | Crear usuario con permisos de administrador |
| `create-user.sh` | Crear usuario normal |
| `healthcheck.sh` | Healthcheck unificado de todos los servicios |
| `logs.sh` | Visualización de logs por servicio |
| `restore-db.sh` | Restauración de base de datos desde backup |
| `restart.sh` | Reiniciar uno o todos los servicios |
| `start.sh` | Iniciar el stack completo |
| `status.sh` | Estado de los contenedores |
| `stop.sh` | Detener el stack completo |
| `update.sh` | Actualización de imágenes y contenedores (combinado) |
| `verify.sh` | Verificación completa de la configuración |

### 11.2 Script de desinstalación

El script `uninstall.sh` en la raíz del proyecto permite la eliminación completa y limpia del stack:

```bash
./uninstall.sh
```

El script:
1. Pide confirmación explícita antes de proceder.
2. Detiene y elimina todos los contenedores.
3. Elimina las redes Docker del proyecto.
4. Pregunta si desea eliminar los volúmenes (datos persistentes).
5. Pregunta si desea eliminar las imágenes construidas/descargadas.
6. Pregunta si desea eliminar el archivo `.env` (secretos).

---

## 12. Limitaciones

### 12.1 Técnicas

1. **Federación deshabilitada**: el servidor está aislado. Para federar, hay que:
   - **Nota**: En v2.0.0 la federación fue completamente removida. Para federar necesitarías restaurar endpoints y configuración manualmente.
   - Cambiar `federation.enabled: true` en `homeserver.yaml`.
   - Exponer el puerto 8448 en `docker-compose.yml`.
   - Configurar `.well-known/matrix/server` con el dominio público.
   - Reconfigurar DNS y firewall para acceso desde Internet.

2. **TLS auto-firmado**: requiere importar CA en cada cliente. No apto para acceso público sin modificación.

3. **Sin LDAP/OIDC/SAML activo**: la configuración existe en `homeserver.yaml` pero está comentada/deshabilitada. Requiere configuración adicional.

4. **Sin alta disponibilidad**: una sola instancia por servicio. Caída del host = servicio caído.

5. **Backup en caliente**: el dump de PostgreSQL es consistente pero puede perder los últimos milisegundos de actividad. Para RPO menor, considerar replicación streaming.

6. **Sin push notifications móviles**: requiere servidor Sygnal adicional (no incluido).

7. **Construcción de Synapse**: el primer despliegue requiere construir la imagen desde el Dockerfile, lo que añade tiempo inicial (~2-5 minutos dependiendo del hardware y conexión).

### 12.2 Operativas

1. **Migración requiere downtime**: el procedimiento de migración entre hosts implica detener el stack durante la transferencia.

2. **Actualizaciones manuales**: las actualizaciones se realizan con `bash scripts/admin/update.sh`, que combina descarga de imágenes y recreación de contenedores.

3. **Sin auto-escalado**: el stack está dimensionado para los recursos del host. No escala automáticamente.

4. **Sin UI de administración**: todas las operaciones son vía CLI. No hay panel web (Synapse Admin es una app cliente separada).

5. **Solo 100 usuarios soportados confortablemente** con la configuración por defecto. Para más, ajustar `max_connections` en PostgreSQL y workers en Synapse.

---

## 13. Dependencias externas

### 13.1 Imágenes Docker base

| Imagen | Tag | Tipo | Tamaño aprox |
|--------|-----|------|--------------|
| Synapse | Build desde `synapse/Dockerfile` (base `matrixdotorg/synapse:v1.118.0`) | **Build** | ~400 MB |
| `postgres` | `16.4-alpine3.20` | Pull | 250 MB |
| `redis` | `7.4-alpine3.20` | Pull | 40 MB |
| `nginx` | `1.27.2-alpine3.20` | Pull | 50 MB |
| `vectorim/element-web` | `v1.11.65` | Pull | 200 MB |

### 13.2 Servicios externos opcionales

- **SMTP server**: para envío de notificaciones. Configurar en `.env`.
- **DNS local**: para resolución de dominios desde clientes.
- **NTP**: para sincronización de hora (crítico para TLS).

### 13.3 Paquetes del host

- `docker` 24+
- `docker compose plugin` v2
- `openssl` (para generación de certs)
- `tar` (para export/import de volúmenes)
- `bash` 4+