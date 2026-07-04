# Restauración

> Procedimientos de restauración desde backups.

---

## 1. Principios de restauración

1. **Siempre hacer backup antes de restaurar**: incluso del estado actual, por si necesitas revertir.
2. **Confirmar explícitamente**: la restauración sobrescribe datos.
3. **Verificar después**: no asumir que funcionó.
4. **Tener plan de rollback**: si la restauración falla, volver al estado previo.
5. **Practicar en staging**: nunca restaurar en producción sin haber probado antes.

---

## 2. Tipos de restauración

### 2.1 Restauración completa de BD

Restaura todas las tablas de Synapse desde un dump SQL.

### 2.2 Restauración selectiva

Restaura solo ciertas tablas o schemas.

### 2.3 Restauración point-in-time

Restaura la BD a un momento específico (requiere WAL archiving, no configurado por defecto).

### 2.4 Restauración de archivos

Restaura configs, certs, signing key desde un tar.gz.

---

## 3. Restauración estándar

### 3.1 Usando el script

```bash
# Linux
bash scripts/linux/restore-db.sh backups/db_YYYYMMDD_HHMMSS.sql.gz

# Windows
.\scripts\windows\restore-db.ps1 backups\db_YYYYMMDD_HHMMSS.sql.gz
```

### 3.2 Qué hace el script

1. **Verifica** que el archivo existe.
2. **Verifica** que PostgreSQL está healthy.
3. **Hace backup preventivo** automático (`pre_restore_*`).
4. **Pide confirmación escrita**: "SI RESTAURAR".
5. **Restaura** con `pg_restore --clean --if-exists --no-owner --no-privileges`.
6. **Verifica** el conteo de tablas.
7. **Sugiere** reiniciar Synapse.

### 3.3 Parámetros de pg_restore usados

| Parámetro | Propósito |
|-----------|-----------|
| `--clean` | DROP objetos antes de crear |
| `--if-exists` | No fallar si el objeto no existe |
| `--no-owner` | No asignar owner original |
| `--no-privileges` | No restaurar grants originales |
| `--verbose` | Output detallado |

---

## 4. Restauración manual

### 4.1 Solo BD

```bash
# Detener Synapse para evitar conexiones durante restore
docker compose stop synapse

# Restaurar
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --clean --if-exists --no-owner --no-privileges \
    --verbose \
    < backups/db_YYYYMMDD_HHMMSS.sql.gz \
    2>&1 | tail -50

# Reiniciar Synapse
docker compose start synapse

# Verificar
bash scripts/linux/status.sh
```

### 4.2 Solo una tabla

```bash
# Listar tablas en el backup
pg_restore --list backups/db_YYYYMMDD_HHMMSS.sql.gz | grep "TABLE"

# Restaurar solo la tabla users
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --table=users \
    --clean --if-exists \
    --no-owner --no-privileges \
    < backups/db_YYYYMMDD_HHMMSS.sql.gz

# Verificar
docker compose exec postgres psql -U synapse_user -d synapse -c "SELECT count(*) FROM users;"
```

### 4.3 Solo datos (sin schema)

Si el schema ya existe pero quieres reemplazar datos:

```bash
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --data-only \
    --disable-triggers \
    < backups/db_YYYYMMDD_HHMMSS.sql.gz
```

### 4.4 Listar contenido del backup

```bash
# Sin extraer
pg_restore --list backups/db_YYYYMMDD_HHMMSS.sql.gz | head -50

# Listar solo tablas
pg_restore --list backups/db_YYYYMMDD_HHMMSS.sql.gz | grep "TABLE DATA"
```

---

## 5. Restauración de configuración

### 5.1 Desde el tar.gz de configs

```bash
# Backup actual (por si acaso)
cp -r synapse synapse.bak
cp -r nginx nginx.bak
cp -r element element.bak
cp -r postgres postgres.bak
cp -r redis redis.bak
cp .env .env.bak

# Restaurar
tar -xzf backups/config_YYYYMMDD_HHMMSS.tar.gz -C ./

# Verificar
diff -r synapse synapse.bak | head
diff .env .env.bak

# Reiniciar para aplicar
bash scripts/linux/restart.sh
```

