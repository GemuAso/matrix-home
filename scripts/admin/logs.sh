#!/usr/bin/env bash
# =============================================================================
# logs.sh - Ver registros (logs) de los servicios del stack Matrix
# =============================================================================
# Muestra los logs de uno o todos los servicios. Soporta el flag -f para
# seguimiento en tiempo real (follow) y --tail para limitar líneas.
#
# Uso:
#   ./scripts/admin/logs.sh                    # Últimos logs de todos los servicios
#   ./scripts/admin/logs.sh synapse            # Logs de Synapse
#   ./scripts/admin/logs.sh -f                 # Seguir todos los servicios en tiempo real
#   ./scripts/admin/logs.sh -f synapse         # Seguir Synapse en tiempo real
#   ./scripts/admin/logs.sh --tail 100 synapse # Últimas 100 líneas de Synapse
# =============================================================================

set -Eeuo pipefail

# --- Detección del directorio raíz del proyecto ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- Colores (solo si hay terminal) ---
if [[ -t 1 ]]; then
    COLOR_ROJO='\033[0;31m'
    COLOR_VERDE='\033[0;32m'
    COLOR_AMARILLO='\033[1;33m'
    COLOR_CYAN='\033[0;36m'
    COLOR_GRIS='\033[0;90m'
    COLOR_NEGRITA='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_ROJO=''
    COLOR_VERDE=''
    COLOR_AMARILLO=''
    COLOR_CYAN=''
    COLOR_GRIS=''
    COLOR_NEGRITA=''
    COLOR_RESET=''
fi

# --- Carga de variables de entorno ---
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
fi

# --- Configuración ---
STACK_NAME="matrix-stack"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
DEFAULT_TAIL=100

# Mapa de nombres amigables a servicios de compose
declare -A NOMBRES_SERVICIOS=(
    ["postgres"]="postgres"
    ["redis"]="redis"
    ["synapse"]="synapse"
    ["element"]="element"
    ["nginx"]="nginx"
    ["all"]=""
)

# --- Funciones auxiliares ---

mostrar_uso() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}Uso:${COLOR_RESET}"
    echo "  $0 [opciones] [servicio]"
    echo ""
    echo -e "${COLOR_NEGRITA}Opciones:${COLOR_RESET}"
    echo "  -f, --follow      Seguir logs en tiempo real"
    echo "  --tail N          Mostrar las últimas N líneas (por defecto: ${DEFAULT_TAIL})"
    echo "  -h, --help        Mostrar esta ayuda"
    echo ""
    echo -e "${COLOR_NEGRITA}Servicios:${COLOR_RESET}"
    echo "  postgres, redis, synapse, element, nginx, all"
    echo ""
    echo -e "${COLOR_NEGRITA}Ejemplos:${COLOR_RESET}"
    echo "  $0                     # Últimos logs de todos"
    echo "  $0 synapse             # Logs de Synapse"
    echo "  $0 -f synapse          # Seguir Synapse"
    echo "  $0 -f --tail 50 nginx  # Últimas 50 líneas y seguir Nginx"
}

validar_servicio() {
    local servicio="$1"
    if [[ "${servicio}" == "all" ]] || [[ -n "${NOMBRES_SERVICIOS["${servicio}"]:-}" ]]; then
        return 0
    fi
    return 1
}

# --- Parseo de argumentos ---
FOLLOW=false
TAIL_LINES="${DEFAULT_TAIL}"
SERVICIO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        --tail)
            if [[ -z "${2:-}" ]]; then
                echo -e "${COLOR_ROJO}ERROR: --tail requiere un número.${COLOR_RESET}"
                exit 1
            fi
            TAIL_LINES="$2"
            shift 2
            ;;
        -h|--help)
            mostrar_uso
            exit 0
            ;;
        -*)
            echo -e "${COLOR_ROJO}ERROR: Opción no reconocida: $1${COLOR_RESET}"
            echo ""
            mostrar_uso
            exit 1
            ;;
        *)
            # Primer argumento no-opcion es el servicio
            if [[ -z "${SERVICIO}" ]]; then
                SERVICIO="$1"
            fi
            shift
            ;;
    esac
done

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Validar servicio si se especificó ---
if [[ -n "${SERVICIO}" ]] && ! validar_servicio "${SERVICIO}"; then
    echo -e "${COLOR_ROJO}ERROR: Servicio no reconocido: '${SERVICIO}'${COLOR_RESET}"
    echo ""
    echo -e "  Servicios válidos: ${COLOR_NEGRITA}postgres, redis, synapse, element, nginx, all${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
# Construir argumentos para docker compose logs
COMPOSE_LOGS_ARGS=("--tail" "${TAIL_LINES}")

if [[ "${FOLLOW}" == true ]]; then
    COMPOSE_LOGS_ARGS+=("--follow")
fi

if [[ -n "${SERVICIO}" && "${SERVICIO}" != "all" ]]; then
    COMPOSE_LOGS_ARGS+=("${NOMBRES_SERVICIOS["${SERVICIO}"]}")
fi

# Información de contexto
if [[ "${FOLLOW}" == false ]]; then
    if [[ -n "${SERVICIO}" && "${SERVICIO}" != "all" ]]; then
        echo -e "${COLOR_NEGRITA}Mostrando las últimas ${TAIL_LINES} líneas de ${SERVICIO}:${COLOR_RESET}"
    else
        echo -e "${COLOR_NEGRITA}Mostrando las últimas ${TAIL_LINES} líneas de todos los servicios:${COLOR_RESET}"
    fi
    echo -e "${COLOR_GRIS}Use -f para seguimiento en tiempo real.${COLOR_RESET}"
    echo -e "${COLOR_GRIS}Presione Ctrl+C para salir.${COLOR_RESET}"
    echo ""
else
    if [[ -n "${SERVICIO}" && "${SERVICIO}" != "all" ]]; then
        echo -e "${COLOR_NEGRITA}Siguiendo logs de ${SERVICIO} en tiempo real...${COLOR_RESET}"
    else
        echo -e "${COLOR_NEGRITA}Siguiendo logs de todos los servicios en tiempo real...${COLOR_RESET}"
    fi
    echo -e "${COLOR_GRIS}Presione Ctrl+C para detener.${COLOR_RESET}"
    echo ""
fi

# Ejecutar docker compose logs
# shellcheck disable=SC2086
exec docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" logs "${COMPOSE_LOGS_ARGS[@]}"