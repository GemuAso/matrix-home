#!/usr/bin/env bash
# =============================================================================
# setup.sh - Setup inicial del proyecto Matrix Docker
# -----------------------------------------------------------------------------
# Realiza:
#   1. Verifica dependencias (Docker, openssl)
#   2. Verifica/Crea .env desde .env.example
#   3. Genera signing key de Synapse (si no existe)
#   4. Genera certificados SSL auto-firmados
#   5. Valida consistencia de secretos
#   6. Construye imagen personalizada de Element
#   7. Verifica docker-compose.yml
#
# Uso:  ./scripts/linux/setup.sh
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

banner
header "Setup inicial Matrix Docker Stack"

# -----------------------------------------------------------------------------
# 1. Dependencias
# -----------------------------------------------------------------------------
log "1/7 - Verificando dependencias..."
require_cmd docker
require_cmd openssl
check_docker
log "   ✓ Docker disponible"
log "   ✓ openssl disponible"

# -----------------------------------------------------------------------------
# 2. .env
# -----------------------------------------------------------------------------
log "2/7 - Verificando .env..."
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        warn "   .env creado desde .env.example"
        warn "   EDITA ${PROJECT_ROOT}/.env y cambia los valores antes de continuar."
        warn "   Presiona ENTER cuando hayas terminado, o Ctrl+C para abortar."
        read -r
    else
        fatal "No existe .env ni .env.example"
    fi
else
    log "   ✓ .env existe"
fi

# Recargar variables
set -a
# shellcheck disable=SC1090
source "${PROJECT_ROOT}/.env"
set +a

# -----------------------------------------------------------------------------
# 3. Signing key
# -----------------------------------------------------------------------------
log "3/7 - Verificando signing key de Synapse..."
SIGNING_KEY="${PROJECT_ROOT}/synapse/signing.key"
if [[ ! -f "${SIGNING_KEY}" ]] || [[ ! -s "${SIGNING_KEY}" ]]; then
    log "   Generando nueva signing key..."
    KEY_ID="$(openssl rand -hex 2)"
    SEED="$(openssl rand -hex 32)"
    B64_SEED="$(echo -n "${SEED}" | xxd -r -p | base64 | tr -d '\n')"
    echo "ed25519 ${KEY_ID} ${B64_SEED}" > "${SIGNING_KEY}"
    chmod 600 "${SIGNING_KEY}"
    log "   ✓ Signing key generada: ${SIGNING_KEY}"
else
    log "   ✓ Signing key existe"
fi

# -----------------------------------------------------------------------------
# 4. Certificados SSL
# -----------------------------------------------------------------------------
log "4/7 - Generando certificados SSL..."
bash "${SCRIPT_DIR}/generate-certs.sh"
log "   ✓ Certificados listos"

# -----------------------------------------------------------------------------
# 5. Validar .env
# -----------------------------------------------------------------------------
log "5/7 - Validando secretos en .env..."
validate_env

# -----------------------------------------------------------------------------
# 6. Construir Element
# -----------------------------------------------------------------------------
log "6/7 - Construyendo imagen personalizada de Element..."
dc build element
log "   ✓ Imagen element construida"

# -----------------------------------------------------------------------------
# 7. Validar compose
# -----------------------------------------------------------------------------
log "7/7 - Validando docker-compose.yml..."
dc config --quiet
log "   ✓ docker-compose.yml válido"

echo
log "✅ Setup completo."
echo
log "Próximos pasos:"
log "  1. Edita .env con tus valores reales (contraseñas, dominios, SMTP)"
log "  2. Si cambiaste dominios, edita:"
log "     - synapse/homeserver.yaml (server_name, public_baseurl, email)"
log "     - element/config.json (m.homeserver.base_url)"
log "     - nginx/conf.d/*.conf (server_name y ssl_certificate paths)"
log "     - nginx/well-known/matrix/*.json"
log "  3. Inicia el stack: scripts/linux/start.sh"
log "  4. Crea un admin: scripts/linux/create-admin.sh admin"
