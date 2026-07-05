# Especificaciones técnicas

> Documento formal de especificaciones del proyecto **Matrix Docker Stack** versión 4.0.0.

---

## 1. Objetivos

### 1.1 Objetivo principal

Desplegar un servidor de mensajería instantánea **Matrix Synapse** completamente funcional en un entorno de red de área local (LAN), mediante contenedores Docker orquestados con Docker Compose, listo para uso productivo sin requerir exposición a Internet pública.

### 1.2 Objetivos específicos

1. Proveer un stack completo (Synapse + PostgreSQL + Redis + Element Web + Nginx) operable con un único comando.
2. Garantizar persistencia de datos mediante volúmenes Docker con nombre.
3. Aislar todos los servicios salvo los estrictamente necesarios para acceso desde la LAN.
4. Externalizar secretos en archivo `.env` no commiteado a control de versiones.
5. **Generar automáticamente todas las claves privadas** (certificados TLS, signing key de Synapse) durante la instalación, sin almacenarlas jamás en Git.
6. Validar completamente el entorno antes del primer arranque (dependencias, puertos, permisos, variables).
7. Proveer scripts administrativos equivalentes para Windows (PowerShell) y Linux (Bash).
8. Permitir migración transparente entre Docker Desktop (Windows) y Ubuntu Server.
9. Documentar exhaustivamente cada componente, decisión y procedimiento operativo.

---

## 2. Alcance

### 2.1 Incluido

- Configuración de Synapse con PostgreSQL, Redis, SMTP, sin federación, sin SQLite.
- Imagen Docker personalizada de Element Web con `config.json` preconfigurado.
- Nginx reverse proxy con TLS auto-firmado, headers de seguridad y rate limiting.
- 16 scripts Bash + 16 scripts PowerShell para administración.
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

## 3. Requisitos funcionales

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
| RF-19 | La instalación debe poder realizarse con un único comando (`./install.sh`) | Alta | ✅ (v4.0.0) |

---

## 4. Requisitos no funcionales

### 4.1 Rendimiento

| ID | Requisito | Métrica |
|----|-----------|---------|
| RNF-01 | Latencia de mensaje enviado/recibido | < 500 ms en LAN |
| RNF-02 | Tiempo de arranque del stack completo | < 5 minutos |
| RNF-03 | Soporte de usuarios concurrentes | ≥ 100 usuarios activos |
| RNF-04 | Throughput de mensajes | ≥ 50 msg/s sostenidos |
| RNF-05 | Tamaño máximo de archivo adjunto | 50 MB configurable |
| RNF-06 | Tiempo de backup de BD | < 30 segundos para 1 GB |

### 4.2 Disponibilidad

| ID | Requisito | Métrica |
|----|-----------|---------|
| RNF-07 | Uptime objetivo | 99.5% (mensual) |
| RNF-08 | Tiempo de recuperación (RTO) | < 15 minutos |
| RNF-09 | Punto de recuperación (RPO) | ≤ 24 horas |
| RNF-10 | Reinicio automático tras fallo | Sí (restart: unless-stopped) |

### 4.3 Seguridad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-11 | Cifrado en tránsito | TLS 1.2/1.3 con Nginx |
| RNF-12 | Cifrado en reposo de mensajes | E2EE nativo de Matrix |
| RNF-13 | Autenticación de usuarios | Password con política + pepper |
| RNF-14 | Secretos externalizados | `.env` con permisos 600 |
| RNF-15 | Aislamiento de red | Dos redes Docker internas |
| RNF-16 | Rate limiting | Por IP y endpoint en Nginx |
| RNF-17 | Hardening de contenedores | `no-new-privileges`, sin root cuando posible |
| RNF-18 | Auditoría de logs | Logs estructurados con retención |
| RNF-19 | Sin exposición innecesaria | Solo puertos 80/443 al host |
| RNF-20 | Contraseñas hasheadas | SCRAM-SHA-256 en PostgreSQL |

