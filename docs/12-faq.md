# FAQ - Preguntas frecuentes

> Respuestas a las dudas más comunes sobre el stack Matrix Docker.

---

## Generales

### ¿Qué es Matrix?

Matrix es un protocolo abierto para mensajería instantánea descentralizada. Permite comunicación en tiempo real con cifrado de extremo a extremo (E2EE), salas grupales, llamadas de voz/video, y federación entre servidores. Synapse es la implementación de referencia del servidor Matrix, desarrollada por Element.

A diferencia de WhatsApp o Telegram, Matrix es auto-alojable: tú controlas tus datos. Y a diferencia de Slack o Microsoft Teams, Matrix es open source y estándar, evitando vendor lock-in.

### ¿Por qué usar este stack y no el oficial de Matrix?

El stack oficial (`matrix-docker-ansible-deploy`) es excelente pero está orientado a deployment con Ansible en un servidor Linux público. Este stack está optimizado para:

- LAN aislada (sin Internet).
- Docker Compose puro (sin Ansible).
- Migrable entre Windows y Ubuntu.
- Configuración simplificada con scripts de administración.
- Documentación exhaustiva en español.

### ¿Puedo usar esto en producción?

Sí. El stack sigue buenas prácticas de producción: versiones pinned, healthchecks, persistencia, secretos externalizados, hardening de contenedores. Adecuado para pequeñas y medianas organizaciones (50-200 usuarios).

Para entornos mayores (500+ usuarios), considera:
- Separar Synapse en workers.
- PostgreSQL replicado.
- Caché distribuida Redis Cluster.

### ¿Es seguro?

El stack implementa múltiples capas de seguridad (ver [`05-seguridad.md`](05-seguridad.md)):

- TLS terminado en Nginx con certs firmados por CA local.
- PostgreSQL y Redis sin exposición al host.
- Contenedores con `no-new-privileges`.
- Rate limiting en Nginx.
- Federación deshabilitada por defecto.
- Secretos en `.env` con permisos 600.

La seguridad real depende también del hardening del host (UFW, fail2ban, actualizaciones).

### ¿Cuánto cuesta operar esto?

Solo el costo del hardware (o electricidad si es self-hosted). No hay licencias comerciales: Synapse, PostgreSQL, Redis, Element y Nginx son open source.

Si ya tienes un servidor Ubuntu, el costo marginal es cero. Si necesitas comprar hardware, una Mini-PC (Intel NUC, Raspberry Pi 4) puede ser suficiente para 20-50 usuarios.

---

## Instalación

### ¿Puedo instalar en Mac?

No oficialmente. macOS tiene Docker Desktop pero con diferencias (no usa Linux kernel nativo). El stack debería funcionar con ajustes menores, pero no está testeado.

### ¿Puedo instalar en Windows sin WSL2?

No recomendado. Docker Desktop en Windows requiere WSL2 para mejor compatibilidad. Con Hyper-V backend hay issues conocidos con volúmenes.

### ¿Necesito Internet para instalar?

Solo para descargar las imágenes Docker (~1 GB total). Una vez descargadas, el stack funciona 100% offline (excepto SMTP si usas servidor externo).

Si tu LAN no tiene Internet, puedes:
1. Descargar imágenes en un host con Internet: `docker pull <imagen>` + `docker save -o imagen.tar`.
2. Transferir al host offline.
3. Cargar: `docker load -i imagen.tar`.

### ¿Puedo usar Podman en lugar de Docker?

No probado. Podman es compatible a nivel de CLI con Docker, pero Docker Compose tiene diferencias. Si lo intentas, reporta resultados.

### ¿Cuánto tarda la primera instalación?

- En host con buena conexión: 10-15 minutos (incluyendo download de imágenes).
- En host lento o con Internet lento: 30-60 minutos.
- Una vez instalado, arranque normal: 1-2 minutos.

---

## Configuración

### ¿Cómo cambio los dominios?

Ver [`03-configuracion.md` sección 7](03-configuracion.md). Necesitas editar:
- `.env`
- `synapse/homeserver.yaml`
- `element/config.json`
- `nginx/conf.d/*.conf`
- `nginx/well-known/matrix/*.json`

Y regenerar certs.

### ¿Puedo usar mi propio dominio público (matrix.midominio.com)?

