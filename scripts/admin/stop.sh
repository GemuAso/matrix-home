#!/usr/bin/env bash
# =============================================================================
# stop.sh - Detener todos los servicios del stack Matrix
# =============================================================================
# Detiene todos los servicios del stack matrix-stack de forma graceful.
# Muestra un aviso de confirmación antes de proceder.
#
# Uso:
#   ./scripts/admin/stop.sh
#   ./scripts/admin/stop.sh --yes    # Saltar confirmación
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
TIMEOUT_DETENCION=30  # Segundos para cierre graceful

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║            DETENER SERVICIOS - matrix-stack                          ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

confirmar() {
    local mensaje="$1"
    if [[ "${SALTAR_CONFIRMACION}" == "true" ]]; then
        return 0
    fi

    echo -ne "  ${COLOR_AMARILLO}${mensaje} [s/N]: ${COLOR_RESET}"
    local respuesta
    read -r respuesta
    case "${respuesta}" in
        s|S|sí|Sí|SÍ|si|Si|SI) return 0 ;;
        *) return 1 ;;
    esac
}

mostrar_servicios_activos() {
    local activos
    activos=$(docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" ps --services --filter "status=running" 2>/dev/null || echo "")

    if [[ -z "${activos}" ]]; then
        echo -e "  ${COLOR_GRIS}No hay servicios en ejecución.${COLOR_RESET}"
        return 1
    fi

    echo -e "  ${COLOR_NEGRITA}Servicios actualmente en ejecución:${COLOR_RESET}"
    echo ""
    while IFS= read -r linea; do
        if [[ -n "${linea}" ]]; then
            echo -e "    ${COLOR_VERDE}●${COLOR_RESET} ${linea}"
        fi
    done <<< "${activos}"
    echo ""
    return 0
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Verificar flag de salto de confirmación ---
SALTAR_CONFIRMACION="false"
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
    SALTAR_CONFIRMACION="true"
fi

# --- Programa principal ---
imprimir_encabezado

# Mostrar servicios activos
if ! mostrar_servicios_activos; then
    echo -e "  ${COLOR_GRIS}No hay nada que detener.${COLOR_RESET}"
    exit 0
fi

# Confirmación
echo -e "  ${COLOR_ROJO}${COLOR_NEGRITA}⚠ ATENCIÓN:${COLOR_RESET} Esto detendrá todos los servicios del stack Matrix."
echo -e "  Los usuarios no podrán acceder a la plataforma durante la detención."
echo ""

if ! confirmar "¿Desea continuar con la detención?"; then
    echo -e "  ${COLOR_GRIS}Operación cancelada por el usuario.${COLOR_RESET}"
    exit 0
fi

echo ""
echo -e "  ${COLOR_NEGRITA}Deteniendo servicios con timeout de ${TIMEOUT_DETENCION}s...${COLOR_RESET}"
echo ""

# Detener con timeout graceful
if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" stop -t "${TIMEOUT_DETENCION}"; then
    echo ""
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Todos los servicios se detuvieron correctamente.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Los contenedores siguen existiendo. Para eliminarlos use ./scripts/admin/uninstall.sh${COLOR_RESET}"
else
    echo ""
    echo -e "  ${COLOR_ROJO}✘ Ocurrieron errores durante la detención.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Revise los logs con: ./scripts/admin/logs.sh${COLOR_RESET}"
    exit 1
fi

echo ""
exit 0