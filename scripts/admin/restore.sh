#!/usr/bin/env bash
# =============================================================================
# restore.sh - Restaurar el stack Matrix desde un respaldo
# =============================================================================
# Lista los respaldos disponibles y restaura el seleccionado:
#   1. Lista respaldos disponibles en BACKUP_DIR
#   2. Solicita confirmación del usuario
#   3. Detiene los servicios
#   4. Restaura la base de datos PostgreSQL
#   5. Copia configuraciones
#   6. Reinicia los servicios
#
# Uso:
#   ./scripts/admin/restore.sh                   # Menú interactivo
#   ./scripts/admin/restore.sh /ruta/al/respaldo # Restaurar respaldo específico
#
# Variables de entorno (.env):
#   BACKUP_DIR    - Directorio de respaldos (por defecto: ./backups)
#   POSTGRES_USER - Usuario de PostgreSQL (por defecto: synapse)
#   POSTGRES_DB   - Base de datos (por defecto: synapse)
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
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
POSTGRES_USER="${POSTGRES_USER:-synapse}"
POSTGRES_DB="${POSTGRES_DB:-synapse}"
POSTGRES_CONTAINER="matrix-postgres"

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║        RESTAURAR DESDE RESPALDO - matrix-stack                       ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Fecha: ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo -e "  Directorio de respaldos: ${COLOR_NEGRITA}${BACKUP_DIR}${COLOR_RESET}"
    echo ""
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

listar_respaldos() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        echo -e "  ${COLOR_ROJO}✘ El directorio de respaldos no existe: ${BACKUP_DIR}${COLOR_RESET}"
        return 1
    fi

    local respaldos
    mapfile -t respaldos < <(find "${BACKUP_DIR}" -name "matrix-backup-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ ${#respaldos[@]} -eq 0 ]]; then
        echo -e "  ${COLOR_ROJO}✘ No se encontraron respaldos en ${BACKUP_DIR}${COLOR_RESET}"
        return 1
    fi

    echo -e "  ${COLOR_NEGRITA}Respaldos disponibles:${COLOR_RESET}"
    echo ""

    local indice=1
    for respaldo in "${respaldos[@]}"; do
        local nombre archivo_tamano fecha
        nombre=$(basename "${respaldo}")
        archivo_tamano=$(du -h "${respaldo}" | cut -f1)
        fecha=$(stat -c '%y' "${respaldo}" 2>/dev/null | cut -d'.' -f1 || echo "desconocida")
        echo -e "    ${COLOR_NEGRITA}${indice})${COLOR_RESET} ${nombre}"
        echo -e "       Tamaño: ${archivo_tamano}  |  Fecha: ${fecha}"
        echo ""
        indice=$((indice + 1))
    done

    # Almacenar en array global para selección
    RESPALDOS_DISPONIBLES=("${respaldos[@]}")

    return 0
}

