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
        fatal "Comando requerido no encontrado: ${cmd}. Instálalo antes de continuar."
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
    # Verificar que Docker daemon esté corriendo
    if ! docker info >/dev/null 2>&1; then
        fatal "Docker daemon no está corriendo. Inicia Docker antes de continuar."
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
# Variables obligatorias en .env
# -----------------------------------------------------------------------------
REQUIRED_ENV_VARS=(
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "POSTGRES_DB"
    "REDIS_PASSWORD"
    "SYNAPSE_SERVER_NAME"
    "SYNAPSE_PUBLIC_URL"
    "SYNAPSE_REGISTRATION_SHARED_SECRET"
    "SYNAPSE_MACAROON_SECRET_KEY"
    "SYNAPSE_FORM_SECRET"
    "SYNAPSE_PASSWORD_PEPPER"
    "ELEMENT_URL"
    "NGINX_MATRIX_DOMAIN"
    "NGINX_ELEMENT_DOMAIN"
)

# -----------------------------------------------------------------------------
# Validar variables obligatorias en .env
# -----------------------------------------------------------------------------
validate_required_vars() {
    local missing=0
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Variable obligatoria vacía o no definida: ${var}"
            missing=$((missing+1))
        fi
    done
    if [[ $missing -gt 0 ]]; then
        fatal "Faltan ${missing} variables obligatorias en .env. Revisa el archivo."
    fi
    log "   Todas las variables obligatorias están definidas (${#REQUIRED_ENV_VARS[@]} variables)"
}

# -----------------------------------------------------------------------------
# Validar que .env tenga valores reales (no ejemplos)
# -----------------------------------------------------------------------------
validate_env() {
    local problems=0
    if [[ "${POSTGRES_PASSWORD:-}" == *"ChangeMe"* ]] || [[ "${POSTGRES_PASSWORD:-}" == *"CambiaEsta"* ]] || [[ "${POSTGRES_PASSWORD:-}" == *"cambiar_por"* ]]; then
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
    if [[ "${SYNAPSE_MACAROON_SECRET_KEY:-}" == *"cambiar_por"* ]]; then
        warn "SYNAPSE_MACAROON_SECRET_KEY parece ser valor de ejemplo."
        problems=$((problems+1))
    fi
    if [[ "${SYNAPSE_FORM_SECRET:-}" == *"cambiar_por"* ]]; then
        warn "SYNAPSE_FORM_SECRET parece ser valor de ejemplo."
        problems=$((problems+1))
    fi
    if [[ "${SYNAPSE_PASSWORD_PEPPER:-}" == *"cambiar_por"* ]]; then
        warn "SYNAPSE_PASSWORD_PEPPER parece ser valor de ejemplo."
        problems=$((problems+1))
    fi
    if [[ $problems -gt 0 ]]; then
        warn "Se encontraron $problems variables con valores de ejemplo."
        warn "El stack puede funcionar pero NO es seguro para producción."
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Verificar disponibilidad de puertos
# -----------------------------------------------------------------------------
check_port() {
    local port="$1"
    local description="${2:-Puerto ${port}}"

    # Verificar con ss (Linux moderno), netstat, o lsof
    local in_use=false
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            in_use=true
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            in_use=true
        fi
    fi

    if [[ "${in_use}" == "true" ]]; then
        # Excepción: ignorar si el propio stack lo está usando
        if dc ps 2>/dev/null | grep -q "matrix-nginx"; then
            debug "Puerto ${port} en uso por el propio stack. Aceptable."
        else
            error "${description} (${port}) ya está en uso por otro proceso."
            error "   Libéralo antes de continuar:"
            error "   sudo lsof -i :${port}   # para identificar el proceso"
            return 1
        fi
    else
        log "   Puerto ${port} disponible (${description})"
    fi
    return 0
}

check_all_ports() {
    local http_port="${NGINX_HTTP_PORT:-80}"
    local https_port="${NGINX_HTTPS_PORT:-443}"
    local ports_ok=true

    log "Verificando puertos requeridos..."
    check_port "${http_port}" "HTTP (Nginx)" || ports_ok=false
    check_port "${https_port}" "HTTPS (Nginx)" || ports_ok=false

    if [[ "${ports_ok}" == "false" ]]; then
        fatal "Hay puertos en uso. Libéralos o cambia NGINX_HTTP_PORT / NGINX_HTTPS_PORT en .env"
    fi
}

# -----------------------------------------------------------------------------
# Verificar permisos de carpetas críticas
# -----------------------------------------------------------------------------
check_permissions() {
    local problems=0

    # Verificar que podemos escribir en las carpetas necesarias
    local dirs=(
        "${PROJECT_ROOT}/nginx/certs"
        "${PROJECT_ROOT}/synapse"
        "${PROJECT_ROOT}/backups"
    )

    log "Verificando permisos de carpetas..."
    for dir in "${dirs[@]}"; do
        if [[ -e "${dir}" ]]; then
            if [[ ! -d "${dir}" ]]; then
                error "${dir} existe pero no es un directorio."
                problems=$((problems+1))
            elif [[ ! -w "${dir}" ]]; then
                error "Sin permisos de escritura en ${dir}"
                problems=$((problems+1))
            fi
        else
            # Crear si no existe
            mkdir -p "${dir}" 2>/dev/null || {
                error "No se pudo crear el directorio ${dir}"
                problems=$((problems+1))
            }
        fi
    done

    if [[ $problems -gt 0 ]]; then
        fatal "Problemas de permisos detectados. Corrígelos antes de continuar."
    fi
    log "   Permisos de carpetas correctos"
}

# -----------------------------------------------------------------------------
# Verificar existencia de archivos críticos generados
# -----------------------------------------------------------------------------
check_critical_files() {
    local problems=0

    log "Verificando archivos críticos..."

    # .env
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        error "Archivo .env no encontrado. Copia .env.example a .env"
        problems=$((problems+1))
    else
        log "   .env existe"
    fi

    # signing.key
    if [[ ! -f "${PROJECT_ROOT}/synapse/signing.key" ]] || [[ ! -s "${PROJECT_ROOT}/synapse/signing.key" ]]; then
        warn "   signing.key no existe o está vacío (se generará automáticamente)"
    else
        log "   signing.key existe"
    fi

    # Certificados
    local cert_files=(
        "nginx/certs/ca.crt"
        "nginx/certs/ca.key"
        "nginx/certs/matrix.crt"
        "nginx/certs/matrix.key"
        "nginx/certs/element.crt"
        "nginx/certs/element.key"
        "nginx/certs/default.crt"
        "nginx/certs/default.key"
    )

    local missing_certs=0
    for cert_rel in "${cert_files[@]}"; do
        if [[ ! -f "${PROJECT_ROOT}/${cert_rel}" ]]; then
            missing_certs=$((missing_certs+1))
        fi
    done

    if [[ $missing_certs -gt 0 ]]; then
        warn "   Faltan ${missing_certs} archivos de certificado (se generarán automáticamente)"
    else
        log "   Todos los certificados existen (${#cert_files[@]} archivos)"
    fi

    if [[ $problems -gt 0 ]]; then
        fatal "Faltan archivos críticos. Ejecuta setup.sh para generarlos."
    fi
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
 |_|  |_|_|\__,_|_|\__,_|  |_| |_| |_|_____|

EOF
    echo -e "${CYAN}Matrix Synapse Docker Stack - LAN${NC}"
    echo -e "${CYAN}Versión: 3.0.0${NC}"
    echo
}