# Resolución de problemas

> Diagnóstico y solución de los problemas más comunes.

---

## 1. Metodología general de diagnóstico

### 1.1 Pasos para diagnosticar cualquier problema

1. **Identificar el síntoma**: qué falla, cuándo, a quién.
2. **Reproducir**: intentar reproducir consistentemente.
3. **Aislar**: ¿es un servicio, todos, un usuario, todos?
4. **Logs**: revisar logs del servicio afectado.
5. **Estado**: verificar healthchecks y dependencias.
6. **Cambios recientes**: ¿se actualizó algo? ¿se cambió config?
7. **Hipótesis**: formular causas posibles.
8. **Probar fix**: aplicar uno a la vez.
9. **Verificar**: confirmar que se resolvió.
10. **Documentar**: anotar el problema y la solución para el futuro.

### 1.2 Comandos de diagnóstico iniciales

```bash
# Estado general
bash scripts/linux/status.sh

# Logs de todos los servicios (últimos 100)
bash scripts/linux/logs.sh

# Espacio en disco
df -h

# Espacio Docker
docker system df

# Procesos Docker
docker ps -a

# Salud de cada servicio
docker compose ps
```

---

## 2. Problemas de arranque

### 2.1 El stack no arranca

**Síntoma**: `docker compose up -d` falla o los contenedores se detienen inmediatamente.

**Diagnóstico**:

```bash
# Ver errores de compose
docker compose up

# Ver logs de cada servicio que falle
docker compose logs postgres
docker compose logs synapse
```

**Causas comunes y soluciones**:

#### Causa A: .env faltante o mal formado

```bash
# Verificar
cat .env | grep -v "^#" | grep "="
# Debe mostrar todas las variables con valores

# Validar docker-compose
docker compose config --quiet
```

#### Causa B: signing key faltante

```bash
ls -la synapse/signing.key
# Debe existir y tener contenido
```

Solución:

```bash
# Generar nueva signing key
bash scripts/linux/setup.sh
# O manualmente
openssl rand -hex 32 | xxd -r -p | base64
echo "ed25519 a1b2c <base64>" > synapse/signing.key
chmod 600 synapse/signing.key
```

#### Causa C: Certificados faltantes

```bash
ls -la nginx/certs/
# Debe contener: ca.crt, ca.key, matrix.crt, .key, etc. (nombres fijos desde v2.0.0)
```

Solución:

```bash
bash scripts/linux/generate-certs.sh
```

#### Causa D: Puerto ocupado

```bash
# Verificar qué usa el puerto 80 o 443
sudo ss -tlnp | grep -E ":80|:443"

# Si hay otro proceso, detenerlo o cambiar puertos en .env
# NGINX_HTTP_PORT=8080
# NGINX_HTTPS_PORT=8443
```

#### Causa E: Imagen no construida

```bash
docker images | grep matrix-element
# Debe mostrar matrix-element:custom
```

Solución:

```bash
docker compose build element
```

### 2.2 PostgreSQL no arranca

**Síntoma**: `matrix-postgres` se reinicia constantemente.

**Diagnóstico**:

```bash
docker compose logs postgres
```

**Causas comunes**:

#### Causa A: Permisos del volumen

```bash
# Verificar permisos
docker run --rm -v matrix_postgres_data:/data alpine ls -la /data
# El owner debe ser 70:70 (postgres en Alpine)
```

Solución:

```bash
docker run --rm -v matrix_postgres_data:/data alpine chown -R 70:70 /data
```

#### Causa B: Config inválida

```bash
# Verificar config
docker compose exec postgres postgres -C config_file=/etc/postgresql/postgresql.conf
```

#### Causa C: BD corrupta

Si los datos están corruptos, no hay mucho que hacer salvo restaurar:

```bash
docker compose down
docker volume rm matrix_postgres_data
bash scripts/linux/restore-db.sh backups/db_ULTIMO.sql.gz
```

### 2.3 Redis no arranca

**Diagnóstico**:

```bash
docker compose logs redis
```