seleccionar_respaldo() {
    if [[ ${#RESPALDOS_DISPONIBLES[@]} -eq 1 ]]; then
        # Solo un respaldo, seleccionarlo automáticamente
        echo -e "  ${COLOR_GRIS}Solo hay un respaldo disponible, seleccionándolo automáticamente.${COLOR_RESET}"
        echo "${RESPALDOS_DISPONIBLES[0]}"
        return 0
    fi

    echo -ne "  ${COLOR_NEGRITA}Seleccione el número de respaldo [1-${#RESPALDOS_DISPONIBLES[@]}]: ${COLOR_RESET}"
    local seleccion
    read -r seleccion

    if ! [[ "${seleccion}" =~ ^[0-9]+$ ]] || [[ ${seleccion} -lt 1 ]] || [[ ${seleccion} -gt ${#RESPALDOS_DISPONIBLES[@]} ]]; then
        echo -e "  ${COLOR_ROJO}Selección no válida.${COLOR_RESET}"
        return 1
    fi

    local indice=$((seleccion - 1))
    echo "${RESPALDOS_DISPONIBLES[${indice}]}"
    return 0
}

detener_servicios() {
    echo -e "  ${COLOR_NEGRITA}Deteniendo servicios...${COLOR_RESET}"
    docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" stop -t 30 2>/dev/null || true
    echo -e "  ${COLOR_VERDE}✔ Servicios detenidos.${COLOR_RESET}"
}

restaurar_base_datos() {
    local dir_temp="$1"

    echo -ne "  Restaurando PostgreSQL .......... "

    local dump_file="${dir_temp}/postgres/${POSTGRES_DB}.sql"

    if [[ ! -f "${dump_file}" ]]; then
        echo -e "${COLOR_AMARILLO}OMITIDO${COLOR_RESET} (no se encontró el volcado)"
        return 0
    fi

    # Verificar que el contenedor existe
    local estado
    estado=$(docker inspect --format '{{.State.Status}}' "${POSTGRES_CONTAINER}" 2>/dev/null || echo "detenido")
    if [[ "${estado}" != "running" ]]; then
        # Intentar iniciar solo PostgreSQL
        echo -ne "iniciando PG... "
        docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" up -d postgres 2>/dev/null || true
        sleep 5
    fi

    # Eliminar conexiones activas y restaurar
    docker exec "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB}' AND pid <> pg_backend_pid();" \
        2>/dev/null || true

    # Eliminar y recrear la base de datos
    docker exec "${POSTGRES_CONTAINER}" dropdb -U "${POSTGRES_USER}" --if-exists "${POSTGRES_DB}" 2>/dev/null || true
    docker exec "${POSTGRES_CONTAINER}" createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null || true

    # Restaurar el volcado
    if docker exec -i "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < "${dump_file}" 2>/dev/null; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
        return 0
    else
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET}"
        return 1
    fi
}

restaurar_configuraciones() {
    local dir_temp="$1"

    echo -ne "  Restaurando configuraciones .... "

    local dir_config="${dir_temp}/config"

    if [[ ! -d "${dir_config}" ]]; then
        echo -e "${COLOR_AMARILLO}OMITIDO${COLOR_RESET} (sin configuraciones en respaldo)"
        return 0
    fi

    # Restaurar .env
    if [[ -f "${dir_config}/.env" ]]; then
        cp "${dir_config}/.env" "${PROJECT_ROOT}/.env"
    fi

    # Restaurar docker-compose.yml
    if [[ -f "${dir_config}/docker-compose.yml" ]]; then
        cp "${dir_config}/docker-compose.yml" "${PROJECT_ROOT}/docker-compose.yml"
    fi

    # Restaurar directorio config/
    if [[ -d "${dir_config}/config" ]]; then
        mkdir -p "${PROJECT_ROOT}/config"
        cp -r "${dir_config}/config/"* "${PROJECT_ROOT}/config/" 2>/dev/null || true
    fi

    # Restaurar nginx/
    if [[ -d "${dir_config}/nginx" ]]; then
        mkdir -p "${PROJECT_ROOT}/nginx"
        cp -r "${dir_config}/nginx/"* "${PROJECT_ROOT}/nginx/" 2>/dev/null || true
    fi

    # Restaurar datos de Synapse (signing key, etc.)
    if [[ -d "${dir_config}/synapse-data" ]]; then
        mkdir -p "${PROJECT_ROOT}/data/synapse"
        cp -r "${dir_config}/synapse-data/"* "${PROJECT_ROOT}/data/synapse/" 2>/dev/null || true
    fi

    echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    return 0
}

iniciar_servicios() {
    echo -e "  ${COLOR_NEGRITA}Iniciando servicios...${COLOR_RESET}"
    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" up -d 2>&1; then
        echo -e "  ${COLOR_VERDE}✔ Servicios iniciados.${COLOR_RESET}"
        return 0
    else
        echo -e "  ${COLOR_ROJO}✘ Error al iniciar servicios.${COLOR_RESET}"
        return 1
    fi
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
imprimir_encabezado

# Determinar archivo de respaldo
ARCHIVO_RESPALDO=""

if [[ -n "${1:-}" ]]; then
    # Ruta específica proporcionada
    if [[ -f "$1" ]]; then
        ARCHIVO_RESPALDO="$1"
    else
        echo -e "  ${COLOR_ROJO}✘ El archivo especificado no existe: $1${COLOR_RESET}"
        exit 1
    fi
else
    # Modo interactivo
    if ! listar_respaldos; then
        exit 1
    fi

    ARCHIVO_RESPALDO=$(seleccionar_respaldo) || exit 1
fi

echo ""
echo -e "  ${COLOR_NEGRITA}Respaldo seleccionado:${COLOR_RESET} $(basename "${ARCHIVO_RESPALDO}")"

# Mostrar metadatos si están disponibles
echo ""
echo -e "  ${COLOR_NEGRITA}Contenido del respaldo:${COLOR_RESET}"
if tar -tzf "${ARCHIVO_RESPALDO}" 2>/dev/null | head -20; then
    total=$(tar -tzf "${ARCHIVO_RESPALDO}" 2>/dev/null | wc -l)
    if [[ ${total} -gt 20 ]]; then
        echo -e "  ${COLOR_GRIS}... y $((${total} - 20)) archivo(s) más.${COLOR_RESET}"
    fi
else
    echo -e "  ${COLOR_AMARILLO}No se pudo listar el contenido.${COLOR_RESET}"
fi

echo ""

# Confirmación final
echo -e "  ${COLOR_ROJO}${COLOR_NEGRITA}═══════════════════════════════════════════════════════════════${COLOR_RESET}"
echo -e "  ${COLOR_ROJO}${COLOR_NEGRITA}  ⚠ ATENCIÓN: La restauración sobrescribirá datos actuales.  ⚠${COLOR_RESET}"
echo -e "  ${COLOR_ROJO}${COLOR_NEGRITA}═══════════════════════════════════════════════════════════════${COLOR_RESET}"
echo ""

if ! confirmar "¿Está SEGURO de que desea restaurar este respaldo?"; then
    echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
    exit 0
fi

echo ""
echo -e "  ${COLOR_NEGRITA}Iniciando restauración...${COLOR_RESET}"
echo ""

# Crear directorio temporal
DIR_TEMP=$(mktemp -d /tmp/matrix-restore.XXXXXX)
trap 'rm -rf "${DIR_TEMP}" 2>/dev/null' EXIT

# Extraer respaldo
echo -ne "  Extrayendo respaldo ............ "
if ! tar -xzf "${ARCHIVO_RESPALDO}" -C "${DIR_TEMP}" 2>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}✘ No se pudo extraer el archivo de respaldo.${COLOR_RESET}"
    exit 1
fi
echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
echo ""

errores=0

# Paso 1: Detener servicios
echo -e "  ${COLOR_NEGRITA}── Paso 1: Detener servicios ──${COLOR_RESET}"
if ! detener_servicios; then
    errores=$((errores + 1))
fi
echo ""

# Paso 2: Restaurar base de datos
echo -e "  ${COLOR_NEGRITA}── Paso 2: Restaurar base de datos ──${COLOR_RESET}"
if ! restaurar_base_datos "${DIR_TEMP}"; then
    errores=$((errores + 1))
fi
echo ""

# Paso 3: Restaurar configuraciones
echo -e "  ${COLOR_NEGRITA}── Paso 3: Restaurar configuraciones ──${COLOR_RESET}"
if ! restaurar_configuraciones "${DIR_TEMP}"; then
    errores=$((errores + 1))
fi
echo ""

# Paso 4: Reiniciar servicios
echo -e "  ${COLOR_NEGRITA}── Paso 4: Reiniciar servicios ──${COLOR_RESET}"
if ! iniciar_servicios; then
    errores=$((errores + 1))
fi
echo ""

# --- Resumen ---
echo -e "  ${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
echo ""

if [[ ${errores} -eq 0 ]]; then
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Restauración completada exitosamente.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Verifique el estado con: ./scripts/admin/status.sh${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Verifique la salud con:  ./scripts/admin/healthcheck.sh${COLOR_RESET}"
else
    echo -e "  ${COLOR_AMARILLO}⚠ Restauración completada con ${errores} error(es).${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Revise los logs con: ./scripts/admin/logs.sh${COLOR_RESET}"
fi

echo ""
exit 0