Sí, pero necesitas:
1. DNS público apuntando a tu IP pública.
2. Exponer el host a Internet (no recomendado para LAN-only).
3. Certificados públicos (Let's Encrypt) en lugar de self-signed.
4. Habilitar federación si quieres comunicar con otros servidores Matrix.

Este stack está diseñado para LAN, no para exposición pública. Si quieres expuesto, considera `matrix-docker-ansible-deploy` que está optimizado para eso.

### ¿Cómo activo el registro público de usuarios?

En `synapse/homeserver.yaml`:

```yaml
enable_registration: true
```

Y en `.env`:

```env
SYNAPSE_ENABLE_REGISTRATION=true
```

> **No recomendado** en producción. Mejor crear usuarios vía script.

### ¿Cómo cambio el branding de Element?

Edita `element/config.json`:

```json
{
    "brand": "Mi Empresa Chat",
    "branding": {
        "authHeaderLogoUrl": "themes/element/img/logos/mi-logo.svg",
        "welcomeBackgroundUrl": "themes/element/img/backgrounds/mi-fondo.jpg"
    }
}
```

Reconstruir: `docker compose build element`.

Para cambios más profundos (CSS, traducciones), necesitas compilar Element desde código fuente.

### ¿Puedo usar LDAP/Active Directory?

Sí, con el módulo `synapse-ldap3`:

1. Editar `synapse/homeserver.yaml`:

```yaml
modules:
  - module: ldap_auth_provider.LdapAuthProviderModule
    config:
      enabled: true
      uri: "ldap://ldap.home.arpa:389"
      start_tls: true
      base: "dc=example,dc=com"
      attributes:
        uid: "cn"
        mail: "mail"
        name: "givenName"
      bind_dn: "cn=admin,dc=example,dc=com"
      bind_password: "<password>"
```

2. Reconstruir imagen de Synapse con el módulo (requiere Dockerfile custom).

### ¿Puedo deshabilitar el cifrado E2EE?

No recomendado, pero posible. En `homeserver.yaml`:

```yaml
encryption_enabled_by_default_for_room_type: off
```

> **No recomendado**. El cifrado E2EE es una de las principales ventajas de Matrix.

---

## Operación

### ¿Cómo veo quién está conectado?

```sql
SELECT user_id, ip, last_seen
FROM user_ips
WHERE last_seen > NOW() - INTERVAL '5 minutes'
ORDER BY last_seen DESC;
```

### ¿Cuántos usuarios puedo tener?

Depende del hardware:

| Hardware | Usuarios concurrentes |
|----------|----------------------|
| 4 GB RAM, 2 cores | 20-50 |
| 8 GB RAM, 4 cores | 50-150 |
| 16 GB RAM, 8 cores | 150-500 |
| 32 GB RAM, 16 cores | 500-1500 |

"Concurrentes" = usuarios activos en la última hora.

### ¿Cómo elimino un usuario completamente?

```bash
# 1. Desactivar
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/deactivate/@usuario:home.arpa" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"erase": true}'
```

### ¿Cómo bloqueo a un usuario?

Desactivarlo (ver arriba) o:

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET deactivated=1 WHERE name='@usuario:home.arpa';"

# Invalidar sesiones
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "DELETE FROM access_tokens WHERE user_id='@usuario:home.arpa';"
```

### ¿Puedo tener más de un admin?

Sí. Crea el usuario y promuévelo:

```bash
bash scripts/linux/create-user.sh nuevo_admin
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET admin=1 WHERE name='@nuevo_admin:home.arpa';"
```

### ¿Cómo cambio el tamaño máximo de archivos?

En `synapse/homeserver.yaml`:

```yaml
max_media_upload_size: 100M   # Era 50M
```

Y en `nginx/conf.d/matrix.home.arpa.conf`:

```nginx
client_max_body_size 100M;
```

Reiniciar Synapse y Nginx.

### ¿Cómo veo el histórico de mensajes?

En Element, abre la sala y scroll up. Synapse carga mensajes bajo demanda.

Para ver todos los eventos en BD:

```sql
SELECT event_id, type, sender, to_timestamp(origin_server_ts/1000) AS time
FROM events
WHERE room_id = '!roomid:home.arpa'
ORDER BY origin_server_ts DESC
LIMIT 50;
```

---

## Backup y restauración

### ¿Cada cuánto hacer backup?

- Diario: automático (cron).
- Semanal: backup manual + verificación.
- Mensual: backup mensual + test de restauración.
- Antes de operaciones críticas: backup manual.

### ¿Cuánto espacio ocupan los backups?

Depende del uso:

| Usuarios activos | Mensajes/día | Tamaño backup diario |
|------------------|--------------|---------------------|
| 10 | 100 | 5-10 MB |
| 50 | 500 | 20-50 MB |
| 100 | 1000 | 50-150 MB |
| 500 | 5000 | 200-500 MB |

Compresión incluida (formato custom de pg_dump).

### ¿Puedo restaurar un solo mensaje?

No directamente. Pero puedes consultar el backup sin restaurar:

```bash
# Extraer eventos de una sala específica
pg_restore --data-only --table=events backups/db_ULTIMO.sql.gz | \
    grep "room_id" | head
```

### ¿Cuánto tarda una restauración?

- BD pequeña (< 100 MB): 30-60 segundos.
- BD media (100 MB - 1 GB): 2-5 minutos.
- BD grande (> 1 GB): 10-30 minutos.

---

## Migración

### ¿Puedo migrar de Windows a Linux sin downtime?

No. El procedimiento requiere detener el stack durante la transferencia.

Para minimizar downtime:
1. Preparar todo en Linux antes.
2. Detener Windows.
3. Exportar volúmenes (5-30 min).
4. Transferir (10-60 min).
5. Importar en Linux (5-30 min).
6. Iniciar Linux.

Total downtime: 30-90 minutos.

### ¿Qué pasa si pierdo la signing key?

Malo. Sin la signing key original:
- El servidor no puede firmar nuevos eventos con la misma identidad.
- Los clientes NO confiarán en eventos nuevos (firma distinta = servidor distinto).
- Posible solución: reset completo, perder historial.

**POR ESO** la signing key se respalda aparte y de forma segura.

### ¿Puedo migrar de Linux a Windows?

Sí, mismo procedimiento pero invertido. Ver [`08-migracion-windows-ubuntu.md` sección 16](08-migracion-windows-ubuntu.md).

---

## Performance

### ¿Por qué Element es lento?

Causas comunes:

1. **Poca RAM en el host**: ajustar `shared_buffers` PostgreSQL, `maxmemory` Redis.
2. **Disco lento**: usar SSD.
3. **Red lenta**: verificar latencia LAN.
4. **Sync pesado**: el primer sync después de login carga todos los mensajes recientes.
5. **Muchas salas**: cada sala genera tráfico de sync.

### ¿Cómo optimizo PostgreSQL?

Ver [`03-configuracion.md` sección 3.1](03-configuracion.md) para ajustes según RAM del host.

### ¿Cómo veo queries lentas?

```bash
# En postgresql.conf:
log_min_duration_statement = 500  # ms - log queries >500ms

# Ver logs
docker compose logs postgres | grep "duration"
```

### ¿Cuándo necesito workers de Synapse?

Si tienes > 200 usuarios activos, considera separar:
- `synchrotron` (handle /sync)
- `federation_sender` (federación)
- `media_repository` (media)

Ver [Synapse workers docs](https://matrix-org.github.io/synapse/latest/workers.html). No incluido en este stack por simplicidad.

---

## Seguridad

### ¿Son seguros los self-signed certs?

Sí, si importas la CA local en los clientes. La encriptación TLS es igual de fuerte que con certs públicos; la diferencia es la confianza (CA local vs CA pública reconocida).

Para LAN, self-signed + CA importada es estándar y seguro.

### ¿Puedo usar Let's Encrypt?

Sí, pero requiere:
1. Dominio público apuntando a tu IP.
2. Exponer el host a Internet (puerto 80).
3. Certbot instalado en el host.

Este stack está diseñado para LAN-only. Si quieres Let's Encrypt, usa `matrix-docker-ansible-deploy` o modifica este stack.

### ¿Cómo activo 2FA?

Synapse soporta TOTP 2FA nativamente. En Element:
1. Ajustes → Cuenta → Seguridad y privacidad.
2. Activar "Verificación en dos pasos".

Para forzar 2FA en admins, no hay forma nativa. Considera LDAP con política de 2FA.

### ¿Cómo veo quién intentó acceder sin permiso?

```bash
# Logs de Synapse
docker compose logs synapse | grep -i "login" | grep -v "200"

# Logs de Nginx
docker compose exec nginx cat /var/log/nginx/matrix-access.log | grep " 401 \| 403 "
```

---

## Federación

### ¿Qué es la federación?

La federación permite que servidores Matrix distintos intercambien mensajes. Si `@alice:server1.com` y `@bob:server2.com` están en la misma sala, sus servidores federan para entregar mensajes.

### ¿Por qué está deshabilitada?

> **v2.0.0**: La federación fue completamente removida del proyecto (no solo deshabilitada). Los endpoints y configuraciones ya no existen.

Para LAN aislada, federación:
- No es necesaria (todos los usuarios están en un servidor).
- Aumenta superficie de ataque (conexiones entrantes).
- Requiere DNS público y certs públicos.

Si necesitas federar, ver [`03-configuracion.md` sección 8](03-configuracion.md).

### ¿Puedo activar federación solo para algunos servidores?

Sí, con whitelist:

```yaml
federation_domain_whitelist:
  - "matrix.org"
  - "otro-servidor.com"
```

---

## Mobile

### ¿Puedo usar Element en móvil?

Sí, Element Android y Element iOS. Configuración:

1. Instalar app.
2. Al hacer login, click en "Cambiar servidor".
3. URL: `https://matrix.home.arpa`.
4. Necesitas importar la CA en el móvil (Android: Settings → Security → Encryption → Install certificates).

### ¿Las notificaciones push funcionan?

No por defecto. Push requiere servidor Sygnal (no incluido en este stack). Sin Sygnal:
- Android: notificaciones solo cuando la app está abierta.
- iOS: no hay notificaciones (requisito de Apple).

Para push, desplegar Sygnal por separado y configurar Synapse para usarlo.

---

## Troubleshooting

### ¿Por qué el log de Synapse está lleno de warnings?

Algunos warnings son normales:
- `synapse.storage.SQL: slow query`: queries >500ms. Si muchas, optimizar.
- `synapse.http.matrixfederationclient`: errores de federación (esperado si federación off).
- `synapse.handlers.presence`: timeouts de presence.

Si crecen excesivamente, investigar caso por caso.

### ¿Por qué el disco se llena?

Causas:
- Logs sin rotación (verificar `log.config` y Docker json-file).
- Media acumulada (purgar periódicamente).
- Backups sin rotación (verificar `BACKUP_RETENTION_DAYS`).
- BD sin VACUUM (ejecutar mensual).

### ¿Por qué los mensajes se duplican?

Normalmente no debería pasar. Si pasa:
- Verificar que solo hay una instancia de Synapse.
- Verificar que Redis está healthy (sin Redis, puede haber duplicados).
- Verificar que no hay múltiples elementos del mismo usuario conectados con same session.

### ¿Por qué Element muestra "No se pudo decryptar"?

Causas comunes:
- Cambio de dispositivo sin verificación cruzada.
- Loss de claves de backup.
- Bug de cliente (actualizar Element).

Solución:
- Verificar dispositivo desde otro cliente.
- Restaurar claves desde backup (si existe).

---

## Misceláneos

### ¿Puedo hacer videollamadas?

Sí, Element incluye videollamadas 1:1 y grupales vía WebRTC. Para sala pequeña (<8 personas), funciona peer-to-peer.

Para más capacidad, desplegar [Element Call](https://call.element.io) (servidor SFU separado).

### ¿Puedo tener bots?

Sí, vía Application Services. Ver [Synapse docs](https://matrix-org.github.io/synapse/latest/application_services.html).

Bots populares:
- [mautrix-telegram](https://github.com/mautrix/telegram) - Bridge a Telegram.
- [mautrix-signal](https://github.com/mautrix/signal) - Bridge a Signal.
- [mautrix-whatsapp](https://github.com/mautrix/whatsapp) - Bridge a WhatsApp.

### ¿Puedo tener integraciones (Jitsi, etc.)?

Sí, con widgets. Element soporta widgets para integrar herramientas externas.

Para Jitsi autoalojado, desplegar por separado y configurar Element `config.json`:

```json
"jitsi": {
    "preferredDomain": "jitsi.home.arpa"
}
```

### ¿Cómo reporto bugs del stack?

Abrir issue en el repositorio del proyecto con:
- Versión del stack.
- Output de `status.sh`.
- Logs relevantes.
- Pasos para reproducir.

### ¿Cómo contribuyo?

Ver [`README.md` sección "Soporte y contribución"](../README.md).

### ¿Dónde consigo ayuda?

- [`docs/11-resolucion-problemas.md`](11-resolucion-problemas.md)
- [`docs/12-faq.md`](12-faq.md) (este documento)
- Comunidad Matrix (si tienes federation): #matrix:matrix.org
- Reddit: r/selfhosted, r/matrixdotorg

### ¿Este proyecto es afiliado a Matrix.org o Element?

No. Es un proyecto independiente que usa los componentes oficiales de Matrix y Element. Matrix y Element son marcas de sus respectivos dueños.