**Causa común**: contraseña incorrecta en redis.conf.

Verificar que `requirepass` en `redis/redis.conf` coincida con `REDIS_PASSWORD` en `.env` y con `redis.password` en `synapse/homeserver.yaml`.

### 2.4 Synapse no arranca

**Diagnóstico**:

```bash
docker compose logs synapse
```

**Causas comunes**:

#### Causa A: No conecta a PostgreSQL

```bash
# Verificar que PostgreSQL está healthy
docker compose ps postgres

# Verificar credenciales
docker compose exec postgres psql -U synapse_user -d synapse -c "SELECT 1;"
```

#### Causa B: No conecta a Redis

```bash
# Verificar que Redis está healthy
docker compose ps redis

# Test conexión
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping
# Esperado: PONG
```

#### Causa C: homeserver.yaml mal formado

```bash
# Validar YAML
docker compose exec synapse python3 -c "import yaml; yaml.safe_load(open('/data/homeserver.yaml'))"
```

#### Causa D: Signing key inválida

```bash
cat synapse/signing.key
# Debe verse como: ed25519 <key_id> <base64>
```

### 2.5 Nginx no arranca

**Diagnóstico**:

```bash
docker compose logs nginx

# Test config
docker compose exec nginx nginx -t
```

**Causas comunes**:

#### Causa A: Config inválida

```bash
docker compose exec nginx nginx -t
# Muestra el error específico
```

#### Causa B: Certs faltantes o inválidos

```bash
docker compose exec nginx ls -la /etc/nginx/certs/

# Verificar cert
openssl x509 -in nginx/certs/matrix.home.arpa.crt -noout -text | head -20
```

---

## 3. Problemas de conectividad

### 3.1 Cliente no puede acceder a Element

**Síntoma**: navegador muestra "no se puede acceder" o "timeout".

**Diagnóstico**:

```bash
# 1. Verificar que el stack está UP
bash scripts/linux/status.sh

# 2. Verificar DNS desde el cliente
nslookup element.home.arpa
# Debe resolver a la IP del host Docker

# 3. Verificar conectividad al puerto 443
curl -kv https://element.home.arpa/
# Debe mostrar conexión establecida (aunque falle TLS)

# 4. Verificar firewall
sudo ufw status
```

**Soluciones**:

- Si DNS no resuelve: configurar DNS local o `/etc/hosts` del cliente.
- Si firewall bloquea: `sudo ufw allow from 192.168.1.0/24 to any port 443`.
- Si el puerto no escucha: verificar `docker compose ps nginx`.

### 3.2 Element carga pero no conecta al homeserver

**Síntoma**: Element muestra "No se pudo conectar al homeserver".

**Diagnóstico**:

```bash
# 1. Verificar .well-known
curl -k https://matrix.home.arpa/.well-known/matrix/client
# Debe devolver JSON con m.homeserver

# 2. Verificar health de Synapse
curl -k https://matrix.home.arpa/health
# Debe devolver "OK"

# 3. Verificar que config.json de Element apunta al homeserver correcto
cat element/config.json | grep -A 3 homeserver
```

**Soluciones**:

- Si `.well-known` no sirve: verificar `nginx/well-known/matrix/client.json`.
- Si health falla: ver logs de Synapse.
- Si config.json incorrecto: editar y reconstruir imagen `docker compose build element`.

### 3.3 Login falla

**Síntoma**: credenciales correctas pero "Invalid username/password".

**Diagnóstico**:

```bash
# 1. Ver logs de Synapse durante login
docker compose logs synapse --since 1m | grep -i "login\|auth"

# 2. Verificar que el usuario existe
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, password_hash IS NOT NULL AS has_password FROM users WHERE name='@usuario:home.arpa';"

# 3. Verificar que no está desactivado
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT name, deactivated FROM users WHERE name='@usuario:home.arpa';"
```

**Causas**:

