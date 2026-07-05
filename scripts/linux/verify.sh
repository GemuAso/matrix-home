#!/usr/bin/env bash
# =============================================================================
# verify.sh - Verifica el estado de todos los servicios del stack
# -----------------------------------------------------------------------------
# Uso: ./scripts/linux/verify.sh
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

banner
header "Verificación de servicios Matrix Docker Stack"

require_stack_running

SERVICES=("postgres" "redis" "synapse" "element" "nginx")
ALL_OK=true

for svc in "${SERVICES[@]}"; do
    local container="matrix-${svc}"
    local state
    state=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "missing")

    if [[ "${state}" == "healthy" ]]; then
        ok "${container} - saludable"
    elif [[ "${state}" == "unhealthy" ]]; then
        fail "${container} - UNHEALTHY"
        echo -e "${Y}  Últimos 5 logs:${NC}"
        docker logs --tail 5 "${container}" 2>&1 | sed 's/^/    /'
        ALL_OK=false
    else
        fail "${container} - no encontrado o sin healthcheck"
        ALL_OK=false
    fi
done

echo

# Verificar endpoints HTTP (si el stack está levantado)
if docker ps --filter "name=matrix-nginx" --filter "status=running" -q | grep -q .; then
    log "Verificando endpoints HTTP..."

    # Nginx healthz
    if curl -skf --max-time 5 "https://localhost/healthz" >/dev/null 2>&1; then
        ok "https://localhost/healthz"
    else
        warn "https://localhost/healthz - no responde (puede ser normal si no hay DNS local)"
    fi

    # Synapse health
    if curl -sf --max-time 5 "http://localhost:8008/health" >/dev/null 2>&1; then
        ok "Synapse /health (interno)"
    fi
fi

echo
if [[ "${ALL_OK}" == "true" ]]; then
    log "Todos los servicios están saludables."
else
    warn "Algunos servicios necesitan atención."
    warn "Diagnóstico: cd ${PROJECT_ROOT} && docker compose ps"
    warn "Logs:        cd ${PROJECT_ROOT} && docker compose logs"
fi