#!/usr/bin/env bash
# =============================================================================
# _common.sh - Funciones y variables compartidas por todos los scripts
# -----------------------------------------------------------------------------
# Este archivo NO se ejecuta directamente. Se incluye con `source` desde otros
# scripts de la carpeta scripts/linux/.
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Detectar la raíz del proyecto (3 niveles arriba de este archivo)
# scripts/linux/_common.sh -> ../.. = raíz del proyecto
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# -----------------------------------------------------------------------------
# Colores para output
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# -----------------------------------------------------------------------------
# Cargar .env si existe
# -----------------------------------------------------------------------------
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
else
    echo -e "${YELLOW}[WARN] No se encontró .env en ${ENV_FILE}${NC}"
    echo -e "${YELLOW}       Copia .env.example a .env y ajusta los valores.${NC}"
fi

# -----------------------------------------------------------------------------
# Funciones de logging
# -----------------------------------------------------------------------------
log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')] [INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [WARN]${NC}  $*" >&2; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" >&2; }
fatal()   { echo -e "${RED}[$(date '+%H:%M:%S')] [FATAL]${NC} $*" >&2; exit 1; }
debug()   { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${CYAN}[$(date '+%H:%M:%S')] [DEBUG]${NC} $*" >&2 || true; }
header()  { echo; echo -e "${BLUE}${BOLD}=== $* ===${NC}"; }

# -----------------------------------------------------------------------------
# Verificar que un comando está disponible
# -----------------------------------------------------------------------------
require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        fatal "Comando requerido no encontrado: ${cmd}"
    fi
}

# -----------------------------------------------------------------------------
# Verificar que Docker y Docker Compose están disponibles
# -----------------------------------------------------------------------------
check_docker() {
    require_cmd docker
    if ! docker compose version >/dev/null 2>&1; then
        if command -v docker-compose >/dev/null 2>&1; then
            warn "Se detectó docker-compose v1. Se recomienda docker compose v2."
            warn "Alias: alias docker-compose='docker compose'"
        else
            fatal "Docker Compose no está instalado. Instala 'docker compose plugin'."
        fi
    fi
}

# -----------------------------------------------------------------------------
# Ejecutar docker compose con cd al proyecto
# -----------------------------------------------------------------------------
dc() {
    (cd "${PROJECT_ROOT}" && docker compose "$@")
}

# -----------------------------------------------------------------------------
# Verificar que el stack esté corriendo
# -----------------------------------------------------------------------------
stack_running() {
    dc ps --services --filter "status=running" 2>/dev/null | grep -q .
}

require_stack_running() {
    if ! stack_running; then
        fatal "El stack no está corriendo. Ejecuta: scripts/linux/start.sh"
    fi
}

# -----------------------------------------------------------------------------
# Validar que .env tenga valores reales (no ejemplos)
# -----------------------------------------------------------------------------
validate_env() {
    local problems=0
    if [[ "${POSTGRES_PASSWORD:-}" == *"ChangeMe"* ]] || [[ "${POSTGRES_PASSWORD:-}" == *"CambiaEsta"* ]]; then
        warn "POSTGRES_PASSWORD parece ser valor de ejemplo. Cámbialo en .env"
        problems=$((problems+1))
    fi
    if [[ "${REDIS_PASSWORD:-}" == *"cambiar_por"* ]]; then
        warn "REDIS_PASSWORD parece ser valor de ejemplo. Cámbialo en .env"
        problems=$((problems+1))
    fi
    if [[ "${SYNAPSE_REGISTRATION_SHARED_SECRET:-}" == *"cambiar_por"* ]]; then
        warn "SYNAPSE_REGISTRATION_SHARED_SECRET parece ser valor de ejemplo."
        problems=$((problems+1))
    fi
    if [[ $problems -gt 0 ]]; then
        warn "Se encontraron $problems variables con valores de ejemplo."
        warn "El stack puede funcionar pero NO es seguro para producción."
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Esperar a que un servicio esté saludable
# -----------------------------------------------------------------------------
wait_for_health() {
    local service="$1"
    local timeout="${2:-120}"
    local elapsed=0
    log "Esperando a que ${service} esté saludable (timeout: ${timeout}s)..."
    while ! dc ps "${service}" 2>/dev/null | grep -q "healthy"; do
        sleep 5
        elapsed=$((elapsed+5))
        if [[ $elapsed -ge $timeout ]]; then
            error "Timeout esperando a ${service}"
            return 1
        fi
        printf "."
    done
    echo
    log "${service} está saludable."
}

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
banner() {
    cat <<'EOF'

  __  __ _       _     _              ____
 |  \/  (_) __ _| | __| |   _ __ ___ |___ \
 | |\/| | |/ _` | |/ _` |  | '_ ` _ \  __) |
 | |  | | | (_| | | (_| |  | | | | | |/ __/
 |_|  |_|_|\__,_|_|\__,_|  |_| |_| |_|_____)

EOF
    echo -e "${CYAN}Matrix Synapse Docker Stack - LAN${NC}"
    echo -e "${CYAN}Versión: 1.0.0${NC}"
    echo
}