- Usuario no existe → crear con `create-user.sh`.
- Usuario desactivado → reactivar (ver [`06-administracion.md`](06-administracion.md) sección 9.1).
- Password incorrecto → resetear (ver [`06-administracion.md`](06-administracion.md) sección 2.5).
- Pepper cambiado → invalida todos los hashes, requiere reset masivo.

### 3.4 Mensajes no llegan

**Síntoma**: usuario envía mensaje pero otros no lo reciben.

**Diagnóstico**:

```bash
# 1. Verificar que Synapse procesó el mensaje
docker compose logs synapse --since 5m | grep -i "send\|event"

# 2. Verificar Redis (pubsub)
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" PUBSUB CHANNELS
# Debe mostrar canales activos

# 3. Verificar que el destinatario está en la sala
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT user_id, membership FROM current_state_events WHERE room_id='!roomid:home.arpa';"
```

**Soluciones**:

- Si Redis no tiene canales: reiniciar `bash scripts/linux/restart.sh redis synapse`.
- Si destinatario no está en la sala: invitar desde Element.

---

## 4. Problemas de performance

### 4.1 Stack lento

**Síntoma**: login tarda >10s, mensajes >5s en aparecer.

**Diagnóstico**:

```bash
# 1. Verificar uso de recursos
docker stats --no-stream

# 2. Verificar queries lentas en PostgreSQL
docker compose logs postgres --since 1h | grep "duration"

# 3. Verificar carga de Synapse
docker compose logs synapse --since 1h | grep "request_times"
```

**Causas y soluciones**:

#### Causa A: Poca RAM

```bash
free -h
# Si_USED > 80%, aumentar RAM del host
```

Ajustar configs:
- `shared_buffers` en `postgresql.conf` (25% de RAM dedicada).
- `maxmemory` en `redis.conf`.

#### Causa B: Disco lento

```bash
# Test velocidad de disco
sudo dd if=/dev/zero of=/tmp/test bs=1M count=100 oflag=dsync
# Debe ser > 50 MB/s para SSD
```

Si es HDD, considerar migrar a SSD.

#### Causa C: PostgreSQL sin VACUUM

```bash
# Verificar último vacuum
docker compose exec postgres psql -U synapse_user -d synapse -c "
SELECT relname, last_vacuum, last_autovacuum, n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;"
```

Si hay tablas con muchos `n_dead_tup`, forzar VACUUM:

```bash
docker compose exec postgres psql -U synapse_user -d synapse -c "VACUUM ANALYZE;"
```

#### Causa D: Too many connections

```sql
SELECT count(*) FROM pg_stat_activity WHERE datname='synapse';
```

Si es > 80% de `max_connections`, aumentar en `postgresql.conf` o ajustar `cp_max` en `homeserver.yaml`.

### 4.2 Sync lento (long-polling)

**Síntoma**: Element tarda mucho en mostrar nuevos mensajes.

**Causa**: puede ser cache miss en Redis o queries ineficientes.

**Solución**:

```bash
# 1. Verificar Redis hit rate
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" INFO stats | grep -E "keyspace_hits|keyspace_misses"

# 2. Si hit rate < 80%, aumentar maxmemory
# Editar redis/redis.conf y reiniciar

# 3. Verificar configuración de caches en homeserver.yaml
# caches:
#   global_factor: 1.0  # subir a 2.0 si hay RAM disponible
```

### 4.3 Subida de archivos lenta

**Causa**: `client_max_body_size` muy alto o disco lento.

**Solución**: ajustar en `nginx/conf.d/matrix.home.arpa.conf`:

```nginx
client_max_body_size 50M;
client_body_buffer_size 16k;
```

---

## 5. Problemas de disco

### 5.1 Disco lleno

**Síntoma**: contenedores se caen, errores de escritura.

**Diagnóstico**:

```bash
df -h
docker system df -v
du -sh /var/lib/docker/volumes/matrix_*
```

**Soluciones**:

#### Limpiar logs Docker antiguos

```bash
docker system prune -a -f
docker builder prune -a -f
```

#### Purgar media antigua de Synapse