### 5.2 Restaurar signing key (CRÍTICO)

Si perdiste la signing key, restaurar desde backup:

```bash
# Extraer del tar de configs
tar -xzf backups/config_YYYYMMDD_HHMMSS.tar.gz synapse/signing.key

# Verificar
cat synapse/signing.key
# Debe verse como: ed25519 a1b2c <base64>

# Permisos
chmod 600 synapse/signing.key

# Reiniciar Synapse
bash scripts/linux/restart.sh synapse
```

> **CRÍTICO**: Sin la signing key original, los clientes NO confiarán en eventos firmados con una key nueva. Esto puede requerir re-crear todas las cuentas.

### 5.3 Restaurar certificados SSL

```bash
# Extraer del tar
tar -xzf backups/config_YYYYMMDD_HHMMSS.tar.gz nginx/certs

# Permisos
chmod 644 nginx/certs/*.crt
chmod 600 nginx/certs/*.key

# Verificar
openssl x509 -in nginx/certs/matrix.crt -noout -dates

# Recargar Nginx
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

---

## 6. Restauración en un host nuevo (DR completo)

### 6.1 Escenario

El host original está caído (hardware failure). Tienes:
- Acceso al último backup (`.sql.gz` + `.tar.gz`).
- Un nuevo host Ubuntu Server.

### 6.2 Procedimiento

```bash
# 1. Instalar Docker en el nuevo host
sudo bash deployment/install-docker-ubuntu.sh

# 2. Copiar proyecto (git clone o descomprimir tarball)
sudo mkdir -p /opt/matrix-docker
sudo chown deploy:deploy /opt/matrix-docker
cd /opt/matrix-docker
# Copiar archivos aquí

# 3. Copiar backups al nuevo host
# scp desde el host original o descargar de offsite
cp /tmp/backups/db_ULTIMO.sql.gz ./backups/
cp /tmp/backups/config_ULTIMO.tar.gz ./backups/

# 4. Configurar .env (puede ser el mismo o ajustado)
nano .env

# 5. Setup inicial (genera certs nuevos si no restauraste los viejos)
bash scripts/linux/setup.sh

# 6. Si quieres restaurar los certs y configs originales:
tar -xzf backups/config_ULTIMO.tar.gz

# 7. Iniciar solo PostgreSQL
docker compose up -d postgres
sleep 30

# 8. Restaurar BD
bash scripts/linux/restore-db.sh backups/db_ULTIMO.sql.gz

# 9. Iniciar el resto del stack
docker compose up -d

# 10. Verificar
bash scripts/linux/status.sh
```

### 6.3 Verificación funcional

```bash
# Health
curl -k https://matrix.home.arpa/health

# Login de prueba
curl -k -X POST https://matrix.home.arpa/_matrix/client/v3/login \
    -H "Content-Type: application/json" \
    -d '{"type":"m.login.password","user":"admin","password":"TEST"}'

# Verificar usuarios migrados
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM users;"
```

---

## 7. Restauración point-in-time (PITR)

### 7.1 Requisitos

PITR requiere WAL archiving, que NO está configurado por defecto en este stack.

Para habilitarlo (futuro):

1. Configurar `archive_mode = on` en `postgresql.conf`.
2. Configurar `archive_command` para enviar WALs a storage seguro.
3. Hacer base backup periódico.
4. En restore: restaurar base backup + replay WALs hasta el momento deseado.

### 7.2 Alternativa: snapshots del volumen

Si el host usa LVM o ZFS, se pueden hacer snapshots del volumen Docker:

```bash
# LVM snapshot
sudo lvcreate -L 1G -s -n matrix_pg_snapshot /dev/vg0/matrix_postgres_data

