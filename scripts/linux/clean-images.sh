#!/usr/bin/env bash
# =============================================================================
# clean-images.sh - Limpia imágenes Docker antiguas y sin usar
# -----------------------------------------------------------------------------
# Ejecuta:
#   - docker image prune (imágenes dangling)
#   - docker builder prune (build cache)
#   - Opcional: docker image prune -a (todas las no usadas, requiere confirmación)
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Limpieza de imágenes Docker"

check_docker

log "Limpiando imágenes dangling (sin tag)..."
docker image prune -f

echo
log "Limpiando build cache..."
docker builder prune -f

echo
warn "¿Eliminar TODAS las imágenes no usadas por contenedores activos? (s/N)"
read -r CONFIRM
if [[ "${CONFIRM}" == "s" ]] || [[ "${CONFIRM}" == "S" ]]; then
    log "Eliminando imágenes no usadas..."
    docker image prune -a -f
else
    log "Omitiendo eliminación profunda."
fi

echo
log "Estadísticas de espacio Docker:"
docker system df

echo
log "✅ Limpieza completada."
