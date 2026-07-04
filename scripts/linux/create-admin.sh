#!/usr/bin/env bash
# =============================================================================
# create-admin.sh - Crea un usuario administrador en Matrix Synapse
# -----------------------------------------------------------------------------
# Uso:
#   ./scripts/linux/create-admin.sh <username>
#   ./scripts/linux/create-admin.sh admin
#
# Te pedirá la contraseña de forma interactiva (no se muestra en pantalla).
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Creación de usuario administrador"

check_docker
require_stack_running

if [[ $# -lt 1 ]]; then
    fatal "Uso: $0 <username> [displayname]"
fi

USERNAME="$1"
DISPLAYNAME="${2:-${USERNAME}}"

log "Creando usuario admin: @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"

# Usar register_new_matrix_user con --admin
# El comando pregunta la contraseña de forma interactiva
dc exec -it synapse \
    register_new_matrix_user \
    --user "${USERNAME}" \
    --admin \
    --yes \
    "http://localhost:8008"

echo
log "✅ Usuario administrador creado: @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"
echo
log "Ahora puedes iniciar sesión en Element con:"
log "   Servidor: ${SYNAPSE_PUBLIC_URL:-https://matrix.home.arpa}"
log "   Usuario:  @${USERNAME}:${SYNAPSE_SERVER_NAME:-home.arpa}"
log "   Contraseña: la que acabas de definir"
