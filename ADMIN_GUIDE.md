# Manual del administrador

> Guía práctica para administración diaria del stack Matrix Docker v5.0.0.
>
> **v5.0.0**: La instalación se realiza con un único comando: `./install.sh`, que ejecuta 14 pasos secuenciales seguidos de 14 pruebas automatizadas de verificación. Todos los secretos se generan automáticamente con `openssl rand`. La IP se detecta automáticamente. Synapse se construye desde un Dockerfile personalizado en vez de usar una imagen pre-construida. Los scripts administrativos se encuentran ahora en `scripts/admin/` y se han añadido `healthcheck.sh`, `update.sh` y `uninstall.sh`. Si necesitas reinstalar, ejecuta `./install.sh` de nuevo (preguntará antes de sobrescribir el `.env`). Para verificar el estado completo de los servicios en cualquier momento: `bash scripts/admin/healthcheck.sh`.

---

## Tabla de contenidos

1. [Rol del administrador](#1-rol-del-administrador)
2. [Tareas diarias](#2-tareas-diarias)
3. [Tareas semanales](#3-tareas-semanales)
4. [Tareas mensuales](#4-tareas-mensuales)
5. [Creación y gestión de usuarios](#5-creación-y-gestión-de-usuarios)
6. [Gestión de contraseñas](#6-gestión-de-contraseñas)
7. [Backups y restauración](#7-backups-y-restauración)
8. [Actualizaciones](#8-actualizaciones)
9. [Healthcheck y diagnóstico](#9-healthcheck-y-diagnóstico)
10. [Mantenimiento de almacenamiento](#10-mantenimiento-de-almacenamiento)
11. [Hardening post-instalación](#11-hardening-post-instalación)
12. [Solución de problemas comunes](#12-solución-de-problemas-comunes)
13. [Procedimientos de emergencia](#13-procedimientos-de-emergencia)
14. [El desinstalador (uninstall.sh)](#14-el-desinstalador-uninstallsh)
15. [Pruebas automatizadas del instalador](#15-pruebas-automatizadas-del-instalador)
16. [Checklist de mantenimiento](#16-checklist-de-mantenimiento)

---

## 1. Rol del administrador

Como administrador del stack Matrix Docker v5.0.0, eres responsable de garantizar el correcto funcionamiento de todos los componentes que conforman la plataforma de mensajería instantánea en tu organización. Este rol abarca cinco áreas fundamentales que deben atenderse de manera proactiva y sistemática para asegurar una experiencia de usuario óptima y un entorno seguro para la comunicación interna.

En primer lugar, la **disponibilidad** del servicio es tu responsabilidad principal: el sistema debe estar accesible para todos los usuarios durante el horario operativo acordado, lo que implica monitorear constantemente el estado de los cinco contenedores (PostgreSQL, Redis, Synapse, Element Web y Nginx) y responder rápidamente ante cualquier interrupción. En segundo lugar, la **integridad de los datos** exige que los mensajes, archivos adjuntos y metadatos de los usuarios se preserven sin pérdida, lo cual se logra mediante una estrategia de backups bien definida con verificación periódica de restauración.

La **seguridad** es otro pilar crítico: debes asegurar que los accesos no autorizados sean imposibles, lo que incluye la gestión adecuada de contraseñas, la rotación periódica de secretos, la revisión de logs de accesos fallidos y el mantenimiento de un entorno de red aislado donde PostgreSQL y Redis no tienen salida a Internet gracias a la red `matrix_internal` con `internal: true`. La **performance** también es relevante, especialmente porque los límites de memoria están definidos en el docker-compose (PostgreSQL 1 GB, Redis 512 MB, Synapse 2 GB, Nginx 256 MB), por lo que debes monitorear el consumo de recursos y ajustar estos valores si el crecimiento de la organización lo demanda. Finalmente, el **cumplimiento** implica respetar las políticas de retención de datos, mantener la trazabilidad de operaciones administrativas y documentar cualquier incidente de seguridad.

No necesitas ser experto en Matrix, Docker, PostgreSQL o Nginx individualmente, pero debes entender cómo interactúan los cinco servicios a través de las dos redes Docker (`matrix_internal` y `matrix_frontend`) y cómo los cinco volúmenes (`synapse_data`, `postgres_data`, `redis_data`, `element_nginx_cache`, `nginx_logs`) almacenan la información persistente. Este manual te guía paso a paso por cada operación administrativa utilizando los scripts ubicados en `scripts/admin/`.

---

## 2. Tareas diarias

### 2.1 Verificación matutina con healthcheck (5 minutos)

Desde la versión 5.0.0, la verificación diaria se realiza de forma unificada con el script `healthcheck.sh`, que valida el estado de todos los servicios, redes, volúmenes y conectividad en una sola ejecución. Este script reemplaza la necesidad de ejecutar múltiples comandos individuales y proporciona un resumen claro y estructurado del estado del stack completo, ideal para la revisión matutina rápida antes de iniciar la jornada laboral.

```bash
# Healthcheck unificado - verifica todo el stack
bash scripts/admin/healthcheck.sh
```

El script `healthcheck.sh` realiza las siguientes verificaciones de forma automática y secuencial: comprueba que los cinco contenedores estén en estado `running`, valida que los cinco volúmenes Docker existan y estén montados correctamente, verifica la conectividad de PostgreSQL mediante `pg_isready`, confirma que Redis responda al comando `PING`, comprueba que Synapse responda en su endpoint `/health`, valida que el certificado TLS sea accesible en el puerto 443, verifica la redirección HTTP a HTTPS, y comprueba que Element Web sea accesible a través del reverse proxy. Cada verificación se muestra con un indicador visual (✅ o ❌) para identificar rápidamente cualquier problema que requiera atención inmediata.

Si prefieres ver únicamente el estado de los contenedores sin la verificación completa de salud, puedes utilizar:

```bash
# Estado de contenedores
bash scripts/admin/status.sh
```

Verifica además de forma manual:
- Sin contenedores en estado `Restarting (N)`.
- Espacio en disco suficiente (>20% libre en la partición donde residen los volúmenes Docker).
- Sin errores recientes en los logs del sistema.

### 2.2 Revisión de logs (5-10 minutos)

La revisión periódica de logs te permite detectar problemas antes de que afecten a los usuarios. Utiliza el script `logs.sh` para acceder rápidamente a los registros de cualquier servicio del stack. Es importante revisar especialmente los logs de Synapse (donde se registran errores de autenticación y problemas de conectividad) y los de Nginx (donde se registran accesos fallidos y códigos de error HTTP).

```bash
# Ver últimos logs de cada servicio
bash scripts/admin/logs.sh

# Ver errores de Synapse en la última hora
bash scripts/admin/logs.sh synapse --since 1h | grep -i error

# Ver accesos fallidos en Nginx
bash scripts/admin/logs.sh nginx --since 24h | grep " 40[13] \| 50[0-9] "
```

El script `logs.sh` acepta como primer argumento el nombre del servicio (postgres, redis, synapse, element, nginx) y permite filtros adicionales como `--since` para limitar por tiempo. Los logs de Nginx también se almacenan de forma persistente en el volumen `nginx_logs`, por lo que pueden consultarse incluso después de reiniciar el contenedor.

### 2.3 Verificación de backups (1 minuto)

Si tienes cron configurado, verifica que el backup nocturno se ejecutó correctamente y que el archivo generado tiene un tamaño razonable. Un backup de base de datos vacía o de menos de 1 KB es señal de que algo falló durante el proceso de volcado.

```bash
ls -lah backups/ | tail -10
cat backups/cron.log | tail -20
```

---

## 3. Tareas semanales

### 3.1 Backup manual de verificación

Realizar un backup manual semanal además del automático te permite confirmar que el proceso funciona correctamente y tener un punto de restauración adicional independiente. El script `backup-db.sh` genera tanto el volcado de PostgreSQL como un archivo tar con las configuraciones críticas del proyecto, todo comprimido con gzip y etiquetado con fecha y hora para facilitar la identificación.

```bash
# Backup manual con etiqueta descriptiva
bash scripts/admin/backup-db.sh verificacion_semanal
# Output: backups/db_YYYYMMDD_HHMMSS_verificacion_semanal.sql.gz + config_*.tar.gz
```

Verifica que el archivo se generó con tamaño razonable (>1 KB) y que la rotación automática está funcionando correctamente eliminando backups más antiguos que el período de retención configurado. Si el backup supera los 500 MB, considera revisar el crecimiento de la base de datos y ajustar la política de retención de media en Synapse.

### 3.2 Limpieza de imágenes antiguas

Con el paso del tiempo y las actualizaciones periódicas, Docker acumula capas de imágenes que ya no están en uso. El script `clean-images.sh` elimina de forma segura todas las imágenes huérfanas, contenedores detenidos y caché de construcción que no están siendo utilizados por el stack en ejecución. Esta limpieza es importante para evitar que el disco se llene con datos innecesarios que podrían afectar el rendimiento general del sistema.

```bash
bash scripts/admin/clean-images.sh
```

### 3.3 Revisión de espacio en disco

La revisión semanal del espacio disponible en disco es fundamental para prevenir problemas de almacenamiento que podrían causar la detención de PostgreSQL (que falla cuando el disco está lleno) o la incapacidad de Synapse para almacenar nuevos archivos multimedia. Verifica tanto el espacio general del host como el uso específico de Docker, incluyendo volúmenes, imágenes y contenedores.

```bash
df -h
docker system df
```

Si el volumen de Synapse (`synapse_data`) crece excesivamente, considera:
- Revisar `media_store_path` en `homeserver.yaml`.
- Configurar `max_media_upload_size` más restrictivo.
- Ejecutar purga de media antigua (ver documentación Synapse).

### 3.4 Rotación de signing key (cada 6-12 meses)

Por seguridad, rota la signing key del servidor periódicamente. La signing key es crítica para la identidad criptográfica del servidor Matrix, y su rotación forma parte de las buenas prácticas de higiene de claves. El proceso implica generar una nueva clave, agregar la antigua a la lista de claves viejas para que las firmas previas sigan siendo válidas, y reiniciar Synapse para que utilice la nueva clave.

1. Genera una nueva key:
   ```bash
   openssl rand -hex 32 | xxd -r -p | base64
   ```
2. Agrega la key vieja a `old_signing_keys` en `homeserver.yaml`.
3. Reemplaza el contenido de `synapse/signing.key`.
4. Reinicia Synapse: `bash scripts/admin/restart.sh synapse`.
5. Verifica que los clientes reconectan correctamente usando `bash scripts/admin/healthcheck.sh`.

---

## 4. Tareas mensuales

### 4.1 Actualización con script unificado

A partir de v5.0.0, el proceso de actualización se simplifica con el script `update.sh`, que combina la descarga de nuevas imágenes (y reconstrucción de Synapse si el Dockerfile cambió) con la recreación ordenada de los contenedores. Este script unificado reemplaza la necesidad de ejecutar `update-images.sh` y `update-containers.sh` por separado, reduciendo la posibilidad de errores humanos durante el proceso de actualización.

```bash
# Actualización completa con un solo comando
bash scripts/admin/update.sh
```

El script `update.sh` realiza lo siguiente de forma secuencial: verifica que el stack esté funcionando antes de iniciar, ejecuta un backup preventivo automático de la base de datos, reconstruye la imagen de Synapse desde el Dockerfile (si hubo cambios), descarga las imágenes actualizadas de los demás servicios, recrea los contenedores con las nuevas imágenes en el orden correcto, y ejecuta el healthcheck final para confirmar que todo funciona correctamente.

Antes de actualizar manualmente:
- Lee el [changelog de Synapse](https://github.com/element-hq/synapse/blob/master/CHANGES.md).
- Verifica compatibilidad con Element Web.
- Programa ventana de mantenimiento si es una actualización mayor.

### 4.2 Revisión de usuarios

Realizar una auditoría mensual de usuarios te permite identificar cuentas inactivas, verificar que los permisos de administrador estén asignados correctamente y mantener la higiene del directorio de usuarios. Esta revisión es especialmente importante en organizaciones con rotación de personal, donde pueden acumularse cuentas de personas que ya no forman parte de la organización.

```bash
# Listar usuarios con fecha de creación y rol
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, to_timestamp(creation_ts) AS created, admin FROM users ORDER BY creation_ts DESC;"
```

Verifica:
- Usuarios inactivos (sin login en 90 días).
- Usuarios con permisos admin innecesarios.
- Cuentas huérfanas (para desactivar).

### 4.3 Auditoría de seguridad

La auditoría mensual de seguridad es una práctica esencial para detectar intentos de intrusión, configuraciones que se hayan modificado accidentalmente y certificados próximos a expirar. Revisa sistemáticamente los siguientes puntos: intentos de login fallidos en logs de Synapse (pueden indicar ataques de fuerza bruta), conexiones rechazadas en PostgreSQL (pueden indicar que alguien intenta acceder directamente a la base de datos), y el estado de los certificados TLS que tienen una validez de 1 año desde su generación.

```bash
# Ver expiración de certs
openssl x509 -enddate -noout -in nginx/certs/matrix.crt
```

### 4.4 Test de restauración

Realizar un test mensual de restauración en un entorno de prueba (nunca en producción) es la única forma de garantizar que tus backups son realmente útiles cuando los necesites. Un backup que no se ha probado de restaurar es equivalente a no tener backup. El proceso debe verificar que las tablas se cargan sin errores, que los usuarios existen con sus datos intactos, y que los mensajes están accesibles desde el cliente Element.

```bash
# En un host de test
bash scripts/admin/restore-db.sh backups/db_YYYYMMDD_HHMMSS.sql.gz
```

Verifica que:
- Las tablas se cargan sin errores.
- Los usuarios existen.
- Los mensajes están accesibles.

---

## 5. Creación y gestión de usuarios

### 5.1 Crear usuario administrador

El script `create-admin.sh` simplifica la creación de usuarios con privilegios de administrador. Este script se conecta al contenedor de Synapse, utiliza la API de registro compartido (configurada con el secret del archivo `.env`) y otorga automáticamente permisos de administración al nuevo usuario. Es el método recomendado para crear la primera cuenta de administración después de la instalación, así como para añadir nuevos administradores cuando el equipo de gestión crece.

```bash
# Crear administrador (pedirá contraseña interactivamente)
bash scripts/admin/create-admin.sh <username>
```

El script pide la contraseña de forma interactiva (no se muestra en pantalla ni se registra en el historial de bash). El usuario creado tiene permisos completos de administración sobre el servidor, incluyendo la capacidad de gestionar otros usuarios, habitaciones y configuración del servidor a través de Element Web.

### 5.2 Crear usuario normal

Para crear usuarios sin privilegios de administración, utiliza el script `create-user.sh`. Este script sigue el mismo flujo que `create-admin.sh` pero no otorga el flag de administrador, por lo que el usuario podrá utilizar todas las funcionalidades estándar de Matrix (mensajería, salas, archivos, videollamadas) sin acceso a las herramientas de administración del servidor.

```bash
# Crear usuario normal
bash scripts/admin/create-user.sh <username>
```

### 5.3 Listar usuarios existentes

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, to_timestamp(creation_ts) AS created, admin FROM users ORDER BY creation_ts DESC;"
```

### 5.4 Promover usuario a admin

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET admin = 1 WHERE name = '@usuario:home.arpa';"
```

### 5.5 Desactivar usuario

```bash
# Vía API admin
docker compose exec synapse \
    curl -X POST http://localhost:8008/_synapse/admin/v1/deactivate/@usuario:home.arpa \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 5.6 Restablecer contraseña de usuario

```bash
# Generar nueva contraseña aleatoria
NEW_PASS=$(openssl rand -base64 18)
echo "Nueva contraseña: $NEW_PASS"

# Hash con bcrypt (requiere Python passlib)
HASH=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.hash('$NEW_PASS', rounds=12))")

# Actualizar en BD
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET password_hash='$HASH' WHERE name='@usuario:home.arpa';"
```

---

## 6. Gestión de contraseñas

### 6.1 Política de contraseñas

La configuración en `homeserver.yaml` define una política de contraseñas robusta que se aplica a todos los usuarios del servidor. Esta política garantiza un nivel mínimo de complejidad que dificulta ataques de fuerza bruta y diccionario, protegiendo las cuentas incluso si la base de datos llega a comprometerse, ya que las contraseñas se almacenan hasheadas con bcrypt y un pepper adicional configurado en el archivo `homeserver.yaml`.

```yaml
password_config:
  policy:
    enabled: true
    minimum_length: 10
    require_digit: true
    require_symbol: true
    require_lowercase: true
    require_uppercase: true
```

Para modificar la política, edita `synapse/homeserver.yaml` y reinicia Synapse con `bash scripts/admin/restart.sh synapse`.

### 6.2 Cambiar tu propia contraseña (como admin)

1. Inicia sesión en Element.
2. Ve a Ajustes → Cuenta → Cambiar contraseña.

### 6.3 Forzar cambio de contraseña a todos los usuarios

En caso de compromiso de credenciales, es necesario forzar un cambio masivo de contraseñas de forma inmediata. Este procedimiento es drástico pero necesario cuando existe la posibilidad de que un atacante haya obtenido acceso a las contraseñas de uno o más usuarios. Debes ejecutar este proceso con cautela y comunicar a todos los usuarios afectados por un canal seguro fuera de banda.

```bash
# 1. Generar nuevas contraseñas aleatorias por usuario
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name FROM users;" > usuarios.txt

# 2. Para cada usuario, generar y aplicar nueva contraseña (ver 5.6)
# 3. Enviar contraseñas por canal fuera de banda (telefono, email externo)
# 4. Invalidar todas las sesiones activas:
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "DELETE FROM access_tokens;"
```

---

## 7. Backups y restauración

### 7.1 Backup manual

El script `backup-db.sh` genera un backup completo de la base de datos PostgreSQL comprimido con gzip, junto con un archivo tar que contiene todas las configuraciones críticas del proyecto (archivos `.env`, `homeserver.yaml`, `redis.conf`, `nginx.conf`, certificados TLS y la signing key de Synapse). Este enfoque de doble archivo garantiza que, en caso de desastre, puedas restaurar no solo los datos sino también la configuración exacta que los generó.

```bash
# Backup manual
bash scripts/admin/backup-db.sh
# Output: backups/db_YYYYMMDD_HHMMSS.sql.gz + config_*.tar.gz
```

### 7.2 Backup automático (Ubuntu)

Configurar backups automáticos mediante cron es fundamental para garantizar que los datos se respalden de forma regular sin intervención manual. El archivo cron se instala en `/etc/cron.d/` y ejecuta el script de backup a la hora configurada, registrando la actividad en un archivo de log específico para facilitar la auditoría y la resolución de problemas si el backup falla en algún momento.

```bash
sudo cp deployment/matrix-backup.cron /etc/cron.d/matrix-backup
sudo chmod 644 /etc/cron.d/matrix-backup
sudo chown root:root /etc/cron.d/matrix-backup
sudo systemctl reload cron
```

Verifica ejecución:

```bash
sudo tail -f /var/log/syslog | grep CRON
cat backups/cron.log
```

### 7.3 Restauración

El script `restore-db.sh` implementa un proceso de restauración seguro que incluye un backup preventivo automático antes de aplicar cualquier cambio. Esto significa que, si la restauración falla o se restaura un backup incorrecto, siempre podrás volver al estado anterior. El script solicita confirmación explícita por escrito (debes escribir "SÍ" para proceder) para evitar restauraciones accidentales causadas por una ejecución involuntaria del comando.

```bash
# Restaurar desde backup
bash scripts/admin/restore-db.sh backups/db_YYYYMMDD_HHMMSS.sql.gz
```

El script:
1. Hace un backup preventivo (por si acaso).
2. Pide confirmación escrita ("SÍ").
3. Restaura con `pg_restore --clean --if-exists`.
4. Reinicia Synapse para recargar datos.

Ver detalles en [`docs/10-restauracion.md`](docs/10-restauracion.md).

### 7.4 Estrategia de retención recomendada

| Tipo | Retención | Ubicación |
|------|-----------|-----------|
| Diarios | 7 días | Local (server) |
| Semanales | 4 semanas | Local + NAS |
| Mensuales | 12 meses | NAS + offsite |
| Anuales | 5 años | Offsite (cold storage) |

---

## 8. Actualizaciones

### 8.1 Actualización con script unificado (v5.0.0)

A partir de la versión 5.0.0, el proceso de actualización se ha simplificado significativamente con la introducción del script `update.sh` en `scripts/admin/`. Este script unificado reemplaza los anteriores `update-images.sh` y `update-containers.sh`, combinando ambas operaciones en un flujo secuencial seguro que incluye verificación previa, backup automático, reconstrucción de la imagen de Synapse desde el Dockerfile personalizado, descarga de nuevas imágenes de los demás servicios, y recreación ordenada de los contenedores.

```bash
# Actualización completa en un solo comando
bash scripts/admin/update.sh
```

El flujo interno del script `update.sh` es el siguiente: primero verifica que todos los contenedores estén funcionando correctamente mediante un healthcheck rápido; luego ejecuta un backup preventivo de la base de datos etiquetado como `pre_update`; a continuación, reconstruye la imagen de Synapse desde el Dockerfile (lo que permite incorporar cambios en dependencias o configuración de la imagen); después descarga las versiones más recientes de las imágenes de PostgreSQL, Redis, Element Web y Nginx; finalmente recrea los contenedores en el orden correcto (primero la base de datos, luego los servicios dependientes) y ejecuta un healthcheck final para confirmar que todo funciona correctamente.

### 8.2 Actualización de versiones pinned

Cuando quieras cambiar Synapse o PostgreSQL a una versión mayor:

1. Lee el **changelog** y los **upgrade notes** de la versión.
2. Verifica compatibilidad con Element Web.
3. Programa ventana de mantenimiento (anuncia a usuarios).
4. Haz backup completo: `bash scripts/admin/backup-db.sh pre_major_update`.
5. Edita la versión base en `synapse/Dockerfile` para Synapse, o el tag en `docker-compose.yml` para PostgreSQL.
6. Si hay cambios de esquema de BD, sigue el procedimiento de migración específico de Synapse.
7. Aplica con `bash scripts/admin/update.sh`.
8. Ejecuta `bash scripts/admin/healthcheck.sh` y monitorea logs por 24 horas.

### 8.3 Rollback

Si la actualización falla y necesitas volver a la versión anterior, el proceso de rollback implica revertir los cambios en los archivos de configuración y restaurar la base de datos desde el backup preventivo que el script `update.sh` creó automáticamente antes de iniciar la actualización.

```bash
# 1. Restaurar versión anterior en docker-compose.yml y/o synapse/Dockerfile
nano docker-compose.yml  # revertir tag
nano synapse/Dockerfile  # revertir versión base de Synapse

# 2. Restaurar BD del backup pre-update
bash scripts/admin/restore-db.sh backups/db_pre_update_*.sql.gz

# 3. Reconstruir y reiniciar
bash scripts/admin/update.sh
```

---

## 9. Healthcheck y diagnóstico

### 9.1 Script healthcheck unificado (v5.0.0)

El script `healthcheck.sh` es una de las novedades más importantes de la versión 5.0.0. Proporciona una verificación completa de la salud del stack en una sola ejecución, validando todos los componentes críticos del sistema de forma secuencial y presentando los resultados de manera clara y estructurada. Este script está diseñado para ser utilizado tanto en la verificación diaria rutinaria como en la resolución de problemas, donde permite identificar rápidamente qué componente está fallando.

```bash
# Healthcheck completo del stack
bash scripts/admin/healthcheck.sh
```

Las verificaciones que realiza el script son las siguientes:

1. **Contenedores en ejecución**: comprueba que los 5 servicios estén en estado `running`.
2. **Volúmenes montados**: valida que los 5 volúmenes Docker existan.
3. **Redes configuradas**: verifica que `matrix_internal` y `matrix_frontend` existan.
4. **Aislamiento de red**: confirma que `matrix_internal` tiene `internal: true`.
5. **PostgreSQL saludable**: ejecuta `pg_isready` contra el contenedor.
6. **Redis saludable**: envía `PING` y verifica la respuesta `PONG`.
7. **Synapse saludable**: verifica que el endpoint `/health` devuelva HTTP 200.
8. **TLS funcional**: comprueba la conexión HTTPS en el puerto 443.
9. **Redirección HTTP→HTTPS**: verifica que el puerto 80 redirige correctamente.
10. **Element Web accesible**: confirma que el cliente web responda con HTML.

Cada verificación se muestra con un indicador ✅ (correcto) o ❌ (fallido), seguido del tiempo de respuesta cuando es aplicable. Al finalizar, el script muestra un resumen con el total de verificaciones pasadas y fallidas, y devuelve un código de salida 0 si todo está correcto o 1 si alguna verificación falló, lo que permite integrarlo en scripts de monitoreo o CI/CD.

### 9.2 Ubicación de logs

| Servicio | Ubicación | Acceso |
|----------|-----------|--------|
| PostgreSQL | Docker logs | `docker compose logs postgres` |
| Redis | Docker logs | `docker compose logs redis` |
| Synapse | Docker logs + `/data/logs/homeserver.log` | `docker compose logs synapse` |
| Element | Docker logs | `docker compose logs element` |
| Nginx | Volumen `nginx_logs` (persistente) | `docker compose logs nginx` |

### 9.3 Comandos útiles de diagnóstico

```bash
# Ver logs en vivo de un servicio
docker compose logs -f synapse

# Últimas 200 líneas
docker compose logs --tail 200 synapse

# Desde una hora atrás
docker compose logs --since 1h synapse

# Rango de tiempo
docker compose logs --since 2026-07-04T10:00:00 --until 2026-07-04T12:00:00 synapse

# Filtrar errores
docker compose logs synapse 2>&1 | grep -i "error\|warning"

# Estadísticas de uso de recursos (incluye límites de memoria v5.0.0)
docker compose stats
```

Más detalles en [`docs/15-logs.md`](docs/15-logs.md).

---

## 10. Mantenimiento de almacenamiento

### 10.1 Verificar espacio

El mantenimiento proactivo del almacenamiento es esencial para prevenir fallos en producción, especialmente porque PostgreSQL detiene su funcionamiento cuando el disco se llena, lo que causaría la caída inmediata de todo el stack. La verificación regular del espacio disponible te permite planificar la ampliación de almacenamiento antes de que se convierta en una emergencia, y también te ayuda a identificar patrones de crecimiento anómalos que podrían indicar un problema de configuración o un uso indebido del sistema.

```bash
# Espacio del host
df -h

# Espacio usado por Docker
docker system df -v

# Tamaño individual de cada volumen
docker volume inspect synapse_data --format '{{.Mountpoint}}'
sudo du -sh /var/lib/docker/volumes/synapse_data/_data
sudo du -sh /var/lib/docker/volumes/postgres_data/_data
sudo du -sh /var/lib/docker/volumes/redis_data/_data
sudo du -sh /var/lib/docker/volumes/element_nginx_cache/_data
sudo du -sh /var/lib/docker/volumes/nginx_logs/_data
```

### 10.2 Limpieza de Docker

La acumulación de recursos no utilizados en Docker (imágenes antiguas, contenedores detenidos, redes huérfanas y caché de construcción) puede consumir una cantidad significativa de espacio en disco con el tiempo. Es importante realizar limpiezas periódicas utilizando los comandos apropiados, teniendo siempre cuidado de no eliminar volúmenes con datos activos. El script `clean-images.sh` (`bash scripts/admin/clean-images.sh`) realiza una limpieza segura de forma automatizada, pero también puedes ejecutar los comandos manualmente si necesitas un control más granular sobre lo que se elimina.

```bash
# Limpiar contenedores parados
docker container prune -f

# Limpiar imágenes sin usar
docker image prune -a -f

# Limpiar redes sin usar
docker network prune -f

# Limpiar build cache (importante porque Synapse se construye desde Dockerfile)
docker builder prune -a -f

# O usar el script que hace todo de forma segura
bash scripts/admin/clean-images.sh
```

> **Nota**: NUNCA ejecutes `docker system prune -a -f --volumes` en producción, ya que eliminaría los volúmenes con datos persistentes.

### 10.3 Purga de media antigua

Synapse acumula archivos multimedia descargados (imágenes, documentos, vídeos) que pueden ocupar mucho espacio con el tiempo. La API de administración permite purgar archivos multimedia anteriores a una fecha específica, liberando espacio en el volumen `synapse_data`. Es recomendable establecer una política de purga periódica, por ejemplo eliminando media con más de 90 días de antigüedad.

```bash
# API admin - purge media older than timestamp (en milisegundos)
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/home.arpa/delete?before_ts=1640000000000" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

### 10.4 VACUUM PostgreSQL

El comando `VACUUM FULL` recupera espacio físico en la base de datos eliminando las tuplas muertas que se acumulan tras operaciones de actualización y borrado. Sin embargo, este comando bloquea las tablas durante su ejecución, por lo que debe programarse en una ventana de mantenimiento donde los usuarios hayan sido notificados previamente. Para una versión menos intrusiva que no bloquea tablas, utiliza `VACUUM ANALYZE` (sin FULL).

```bash
# VACUUM completo (bloquea tablas - ventana de mantenimiento)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "VACUUM FULL ANALYZE;"

# VACUUM sin bloqueo (se puede ejecutar en horario productivo)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "VACUUM ANALYZE;"
```

---

## 11. Hardening post-instalación

### 11.1 Endurecimiento del host (Ubuntu)

El endurecimiento del sistema operativo subyacente es una capa adicional de seguridad que complementa las medidas ya implementadas dentro de los contenedores Docker. Estas configuraciones protegen contra ataques que no pasan por los servicios de Matrix, como intentos de acceso SSH directo al servidor o explotación de vulnerabilidades en otros servicios que puedan estar ejecutándose en el mismo host. La implementación de estas medidas debe realizarse inmediatamente después de la instalación del stack y revisarse periódicamente para asegurar que se mantienen vigentes.

```bash
# 1. SSH: deshabilitar login root y password
sudo sed -i 's/#PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 2. Fail2ban
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# 3. Actualizaciones automáticas de seguridad
sudo dpkg-reconfigure -plow unattended-upgrades

# 4. Firewall (ver deployment/setup-firewall.sh)
sudo bash deployment/setup-firewall.sh 192.168.1.0/24
```

### 11.2 Endurecimiento de Synapse

Edita `synapse/homeserver.yaml` para verificar o reforzar las configuraciones de seguridad del servidor Matrix. La mayoría de estas configuraciones ya están establecidas por el instalador, pero es importante verificarlas y ajustarlas según las necesidades específicas de tu organización, especialmente los parámetros de throttling que protegen contra ataques de fuerza bruta en los endpoints de autenticación.

```yaml
# Deshabilitar federation explícitamente
federation:
  enabled: false

# Limitar tamaño de uploads
max_upload_size: 50M

# Throttling agresivo para auth
rc_login:
  address:
    per_second: 0.1
    burst_count: 3

# Deshabilitar registration pública
enable_registration: false

# Deshabilitar URL preview (LAN sin Internet)
url_preview_enabled: false
```

Después de cualquier cambio, reinicia Synapse: `bash scripts/admin/restart.sh synapse`.

### 11.3 Endurecimiento de Nginx

Ya incluido en `nginx/nginx.conf` y `nginx/snippets/security-headers.conf`. Verifica que las configuraciones de seguridad están activas consultando la configuración compilada de Nginx dentro del contenedor. Esto te permite confirmar que los protocolos TLS, los cifrados permitidos y los headers de seguridad están configurados correctamente sin necesidad de inspeccionar manualmente cada archivo de configuración.

```bash
docker compose exec nginx nginx -T | grep -E "ssl_protocols|ssl_ciphers|server_tokens"
```

---

## 12. Solución de problemas comunes

### 12.1 El stack no arranca

Cuando el stack completo no arranca, el problema suele estar relacionado con la configuración del archivo `.env`, certificados TLS faltantes, o problemas de permisos en los volúmenes. Sigue estos pasos de diagnóstico en orden para identificar la causa raíz del problema de forma sistemática. Comienza verificando la sintaxis del archivo docker-compose, luego revisa los logs de cada servicio individualmente, y finalmente verifica los archivos de configuración y certificados.

```bash
# 1. Ver errores de compose
docker compose config
docker compose up

# 2. Ver logs de cada servicio
docker compose logs

# 3. Verificar que .env existe y tiene valores válidos
cat .env | grep -v "^#"

# 4. Verificar signing key
ls -la synapse/signing.key

# 5. Verificar certs
ls -la nginx/certs/

# 6. Si Synapse usa Dockerfile, verificar la build
docker compose build synapse
```

### 12.2 Element no conecta con Matrix

Los problemas de conexión entre Element Web y Synapse suelen estar relacionados con la configuración del endpoint `.well-known`, problemas de DNS local, o certificados TLS que no son confiados por el navegador del cliente. Sigue estos pasos de diagnóstico para identificar rápidamente donde está el fallo en la cadena de conexión entre el navegador del usuario y el servidor Synapse a través del reverse proxy Nginx.

```bash
# 1. Verificar que Synapse responde
curl -k https://matrix.home.arpa/health

# 2. Verificar .well-known
curl -k https://matrix.home.arpa/.well-known/matrix/client

# 3. Verificar DNS local
nslookup matrix.home.arpa
nslookup element.home.arpa

# 4. Verificar que el cliente confía en la CA
# Importar nginx/certs/ca.crt en el navegador
```

### 12.3 PostgreSQL no arranca

Los fallos de PostgreSQL son críticos ya que sin la base de datos, todo el stack queda inoperativo. Las causas más comunes incluyen corrupción del volumen de datos (por un apagado abrupto del host), permisos incorrectos en los archivos del volumen, o un disco lleno. Antes de tomar cualquier acción drástica como eliminar el volumen, asegúrate de tener un backup reciente disponible para restaurar los datos.

```bash
# Logs
docker compose logs postgres

# Verificar permisos del volumen
docker compose exec postgres ls -la /var/lib/postgresql/data

# Si el volumen está corrupto (PELIGROSO - solo si tienes backup)
docker volume rm postgres_data
docker compose up -d postgres
bash scripts/admin/restore-db.sh backups/db_*.sql.gz
```

### 12.4 Redis OOM o lento

Redis tiene un límite de memoria de 512 MB configurado tanto en el `redis.conf` como en el límite Docker del contenedor. Si Redis alcanza este límite, comenzará a rechazar operaciones de escritura o a evictar claves según la política configurada. Verifica el uso de memoria actual y ajusta la configuración si es necesario.

```bash
# Verificar uso de memoria
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO memory

# Ajustar maxmemory en redis/redis.conf
# Reiniciar: bash scripts/admin/restart.sh redis
```

Más problemas en [`docs/11-resolucion-problemas.md`](docs/11-resolucion-problemas.md).

---

## 13. Procedimientos de emergencia

### 13.1 Caída del servicio en horario productivo

Cuando el servicio se cae durante el horario productivo, la prioridad es restaurar la disponibilidad lo más rápido posible. Sigue estos pasos en orden, avanzando al siguiente solo si el anterior no resuelve el problema. Es fundamental comunicar a los usuarios a través de un canal alternativo (email, teléfono, otro sistema de mensajería) que se está trabajando en la resolución del problema para evitar que intenten acciones que puedan empeorar la situación.

1. **Diagnosticar**: `bash scripts/admin/healthcheck.sh` para identificar qué servicio falla.
2. **Reiniciar servicio caído**: `bash scripts/admin/restart.sh <servicio>`.
3. **Si no funciona**: `bash scripts/admin/stop.sh && bash scripts/admin/start.sh`.
4. **Si persiste**: revisar logs del servicio afectado con `bash scripts/admin/logs.sh <servicio>`.
5. **Comunicar a usuarios**: usar canal alternativo (email, teléfono).

### 13.2 Pérdida de datos (escenario desastre)

La pérdida de datos es el escenario más crítico que un administrador puede enfrentar. En este caso, la prioridad es detener inmediatamente cualquier actividad que pueda causar más daño, evaluar el alcance de la pérdida, y proceder con la restauración desde el backup más reciente disponible. Es fundamental documentar detalladamente el incidente, incluyendo la hora de detección, el alcance estimado de la pérdida, y las acciones tomadas para la recuperación.

1. **Detener el stack**: `bash scripts/admin/stop.sh`
2. **Restaurar último backup**:
   ```bash
   bash scripts/admin/restore-db.sh backups/db_ULTIMO.sql.gz
   ```
3. **Si el volumen está corrupto**:
   ```bash
   docker compose down -v  # ⚠️ borra volúmenes
   docker volume create synapse_data
   docker volume create postgres_data
   docker volume create redis_data
   docker volume create element_nginx_cache
   docker volume create nginx_logs
   bash scripts/admin/restore-db.sh backups/db_ULTIMO.sql.gz
   ```
4. **Iniciar**: `bash scripts/admin/start.sh`
5. **Verificar integridad**: `bash scripts/admin/healthcheck.sh`
6. **Auditar qué se perdió** entre el último backup y el incidente.

### 13.3 Compromiso de credenciales

Ante la sospecha o confirmación de un compromiso de credenciales, es necesario actuar de forma rápida y exhaustiva para contener la brecha de seguridad. Esto incluye la desactivación inmediata de las cuentas afectadas, la invalidación de todas las sesiones activas, el reseteo de todas las contraseñas, y la rotación de todos los secretos del sistema (contraseñas de base de datos, claves de registro, claves de macaroon y pepper de contraseñas).

1. **Identificar alcance**: qué cuentas/secciones comprometidas.
2. **Desactivar cuentas afectadas** (ver 5.5).
3. **Forzar logout de todas las sesiones**:
   ```bash
   docker compose exec postgres psql -U synapse_user -d synapse \
       -c "DELETE FROM access_tokens;"
   ```
4. **Resetear contraseñas** (ver 5.6).
5. **Rotar secretos** en `.env` y `homeserver.yaml`:
   - `POSTGRES_PASSWORD`
   - `REDIS_PASSWORD`
   - `SYNAPSE_REGISTRATION_SHARED_SECRET`
   - `SYNAPSE_MACAROON_SECRET_KEY`
   - `password_config.pepper` (invalida todos los hashes de password)
6. **Reiniciar stack**: `bash scripts/admin/restart.sh`
7. **Auditar logs** buscando actividad maliciosa.
8. **Documentar incidente**.

### 13.4 Host caído (hardware failure)

Cuando el hardware del servidor falla completamente, la recuperación requiere aprovisionar un nuevo servidor y restaurar tanto el proyecto como los datos desde los backups. Este escenario es la razón principal por la que los backups deben almacenarse en una ubicación externa al servidor (offsite), ya que si el disco del servidor está dañado, los backups locales también lo estarán. Asegúrate de tener documentado el procedimiento completo de recuperación y de haberlo probado al menos una vez al trimestre.

1. **Tener backup reciente accesible** (offsite).
2. **Aprovisionar nuevo host** Ubuntu Server 22.04/24.04 LTS.
3. **Instalar Docker**: `bash deployment/install-docker-ubuntu.sh`.
4. **Restaurar proyecto completo** desde el repositorio.
5. **Ejecutar `./install.sh`** para reconstruir el entorno.
6. **Restaurar BD**: `bash scripts/admin/restore-db.sh ...`.
7. **Actualizar DNS** para apuntar al nuevo host (o usar **Tailscale**).
8. **Verificar acceso**: `bash scripts/admin/healthcheck.sh`.

---

## 14. El desinstalador (uninstall.sh)

### 14.1 Descripción general

El script `uninstall.sh`, ubicado en la raíz del proyecto, es una de las novedades más importantes de la versión 5.0.0 y proporciona un mecanismo limpio, seguro y controlado para eliminar completamente el stack Matrix Docker del servidor. A diferencia de un `docker compose down -v` que elimina todo sin confirmación ni posibilidad de seleccionar qué componentes conservar, el desinstalador guía al administrador paso a paso, solicitando confirmación explícita antes de cada acción destructiva y permitiendo un control granular sobre qué elementos se eliminan y cuáles se conservan. Este enfoque por pasos reduce significativamente el riesgo de pérdida accidental de datos y permite desinstalaciones parciales cuando solo se desea eliminar los contenedores pero conservar los datos para una posible reinstalación futura.

### 14.2 Cómo ejecutarlo

El desinstalador debe ejecutarse desde la raíz del proyecto con permisos de ejecución. Se recomienda detener primero el stack con `bash scripts/admin/stop.sh` antes de ejecutar el desinstalador, aunque el script lo hará automáticamente si el stack aún está en ejecución.

```bash
# Ejecutar el desinstalador
./uninstall.sh
```

### 14.3 Flujo de ejecución

El script `uninstall.sh` sigue un flujo secuencial de seis pasos, donde cada paso requiere confirmación explícita del administrador antes de proceder. Este diseño garantiza que el administrador tenga control total sobre el proceso de desinstalación y pueda detenerlo en cualquier punto si se arrepiente o si identifica que no debería eliminar un componente específico.

1. **Confirmación inicial**: el script muestra un resumen de lo que será eliminado y solicita que escribas "SÍ" para continuar. Si escribes cualquier otra cosa, el script se cancela inmediatamente sin realizar ningún cambio.
2. **Detención y eliminación de contenedores**: ejecuta `docker compose down` para detener y eliminar los cinco contenedores del stack.
3. **Eliminación de redes Docker**: elimina las redes `matrix_internal` y `matrix_frontend` que fueron creadas por el proyecto.
4. **Opción de eliminar volúmenes**: pregunta si deseas eliminar los cinco volúmenes Docker (`synapse_data`, `postgres_data`, `redis_data`, `element_nginx_cache`, `nginx_logs`). Responder "no" aquí te permite reinstalar el stack después conservando todos los datos.
5. **Opción de eliminar imágenes**: pregunta si deseas eliminar las imágenes Docker (incluyendo la imagen construida de Synapse). Esto libera el espacio en disco utilizado por las imágenes.
6. **Opción de eliminar el archivo .env**: pregunta si deseas eliminar el archivo `.env` que contiene todos los secretos (contraseñas, tokens, claves). Responder "sí" destruye permanentemente los secretos del sistema.

### 14.4 Cuándo utilizar el desinstalador

Utiliza el script `uninstall.sh` en las siguientes situaciones: cuando necesitas hacer una reinstalación limpia desde cero (eliminando volúmenes y `.env`), cuando el servidor va a ser repuesto y necesitas liberar todos los recursos de Docker utilizados por el stack, cuando estás migrando a otro servidor y ya has restaurado los datos en el nuevo destino, o cuando ya no necesitas el servicio de mensajería Matrix en este servidor. En todos los casos, asegúrate de tener un backup actualizado antes de ejecutar el desinstalador, especialmente si vas a eliminar los volúmenes de datos.

### 14.5 Precauciones importantes

Antes de ejecutar el desinstalador, ten en cuenta las siguientes precauciones: **nunca ejecute el desinstalador sin tener un backup reciente** si planea conservar los datos; la eliminación de volúmenes es **irreversible** y no puede deshacerse; la eliminación del archivo `.env` destruye las contraseñas y tokens del sistema, por lo que necesitarás generar nuevos secretos si reinstalas; y la eliminación de la imagen construida de Synapse requerirá una nueva compilación desde el Dockerfile si decides reinstalar el stack en el futuro.

---

## 15. Pruebas automatizadas del instalador

### 15.1 Descripción general

Una de las funcionalidades más relevantes introducidas en la versión 5.0.0 es la inclusión de 14 pruebas automatizadas que se ejecutan al final del proceso de instalación (`install.sh`). Estas pruebas validan de forma exhaustiva que el despliegue se ha completado correctamente y que todos los componentes del stack funcionan e interactúan entre sí como es esperado. Esta automatización elimina la necesidad de verificar manualmente cada componente después de la instalación, reduce significativamente la posibilidad de errores humanos en la verificación, y proporciona un registro detallado del resultado de cada prueba que puede consultarse posteriormente para auditoría o diagnóstico.

Las 14 pruebas se ejecutan automáticamente como el paso final del instalador (paso 14 de los 14 pasos de instalación) y su resultado determina si la instalación se considera exitosa o no. Si alguna prueba falla, el instalador muestra un resumen claro indicando qué verificación falló y sugerencias sobre cómo resolver el problema, permitiendo al administrador actuar de forma inmediata sin necesidad de investigar manualmente cuál componente no funciona.

### 15.2 Lista completa de las 14 pruebas

| # | Prueba | Qué valida | Comando/Verificación |
|---|--------|-----------|---------------------|
| 1 | Contenedores ejecutándose | Los 5 servicios están en estado `running` | `docker compose ps` |
| 2 | Volúmenes montados | Los 5 volúmenes existen y están asociados | `docker volume ls` |
| 3 | Redes creadas | `matrix_internal` y `matrix_frontend` existen | `docker network ls` |
| 4 | Aislamiento de red interna | `matrix_internal` tiene `internal: true` | Inspección de la red |
| 5 | Healthcheck de PostgreSQL | Responde a `pg_isready` | `docker compose exec postgres pg_isready` |
| 6 | Healthcheck de Redis | Responde a `redis-cli ping` con `PONG` | `docker compose exec redis redis-cli ping` |
| 7 | Healthcheck de Synapse | Endpoint `/health` devuelve HTTP 200 | `curl` interno al contenedor |
| 8 | TLS funcional | Certificado válido y accesible en puerto 443 | `openssl s_client` contra el host |
| 9 | Redirección HTTP→HTTPS | Puerto 80 redirige con 301/302 a 443 | `curl -I` contra puerto 80 |
| 10 | Element Web accesible | `https://element.home.arpa` devuelve HTML | `curl` con flag `-k` |
| 11 | `.well-known` configurado | Client config accesible vía HTTPS | `curl` al endpoint `.well-known` |
| 12 | Archivo `.env` presente | Variables de entorno cargadas y válidas | Verificación de existencia y contenido |
| 13 | Signing key existe | `synapse/signing.key` presente en volumen | `docker compose exec synapse ls` |
| 14 | Espacio en disco | Mínimo 5 GB libres en la partición de Docker | `df` con verificación de umbral |

### 15.3 Ejecutar las pruebas de forma independiente

Si necesitas volver a ejecutar las pruebas automatizadas en cualquier momento después de la instalación (por ejemplo, después de un cambio de configuración o una actualización), puedes utilizar el script de verificación que ejecuta el mismo conjunto de pruebas:

```bash
# Ejecutar las 14 pruebas de verificación
bash scripts/admin/verify.sh
```

El script `verify.sh` ejecuta las mismas 14 pruebas que el instalador y presenta los resultados de forma idéntica, con indicadores visuales ✅/❌ y un resumen final. Este script es especialmente útil después de ejecutar `bash scripts/admin/update.sh` para confirmar que la actualización no rompió ningún componente del stack.

### 15.4 Interpretación de resultados

Cada prueba muestra un indicador visual inmediato: ✅ verde si la prueba pasó correctamente, o ❌ rojo si la prueba falló. Al finalizar las 14 pruebas, se muestra un resumen con el total de pruebas pasadas y fallidas. El script devuelve código de salida 0 si todas las pruebas pasaron (lo que indica una instalación exitosa) o código 1 si alguna prueba falló (lo que requiere intervención del administrador). Si alguna prueba falla, revisa el mensaje de error específico que acompaña al indicador ❌, que generalmente incluye el comando exacto que falló y una sugerencia sobre la causa más probable del problema.

---

## 16. Checklist de mantenimiento

### Diario

- [ ] `bash scripts/admin/healthcheck.sh` - verificar estado completo del stack
- [ ] Verificar espacio en disco (`df -h`)
- [ ] Revisar logs de errores (5 min con `bash scripts/admin/logs.sh synapse`)
- [ ] Confirmar backup nocturno (verificar archivo y tamaño en `backups/`)

### Semanal

- [ ] Backup manual de verificación (`bash scripts/admin/backup-db.sh verificacion_semanal`)
- [ ] `bash scripts/admin/clean-images.sh` - limpieza de imágenes y cache
- [ ] Revisar tamaño de los 5 volúmenes Docker
- [ ] Auditar accesos fallidos en logs de Synapse y Nginx

### Mensual

- [ ] Actualización del stack (`bash scripts/admin/update.sh`)
- [ ] Test de restauración en entorno de pruebas
- [ ] Revisar lista de usuarios (inactivos, permisos de admin)
- [ ] Verificar expiración de certificados TLS (`openssl x509 -enddate`)
- [ ] `VACUUM ANALYZE` en PostgreSQL
- [ ] Revisar consumo de memoria por servicio (`docker compose stats`)

### Trimestral

- [ ] Rotar signing key de Synapse
- [ ] Auditoría de seguridad completa (logs, accesos, configuración)
- [ ] Revisar política de retención de backups
- [ ] Actualizar documentación con cambios realizados
- [ ] Test de DR (disaster recovery) completo en host separado

### Anual

- [ ] Revisar roadmap y planes de mejora del sistema
- [ ] Renovar CA local (10 años de validez, pero planificar con antelación)
- [ ] Auditar cumplimiento normativo (si aplica a tu organización)
- [ ] Capacitación refresh del equipo de administración
- [ ] Evaluación de límites de memoria (1 GB PostgreSQL, 512 MB Redis, 2 GB Synapse, 256 MB Nginx) y ajuste según crecimiento de usuarios