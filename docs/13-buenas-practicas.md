# Buenas prácticas

> Recomendaciones operativas para mantener un stack sano y seguro.

---

## 1. Principios generales

### 1.1 Filosofía operativa

1. **Prevenir antes que curar**: monitorear proactivamente, no reaccionar a incidentes.
2. **Documentar todo**: cambios, decisiones, incidentes.
3. **Automatizar lo repetible**: scripts para tareas frecuentes.
4. **Principio de menor privilegio**: solo el acceso necesario.
5. **Defensa en profundidad**: múltiples capas de seguridad.
6. **Fail-safe**: ante la duda, denegar.
7. **KISS (Keep It Simple)**: complejidad extra = puntos de fallo extra.

### 1.2 Reglas de oro

- **NUNCA** modifiques producción sin backup previo.
- **NUNCA** expongas secretos en logs, commits, o chat.
- **NUNCA** deshabilites TLS "temporalmente".
- **NUNCA** uses `latest` tag en imágenes (usa versiones pinned).
- **NUNCA** concedas permisos de admin a usuarios no confiables.
- **SIEMPRE** prueba cambios en staging primero.
- **SIEMPRE** documentar incidentes y post-mortem.
- **SIEMPRE** rotar secretos periódicamente.
- **SIEMPRE** mantener backups offsite.
- **SIEMPRE** actualizar con procedimiento, no en caliente.

---

## 2. Docker y contenedores

### 2.1 Imágenes

- **Usar tags específicos**: `postgres:16.4-alpine3.20` en lugar de `postgres:latest`.
- **Preferir Alpine** para reducir superficie de ataque (menos paquetes = menos vulnerabilidades).
- **Verificar imágenes con `docker scan`** o Trivy antes de usar.
- **Mantener imágenes actualizadas** con procedimiento de actualización.
- **Construir imágenes custom con multi-stage build** para minimizar tamaño.

### 2.2 Contenedores

- **`restart: unless-stopped`** para servicios críticos.
- **`security_opt: - no-new-privileges:true`** en todos los servicios.
- **`read_only: true`** cuando sea posible (Synapse no lo soporta por writes en /data).
- **`tmpfs`** para /tmp cuando sea posible.
- **`cap_drop: [ALL]`** y agregar solo los necesarios.
- **`mem_limit` y `cpus`** para limitar recursos por contenedor.

### 2.3 Volúmenes

- **Usar volúmenes con nombre** (no bind mounts) para datos persistentes.
- **Backup regular** de volúmenes críticos.
- **Monitorear espacio** de volúmenes.
- **Permisos correctos**: dueño correcto en cada volumen.

### 2.4 Redes

- **Una red por capa de seguridad** (frontend, backend, etc.).
- **No publicar puertos innecesarios** al host.
- **Usar `internal: true`** para redes que no necesitan salida a Internet.

### 2.5 Compose

- **Validar con `docker compose config`** antes de aplicar.
- **Usar `.env`** para secretos.
- **`depends_on` con `condition: service_healthy`** para arranque ordenado.
- **Healthchecks en todos los servicios**.
- **`logging` con rotación** (`max-size`, `max-file`).

---

## 3. Seguridad

### 3.1 Secretos

- **Nunca commitear secretos** a Git (verificar `.gitignore`).
- **Permisos 600** en `.env`, `signing.key`, certs.
- **Rotar secretos** al menos anualmente.
- **Usar password manager** para almacenar secretos.
- **No reutilizar secretos** entre entornos (dev, staging, prod).
- **Generar secretos con `openssl rand`** (32+ caracteres).

### 3.2 Red

- **Firewall UFW activo** (Ubuntu) o equivalente.
- **Solo puertos 80/443** accesibles desde LAN.
- **SSH deshabilitado para root**, solo keys, solo desde LAN.
- **Fail2ban** para bloquear intentos de brute force.
- **No exponer PostgreSQL ni Redis** al host.

### 3.3 TLS

- **TLS 1.2 y 1.3 únicamente** (sin 1.0/1.1).
- **Ciphers modernas** (ECDHE, AES-GCM, CHACHA20).
- **HSTS** activado.
- **Certificados con validez limitada** (1 año certs, 10 años CA).
- **Renovar antes de expirar** (alerta 30 días antes).

### 3.4 Hardening del host

- **Actualizaciones automáticas de seguridad** (`unattended-upgrades`).
- **Auditd** para auditoría de sistema.
- **AppArmor/SELinux** activo.
- **Minimizar paquetes instalados**.
- **Deshabilitar servicios innecesarios**.
- **IP estática** (no DHCP para servidores).

### 3.5 Backups seguros

- **Cifrar backups offsite** con GPG/AES-256.
- **Permisos 600** en archivos de backup.
- **Backup de la passphrase GPG** en lugar seguro (password manager).
- **No almacenar backups en el mismo disco** que los datos.
- **Verificar restore** periódicamente.

---

## 4. Synapse

### 4.1 Configuración

