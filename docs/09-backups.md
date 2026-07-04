# Backups

> Estrategia, scripts y procedimientos de respaldo.

---

## 1. Estrategia de respaldo

### 1.1 Principios

1. **Backup en caliente**: sin detener el stack (usando `pg_dump` y snapshots de volumen).
2. **3-2-1**: 3 copias, 2 medios, 1 offsite.
3. **Rotación automática**: eliminar backups antiguos para no llenar disco.
4. **Verificación periódica**: test de restauración al menos trimestral.
5. **Cifrado offsite**: si los backups salen del host, deben ir cifrados.

### 1.2 Qué respaldar

| Componente | Método | Frecuencia |
|------------|--------|------------|
| Base de datos PostgreSQL | `pg_dump --format=custom` | Diario |
| Configuración Synapse | `tar` de archivos YAML/JSON | Diario |
| Signing key | Incluida en backup de config | Diario |
| Configuración PostgreSQL | Incluida en backup de config | Diario |
| Configuración Redis | Incluida en backup de config | Diario |
| Configuración Element | Incluida en backup de config | Diario |
| Configuración Nginx | Incluida en backup de config | Diario |
| Certificados SSL | Incluida en backup de config | Semanal |
| Media de Synapse | Snapshot de volumen o rsync | Semanal |
| Logs | Opcional, según retención | Semanal |

### 1.3 Qué NO respaldar

- Imágenes Docker (se descargan via `docker pull`).
- Caché de Redis (es efímera, se regenera).
- Logs de Docker (rotados automáticamente).

---

## 2. Scripts de backup

### 2.1 Linux: `scripts/linux/backup-db.sh`

```bash
# Backup con timestamp automático
bash scripts/linux/backup-db.sh

# Backup con nombre personalizado
bash scripts/linux/backup-db.sh pre_actualizacion

# Output:
# backups/db_YYYYMMDD_HHMMSS.sql.gz
# backups/config_db_YYYYMMDD_HHMMSS.tar.gz
```

### 2.2 Windows: `scripts/windows/backup-db.ps1`

```powershell
# Backup con timestamp automático
.\scripts\windows\backup-db.ps1

# Backup con nombre personalizado
.\scripts\windows\backup-db.ps1 pre_actualizacion
```

### 2.3 Qué hacen los scripts

1. **Verifican** que PostgreSQL esté healthy.
2. **Ejecutan** `pg_dump` con `--format=custom --compress=9` para máximo compresión y flexibilidad de restore.
3. **Generan** tar.gz con todos los archivos de configuración (excluyendo logs y backups antiguos).
4. **Verifican** que el archivo de backup tiene tamaño razonable (>100 bytes).
5. **Rotan** backups antiguos según `BACKUP_RETENTION_DAYS` del `.env`.

### 2.4 Formato del backup de BD

El backup usa `--format=custom` de `pg_dump`:

- Formato binario comprimido nativo de PostgreSQL.
- Permite restore selectivo (una tabla, un schema).
- Más rápido que SQL plano para BDs grandes.
- Compatible con `pg_restore`.

> **Nota**: el archivo resultante tiene extensión `.sql.gz` por convención, pero internamente es formato custom comprimido. Se restaura con `pg_restore` (no con `psql`).

---

## 3. Backup manual

### 3.1 Backup completo en caliente

```bash
# Linux
bash scripts/linux/backup-db.sh manual_$(date +%Y%m%d_%H%M%S)

# Windows
.\scripts\windows\backup-db.ps1 manual_$(Get-Date -Format "yyyyMMdd_HHmmss")
```

### 3.2 Verificar backup

```bash
# Tamaño
ls -lh backups/db_*.sql.gz

# Contenido (listar tablas incluidas)
pg_restore --list backups/db_*.sql.gz | head -50

# Test de integridad
pg_restore --list backups/db_*.sql.gz | wc -l
# Debe ser > 100 líneas para una BD con datos
```

### 3.3 Backup solo de BD (sin config)

Si solo necesitas la BD:

```bash
docker compose exec -T postgres \
    pg_dump -U synapse_user -d synapse \
    --format=custom --compress=9 --no-owner --no-privileges \
    > backups/db_manual_$(date +%Y%m%d_%H%M%S).sql.gz
```

### 3.4 Backup solo de media (volúmenes)

El media de Synapse está en el volumen `matrix_synapse_data`. Para respaldarlo por separado:

