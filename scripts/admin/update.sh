#!/usr/bin/env bash
# =============================================================================
# update.sh - Actualizar imágenes y reconstruir el stack Matrix
# =============================================================================
# Realiza la actualización completa del stack:
#   1. Extrae las últimas imágenes base
#   2. Reconstruye las imágenes personalizadas (Synapse, Element)
#   3. Reinicia el stack intentando zero-downtime cuando sea posible
#
# Uso:
#   ./scripts/admin/update.sh
#   ./scripts/admin/update.sh --no-restart   # Solo actualizar imágenes, no reiniciar
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
SERVICIOS_CONSTRUIR=("synapse" "element")
NO_RESTART=false

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║          ACTUALIZAR STACK - matrix-stack                            ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Fecha: ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo ""
}

imprimir_paso() {
    local paso="$1"
    local descripcion="$2"
    echo -e "  ${COLOR_NEGRITA}${COLOR_CYAN}► Paso ${paso}: ${descripcion}${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}────────────────────────────────────────${COLOR_RESET}"
}

imprimir_exito() {
    echo -e "  ${COLOR_VERDE}✔ $1${COLOR_RESET}"
}

imprimir_error() {
    echo -e "  ${COLOR_ROJO}✘ $1${COLOR_RESET}"
}

imprimir_advertencia() {
    echo -e "  ${COLOR_AMARILLO}⚠ $1${COLOR_RESET}"
}

confirmar() {
    local mensaje="$1"
    echo -ne "  ${COLOR_AMARILLO}${mensaje} [s/N]: ${COLOR_RESET}"
    local respuesta
    read -r respuesta
    case "${respuesta}" in
        s|S|sí|Sí|SÍ|si|Si|SI) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Parseo de argumentos ---
if [[ "${1:-}" == "--no-restart" ]]; then
    NO_RESTART=true
fi

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

# =====================================================================
# PASO 1: Crear respaldo previo si hay servicios ejecutándose
# =====================================================================
imprimir_paso "1" "Verificar estado previo"

hay_ejecutando=false
for svc in postgres redis synapse element nginx; do
    estado=$(docker inspect --format '{{.State.Status}}' "matrix-${svc}" 2>/dev/null || echo "detenido")
    if [[ "${estado}" == "running" ]]; then
        hay_ejecutando=true
        break
    fi
done

if [[ "${hay_ejecutando}" == "true" ]]; then
    echo -e "  Se detectaron servicios en ejecución."
    if ! confirmar "¿Desea continuar con la actualización?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
        exit 0
    fi
else
    echo -e "  No hay servicios en ejecución. Procediendo con la actualización."
fi
echo ""

# =====================================================================
# PASO 2: Extraer las últimas imágenes base
# =====================================================================
imprimir_paso "2" "Extraer últimas imágenes (docker compose pull)"

if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" pull 2>&1; then
    imprimir_exito "Imágenes base extraídas correctamente."
else
    imprimir_error "Error al extraer imágenes. Algunas imágenes pueden no estar actualizadas."
    echo -e "  ${COLOR_GRIS}Continuando con la reconstrucción...${COLOR_RESET}"
fi
echo ""

# =====================================================================
# PASO 3: Reconstruir imágenes personalizadas
# =====================================================================
imprimir_paso "3" "Reconstruir imágenes personalizadas"

for servicio in "${SERVICIOS_CONSTRUIR[@]}"; do
    echo -e "  Construyendo imagen de ${COLOR_NEGRITA}${servicio}${COLOR_RESET}..."
    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" build --no-cache "${servicio}" 2>&1; then
        imprimir_exito "Imagen de ${servicio} reconstruida."
    else
        imprimir_error "Error al construir la imagen de ${servicio}."
    fi
done
echo ""

# =====================================================================
# PASO 4: Reiniciar el stack (zero-downtime si es posible)
# =====================================================================
if [[ "${NO_RESTART}" == "true" ]]; then
    imprimir_advertencia "Modo --no-restart: omitiendo reinicio del stack."
    echo ""
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Actualización de imágenes completada.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Reinicie manualmente con: ./scripts/admin/restart.sh all${COLOR_RESET}"
    exit 0
fi

imprimir_paso "4" "Reiniciar el stack (zero-downtime)"

# Estrategia de zero-downtime:
# 1. Nginx es el punto de entrada, se actualiza primero sin afectar el resto
# 2. Luego se actualizan servicios internos
# 3. Finalmente se recarga nginx para apuntar a los nuevos contenedores

echo -e "  ${COLOR_NEGRITA}Estrategia de actualización:${COLOR_RESET}"
echo -e "    1. Reiniciar PostgreSQL y Redis (capa de datos)"
echo -e "    2. Reiniciar Synapse (servidor Matrix)"
echo -e "    3. Reiniciar Element (cliente web)"
echo -e "    4. Reiniciar Nginx (proxy inverso)"
echo ""

echo -e "  ${COLOR_AMARILLO}NOTA: La actualización zero-downtime completa requiere un balanceador${COLOR_RESET}"
echo -e "  ${COLOR_AMARILLO}de carga externo. Durante el reinicio de cada servicio habrá una${COLOR_RESET}"
echo -e "  ${COLOR_AMARILLO}interrupción breve de ese componente en particular.${COLOR_RESET}"
echo ""

if ! confirmar "¿Proceder con el reinicio?"; then
    echo -e "  ${COLOR_GRIS}Operación cancelada. Las imágenes están listas para uso futuro.${COLOR_RESET}"
    exit 0
fi

echo ""
echo -e "  ${COLOR_NEGRITA}Reiniciando servicios en orden...${COLOR_RESET}"
echo ""

# Reiniciar en orden: datos -> aplicación -> proxy
ORDEN=("postgres" "redis" "synapse" "element" "nginx")
errores=0

for servicio in "${ORDEN[@]}"; do
    echo -ne "  Reiniciando ${servicio}... "
    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" up -d --no-deps --force-recreate "${servicio}" &>/dev/null; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    else
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET}"
        errores=$((errores + 1))
    fi

    # Pausa entre servicios para estabilización
    if [[ "${servicio}" != "nginx" ]]; then
        sleep 2
    fi
done

echo ""

# =====================================================================
# RESUMEN
# =====================================================================
echo -e "  ${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
echo ""
echo -e "  ${COLOR_NEGRITA}RESUMEN DE ACTUALIZACIÓN:${COLOR_RESET}"
echo ""

if [[ ${errores} -eq 0 ]]; then
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Actualización completada exitosamente.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Verifique el estado con: ./scripts/admin/status.sh${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Verifique la salud con:  ./scripts/admin/healthcheck.sh${COLOR_RESET}"
else
    echo -e "  ${COLOR_AMARILLO}⚠ Actualización completada con ${errores} error(es).${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Revise los logs: ./scripts/admin/logs.sh${COLOR_RESET}"
fi

echo ""
exit 0