- **`report_stats: false`** para privacidad.
- **`enable_registration: false`** en producción.
- **`federation.enabled: false`** si no se necesita (en v2.0.0, la federación fue completamente removida).
- **Política de contraseñas fuerte** activada.
- **`url_preview_enabled: false`** en LAN sin Internet.
- **Rate limiting** configurado adecuadamente.
- **`max_upload_size`** razonable (50 MB default).

### 4.2 Signing key

- **Permisos 600** en `signing.key`.
- **Backup seguro** de la signing key (junto con CA).
- **Rotar cada 12 meses**.
- **Nunca commitear** a Git.
- **Mantener `old_signing_keys`** al rotar para transición.

### 4.3 Performance

- **`cp_max` ajustado** al número de usuarios.
- **`caches.global_factor`** ajustado según RAM.
- **Redis activado** para caché.
- **Workers** si > 200 usuarios.
- **VACUUM ANALYZE** mensual en PostgreSQL.

### 4.4 Media

- **`max_media_upload_size`** limitado.
- **Purgar media antigua** mensualmente (>90 días).
- **Monitorear crecimiento** del volumen.
- **`url_preview_enabled: false`** para no salir a Internet.

---

## 5. PostgreSQL

### 5.1 Configuración

- **`shared_buffers` = 25% RAM** dedicada a PG.
- **`effective_cache_size` = 50-75% RAM** total.
- **`work_mem`** ajustado (16-64 MB).
- **`maintenance_work_mem`** alto (256 MB-1 GB).
- **`autovacuum` activo** con parámetros agresivos.
- **`wal_buffers` = 16 MB**.
- **`max_wal_size` = 1 GB**.

### 5.2 Seguridad

- **`password_encryption = scram-sha-256`**.
- **`pg_hba.conf` restrictivo** (solo IPs internas).
- **`ssl = off`** solo si tráfico interno entre contenedores.
- **No exponer puerto 5432** al host.
- **Rotar password** de synapse_user anualmente.

### 5.3 Mantenimiento

- **VACUUM ANALYZE** diario (lo hace autovacuum).
- **VACUUM FULL** mensual (ventana de mantenimiento).
- **REINDEX** trimestral si hay fragmentación.
- **Monitorear `pg_stat_activity`** para conexiones colgadas.
- **`log_min_duration_statement = 500`** para detectar queries lentas.

### 5.4 Backups

- **`pg_dump --format=custom --compress=9`** diario.
- **Backup en caliente** (no requiere downtime).
- **Verificar restore** trimestralmente.
- **Retención 7-30 días** según necesidades.
- **Backup offsite** cifrado.

---

## 6. Redis

### 6.1 Configuración

- **`requirepass`** obligatorio.
- **`maxmemory`** definido según RAM.
- **`maxmemory-policy allkeys-lru`** para caché.
- **`appendonly yes`** para persistencia.
- **`appendfsync everysec`** balance durabilidad/performance.
- **Renombrar/deshabilitar comandos peligrosos** (`FLUSHALL`, `CONFIG`, etc.).

### 6.2 Mantenimiento

- **Monitorear `used_memory`** vs `max_memory`.
- **Verificar `INFO persistence`** para confirmar AOF activo.
- **No usar `KEYS *`** en producción (usa `SCAN`).
- **Reiniciar Redis** si acumula fragmentación excesiva.

---

## 7. Nginx

### 7.1 Configuración

- **`server_tokens off`**.
- **TLS 1.2/1.3 únicamente**.
- **HSTS** activado.
- **Headers de seguridad** (CSP, X-Frame-Options, etc.).
- **Rate limiting** por IP y endpoint.
- **`client_max_body_size`** coherente con Synapse.
- **gzip** activado para respuestas.

### 7.2 Performance

- **`worker_processes auto`**.
- **`worker_connections 4096`**.
- **`keepalive_timeout 65`**.
- **`keepalive` en upstreams**.
- **`proxy_buffering on`** (excepto para sync long-polling).
- **Caché de archivos estáticos** (Element).

### 7.3 Mantenimiento

- **`nginx -t`** antes de reload.
- **Monitorear access log** para detectar patrones anómalos.
- **Rotar logs** con logrotate.
- **Renovar certs** antes de expirar.

---

## 8. Operaciones

### 8.1 Cambios

- **Procedimiento de cambio**: documentar antes, ejecutar, verificar después.
- **Ventana de mantenimiento** para cambios grandes.
- **Rollback plan** siempre preparado.
- **Cambios uno a la vez** (no acumular).
- **Peer review** para cambios críticos.

### 8.2 Actualizaciones

- **Leer changelog** antes de actualizar.
- **Backup previo** obligatorio.
- **Test en staging** si es posible.
- **Monitorear 24h post-actualización**.
- **Documentar en CHANGELOG.md**.

### 8.3 Backups

- **Automatizar** (cron).
- **Verificar** que se ejecutan.
- **Test de restore** trimestral.
- **Offsite** cifrado.
- **Retención** adecuada.

### 8.4 Monitoreo

- **Espacio en disco** (alerta >80%).
- **CPU/RAM** (alerta sostenido >80%).
- **Healthchecks** (alerta si no healthy).
- **Logs** (alerta si aparecen errores frecuentes).
- **Backups** (alerta si no se generan).