```bash
TS_30_DAYS_AGO=$(( ( $(date +%s) - 30*24*60*60 ) * 1000 ))
docker compose exec synapse curl -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/home.arpa/delete?before_ts=$TS_30_DAYS_AGO" \
    -H "Authorization: Bearer $SYNAPSE_ADMIN_API_TOKEN"
```

#### VACUUM FULL PostgreSQL

```bash
docker compose exec postgres psql -U synapse_user -d synapse -c "VACUUM FULL ANALYZE;"
```

#### Limpiar backups antiguos

```bash
find backups/ -mtime +30 -delete
```

### 5.2 Volumen Docker corrupto

**Síntoma**: errores de I/O en logs.

**Diagnóstico**:

```bash
# Verificar filesystem del host
sudo fsck /dev/sdX  # (desmontado)

# Verificar volumen
docker run --rm -v matrix_synapse_data:/data alpine sh -c "ls /data && touch /data/test"
```

**Solución**:

Si el volumen está corrupto, restaurar desde backup:

```bash
docker compose down
docker volume rm matrix_synapse_data
docker volume create matrix_synapse_data
# Restaurar backup del volumen
bash scripts/linux/restore-db.sh backups/db_ULTIMO.sql.gz
docker compose up -d
```

---

## 6. Problemas de certificados

### 6.1 Warning de certificado en navegador

**Causa**: la CA local no está importada en el cliente.

**Solución**: ver [`01-guia-rapida.md` paso 7](01-guia-rapida.md).

### 6.2 Certificado expirado

**Síntoma**: navegador muestra `NET::ERR_CERT_DATE_INVALID`.

**Diagnóstico**:

```bash
openssl x509 -in nginx/certs/matrix.home.arpa.crt -noout -dates
# Muestra notBefore y notAfter
```

**Solución**:

```bash
# Regenerar certs
rm nginx/certs/*.crt nginx/certs/*.key nginx/certs/*.srl
bash scripts/linux/generate-certs.sh

# Recargar Nginx
docker compose exec nginx nginx -s reload

# Re-importar CA en clientes
```

### 6.3 Certificado no coincide con dominio

**Causa**: cambiaste dominios sin regenerar certs.

**Solución**:

```bash
# 1. Actualizar dominios en .env
nano .env

# 2. Regenerar certs
rm nginx/certs/*.crt nginx/certs/*.key nginx/certs/*.srl
bash scripts/linux/generate-certs.sh

# 3. Reiniciar Nginx
bash scripts/linux/restart.sh nginx
```

---

## 7. Problemas de email

### 7.1 Notificaciones no llegan

**Diagnóstico**:

```bash
# 1. Verificar config SMTP en homeserver.yaml
grep -A 10 "email:" synapse/homeserver.yaml

# 2. Ver logs de Synapse buscando errores SMTP
docker compose logs synapse | grep -i "smtp\|mail\|email"

# 3. Test SMTP manual
docker compose exec synapse python3 -c "
import smtplib
s = smtplib.SMTP('smtp.home.arpa', 587)
s.starttls()
s.login('user', 'pass')
s.sendmail('from@home.arpa', ['to@home.arpa'], 'Subject: Test\n\nTest')
print('OK')
"
```

**Causas comunes**:

- Credenciales SMTP incorrectas.
- SMTP bloqueado por firewall.
- TLS requerido pero no configurado.
- Email del destinatario inválido.

### 7.2 Reset password por email no funciona

**Causa**: `password_reset` requiere SMTP funcional.

Verificar:
- `email.enable_notifs: true` en homeserver.yaml.
- `email.require_transport_security: true` si el SMTP requiere TLS.
- El usuario tiene email verificado.

---

## 8. Problemas de federation

### 8.1 No puedo federar (esperado)

Por defecto, la federación está deshabilitada. Esto es intencional para LAN aislada.

Si necesitas federar, ver [`03-configuracion.md` sección 8](03-configuracion.md).

---

## 9. Problemas de backup

### 9.1 Backup falla

**Diagnóstico**:

```bash
# Verificar que PostgreSQL está healthy
docker compose ps postgres

# Verificar permisos de carpeta backups
ls -ld backups/

# Ejecutar backup manual con verbose
bash -x scripts/linux/backup-db.sh
```

**Causas comunes**:

- PostgreSQL no healthy → esperar o reiniciar.
- Sin espacio en disco → limpiar.
- Permisos incorrectos → `chmod 755 backups/`.

### 9.2 Restore falla

Ver [`10-restauracion.md` sección 11](10-restauracion.md).

---

## 10. Problemas después de actualización

### 10.1 Servicios no arrancan después de update

**Diagnóstico**:

```bash
docker compose logs synapse
docker compose logs postgres
```

**Solución**: rollback a versión anterior (ver [`07-actualizacion.md` sección 6](07-actualizacion.md)).

### 10.2 BD requiere migración manual

Algunas actualizaciones de Synapse requieren migraciones manuales. Leer upgrade notes.

```bash
# Ver migraciones pendientes
docker compose exec synapse synapse_port_db --help
```

### 10.3 Config deprecated

```bash
docker compose logs synapse | grep -i "deprecat"
```

Eliminar o actualizar las opciones marcadas como deprecated.

---

## 11. Debug avanzado

### 11.1 Entrar a un contenedor

```bash
# Shell interactivo
docker compose exec synapse bash
docker compose exec postgres sh
docker compose exec redis sh

# Como root (si necesario)
docker compose exec --user root synapse bash
```

### 11.2 Ver procesos dentro del contenedor

```bash
docker compose top synapse
```

### 11.3 Ver recursos de un contenedor

```bash
docker stats matrix-synapse
```

### 11.4 Inspeccionar red Docker

```bash
# Ver redes
docker network ls

# Inspeccionar red
docker network inspect matrix_internal

# Ver IPs de contenedores
docker compose exec synapse ping postgres
docker compose exec synapse ping redis
```

### 11.5 Capturar tráfico de red

```bash
# Instalar tcpdump en contenedor
docker compose exec synapse apt-get update && apt-compose exec synapse apt-get install -y tcpdump

# Capturar
docker compose exec synapse tcpdump -i any -w /tmp/capture.pcap port 5432

# Analizar con Wireshark después
```

### 11.6 Ver variables de entorno de un contenedor

```bash
docker compose exec synapse env
```

### 11.7 Ver filesystem de un contenedor

```bash
docker compose exec synapse find / -name "homeserver.yaml"
docker compose exec postgres find / -name "postgresql.conf"
```

---

## 12. Pedir ayuda

Si no puedes resolver el problema:

1. **Recolectar información**:
   - Output de `bash scripts/linux/status.sh`.
   - Logs relevantes (`docker compose logs <servicio>`).
   - Versión del stack (`docker compose version`, imágenes).
   - Versión del OS del host.
   - Pasos para reproducir.

2. **Buscar en issues existentes**:
   - Synapse: https://github.com/element-hq/synapse/issues
   - Element: https://github.com/element-hq/element-web/issues
   - PostgreSQL: https://www.postgresql.org/list/pgsql-bugs/
   - Docker: https://github.com/docker/compose/issues

3. **Preguntar en comunidades**:
   - Matrix HQ: #matrix:matrix.org (si tienes acceso a federation)
   - Reddit: r/selfhosted, r/matrixdotorg
   - Stack Overflow: tag `matrix` o `synapse`

4. **Reportar bug del stack**:
   - Si es problema de este proyecto (no de Synapse upstream), abrir issue en el repositorio del proyecto.

---

## 13. Prevención

Para minimizar problemas:

1. **Backups regulares**: diario + verificación trimestral.
2. **Monitoreo**: alertas de disco, salud, etc.
3. **Actualizar con procedimiento**: nunca actualizar sin backup previo.
4. **Test en staging**: cambios importantes primero en test.
5. **Documentar cambios**: anotar cada cambio en CHANGELOG.md.
6. **Capacitación**: al menos 2 personas deben poder operar el stack.
7. **Hardening**: aplicar checklist de seguridad post-instalación.
