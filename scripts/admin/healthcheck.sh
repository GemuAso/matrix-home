#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh - Verificación de salud detallada de cada servicio
# =============================================================================
# Realiza comprobaciones de salud específicas para cada servicio del stack:
#   - Synapse:     curl al endpoint /_matrix/client/versions
#   - PostgreSQL:  pg_isready vía docker exec
#   - Redis:       redis-cli ping vía docker exec
#   - Element:     wget al servidor web interno
#   - Nginx:       nginx -t (configuración) y wget /healthz
#
# Muestra una tabla resumen al final.
#
# Uso:
#   ./scripts/admin/healthcheck.sh
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
SERVICIOS=("matrix-postgres" "matrix-redis" "matrix-synapse" "matrix-element" "matrix-nginx")

# Arrays para almacenar resultados
declare -A RESULTADO_ESTADO
declare -A RESULTADO_DETALLE
declare -A RESULTADO_TIEMPO

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║     VERIFICACIÓN DE SALUD - DETALLADA - matrix-stack               ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Fecha: ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo ""
}

verificar_contenedor_ejecutandose() {
    local contenedor="$1"
    local estado
    estado=$(docker inspect --format '{{.State.Status}}' "${contenedor}" 2>/dev/null || echo "")
    if [[ "${estado}" != "running" ]]; then
        return 1
    fi
    return 0
}

registrar_resultado() {
    local servicio="$1"
    local estado="$2"   # OK, ERROR, ADVERTENCIA
    local detalle="$3"
    local tiempo="$4"
    RESULTADO_ESTADO["${servicio}"]="${estado}"
    RESULTADO_DETALLE["${servicio}"]="${detalle}"
    RESULTADO_TIEMPO["${servicio}"]="${tiempo}"
}

# --- Verificaciones individuales ---

verificar_postgres() {
    local contenedor="matrix-postgres"
    local inicio tiempo_ms salida codigo

    echo -ne "  Verificando PostgreSQL ........... "

    if ! verificar_contenedor_ejecutandose "${contenedor}"; then
        echo -e "${COLOR_ROJO}CONTENEDOR DETENIDO${COLOR_RESET}"
        registrar_resultado "${contenedor}" "ERROR" "Contenedor no está en ejecución" "-"
        return
    fi

    inicio=$(date +%s%N)
    salida=$(docker exec "${contenedor}" pg_isready -U "${POSTGRES_USER:-synapse}" 2>&1) || true
    codigo=$?
    tiempo_ms=$(( ( $(date +%s%N) - inicio ) / 1000000 ))

    if [[ ${codigo} -eq 0 ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tiempo_ms}ms)"
        registrar_resultado "${contenedor}" "OK" "${salida}" "${tiempo_ms}ms"
    else
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET} (${tiempo_ms}ms)"
        registrar_resultado "${contenedor}" "ERROR" "${salida}" "${tiempo_ms}ms"
    fi
}

verificar_redis() {
    local contenedor="matrix-redis"
    local inicio tiempo_ms salida codigo

    echo -ne "  Verificando Redis ............... "

    if ! verificar_contenedor_ejecutandose "${contenedor}"; then
        echo -e "${COLOR_ROJO}CONTENEDOR DETENIDO${COLOR_RESET}"
        registrar_resultado "${contenedor}" "ERROR" "Contenedor no está en ejecución" "-"
        return
    fi

    inicio=$(date +%s%N)
    salida=$(docker exec "${contenedor}" redis-cli ping 2>&1) || true
    codigo=$?
    tiempo_ms=$(( ( $(date +%s%N) - inicio ) / 1000000 ))

    if [[ "${salida}" == *"PONG"* ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tiempo_ms}ms) - PONG"
        registrar_resultado "${contenedor}" "OK" "PONG recibido" "${tiempo_ms}ms"
    else
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET} (${tiempo_ms}ms)"
        registrar_resultado "${contenedor}" "ERROR" "${salida}" "${tiempo_ms}ms"
    fi
}

verificar_synapse() {
    local contenedor="matrix-synapse"
    local inicio tiempo_ms codigo_http respuesta

    echo -ne "  Verificando Synapse .............. "

    if ! verificar_contenedor_ejecutandose "${contenedor}"; then
        echo -e "${COLOR_ROJO}CONTENEDOR DETENIDO${COLOR_RESET}"
        registrar_resultado "${contenedor}" "ERROR" "Contenedor no está en ejecución" "-"
        return
    fi

    inicio=$(date +%s%N)
    # Usar curl dentro del contenedor para verificar el endpoint
    respuesta=$(docker exec "${contenedor}" curl -s -o /dev/null -w '%{http_code}' \
        "http://localhost:8008/_matrix/client/versions" 2>/dev/null) || respuesta="000"
    tiempo_ms=$(( ( $(date +%s%N) - inicio ) / 1000000 ))

    if [[ "${respuesta}" == "200" ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tiempo_ms}ms) - HTTP ${respuesta}"
        registrar_resultado "${contenedor}" "OK" "Endpoint /_matrix/client/versions responde 200" "${tiempo_ms}ms"
    elif [[ "${respuesta}" =~ ^[45] ]]; then
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET} (${tiempo_ms}ms) - HTTP ${respuesta}"
        registrar_resultado "${contenedor}" "ERROR" "HTTP ${respuesta} en /_matrix/client/versions" "${tiempo_ms}ms"
    else
        echo -e "${COLOR_AMARILLO}ADVERTENCIA${COLOR_RESET} (${tiempo_ms}ms) - Sin respuesta"
        registrar_resultado "${contenedor}" "ADVERTENCIA" "No se pudo conectar al endpoint" "${tiempo_ms}ms"
    fi
}

