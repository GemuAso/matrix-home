#!/usr/bin/env bash
# =============================================================================
# status.sh - Estado de todos los servicios del stack Matrix
# =============================================================================
# Muestra el estado (ejecutando/detenido/saludable/no saludable), tiempo de
# actividad y uso de memoria/CPU de cada servicio del stack matrix-stack.
#
# Uso:
#   ./scripts/admin/status.sh
#
# Servicios monitoreados: postgres, redis, synapse, element, nginx
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
    COLOR_AZUL='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_GRIS='\033[0;90m'
    COLOR_NEGRITA='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_ROJO=''
    COLOR_VERDE=''
    COLOR_AMARILLO=''
    COLOR_AZUL=''
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
SERVICES=("matrix-postgres" "matrix-redis" "matrix-synapse" "matrix-element" "matrix-nginx")
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║        ESTADO DEL STACK MATRIX - matrix-stack                      ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Fecha: ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo -e "  Proyecto: ${COLOR_NEGRITA}${PROJECT_ROOT}${COLOR_RESET}"
    echo ""
}

obtener_estado_contenedor() {
    local contenedor="$1"
    local estado

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${contenedor}$"; then
        echo "inexistente"
        return
    fi

    estado=$(docker inspect --format '{{.State.Status}}' "${contenedor}" 2>/dev/null || echo "desconocido")

    if [[ "${estado}" == "running" ]]; then
        # Verificar salud si el contenedor tiene healthcheck
        salud=$(docker inspect --format '{{.State.Health.Status}}' "${contenedor}" 2>/dev/null || echo "")
        if [[ -n "${salud}" ]]; then
            case "${salud}" in
                healthy)   echo "saludable" ;;
                unhealthy) echo "no_saludable" ;;
                starting)  echo "iniciando" ;;
                *)         echo "ejecutando" ;;
            esac
        else
            echo "ejecutando"
        fi
    elif [[ "${estado}" == "exited" ]]; then
        echo "detenido"
    elif [[ "${estado}" == "dead" ]]; then
        echo "muerto"
    else
        echo "${estado}"
    fi
}

obtener_color_estado() {
    local estado="$1"
    case "${estado}" in
        saludable)    echo "${COLOR_VERDE}" ;;
        ejecutando)   echo "${COLOR_VERDE}" ;;
        iniciando)    echo "${COLOR_AMARILLO}" ;;
        no_saludable) echo "${COLOR_ROJO}" ;;
        detenido)     echo "${COLOR_ROJO}" ;;
        muerto)       echo "${COLOR_ROJO}" ;;
        inexistente)  echo "${COLOR_GRIS}" ;;
        *)            echo "${COLOR_GRIS}" ;;
    esac
}

obtener_etiqueta_estado() {
    local estado="$1"
    case "${estado}" in
        saludable)    echo "✔ SALUDABLE" ;;
        ejecutando)   echo "✔ EJECUTANDO" ;;
        iniciando)    echo "⏳ INICIANDO" ;;
        no_saludable) echo "✘ NO SALUDABLE" ;;
        detenido)     echo "✘ DETENIDO" ;;
        muerto)       echo "✘ MUERTO" ;;
        inexistente)  echo "● INEXISTENTE" ;;
        *)            echo "? DESCONOCIDO" ;;
    esac
}

obtener_tiempo_actividad() {
    local contenedor="$1"
    docker inspect --format '{{.State.StartedAt}}' "${contenedor}" 2>/dev/null | \
        awk -F'.' '{print $1}' | \
        xargs -I{} date -d "{}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A"
}

calcular_uptime() {
    local contenedor="$1"
    local inicio

    inicio=$(docker inspect --format '{{.State.StartedAt}}' "${contenedor}" 2>/dev/null) || {
        echo "N/A"
        return
    }

    if [[ -z "${inicio}" ]]; then
        echo "N/A"
        return
    fi

    # Convertir timestamp de Docker a epoch
    local epoch_inicio epoch_ahora diff_seconds diff_minutos diff_horas diff_dias

    epoch_inicio=$(date -d "${inicio}" '+%s' 2>/dev/null) || {
        echo "N/A"
        return
    }
    epoch_ahora=$(date '+%s')
    diff_seconds=$(( epoch_ahora - epoch_inicio ))

    if [[ ${diff_seconds} -lt 0 ]]; then
        echo "N/A"
        return
    fi

    diff_dias=$(( diff_seconds / 86400 ))
    diff_horas=$(( (diff_seconds % 86400) / 3600 ))
    diff_minutos=$(( (diff_seconds % 3600) / 60 ))

    if [[ ${diff_dias} -gt 0 ]]; then
        echo "${diff_dias}d ${diff_horas}h ${diff_minutos}m"
    elif [[ ${diff_horas} -gt 0 ]]; then
        echo "${diff_horas}h ${diff_minutos}m"
    else
        echo "${diff_minutos}m"
    fi
}