```bash
# Crear tar del volumen
docker run --rm \
    -v matrix_synapse_data:/data:ro \
    -v $(pwd)/backups:/backup \
    alpine:3.20 \
    tar -czf /backup/media_$(date +%Y%m%d_%H%M%S).tar.gz -C /data media
```

---

## 4. Backup automático en Ubuntu

### 4.1 Cron job

El archivo `deployment/matrix-backup.cron` define:

```cron
# Backup diario a las 02:00 AM
0 2 * * * deploy /opt/matrix-docker/scripts/linux/backup-db.sh auto_daily >> /opt/matrix-docker/backups/cron.log 2>&1

# Limpieza de backups antiguos (>30 días) cada domingo a las 04:00 AM
0 4 * * 0 deploy find /opt/matrix-docker/backups -name "*.sql.gz" -mtime +30 -delete && find /opt/matrix-docker/backups -name "*.tar.gz" -mtime +30 -delete
```

### 4.2 Instalación

```bash
sudo cp /opt/matrix-docker/deployment/matrix-backup.cron /etc/cron.d/matrix-backup
sudo chmod 644 /etc/cron.d/matrix-backup
sudo chown root:root /etc/cron.d/matrix-backup
sudo systemctl reload cron
```

### 4.3 Verificación

```bash
# Verificar que cron está cargado
sudo cat /etc/cron.d/matrix-backup

# Verificar ejecución (después de las 02:00 AM)
ls -la /opt/matrix-docker/backups/ | tail -10
cat /opt/matrix-docker/backups/cron.log
```

### 4.4 Forzar ejecución inmediata

Para probar sin esperar al horario programado:

```bash
sudo -u deploy bash /opt/matrix-docker/scripts/linux/backup-db.sh test_cron
```

---

## 5. Estrategia de retención

### 5.1 Configuración

La variable `BACKUP_RETENTION_DAYS` en `.env` controla cuántos días se conservan los backups:

```env
BACKUP_RETENTION_DAYS=7   # Conservar 7 días
```

### 5.2 Recomendación por escenario

| Escenario | Retención | Justificación |
|-----------|-----------|---------------|
| LAN pequeña (<50 users) | 7 días | Suficiente para restore puntuales |
| LAN mediana (50-200 users) | 14 días | Más margen de recuperación |
| LAN grande (200+ users) | 30 días | Requerimientos operativos |
| Compliance / auditoría | 90 días mínimo | Requisitos legales |

### 5.3 Backups mensuales y anuales

Para retención a largo plazo:

```bash
# Backup mensual (1ro de cada mes)
0 3 1 * * deploy /opt/matrix-docker/scripts/linux/backup-db.sh monthly_$(date +\%Y\%m) >> /opt/matrix-docker/backups/cron.log 2>&1

# Mover backups mensuales a almacenamiento separado (no se rotan con la limpieza diaria)
# Ej: mover a /mnt/nas/matrix-backups/monthly/
```

---

## 6. Backup offsite

### 6.1 Sincronización con NAS o servidor remoto

```bash
# Script de sync post-backup (añadir a cron después del backup)
rsync -avz --delete /opt/matrix-docker/backups/ deploy@nas.home.arpa:/volume1/matrix-backups/daily/
```

### 6.2 Cifrado de backups offsite

Antes de transferir, cifrar con GPG:

```bash
# Cifrar
gpg --symmetric --cipher-algo AES256 --output backups/db_YYYYMMDD.sql.gz.gpg backups/db_YYYYMMDD.sql.gz

# Eliminar original (opcional)
rm backups/db_YYYYMMDD.sql.gz

# Transferir solo el .gpg
rsync -avz backups/*.gpg deploy@nas.home.arpa:/volume1/matrix-backups/encrypted/

# Eliminar cifrado local (opcional)
rm backups/*.gpg
```

### 6.3 Script completo de backup + cifrado + sync

```bash
#!/usr/bin/env bash
# /opt/matrix-docker/scripts/linux/backup-offsite.sh
set -Eeuo pipefail

source /opt/matrix-docker/scripts/linux/_common.sh

# 1. Backup local
bash /opt/m/my-project/matrix-docker/scripts/linux/backup-db.sh

# 2. Cifrar backups del día
LATEST_DB=$(ls -t /opt/matrix-docker/backups/db_*.sql.gz | head -1)
gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase "$GPG_PASSPHRASE" \
    --output "${LATEST_DB}.gpg" "${LATEST_DB}"

# 3. Sync con NAS
rsync -avz --delete \
    /opt/matrix-docker/backups/*.gpg \
    deploy@nas.home.arpa:/volume1/matrix-backups/encrypted/

# 4. Limpiar cifrados locales
rm /opt/matrix-docker/backups/*.gpg

log "Backup offsite completado."
```

