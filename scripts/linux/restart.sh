#!/usr/bin/env bash
# =============================================================================
# restart.sh - Reinicia el stack completo o un servicio específico
# -----------------------------------------------------------------------------
# Uso:
#   ./scripts/linux/restart.sh           # Reinicia todo
#   ./scripts/linux/restart.sh synapse   # Reinicia solo synapse
#   ./scripts/linux/restart.sh nginx synapse  # Reinicia varios
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Reiniciando Matrix Docker Stack"

check_docker

if [[ $# -eq 0 ]]; then
    log "Reiniciando todos los servicios..."
    dc restart
    echo
    log "Esperando healthchecks..."
    wait_for_health postgres 60
    wait_for_health redis 30
    wait_for_health synapse 120
    wait_for_health element 30
    wait_for_health nginx 30
else
    for svc in "$@"; do
        log "Reiniciando ${svc}..."
        dc restart "${svc}"
        wait_for_health "${svc}" 120
    done
fi

echo
header "Estado final"
dc ps
echo
log "✅ Reinicio completado."
