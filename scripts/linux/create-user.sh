#!/usr/bin/env bash
# =============================================================================
# create-user.sh - Crea un usuario normal (no admin) en Matrix Synapse
# -----------------------------------------------------------------------------
# Uso:
#   ./scripts/linux/create-user.sh <username>
#   ./scripts/linux/create-user.sh juan.perez
#
# Te pedirá la contraseña de forma interactiva.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Creación de usuario"

check_docker
require_stack_running

if [[ $# -lt 1 ]]; then
    fatal "Uso: $0 <username>"
fi

USERNAME="$1"

log "Creando usuario: @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"

dc exec -it synapse \
    register_new_matrix_user \
    --user "${USERNAME}" \
    --no-admin \
    --yes \
    "http://localhost:8008"

echo
log "✅ Usuario creado: @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"
echo
log "El usuario puede iniciar sesión en Element:"
log "   URL: https://${NGINX_ELEMENT_DOMAIN:-element.home.arpa}"
log "   Usuario: @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"
