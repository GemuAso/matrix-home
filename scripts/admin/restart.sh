#!/usr/bin/env bash
# =============================================================================
# restart.sh - Reiniciar servicios del stack Matrix
# =============================================================================
# Reinicia un servicio individual o todos los servicios del stack matrix-stack.
#
# Uso:
#   ./scripts/admin/restart.sh [servicio]
#   ./scripts/admin/restart.sh              # Muestra menú interactivo
#   ./scripts/admin/restart.sh postgres     # Reinicia solo PostgreSQL
#   ./scripts/admin/restart.sh all          # Reinicia todos los servicios
#
# Servicios válidos: postgres, redis, synapse, element, nginx, all
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

# Mapa de nombres de usuario a nombres de contenedor/servicio de compose
declare -A NOMBRES_SERVICIOS=(
    ["postgres"]="postgres"
    ["redis"]="redis"
    ["synapse"]="synapse"
    ["element"]="element"
    ["nginx"]="nginx"
)

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║          REINICIAR SERVICIOS - matrix-stack                        ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

mostrar_menu() {
    echo -e "  ${COLOR_NEGRITA}Seleccione el servicio a reiniciar:${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_NEGRITA}1)${COLOR_RESET} PostgreSQL  (matrix-postgres)"
    echo -e "    ${COLOR_NEGRITA}2)${COLOR_RESET} Redis       (matrix-redis)"
    echo -e "    ${COLOR_NEGRITA}3)${COLOR_RESET} Synapse     (matrix-synapse)"
    echo -e "    ${COLOR_NEGRITA}4)${COLOR_RESET} Element     (matrix-element)"
    echo -e "    ${COLOR_NEGRITA}5)${COLOR_RESET} Nginx       (matrix-nginx)"
    echo -e "    ${COLOR_AMARILLO}    6)${COLOR_RESET} Todos los servicios"
    echo -e "    ${COLOR_GRIS}    0)${COLOR_RESET} Cancelar"
    echo ""
    echo -ne "  ${COLOR_NEGRITA}Opción [0-6]: ${COLOR_RESET}"
}

leer_opcion() {
    local opcion
    read -r opcion
    echo "${opcion}"
}

reiniciar_servicio() {
    local servicio="$1"
    local compose_service="$2"

    echo -e "  ${COLOR_AMARILLO}⏳ Reiniciando ${servicio}...${COLOR_RESET}"

    if ! docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" restart "${compose_service}"; then
        echo -e "  ${COLOR_ROJO}✘ Error al reiniciar ${servicio}.${COLOR_RESET}"
        return 1
    fi

    # Esperar un momento y verificar estado
    sleep 3

    local estado
    estado=$(docker inspect --format '{{.State.Status}}' "matrix-${compose_service}" 2>/dev/null || echo "desconocido")

    if [[ "${estado}" == "running" ]]; then
        echo -e "  ${COLOR_VERDE}✔ ${servicio} reiniciado correctamente (estado: ejecutando).${COLOR_RESET}"
        return 0
    else
        echo -e "  ${COLOR_AMARILLO}⚠ ${servicio} reiniciado pero estado: ${estado}.${COLOR_RESET}"
        return 0
    fi
}

reiniciar_todos() {
    echo -e "  ${COLOR_AMARILLO}⏳ Reiniciando todos los servicios...${COLOR_RESET}"
    echo ""

    # Orden de reinicio: primero bases de datos, luego aplicaciones, luego proxy
    local orden=("postgres" "redis" "synapse" "element" "nginx")
    local errores=0

    for servicio in "${orden[@]}"; do
        if ! reiniciar_servicio "matrix-${servicio}" "${servicio}"; then
            errores=$((errores + 1))
        fi
        echo ""
    done

    if [[ ${errores} -eq 0 ]]; then
        echo -e "  ${COLOR_VERDE}✔ Todos los servicios se reiniciaron correctamente.${COLOR_RESET}"
    else
        echo -e "  ${COLOR_ROJO}✘ ${errores} servicio(s) con error al reiniciar.${COLOR_RESET}"
    fi
}

validar_servicio() {
    local servicio="$1"
    if [[ -n "${NOMBRES_SERVICIOS["${servicio}"]:-}" ]]; then
        return 0
    fi
    return 1
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
imprimir_encabezado

SERVICIO_SOLICITADO="${1:-}"

if [[ -z "${SERVICIO_SOLICITADO}" ]]; then
    # Modo interactivo
    mostrar_menu
    opcion=$(leer_opcion)

    case "${opcion}" in
        1) reiniciar_servicio "PostgreSQL" "postgres" ;;
        2) reiniciar_servicio "Redis" "redis" ;;
        3) reiniciar_servicio "Synapse" "synapse" ;;
        4) reiniciar_servicio "Element" "element" ;;
        5) reiniciar_servicio "Nginx" "nginx" ;;
        6) reiniciar_todos ;;
        0)
            echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
            exit 0
            ;;
        *)
            echo -e "  ${COLOR_ROJO}Opción no válida: ${opcion}${COLOR_RESET}"
            exit 1
            ;;
    esac
elif [[ "${SERVICIO_SOLICITADO}" == "all" ]]; then
    reiniciar_todos
elif validar_servicio "${SERVICIO_SOLICITADO}"; then
    compose_name="${NOMBRES_SERVICIOS["${SERVICIO_SOLICITADO}"]}"
    reiniciar_servicio "matrix-${SERVICIO_SOLICITADO}" "${compose_name}"
else
    echo -e "  ${COLOR_ROJO}ERROR: Servicio no reconocido: '${SERVICIO_SOLICITADO}'${COLOR_RESET}"
    echo ""
    echo -e "  Servicios válidos: ${COLOR_NEGRITA}postgres, redis, synapse, element, nginx, all${COLOR_RESET}"
    echo -e "  O ejecute sin argumentos para el menú interactivo."
    exit 1
fi

echo ""
exit 0