obtener_uso_recursos() {
    local contenedor="$1"
    local stats

    stats=$(docker stats --no-stream --format '{{.MemUsage}}|{{.CPUPerc}}' "${contenedor}" 2>/dev/null) || {
        echo "N/A | N/A"
        return
    }

    local mem cpu
    mem=$(echo "${stats}" | cut -d'|' -f1)
    cpu=$(echo "${stats}" | cut -d'|' -f2)
    echo "${mem} | ${cpu}"
}

obtener_puerto() {
    local contenedor="$1"
    docker port "${contenedor}" 2>/dev/null | head -1 | awk '{print $NF}' || echo "N/A"
}

imprimir_separador() {
    echo -e "${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
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

# --- Programa principal ---
imprimir_encabezado

# Contadores
total=0
saludables=0
problemas=0

for servicio in "${SERVICES[@]}"; do
    total=$((total + 1))
    estado=$(obtener_estado_contenedor "${servicio}")
    color_estado=$(obtener_color_estado "${estado}")
    etiqueta=$(obtener_etiqueta_estado "${estado}")

    echo -e "  ${COLOR_NEGRITA}┌─ ${servicio}${COLOR_RESET}"
    echo -e "  │ Estado:      ${color_estado}${COLOR_NEGRITA}${etiqueta}${COLOR_RESET}"

    if [[ "${estado}" != "detenido" && "${estado}" != "inexistente" && "${estado}" != "muerto" ]]; then
        uptime=$(calcular_uptime "${servicio}")
        recursos=$(obtener_uso_recursos "${servicio}")
        puerto=$(obtener_puerto "${servicio}")
        imagen=$(docker inspect --format '{{.Config.Image}}' "${servicio}" 2>/dev/null || echo "N/A")

        echo -e "  │ Tiempo act.: ${COLOR_NEGRITA}${uptime}${COLOR_RESET}"
        echo -e "  │ Memoria/CPU: ${COLOR_NEGRITA}${recursos}${COLOR_RESET}"
        echo -e "  │ Puerto:      ${COLOR_NEGRITA}${puerto}${COLOR_RESET}"
        echo -e "  │ Imagen:      ${COLOR_GRIS}${imagen}${COLOR_RESET}"

        if [[ "${estado}" == "saludable" || "${estado}" == "ejecutando" ]]; then
            saludables=$((saludables + 1))
        else
            problemas=$((problemas + 1))
        fi
    else
        problemas=$((problemas + 1))
        if [[ "${estado}" == "detenido" ]]; then
            echo -e "  │ Detenido desde: $(docker inspect --format '{{.State.FinishedAt}}' "${servicio}" 2>/dev/null | awk -F'.' '{print $1}' | xargs -I{} date -d "{}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A')"
        fi
    fi

    echo -e "  ${COLOR_NEGRITA}└─────────────────────────────────────────${COLOR_RESET}"
    echo ""
done

# --- Resumen ---
imprimir_separador
echo -e ""
echo -e "  ${COLOR_NEGRITA}RESUMEN:${COLOR_RESET}"
echo -e "    Total de servicios:  ${COLOR_NEGRITA}${total}${COLOR_RESET}"
echo -e "    Saludables:          ${COLOR_VERDE}${COLOR_NEGRITA}${saludables}${COLOR_RESET}"
echo -e "    Con problemas:       ${COLOR_ROJO}${COLOR_NEGRITA}${problemas}${COLOR_RESET}"

if [[ ${problemas} -gt 0 ]]; then
    echo -e ""
    echo -e "  ${COLOR_AMARILLO}⚠ Algunos servicios tienen problemas. Ejecute ./scripts/admin/healthcheck.sh para más detalles.${COLOR_RESET}"
fi

echo -e ""
imprimir_separador
echo ""

exit 0