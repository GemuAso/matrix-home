#!/usr/bin/env bash
# =============================================================================
# backup-db.sh - Respaldo completo de la base de datos PostgreSQL
# -----------------------------------------------------------------------------
# Crea un dump comprimido de la base de datos Synapse.
# También respalda configuraciones y media.
#
# Uso:
#   ./scripts/linux/backup-db.sh                   # Backup con timestamp
#   ./scripts/linux/backup-db.sh mi_backup         # Backup con nombre custom
#
# Output: ./backups/db_YYYYMMDD_HHMMSS.sql.gz
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Respaldo de base de datos"

check_docker

# Validar .env
if [[ -z "${POSTGRES_USER:-}" ]] || [[ -z "${POSTGRES_DB:-}" ]]; then
    fatal "POSTGRES_USER o POSTGRES_DB no definidos en .env"
fi

# Crear directorio de backups
BACKUP_DIR="${PROJECT_ROOT}/backups"
mkdir -p "${BACKUP_DIR}"

# Nombre del backup
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
if [[ $# -ge 1 ]]; then
    BACKUP_NAME="db_${1}_${TIMESTAMP}"
else
    BACKUP_NAME="db_${TIMESTAMP}"
fi

SQL_FILE="${BACKUP_DIR}/${BACKUP_NAME}.sql"
GZ_FILE="${BACKUP_DIR}/${BACKUP_NAME}.sql.gz"

log "Generando backup: ${BACKUP_NAME}"

# Verificar que postgres esté corriendo
if ! dc ps postgres 2>/dev/null | grep -q "healthy"; then
    fatal "PostgreSQL no está saludable. Inicia el stack primero."
fi

# -----------------------------------------------------------------------------
# Dump SQL (custom format para restore flexible)
# -----------------------------------------------------------------------------
log "Ejecutando pg_dump..."
dc exec -T postgres \
    pg_dump \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --format=custom \
    --compress=9 \
    --no-owner \
    --no-privileges \
    --verbose \
    > "${GZ_FILE}"

# Validar tamaño
SIZE=$(stat -c%s "${GZ_FILE}" 2>/dev/null || stat -f%z "${GZ_FILE}")
if [[ ${SIZE} -lt 100 ]]; then
    error "El backup parece estar vacío (${SIZE} bytes)"
    rm -f "${GZ_FILE}"
    fatal "Backup fallido"
fi

# Convertir tamaño a humano
HUMAN_SIZE=$(numfmt --to=iec --suffix=B "${SIZE}" 2>/dev/null || echo "${SIZE} bytes")

log "✅ Backup de BD completado: ${GZ_FILE} (${HUMAN_SIZE})"

# -----------------------------------------------------------------------------
# Backup de configuraciones
# -----------------------------------------------------------------------------
log "Respaldando configuraciones..."
TAR_FILE="${BACKUP_DIR}/config_${BACKUP_NAME}.tar.gz"
tar -czf "${TAR_FILE}" \
    --exclude='*.log' \
    --exclude='__pycache__' \
    -C "${PROJECT_ROOT}" \
    docker-compose.yml \
    .env \
    synapse/homeserver.yaml \
    synapse/log.config \
    synapse/signing.key \
    postgres/postgresql.conf \
    postgres/pg_hba.conf \
    postgres/init.sql \
    redis/redis.conf \
    element/config.json \
    element/nginx.conf \
    element/Dockerfile \
    nginx/nginx.conf \
    nginx/conf.d \
    nginx/snippets \
    nginx/well-known \
    2>/dev/null || warn "Algunos archivos de config no se pudieron respaldar"

log "✅ Backup de config completado: ${TAR_FILE}"

# -----------------------------------------------------------------------------
# Rotación de backups antiguos
# -----------------------------------------------------------------------------
RETENTION="${BACKUP_RETENTION_DAYS:-7}"
log "Rotando backups con más de ${RETENTION} días..."
find "${BACKUP_DIR}" -name "db_*.sql.gz" -mtime "+${RETENTION}" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "config_*.tar.gz" -mtime "+${RETENTION}" -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "media_*.tar.gz" -mtime "+${RETENTION}" -delete 2>/dev/null || true

echo
log "✅ Backup completo."
echo
log "Archivos generados:"
ls -lh "${BACKUP_DIR}"/*"${BACKUP_NAME}"* 2>/dev/null || true
