#!/usr/bin/env bash
# =============================================================================
# start.sh - Inicia el stack completo de Matrix
# -----------------------------------------------------------------------------
# Ejecuta `docker compose up -d` con todas las verificaciones previas.
# Si los certificados no existen, ejecuta generate-certs automáticamente.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Iniciando Matrix Docker Stack"

check_docker

# Verificar .env
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    fatal "No existe .env. Ejecuta primero: scripts/linux/setup.sh"
fi

# Verificar signing key
if [[ ! -f "${PROJECT_ROOT}/synapse/signing.key" ]]; then
    warn "Signing key no encontrada. Ejecutando setup parcial..."
    KEY_ID="$(openssl rand -hex 2)"
    SEED="$(openssl rand -hex 32)"
    B64_SEED="$(echo -n "${SEED}" | xxd -r -p | base64 | tr -d '\n')"
    echo "ed25519 ${KEY_ID} ${B64_SEED}" > "${PROJECT_ROOT}/synapse/signing.key"
    chmod 600 "${PROJECT_ROOT}/synapse/signing.key"
    log "Signing key generada automáticamente."
fi

# Verificar certificados
CERTS_DIR="${PROJECT_ROOT}/nginx/certs"
if [[ ! -f "${CERTS_DIR}/matrix.crt" ]] || [[ ! -f "${CERTS_DIR}/element.crt" ]]; then
    warn "Certificados no encontrados. Generando..."
    bash "${SCRIPT_DIR}/generate-certs.sh"
fi

# Verificar que element esté construido
if ! docker image inspect matrix-element:custom >/dev/null 2>&1; then
    log "Construyendo imagen de Element..."
    dc build element
fi

log "Iniciando servicios..."
dc up -d

echo
log "Servicios iniciados. Esperando healthchecks..."

# Esperar a que los servicios estén saludables
wait_for_health postgres 60
wait_for_health redis 30
wait_for_health synapse 120
wait_for_health element 30
wait_for_health nginx 30

echo
header "Estado final"
dc ps

echo
log "✅ Stack iniciado correctamente."
echo
log "URLs de acceso:"
log "  Element:  https://${NGINX_ELEMENT_DOMAIN:-element.home.arpa}"
log "  Matrix:   https://${NGINX_MATRIX_DOMAIN:-matrix.home.arpa}"
echo
log "Para crear el primer administrador:"
log "  scripts/linux/create-admin.sh <username>"
