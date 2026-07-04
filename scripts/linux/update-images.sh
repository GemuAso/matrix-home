#!/usr/bin/env bash
# =============================================================================
# update-images.sh - Descarga las últimas versiones de las imágenes
# -----------------------------------------------------------------------------
# Hace `docker compose pull` para todas las imágenes del stack.
# NO reinicia los contenedores - para eso usar update-containers.sh
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Actualizando imágenes Docker"

check_docker

log "Descargando últimas versiones de imágenes..."
dc pull

echo
log "Reconstruyendo imagen de Element (si hay cambios)..."
dc build --pull element

echo
log "✅ Imágenes actualizadas."
echo
warn "Las imágenes se descargaron pero los contenedores NO se reiniciaron."
log "Para aplicar los cambios: scripts/linux/update-containers.sh"