### 4.4 Mantenibilidad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-21 | Versiones pinned | Tags inmutables en docker-compose |
| RNF-22 | Documentación completa | 15 documentos + diagramas |
| RNF-23 | Scripts idempotentes | Verifican estado antes de actuar |
| RNF-24 | Estructura modular | Carpetas por servicio |
| RNF-25 | Backups automáticos | Cron job configurable |

### 4.5 Portabilidad

| ID | Requisito | Implementación |
|----|-----------|----------------|
| RNF-26 | Compatibilidad Windows + Linux | Scripts en PowerShell + Bash |
| RNF-27 | Migración sin reconfiguración | Scripts de export/import de volúmenes |
| RNF-28 | Sin dependencias del host | Todo en Docker, solo requiere Docker + openssl |

---

## 5. Hardware recomendado

### 5.1 Hardware mínimo

| Componente | Mínimo | Notas |
|------------|--------|-------|
| CPU | 2 núcleos x86_64 | 1.5 GHz mínimo |
| RAM | 4 GB | Docker + 5 contenedores |
| Almacenamiento | 20 GB SSD | Imágenes + datos + logs |
| Red | 100 Mbps | LAN |
| Storage tipo | SSD recomendado | HDD afecta rendimiento PostgreSQL |

### 5.2 Hardware recomendado

| Componente | Recomendado | Para |
|------------|-------------|------|
| CPU | 4+ núcleos x86_64 | 50+ usuarios concurrentes |
| RAM | 8 GB | Synapse + PostgreSQL cache |
| Almacenamiento | 100 GB SSD NVMe | Histórico de mensajes + media |
| Red | 1 Gbps | Videollamadas + media |
| Backup storage | 50 GB externo | Rotación 7 días |

### 5.3 Hardware para alta carga (200+ usuarios)

| Componente | Recomendado |
|------------|-------------|
| CPU | 8+ núcleos |
| RAM | 16-32 GB |
| Almacenamiento | 500 GB SSD NVMe + 1 TB HDD para backups |
| Red | 10 Gbps |

### 5.4 Desglose de RAM por servicio

| Servicio | Mínimo | Recomendado | Pico |
|----------|--------|-------------|------|
| PostgreSQL | 256 MB | 1 GB | 2 GB |
| Redis | 64 MB | 512 MB | 1 GB |
| Synapse | 512 MB | 2 GB | 4 GB |
| Element | 32 MB | 64 MB | 128 MB |
| Nginx | 32 MB | 64 MB | 128 MB |
| **Total** | **896 MB** | **3.6 GB** | **7.3 GB** |

---

## 6. Almacenamiento

### 6.1 Volúmenes Docker

| Volumen | Tamaño inicial estimado | Crecimiento | Tipo |
|---------|-------------------------|-------------|------|
| `matrix_synapse_data` | 100 MB | 1-10 GB | Mensajes, media, logs internos |
| `matrix_postgres_data` | 100 MB | 1-5 GB | Base de datos |
| `matrix_redis_data` | 10 MB | 100 MB | Caché persistente |
| `matrix_element_cache` | 10 MB | 100 MB | Cache nginx Element |
| `matrix_nginx_logs` | 10 MB | 500 MB | Access + error logs |

### 6.2 Estimación de crecimiento

Para 50 usuarios activos con uso moderado (100 mensajes/día + 5 MB media/día):
- Mensajes: ~50 KB/día → 18 MB/año
- Media: 250 MB/día → 91 GB/año
- Logs: 5 MB/día → 1.8 GB/año

**Recomendación**: dimensionar 50 GB/año de crecimiento para 50 usuarios activos.

---

## 7. Red

### 7.1 Puertos expuestos al host

| Puerto | Servicio | Propósito |
|--------|----------|-----------|
| 80 (TCP) | Nginx | HTTP - redirige a HTTPS |
| 443 (TCP) | Nginx | HTTPS - acceso cliente |

### 7.2 Puertos internos (no publicados)

