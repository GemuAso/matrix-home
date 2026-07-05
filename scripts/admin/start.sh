#!/usr/bin/env bash
# =============================================================================
# start.sh - Iniciar todos los servicios del stack Matrix
# =============================================================================
# Inicia todos los servicios del stack matrix-stack usando docker compose up -d
# y verifica que cada contenedor quede en estado saludable.
#
# Uso:
#   ./scripts/admin/start.sh
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
SERVICIOS=("postgres" "redis" "synapse" "element" "nginx")
TIMEOUT_ESPERA=60  # Segundos máximos de espera para salud

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║           INICIAR SERVICIOS - matrix-stack                          ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

esperar_saludable() {
    local contenedor="$1"
    local servicio="$2"
    local tiempo_maximo="$3"
    local transcurrido=0
    local intervalo=3

    echo -ne "  Esperando que ${servicio} esté saludable"

    while [[ ${transcurrido} -lt ${tiempo_maximo} ]]; do
        local estado salud
        estado=$(docker inspect --format '{{.State.Status}}' "${contenedor}" 2>/dev/null || echo "detenido")

        if [[ "${estado}" != "running" ]]; then
            echo -e "\r  ${COLOR_ROJO}✘ ${servicio} se detuvo inesperadamente.${COLOR_RESET}               "
            return 1
        fi

        salud=$(docker inspect --format '{{.State.Health.Status}}' "${contenedor}" 2>/dev/null || echo "")

        if [[ -z "${salud}" ]]; then
            # Sin healthcheck definido, si está ejecutando es suficiente
            echo -e "\r  ${COLOR_VERDE}✔ ${servicio} está ejecutándose (sin healthcheck).${COLOR_RESET}        "
            return 0
        fi

        if [[ "${salud}" == "healthy" ]]; then
            echo -e "\r  ${COLOR_VERDE}✔ ${servicio} está saludable.${COLOR_RESET}                          "
            return 0
        fi

        echo -ne "\r  Esperando que ${servicio} esté saludable [${transcurrido}s/${tiempo_maximo}s]"
        sleep "${intervalo}"
        transcurrido=$((transcurrido + intervalo))
    done

    echo -e "\r  ${COLOR_AMARILLO}⚠ ${servicio} no alcanzó estado saludable en ${tiempo_maximo}s.${COLOR_RESET}"
    return 1
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: El daemon de Docker no está en ejecución.${COLOR_RESET}"
    exit 1
fi

# --- Verificar que docker-compose.yml existe ---
if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo -e "${COLOR_ROJO}ERROR: No se encontró docker-compose.yml en ${PROJECT_ROOT}${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
imprimir_encabezado

echo -e "  ${COLOR_NEGRITA}Iniciando stack ${STACK_NAME}...${COLOR_RESET}"
echo ""

# Iniciar todos los servicios
if ! docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" up -d; then
    echo ""
    echo -e "  ${COLOR_ROJO}✘ Error al iniciar los servicios con docker compose.${COLOR_RESET}"
    exit 1
fi

echo ""
echo -e "  ${COLOR_NEGRITA}Servicios iniciados. Verificando estado de salud...${COLOR_RESET}"
echo ""

# Verificar cada servicio
errores=0

for servicio in "${SERVICIOS[@]}"; do
    contenedor="matrix-${servicio}"
    if ! esperar_saludable "${contenedor}" "${servicio}" "${TIMEOUT_ESPERA}"; then
        errores=$((errores + 1))
    fi
done

echo ""

# --- Resumen ---
if [[ ${errores} -eq 0 ]]; then
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Todos los servicios se iniciaron correctamente.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Ejecute ./scripts/admin/healthcheck.sh para verificaciones detalladas.${COLOR_RESET}"
else
    echo -e "  ${COLOR_AMARILLO}⚠ ${errores} servicio(s) no alcanzaron estado saludable.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Revise los logs con: ./scripts/admin/logs.sh <servicio>${COLOR_RESET}"
fi

echo ""
exit 0