---

## 7. Backup de certs y signing key

### 7.1 Por separado (alto secreto)

La signing key y los certs de la CA son secretos críticos. Respalda por separado:

```bash
# Tar separado
tar -czf /secure/location/secrets_$(date +%Y%m%d).tar.gz \
    synapse/signing.key \
    nginx/certs/ca.key \
    nginx/certs/ca.crt

# Cifrar
gpg --symmetric --cipher-algo AES256 \
    --output /secure/location/secrets_$(date +%Y%m%d).tar.gz.gpg \
    /secure/location/secrets_$(date +%Y%m%d).tar.gz

# Eliminar tar original
rm /secure/location/secrets_$(date +%Y%m%d).tar.gz
```

### 7.2 Almacenamiento físico

- USB drive cifrado (Veracrypt, LUKS) guardado en caja fuerte.
- O password manager (1Password, Bitwarden) con archivo adjunto.
- O hardware security module (HSM) si disponible.

---

## 8. Verificación de backups

### 8.1 Verificar que el backup se puede restaurar

**CRÍTICO**: un backup que no se puede restaurar NO es un backup.

```bash
# Test trimestral
# 1. Levantar stack de test
docker compose -f docker-compose.test.yml up -d postgres

# 2. Restaurar backup
docker compose exec -T postgres pg_restore \
    -U synapse_user -d test_synapse \
    --clean --if-exists \
    < backups/db_ULTIMO.sql.gz

# 3. Verificar tablas
docker compose exec postgres psql -U synapse_user -d test_synapse -c "\dt"

# 4. Verificar usuarios
docker compose exec postgres psql -U synapse_user -d test_synapse \
    -c "SELECT count(*) FROM users;"

# 5. Limpiar
docker compose -f docker-compose.test.yml down -v
```

### 8.2 Verificar checksums

```bash
# Generar checksum al crear backup
sha256sum backups/db_*.sql.gz > backups/checksums.txt

# Verificar después
sha256sum -c backups/checksums.txt
```

### 8.3 Test de backup dañado

Simular corrupción:

```bash
# Crear copia corrupta
cp backups/db_ULTIMO.sql.gz /tmp/db_corrupto.sql.gz
echo "BASURA" >> /tmp/db_corrupto.sql.gz

# Intentar restaurar (debe fallar)
docker compose exec -T postgres pg_restore \
    -U synapse_user -d synapse_test \
    < /tmp/db_corrupto.sql.gz
# Esperado: error de formato
```

---

## 9. Restore testing (DR drill)

### 9.1 Drill trimestral

Una vez al trimestre, simular un desastre:

1. **Avisar a usuarios**: "Test de DR el día X".
2. **Hacer backup** antes del drill.
3. **En un host de test**: levantar stack vacío.
4. **Restaurar backup**: `bash scripts/linux/restore-db.sh ...`
5. **Verificar**:
   - Login con usuarios
   - Mensajes accesibles
   - Salas presentes
   - Media accesible
6. **Documentar** tiempo total y problemas encontrados.
7. **Mejorar procedimientos** si fue lento o fallido.

### 9.2 Métricas a medir

| Métrica | Objetivo |
|---------|----------|
| RTO (Recovery Time Objective) | < 15 min |
| RPO (Recovery Point Objective) | < 24 h |
| Tiempo de restore | < 5 min para 1 GB |
| Tiempo de verificación | < 30 min |
| Tasa de éxito | 100% |

---

## 10. Backup de logs (opcional)

Los logs pueden ser útiles para auditoría. Para respaldarlos:

```bash
# Exportar logs de Docker a archivo
docker compose logs --no-color > backups/logs_$(date +%Y%m%d).log
gzip backups/logs_*.log

# O exportar logs de un servicio específico
docker compose logs synapse --no-color > backups/synapse_logs_$(date +%Y%m%d).log
gzip backups/synapse_logs_*.log
```

Para logs persistentes de Nginx (fuera del volumen):