# Restaurar desde snapshot
docker compose stop postgres
sudo lvconvert --merge /dev/vg0/matrix_pg_snapshot
docker compose start postgres
```

---

## 8. Restauración de media

### 8.1 Desde backup de media

Si hiciste backup del volumen de media:

```bash
# Detener Synapse
docker compose stop synapse

# Restaurar media
docker run --rm \
    -v matrix_synapse_data:/data \
    -v $(pwd)/backups:/backup:ro \
    alpine:3.20 \
    tar -xzf /backup/media_YYYYMMDD_HHMMSS.tar.gz -C /data

# Reiniciar Synapse
docker compose start synapse
```

### 8.2 Verificar media

```bash
# Tamaño del directorio
docker compose exec synapse du -sh /data/media

# Contar archivos
docker compose exec synapse find /data/media -type f | wc -l

# Verificar accesibilidad desde Element
# (subir un archivo de prueba y verificar que se descarga)
```

---

## 9. Restauración de usuarios específicos

### 9.1 Restaurar un usuario eliminado

Si un usuario fue desactivado pero no borrado:

```bash
# Reactivar
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "UPDATE users SET deactivated=0 WHERE name='@usuario:home.arpa';"

# Si se borró completamente, restaurar desde backup:
# 1. Extraer fila del backup
pg_restore --data-only --table=users backups/db_YYYYMMDD.sql.gz | \
    grep "@usuario:home.arpa" > /tmp/user_row.sql

# 2. Insertar en la BD actual
docker compose exec -T postgres psql -U synapse_user -d synapse < /tmp/user_row.sql
```

### 9.2 Restaurar salas eliminadas

Si se eliminó una sala por error:

```bash
# Las salas eliminadas con purge=true se borran completamente.
# Necesitas restaurar desde backup completo.

# 1. Detener Synapse
docker compose stop synapse

# 2. Restaurar BD del backup previo a la eliminación
bash scripts/linux/restore-db.sh backups/db_PRE_ELIMINACION.sql.gz

# 3. Reiniciar
docker compose start synapse
```

---

## 10. Verificación post-restauración

### 10.1 Lista de verificación

- [ ] Stack está UP y healthy.
- [ ] Login de admin funciona.
- [ ] Login de usuario normal funciona.
- [ ] Salas existentes visibles.
- [ ] Mensajes antiguos cargan.
- [ ] Media (imágenes, archivos) cargan.
- [ ] Enviar mensaje nuevo funciona.
- [ ] Recibir mensaje funciona.
- [ ] Notificaciones por email llegan (si SMTP activo).
- [ ] Logs sin errores post-restore.

### 10.2 Comandos de verificación

```bash
# Estado
bash scripts/linux/status.sh

# Usuarios
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM users;"

# Salas
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM rooms;"

# Eventos (mensajes)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM events;"

# Access tokens (sesiones activas)
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM access_tokens;"

# Media
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SELECT count(*) FROM local_media_repository;"

# Logs de error
docker compose logs synapse --since 1h 2>&1 | grep -iE "error|fatal" | head
```

---

## 11. Problemas comunes de restauración

### 11.1 "pg_restore: [archiver] input file does not appear to be a valid archive"

Causa: el archivo está corrupto o no es formato custom.

Solución:
- Verificar que el backup se generó con `--format=custom`.
- Si es SQL plano, restaurar con `psql` en lugar de `pg_restore`.

### 11.2 "role 'synapse_user' does not exist"

Causa: el backup incluye ownership al usuario original.

Solución: usar `--no-owner`:

```bash
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --no-owner --no-privileges \
    < backups/db_*.sql.gz
```

### 11.3 "database 'synapse' does not exist"

Causa: la BD no fue creada.

Solución: el script de init.sql la crea automáticamente. Si no, crear manualmente:

```bash
docker compose exec postgres psql -U synapse_user -d postgres \
    -c "CREATE DATABASE synapse OWNER synapse_user;"
```

### 11.4 Restauración muy lenta

Causa: índices y constraints se crean durante restore.

Solución: deshabilitar temporalmente:

```bash
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --no-owner --no-privileges \
    --disable-triggers \
    --no-data-for-failed-tables \
    < backups/db_*.sql.gz

