#!/usr/bin/env bash
# =============================================================================
# export-volumes.sh - Exporta volúmenes Docker para migración (Linux a Linux)
# -----------------------------------------------------------------------------
# Genera un tarball con proyecto + volúmenes para transferir a otro host Linux.
#
# Uso:
#   bash scripts/linux/export-volumes.sh [output-path]
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Exportación de volúmenes para migración"

check_docker

OUTPUT="${1:-${PROJECT_ROOT}/matrix-migration.tar.gz}"
OUTPUT="$(cd "$(dirname "${OUTPUT}")" && pwd)/$(basename "${OUTPUT}")"

log "Archivo destino: ${OUTPUT}"

# Verificar tar
require_cmd tar

# 1. Crear directorio temporal
TMP_DIR="$(mktemp -d)"
trap "rm -rf ${TMP_DIR}" EXIT

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/volumes"

# 2. Detener el stack
log "Deteniendo el stack antes de exportar..."
dc stop

# 3. Copiar archivos del proyecto
log "Copiando archivos del proyecto..."
rsync -a --exclude='backups/*.sql.gz' --exclude='backups/*.tar.gz' \
      --exclude='*.log' --exclude='node_modules' --exclude='.git' \
      "${PROJECT_ROOT}/" "${TMP_DIR}/project/"

# 4. Exportar volúmenes
volumes=("matrix_synapse_data" "matrix_postgres_data" "matrix_redis_data")
for vol in "${volumes[@]}"; do
    log "Exportando volumen: ${vol}"
    if ! docker volume inspect "${vol}" >/dev/null 2>&1; then
        warn "Volumen ${vol} no existe. Saltando."
        continue
    fi
    docker run --rm \
        -v "${vol}:/data:ro" \
        -v "${TMP_DIR}/volumes:/backup" \
        alpine:3.20 \
        tar -cf "/backup/${vol}.tar" -C /data .
done

# 5. Crear tarball final
log "Creando tarball final: ${OUTPUT}"
tar -czf "${OUTPUT}" -C "${TMP_DIR}" project volumes

# 6. Verificar
SIZE=$(du -h "${OUTPUT}" | cut -f1)
log "Tarball creado: ${OUTPUT} (${SIZE})"

echo
log "Exportación completada."
echo
log "Próximos pasos:"
log "  1. Transfiere ${OUTPUT} al servidor destino (scp / rsync)"
log "  2. En el destino ejecuta:"
log "     sudo bash deployment/migrate-from-windows.sh ${OUTPUT} /opt/matrix-docker"
