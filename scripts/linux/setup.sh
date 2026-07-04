#!/usr/bin/env bash
# =============================================================================
# setup.sh - Setup inicial del proyecto Matrix Docker
# -----------------------------------------------------------------------------
# Realiza:
#   1. Verifica dependencias (Docker, Docker Compose, OpenSSL)
#   2. Verifica/Crea .env desde .env.example
#   3. Validación completa antes de continuar:
#      - Variables obligatorias en .env
#      - Valores de ejemplo detectados
#      - Puertos disponibles (80, 443)
#      - Permisos de carpetas
#   4. Genera signing key de Synapse (si no existe)
#   5. Genera certificados SSL auto-firmados (si no existen)
#   6. Construye imagen personalizada de Element
#   7. Verifica docker-compose.yml
#   8. Validación final pre-arranque
#
# Uso:  ./scripts/linux/setup.sh
#
# IMPORTANTE: Tras ejecutar este script, el proyecto está listo para:
#   docker compose up -d
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

banner
header "Setup inicial Matrix Docker Stack v3.0.0"

# =============================================================================
# 1. Dependencias
# =============================================================================
log "1/8 - Verificando dependencias..."
require_cmd docker
require_cmd openssl
check_docker
log "   Docker y Docker Compose disponibles"
log "   openssl disponible"

# =============================================================================
# 2. .env
# =============================================================================
log "2/8 - Verificando .env..."
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
        cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
        warn "   .env creado desde .env.example"
        warn "   ============================================"
        warn "   EDITA ${PROJECT_ROOT}/.env y cambia los valores antes de continuar."
        warn "   Debes cambiar AL MENOS las contraseñas y secretos."
        warn "   ============================================"
        warn "   Presiona ENTER cuando hayas terminado, o Ctrl+C para abortar."
        read -r
        # Recargar variables
        set -a
        # shellcheck disable=SC1090
        source "${PROJECT_ROOT}/.env"
        set +a
    else
        fatal "No existe .env ni .env.example. No se puede continuar."
    fi
else
    log "   .env existe"
    # Recargar para asegurar que tenemos las últimas variables
    set -a
    # shellcheck disable=SC1090
    source "${PROJECT_ROOT}/.env"
    set +a
fi

# =============================================================================
# 3. Validar variables obligatorias
# =============================================================================
log "3/8 - Validando variables obligatorias en .env..."
validate_required_vars

# =============================================================================
# 4. Validar que no sean valores de ejemplo
# =============================================================================
log "4/8 - Detectando valores de ejemplo..."
validate_env

# =============================================================================
# 5. Verificar permisos de carpetas
# =============================================================================
log "5/8 - Verificando permisos..."
check_permissions

# =============================================================================
# 6. Verificar puertos disponibles
# =============================================================================
log "6/8 - Verificando puertos..."
check_all_ports

# =============================================================================
# 7. Generar archivos faltantes
# =============================================================================

# 7a. Signing key
log "7/8 - Verificando/Gerando archivos críticos..."
log "   Signing key de Synapse..."
SIGNING_KEY="${PROJECT_ROOT}/synapse/signing.key"
if [[ ! -f "${SIGNING_KEY}" ]] || [[ ! -s "${SIGNING_KEY}" ]]; then
    log "   Generando nueva signing key..."

    # Intentar método oficial de Synapse (docker run generate_signing_key)
    SYNAPSE_IMAGE="matrixdotorg/synapse:v1.118.0"
    if docker image inspect "${SYNAPSE_IMAGE}" >/dev/null 2>&1; then
        log "   Usando método oficial de Synapse (generate_signing_key)..."
        docker run --rm \
            -v "${PROJECT_ROOT}/synapse":/signing \
            "${SYNAPSE_IMAGE}" \
            generate_signing_key -O /signing 2>/dev/null && \
            mv -f "${PROJECT_ROOT}/synapse/signing.key" "${SIGNING_KEY}" 2>/dev/null || true
    fi

    # Si el método oficial falló o no hay imagen, generar manualmente
    if [[ ! -f "${SIGNING_KEY}" ]] || [[ ! -s "${SIGNING_KEY}" ]]; then
        log "   Usando generación manual (fallback)..."
        KEY_ID="$(openssl rand -hex 2)"
        SEED="$(openssl rand -hex 32)"
        B64_SEED="$(echo -n "${SEED}" | xxd -r -p | base64 | tr -d '\n')"
        echo "ed25519 ${KEY_ID} ${B64_SEED}" > "${SIGNING_KEY}"
    fi

    chmod 600 "${SIGNING_KEY}"
    log "   Signing key generada: ${SIGNING_KEY}"
else
    log "   Signing key ya existe"
fi

# 7b. Certificados SSL
log "   Certificados SSL..."
bash "${SCRIPT_DIR}/generate-certs.sh"

# =============================================================================
# 8. Validación final y build
# =============================================================================
log "8/8 - Validación final..."

# Verificar que los archivos críticos existen ahora
if [[ ! -f "${PROJECT_ROOT}/synapse/signing.key" ]] || [[ ! -s "${PROJECT_ROOT}/synapse/signing.key" ]]; then
    fatal "signing.key no se generó correctamente. Revisa los logs arriba."
fi

CERT_FILES_OK=true
for cert_file in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
    if [[ ! -f "${PROJECT_ROOT}/nginx/certs/${cert_file}" ]]; then
        error "Falta certificado: nginx/certs/${cert_file}"
        CERT_FILES_OK=false
    fi
done

if [[ "${CERT_FILES_OK}" == "false" ]]; then
    fatal "Algunos certificados no se generaron correctamente. Revisa los logs arriba."
fi
log "   Todos los archivos críticos verificados"

# Construir Element
log "   Construyendo imagen personalizada de Element..."
dc build element
log "   Imagen element construida"

# Validar compose
log "   Validando docker-compose.yml..."
dc config --quiet
log "   docker-compose.yml válido"

echo
log "✅ Setup completo. Todos los archivos críticos han sido generados/validados."
echo
log "El proyecto está listo para iniciar con:"
echo
log "  docker compose up -d"
echo
log "O usando el script de inicio:"
echo
log "  bash scripts/linux/start.sh"
echo
log "Después de iniciar, crea el primer administrador:"
echo
log "  bash scripts/linux/create-admin.sh admin"
echo