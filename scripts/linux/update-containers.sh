#!/usr/bin/env bash
# =============================================================================
# update-containers.sh - Recrea contenedores con las imágenes actualizadas
# -----------------------------------------------------------------------------
# Ejecuta `docker compose up -d` para recrear contenedores con nuevas imágenes.
# Requiere haber ejecutado update-images.sh previamente.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Actualizando contenedores"

check_docker

log "Verificando nuevas imágenes..."
dc pull --ignore-pull-failures

log "Recreando contenedores (si la imagen cambió)..."
dc up -d

echo
log "Esperando healthchecks..."
wait_for_health postgres 60
wait_for_health redis 30
wait_for_health synapse 120
wait_for_health element 30
wait_for_health nginx 30

echo
header "Estado final"
dc ps

echo
log "✅ Contenedores actualizados."
log "Verifica los logs si hay problemas: scripts/linux/logs.sh"