# Reindexar después
docker compose exec postgres psql -U synapse_user -d synapse -c "REINDEX DATABASE synapse;"
```

### 11.5 "out of memory" durante restore

Causa: datos muy grandes para work_mem.

Solución: aumentar maintenance_work_mem temporalmente:

```bash
docker compose exec postgres psql -U synapse_user -d synapse \
    -c "SET maintenance_work_mem = '1GB';"

# Luego hacer el restore
```

### 11.6 Tablas con dependencias circulares

Causa: foreign keys entre tablas.

Solución: usar `--disable-triggers` o restaurar en orden:

```bash
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse \
    --no-owner --no-privileges \
    --disable-triggers \
    < backups/db_*.sql.gz
```

---

## 12. Restauración de respaldo cifrado (GPG)

### 12.1 Si cifraste los backups

```bash
# Desencriptar
gpg --decrypt --output backups/db_YYYYMMDD.sql.gz backups/db_YYYYMMDD.sql.gz.gpg

# Te pedirá la passphrase

# Restaurar normalmente
bash scripts/linux/restore-db.sh backups/db_YYYYMMDD.sql.gz

# Eliminar el archivo desencriptado después
shred -u backups/db_YYYYMMDD.sql.gz
```

### 12.2 Si perdiste la passphrase

Malas noticias: los datos están perdidos. Asegúrate de guardar la passphrase en un password manager seguro.

---

## 13. Rollback de restauración

Si la restauración falla o trae datos incorrectos:

### 13.1 Volver al estado pre-restore

El script `restore-db.sh` hace un backup automático antes de restaurar (`pre_restore_*`):

```bash
# Restaurar el backup pre-restore
bash scripts/linux/restore-db.sh backups/db_pre_restore_YYYYMMDD_HHMMSS.sql.gz
```

### 13.2 Si perdiste el backup pre-restore

```bash
# Buscar el backup más reciente antes del restore fallido
ls -lt backups/db_*.sql.gz | head -10

# Restaurar el más reciente válido
bash scripts/linux/restore-db.sh backups/db_VALIDO.sql.gz
```

---

## 14. Documentación post-restauración

Después de cualquier restore, documentar:

```markdown
## Restore realizado el YYYY-MM-DD HH:MM

**Operador**: <nombre>
**Motivo**: <motivo>
**Backup restaurado**: db_YYYYMMDD_HHMMSS.sql.gz
**Tamaño**: X GB
**Tiempo total**: X minutos
**Problemas encontrados**: <si hubo>
**Verificación**: OK / con errores
**Notas**: <cualquier observación>
```

Guardar en `backups/restore_log.md` (no se commitea a Git).

---

## 15. Práctica recomendada

### 15.1 Drill trimestral

Una vez al trimestre, simular un desastre completo:

1. Avisar a usuarios.
2. Hacer backup final.
3. "Borrar" la BD (en un entorno de staging).
4. Restaurar desde backup.
5. Verificar todo.
6. Documentar tiempo y problemas.
7. Mejorar procedimientos.

### 15.2 Verificar backups antiguos

Mensualmente, intentar restaurar un backup de hace 1-2 meses:

```bash
# Buscar backup de hace 30 días
TARGET_DATE=$(date -d "30 days ago" +%Y%m%d)
LATEST_OLD=$(ls backups/db_${TARGET_DATE}_*.sql.gz 2>/dev/null | head -1)

if [ -n "$LATEST_OLD" ]; then
    echo "Verificando backup antiguo: $LATEST_OLD"
    # Restaurar en entorno de test
fi
```

### 15.3 Capacitación

Asegurarte de que al menos 2 personas sepán:
- Cómo hacer un backup.
- Cómo restaurar.
- Dónde están los backups offsite.
- Dónde está la passphrase de cifrado.
- Procedimiento de DR completo.

Si solo una persona sabe, es un single point of failure.
