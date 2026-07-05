#!/usr/bin/env bash
# =============================================================================
# setup.sh - Setup de archivos generados para el proyecto Matrix Docker
# -----------------------------------------------------------------------------
# Este script genera los archivos que Git no contiene (claves, certificados)
# y valida la configuración. Para una instalación completa desde cero,
# ejecuta ./install.sh en su lugar.
#
# Uso:  ./scripts/linux/setup.sh
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

banner
header "Setup de archivos generados v4.0.0"

# 1. Dependencias
log "1/6 - Verificando dependencias..."
require_cmd docker
require_cmd openssl
check_docker
ok "Docker, Docker Compose y OpenSSL disponibles"

# 2. .env
log "2/6 - Verificando .env..."
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    error "No se encontró .env."
    error "Ejecuta ./install.sh para generar la configuración automáticamente,"
    error "o copia .env.example y rellena los valores manualmente:"
    error "  cp .env.example .env && nano .env"
    fatal "No se puede continuar sin .env."
fi
ok ".env existe"
set -a; source "${PROJECT_ROOT}/.env"; set +a

# 3. Validaciones
log "3/6 - Validando configuración..."
validate_required_vars
validate_env
check_permissions
check_all_ports
ok "Validaciones pasadas"

# 4. Signing key
log "4/6 - Verificando signing key..."
SIGNING_KEY="${PROJECT_ROOT}/synapse/signing.key"
if [[ -f "${SIGNING_KEY}" && -s "${SIGNING_KEY}" ]]; then
    ok "Signing key ya existe"
else
    log "Generando signing key..."
    mkdir -p "${PROJECT_ROOT}/synapse"
    SYNAPSE_IMAGE="matrixdotorg/synapse:v1.118.0"
    if docker image inspect "${SYNAPSE_IMAGE}" >/dev/null 2>&1; then
        docker run --rm -v "${PROJECT_ROOT}/synapse":/signing \
            "${SYNAPSE_IMAGE}" generate_signing_key -O /signing 2>/dev/null || true
    fi
    if [[ ! -f "${SIGNING_KEY}" ]] || [[ ! -s "${SIGNING_KEY}" ]]; then
        KEY_ID="$(openssl rand -hex 2)"
        SEED="$(openssl rand -hex 32)"
        B64_SEED="$(echo -n "${SEED}" | xxd -r -p | base64 | tr -d '\n')"
        echo "ed25519 ${KEY_ID} ${B64_SEED}" > "${SIGNING_KEY}"
    fi
    chmod 600 "${SIGNING_KEY}"
    ok "Signing key generada"
fi

# 5. Certificados
log "5/6 - Verificando certificados..."
bash "${SCRIPT_DIR}/generate-certs.sh"
ok "Certificados listos"

# 6. Build y validación
log "6/6 - Build y validación final..."
dc build element 2>&1 | tail -1
dc config --quiet
ok "docker-compose.yml válido"
ok "Imagen element construida"

echo
log "Setup completo. Para iniciar el stack:"
echo
log "  docker compose up -d"
echo
log "O ejecuta ./install.sh para una instalación completa automática."
echo