### 8.5 Documentación

- **Mantener runbooks** actualizados.
- **Documentar incidentes** con post-mortem.
- **CHANGELOG.md** al día.
- **Diagramas** actualizados.
- **Capacitación** de nuevos admins.

---

## 9. Equipo y procesos

### 9.1 Roles

Definir al menos:

- **Admin primario**: responsable del día a día.
- **Admin backup**: puede operar si primario no está.
- **Aprobador**: para cambios críticos.
- **Revisor**: para cambios en config.

### 9.2 On-call

- **Procedimiento de escalamiento** definido.
- **Contacto** disponible 24/7 para producción.
- **Runbook** accesible offline.

### 9.3 Capacitación

- **Al menos 2 personas** saben operar el stack.
- **Drill de DR** trimestral.
- **Documentación** accesible.
- **Shadowing** para nuevos admins.

---

## 10. Compliance y auditoría

### 10.1 Logs de auditoría

- **Quién creó/modificó/eliminó usuarios**.
- **Quién accedió a la API admin**.
- **Cambios en configuración**.
- **Backups y restores**.

### 10.2 Retención

Definir y documentar:

- **Mensajes**: retención según política organizacional.
- **Logs**: 30-90 días.
- **Backups**: 7-90 días según criticidad.
- **Usuarios eliminados**: GDPR derecho al olvido.

### 10.3 Privacidad

- **Aviso a usuarios** sobre tratamiento de datos.
- **Consentimiento** para captura de logs.
- **DPIA** si aplica (GDPR).
- **Cifrado** de datos sensibles.

---

## 11. Costos y recursos

### 11.1 Optimización de recursos

- **Right-sizing**: ajustar CPU/RAM al uso real.
- **VACUUM** regular para evitar growth innecesario.
- **Purga de media** antigua.
- **Limpieza de logs** con rotación.
- **Imágenes pequeñas** (Alpine).

### 11.2 Costos ocultos

- **Storage growth**: monitorear y planificar.
- **Backup storage**: especialmente offsite.
- **Electricidad**: si self-hosted.
- **Tiempo de administración**: contar horas reales.
- **Capacitación**: tiempo del equipo.

---

## 12. Mejora continua

### 12.1 Métricas

Definir y trackear:

- **Uptime** mensual.
- **Tiempo de respuesta** de login/sync.
- **Tiempo de recuperación** (RTO real vs objetivo).
- **Backups exitosos** vs fallidos.
- **Incidentes** por mes.

### 12.2 Post-mortem

Después de cada incidente:

1. **Timeline** detallado.
2. **Causa raíz** identificada.
3. **Acciones tomadas**.
4. **Acciones preventivas** propuestas.
5. **Responsables** de cada acción.
6. **Plazo** de implementación.

### 12.3 Review mensual

- **Métricas del mes** vs objetivo.
- **Incidentes** del mes.
- **Cambios** realizados.
- **Mejoras** pendientes.
- **Capacitación** pendiente.

### 12.4 Review anual

- **Cumplimiento de objetivos**.
- **Roadmap** del próximo año.
- **Tecnologías a evaluar**.
- **Renovación de hardware** si aplica.
- **Auditoría de seguridad** completa.

---

## 13. Checklist de buenas prácticas

### Diario
- [ ] Verificar estado del stack.
- [ ] Revisar logs de errores.
- [ ] Confirmar backup nocturno.

### Semanal
- [ ] Backup manual de verificación.
- [ ] Limpieza de imágenes Docker.
- [ ] Revisar tamaño de volúmenes.
- [ ] Auditar accesos fallidos.

### Mensual
- [ ] Actualizar imágenes (con procedimiento).
- [ ] VACUUM ANALYZE PostgreSQL.
- [ ] Test de restore.
- [ ] Revisar usuarios inactivos.
- [ ] Verificar espacio en disco.
- [ ] Actualizar documentación.

### Trimestral
- [ ] Drill de DR completo.
- [ ] Rotar signing key.
- [ ] Auditoría de seguridad.
- [ ] Review de métricas.
- [ ] Capacitación refresh.

### Anual
- [ ] Review completo de arquitectura.
- [ ] Renovar CA local (planificar).
- [ ] Auditoría de compliance.
- [ ] Roadmap del próximo año.

---

## 14. Anti-patrones (NO hacer)

- ❌ Usar `latest` tag en imágenes.
- ❌ Exponer puertos de BD al host.
- ❌ Commitear secretos a Git.
- ❌ Deshabilitar TLS "temporalmente".
- ❌ Hacer cambios en producción sin backup.
- ❌ Reiniciar todo el stack para fix de un servicio.
- ❌ Ignorar warnings en logs.
- ❌ No documentar cambios.
- ❌ Una sola persona sabe operar.
- ❌ Backups sin test de restore.
- ❌ actualizar en caliente sin procedimiento.
- ❌ Conceder admin a "probar".
- ❌ Reutilizar passwords entre entornos.
- ❌ No monitorear espacio en disco.
- ❌ No rotar secretos.
- ❌ Confiar en un solo backup location.