| Puerto | Servicio | Accesible por |
|--------|----------|---------------|
| 5432 | PostgreSQL | Solo contenedores en `matrix_internal` |
| 6379 | Redis | Solo contenedores en `matrix_internal` |
| 8008 | Synapse | Solo contenedores en `matrix_internal` + `matrix_frontend` |
| 80 | Element | Solo contenedores en `matrix_frontend` |

### 7.3 Redes Docker

| Red | Tipo | `internal` | Servicios | Salida a Internet |
|-----|------|------------|-----------|-------------------|
| `matrix_internal` | bridge | **true** | PostgreSQL, Redis, Synapse | No (aislado) |
| `matrix_frontend` | bridge | false | Nginx, Element, Synapse | Sí (Synapse para SMTP) |

> **Nota v3.0.0**: `matrix_internal` tiene `internal: true`, lo que significa que los contenedores en esta red no tienen gateway a Internet. Synapse, que pertenece a ambas redes, utiliza `matrix_frontend` para conexiones SMTP salientes. Esto aísla completamente a PostgreSQL y Redis de cualquier comunicación externa.

### 7.4 Resolución DNS

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

## 8. Compatibilidad

### 8.1 Sistemas operativos del host

| OS | Versión | Soporte | Notas |
|----|---------|---------|-------|
| Ubuntu Server | 20.04 LTS | ✅ | Docker Engine nativo |
| Ubuntu Server | 22.04 LTS | ✅ Recomendado | Docker Engine nativo |
| Ubuntu Server | 24.04 LTS | ✅ | Docker Engine nativo, plataforma principal |
| Debian | 11, 12 | ✅ | Docker Engine nativo |
| Raspberry Pi 4 | ARM64 | ✅ | Todas las imágenes Docker soportan ARM64 |
| CentOS/RHEL | 8, 9 | ⚠️ No probado | Requiere ajustes de firewall |

### 8.2 Navegadores soportados (cliente Element)

- Chrome 100+ (recomendado)
- Firefox 100+ (recomendado)
- Edge 100+
- Safari 15+ (parcial - algunas features de videollamada pueden no funcionar)

### 8.3 Clientes móviles

- Element Android: configurable manualmente, requiere acceso a la URL del servidor.
- Element iOS: configurable manualmente, requiere confianza del certificado CA.

---

## 9. Limitaciones

### 9.1 Técnicas

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

### 9.2 Operativas

1. **Migración requiere downtime**: el procedimiento de migración Windows → Ubuntu implica detener el stack durante la transferencia.

2. **No hay auto-actualización**: las actualizaciones de imágenes son manuales via `update-images.sh` + `update-containers.sh`.

3. **Sin auto-escalado**: el stack está dimensionado para los recursos del host. No escala automáticamente.

4. **Sin UI de administración**: todas las operaciones son vía CLI. No hay panel web (Synapse Admin es una app cliente separada).

5. **Solo 100 usuarios soportados confortablemente** con la configuración por defecto. Para más, ajustar `max_connections` en PostgreSQL y workers en Synapse.

---

## 10. Dependencias externas

### 10.1 Imágenes Docker base

| Imagen | Tag | Tamaño aprox |
|--------|-----|--------------|
| `matrixdotorg/synapse` | `v1.118.0` | 350 MB |
| `postgres` | `16.4-alpine3.20` | 250 MB |
| `redis` | `7.4-alpine3.20` | 40 MB |
| `nginx` | `1.27.2-alpine3.20` | 50 MB |
| `vectorim/element-web` | `v1.11.65` | 200 MB |
| `alpine` | `3.20` (para scripts de migración) | 10 MB |

### 10.2 Servicios externos opcionales

- **SMTP server**: para envío de notificaciones. Configurar en `.env`.
- **DNS local**: para resolución de dominios desde clientes.
- **NTP**: para sincronización de hora (crítico para TLS).

### 10.3 Paquetes del host

- `docker` 24+
- `docker compose plugin` v2
- `openssl` (para generación de certs)
- `tar` (para export/import de volúmenes)
- `bash` 4+ (Linux) o `PowerShell` 5+ (Windows)
