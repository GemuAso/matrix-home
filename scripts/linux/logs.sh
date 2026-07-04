#!/usr/bin/env bash
# =============================================================================
# logs.sh - Ver logs de los servicios
# -----------------------------------------------------------------------------
# Uso:
#   ./scripts/linux/logs.sh                       # Todos los servicios (last 100)
#   ./scripts/linux/logs.sh synapse               # Solo synapse (follow)
#   ./scripts/linux/logs.sh nginx --tail 200      # Últimas 200 líneas
#   ./scripts/linux/logs.sh synapse --since 1h    # Última hora
#   ./scripts/linux/logs.sh synapse --since 30m --follow
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Logs de Matrix Docker Stack"

check_docker

SERVICES=("postgres" "redis" "synapse" "element" "nginx")

if [[ $# -eq 0 ]]; then
    # Sin argumentos: mostrar últimos logs de todos
    log "Últimos logs de todos los servicios:"
    echo
    for svc in "${SERVICES[@]}"; do
        echo -e "${BLUE}--- ${svc} ---${NC}"
        dc logs --tail 20 "${svc}" 2>&1 || true
        echo
    done
    exit 0
fi

# Mostrar logs de servicio(s) específico(s)
log "Mostrando logs de: $*"
echo

# Pasar todos los argumentos directamente a docker compose logs
dc logs "$@"
