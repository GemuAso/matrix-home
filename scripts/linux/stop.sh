#!/usr/bin/env bash
# =============================================================================
# stop.sh - Detiene el stack completo de Matrix
# -----------------------------------------------------------------------------
# Detiene los contenedores sin eliminar volúmenes ni redes.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Deteniendo Matrix Docker Stack"

check_docker

if ! stack_running; then
    warn "El stack no parece estar corriendo."
    log "Deteniendo igualmente por si hay contenedores parados..."
fi

log "Deteniendo servicios..."
dc stop

echo
log "✅ Stack detenido."
echo
log "Para iniciarlo de nuevo: scripts/linux/start.sh"
log "Para detener y eliminar contenedores: docker compose down"
log "Para eliminar también volúmenes (PELIGROSO): docker compose down -v"
