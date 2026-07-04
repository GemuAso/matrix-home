#!/usr/bin/env bash
# =============================================================================
# restore-db.sh - Restaura un backup de base de datos
# -----------------------------------------------------------------------------
# Restaura un dump SQL (formato custom de pg_dump) a PostgreSQL.
#
# Uso:
#   ./scripts/linux/restore-db.sh <archivo.sql.gz>     # Backup completo (gz)
#   ./scripts/linux/restore-db.sh <archivo.sql>        # Backup custom format
#
# ADVERTENCIA: Esto SOBREESCRIBE la base de datos actual.
# Realiza un backup automático antes de restaurar.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Restauración de base de datos"

check_docker

if [[ $# -lt 1 ]]; then
    fatal "Uso: $0 <archivo.sql.gz|archivo.sql>"
fi

BACKUP_FILE="$1"

# Resolver ruta absoluta
if [[ ! -f "${BACKUP_FILE}" ]]; then
    BACKUP_FILE="${PROJECT_ROOT}/backups/${BACKUP_FILE}"
fi

if [[ ! -f "${BACKUP_FILE}" ]]; then
    fatal "Archivo no encontrado: $1"
fi

log "Archivo a restaurar: ${BACKUP_FILE}"
log "Tamaño: $(du -h "${BACKUP_FILE}" | cut -f1)"

# Verificar que PostgreSQL esté corriendo
if ! dc ps postgres 2>/dev/null | grep -q "healthy"; then
    fatal "PostgreSQL no está saludable. Inicia el stack primero."
fi

# -----------------------------------------------------------------------------
# Backup automático antes de restaurar
# -----------------------------------------------------------------------------
warn "Se realizará un backup automático antes de restaurar."
warn "Presiona ENTER para continuar, o Ctrl+C para abortar."
read -r

AUTO_BACKUP_NAME="pre_restore_$(date '+%Y%m%d_%H%M%S')"
log "Creando backup preventivo: ${AUTO_BACKUP_NAME}"
bash "${SCRIPT_DIR}/backup-db.sh" "${AUTO_BACKUP_NAME}"

# -----------------------------------------------------------------------------
# Confirmar
# -----------------------------------------------------------------------------
echo
warn "⚠️  ESTO BORRARÁ Y RECREARÁ LA BASE DE DATOS '${POSTGRES_DB:-synapse}'"
warn "⚠️  Todos los datos actuales se perderán."
warn "Confirma escribiendo 'SI RESTAURAR':"
read -r CONFIRM
if [[ "${CONFIRM}" != "SI RESTAURAR" ]]; then
    log "Operación cancelada."
    exit 0
fi

# -----------------------------------------------------------------------------
# Determinar formato
# -----------------------------------------------------------------------------
log "Restaurando base de datos..."

if [[ "${BACKUP_FILE}" == *.gz ]]; then
    # Backup comprimido con gzip (formato custom de pg_dump)
    gunzip -c "${BACKUP_FILE}" | dc exec -T postgres \
        pg_restore \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --verbose \
        2>&1 | tail -50
else
    # Archivo SQL plano o custom sin gzip
    dc exec -T postgres \
        pg_restore \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --verbose \
        < "${BACKUP_FILE}" \
        2>&1 | tail -50
fi

# -----------------------------------------------------------------------------
# Verificar
# -----------------------------------------------------------------------------
echo
log "Verificando restauración..."
TABLES=$(dc exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d '[:space:]')
log "Tablas en la base restaurada: ${TABLES}"

echo
log "✅ Restauración completada."
log "Reinicia Synapse para que cargue los datos: scripts/linux/restart.sh synapse"