verificar_element() {
    local contenedor="matrix-element"
    local inicio tiempo_ms codigo

    echo -ne "  Verificando Element Web ......... "

    if ! verificar_contenedor_ejecutandose "${contenedor}"; then
        echo -e "${COLOR_ROJO}CONTENEDOR DETENIDO${COLOR_RESET}"
        registrar_resultado "${contenedor}" "ERROR" "Contenedor no está en ejecución" "-"
        return
    fi

    inicio=$(date +%s%N)
    # Verificar que nginx dentro del contenedor de element responde
    docker exec "${contenedor}" wget -q --spider "http://localhost:80" 2>/dev/null
    codigo=$?
    tiempo_ms=$(( ( $(date +%s%N) - inicio ) / 1000000 ))

    if [[ ${codigo} -eq 0 ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tiempo_ms}ms)"
        registrar_resultado "${contenedor}" "OK" "Servidor web responde en puerto 80" "${tiempo_ms}ms"
    else
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET} (${tiempo_ms}ms)"
        registrar_resultado "${contenedor}" "ERROR" "Servidor web no responde" "${tiempo_ms}ms"
    fi
}

verificar_nginx() {
    local contenedor="matrix-nginx"
    local inicio tiempo_ms config_salida config_codigo wget_codigo

    echo -ne "  Verificando Nginx ............... "

    if ! verificar_contenedor_ejecutandose "${contenedor}"; then
        echo -e "${COLOR_ROJO}CONTENEDOR DETENIDO${COLOR_RESET}"
        registrar_resultado "${contenedor}" "ERROR" "Contenedor no está en ejecución" "-"
        return
    fi

    # Verificar configuración de nginx
    config_salida=$(docker exec "${contenedor}" nginx -t 2>&1) || true
    config_codigo=$?

    # Verificar endpoint de salud
    inicio=$(date +%s%N)
    docker exec "${contenedor}" wget -q --spider "http://localhost:80/healthz" 2>/dev/null || \
    docker exec "${contenedor}" wget -q --spider "http://localhost:80/" 2>/dev/null || true
    wget_codigo=$?
    tiempo_ms=$(( ( $(date +%s%N) - inicio ) / 1000000 ))

    if [[ ${config_codigo} -eq 0 && ${wget_codigo} -eq 0 ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tiempo_ms}ms) - Config válida, endpoint responde"
        registrar_resultado "${contenedor}" "OK" "Configuración válida, endpoint responde" "${tiempo_ms}ms"
    elif [[ ${config_codigo} -ne 0 ]]; then
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET} - Config inválida"
        registrar_resultado "${contenedor}" "ERROR" "Configuración de nginx inválida" "${tiempo_ms}ms"
    else
        echo -e "${COLOR_AMARILLO}ADVERTENCIA${COLOR_RESET} (${tiempo_ms}ms) - Config OK pero endpoint no responde"
        registrar_resultado "${contenedor}" "ADVERTENCIA" "Configuración OK, pero endpoint no responde" "${tiempo_ms}ms"
    fi
}

# --- Tabla resumen ---
imprimir_tabla_resumen() {
    echo ""
    echo -e "  ${COLOR_NEGRITA}TABLA RESUMEN:${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_NEGRITA}$(printf '%-22s %-14s %-10s %s' 'SERVICIO' 'ESTADO' 'TIEMPO' 'DETALLE')${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}$(printf '%-22s %-14s %-10s %s' '──────────────────────' '──────────────' '──────────' '────────────────────────────────────────')${COLOR_RESET}"

    for servicio in "${SERVICIOS[@]}"; do
        local estado="${RESULTADO_ESTADO["${servicio}"]:-SIN DATOS}"
        local tiempo="${RESULTADO_TIEMPO["${servicio}"]:-"-"}"
        local detalle="${RESULTADO_DETALLE["${servicio}"]:-"No verificado"}"

        local color_estado
        case "${estado}" in
            OK)          color_estado="${COLOR_VERDE}" ;;
            ERROR)       color_estado="${COLOR_ROJO}" ;;
            ADVERTENCIA) color_estado="${COLOR_AMARILLO}" ;;
            *)           color_estado="${COLOR_GRIS}" ;;
        esac

        # Truncar detalle si es muy largo
        if [[ ${#detalle} -gt 48 ]]; then
            detalle="${detalle:0:45}..."
        fi

        printf "  %-22s " "${servicio}"
        echo -ne "${color_estado}$(printf '%-14s' "${estado}")${COLOR_RESET}"
        printf "%-10s %s\n" "${tiempo}" "${detalle}"
    done
    echo ""
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

verificar_postgres
verificar_redis
verificar_synapse
verificar_element
verificar_nginx

imprimir_tabla_resumen

# --- Resultado final ---
errores=0
advertencias=0

for servicio in "${SERVICIOS[@]}"; do
    case "${RESULTADO_ESTADO["${servicio}"]:-}" in
        ERROR)       errores=$((errores + 1)) ;;
        ADVERTENCIA) advertencias=$((advertencias + 1)) ;;
    esac
done

echo -e "  ${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
if [[ ${errores} -eq 0 && ${advertencias} -eq 0 ]]; then
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Todos los servicios están saludables.${COLOR_RESET}"
    exit 0
elif [[ ${errores} -eq 0 ]]; then
    echo -e "  ${COLOR_AMARILLO}⚠ ${advertencias} servicio(s) con advertencia(s).${COLOR_RESET}"
    exit 0
else
    echo -e "  ${COLOR_ROJO}✘ ${errores} servicio(s) con error(es), ${advertencias} advertencia(s).${COLOR_RESET}"
    exit 1
fi