```bash
docker cp matrix-nginx:/var/log/nginx/matrix-access.log backups/nginx_access_$(date +%Y%m%d).log
docker cp matrix-nginx:/var/log/nginx/matrix-error.log backups/nginx_error_$(date +%Y%m%d).log
```

---

## 11. Monitoreo de backups

### 11.1 Alerta si no hay backup reciente

```bash
#!/usr/bin/env bash
# /opt/matrix-docker/scripts/linux/check-backup.sh

LATEST=$(find /opt/matrix-docker/backups -name "db_*.sql.gz" -mmin -25 -print -quit)
if [ -z "$LATEST" ]; then
    echo "ALERTA: No hay backup en las últimas 25 horas" | \
    mail -s "Matrix: backup failed" admin@home.arpa
fi
```

Añadir a cron:

```cron
0 6 * * * deploy /opt/matrix-docker/scripts/linux/check-backup.sh
```

### 11.2 Verificar tamaño esperado

```bash
#!/usr/bin/env bash
# Alerta si el backup es sospechosamente pequeño
LATEST=$(ls -t /opt/matrix-docker/backups/db_*.sql.gz | head -1)
SIZE=$(stat -c%s "$LATEST")
if [ "$SIZE" -lt 10000 ]; then
    echo "ALERTA: Backup $LATEST tiene tamaño inusual: $SIZE bytes" | \
    mail -s "Matrix: backup size warning" admin@home.arpa
fi
```

---

## 12. Backup antes de operaciones críticas

### 12.1 Antes de actualización

```bash
bash scripts/linux/backup-db.sh pre_update_$(date +%Y%m%d_%H%M%S)
```

### 12.2 Antes de cambio de config

```bash
bash scripts/linux/backup-db.sh pre_config_change_$(date +%Y%m%d_%H%M%S)
```

### 12.3 Antes de migración

```bash
bash scripts/linux/backup-db.sh pre_migration_$(date +%Y%m%d_%H%M%S)
```

### 12.4 Antes de purgar media

```bash
bash scripts/linux/backup-db.sh pre_media_purge_$(date +%Y%m%d_%H%M%S)
```

---

## 13. Almacenamiento de backups

### 13.1 Local

- `/opt/matrix-docker/backups/` (en el host del stack).
- Permite restore rápido.
- Volátil si el host falla.

### 13.2 NAS local

- NAS en la misma LAN.
- Accesible vía rsync, NFS, SMB.
- Protege contra fallo del host.

### 13.3 Offsite

- Servidor remoto o cloud (S3, Backblaze B2).
- Protege contra desastre físico (incendio, robo).
- Recomendado cifrado GPG antes de subir.

### 13.4 Cold storage

- USB drive o disco externo.
- Guardado en caja fuerte.
- Para backups mensuales/anuales.

---

## 14. Cumplimiento normativo

Si tu organización está sujeta a regulaciones (SOX, HIPAA, GDPR):

- **Retención mínima**: según normativa (ej. SOX 7 años).
- **Inmutabilidad**: WORM storage o backups firmados.
- **Cifrado**: AES-256 mínimo.
- **Auditoría**: logs de acceso a backups.
- **Ubicación**: datos no salen de la jurisdicción (GDPR: UE).

---

## 15. FAQ de backups

### ¿Puedo hacer backup con el stack corriendo?

Sí. `pg_dump` hace backup consistente sin bloquear la BD.

### ¿Cuánto tarda un backup?

Para una BD de 1 GB: ~30 segundos. Para 10 GB: ~5 minutos.

### ¿Puedo comprimir más?

Sí, ajustando `--compress=9` (ya al máximo). Alternativamente, usar `xz` en lugar de `gzip` para mejor ratio (pero más lento).

### ¿Necesito detener Synapse?

No. `pg_dump` usa transacciones MVCC, Synapse puede seguir operando.

### ¿Cómo restauro un solo usuario?

```bash
# Extraer solo la tabla users del backup
pg_restore -t users backups/db_ULTIMO.sql.gz | \
    docker compose exec -T postgres psql -U synapse_user -d synapse
```

### ¿Puedo restaurar en otra versión de PostgreSQL?

- Same major version (16.x → 16.y): sí, directo.
- Major version diferente (15 → 16): sí, pero usar `pg_dump` en la versión vieja y `pg_restore` en la nueva.
- Mayor a 2 versiones (13 → 16): usar `pg_upgrade` o dump+restore completo.
