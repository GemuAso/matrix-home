#!/usr/bin/env bash
# =============================================================================
# backup.sh - Crear respaldo completo del stack Matrix
# =============================================================================
# Crea un respaldo que incluye:
#   - Volcado de PostgreSQL (pg_dump)
#   - Copia de configuraciones (docker-compose.yml, .env, configs/)
#   - Todo empaquetado en un archivo .tar.gz
#   - Rotación automática según BACKUP_RETENTION_DAYS
#
# Uso:
#   ./scripts/admin/backup.sh
#   ./scripts/admin/backup.sh --no-rotate   # No eliminar respaldos antiguos
#
# Variables de entorno (.env):
#   BACKUP_DIR           - Directorio de respaldos (por defecto: ./backups)
#   BACKUP_RETENTION_DAYS - Días de retención (por defecto: 30)
#   POSTGRES_USER        - Usuario de PostgreSQL (por defecto: synapse)
#   POSTGRES_DB          - Base de datos (por defecto: synapse)
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
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
POSTGRES_USER="${POSTGRES_USER:-synapse}"
POSTGRES_DB="${POSTGRES_DB:-synapse}"
POSTGRES_CONTAINER="matrix-postgres"
NO_ROTATE=false

# --- Parseo de argumentos ---
if [[ "${1:-}" == "--no-rotate" ]]; then
    NO_ROTATE=true
fi

# --- Funciones auxiliares ---

imprimir_encabezado() {
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╔══════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}║            RESPALDO COMPLETO - matrix-stack                          ║${COLOR_RESET}"
    echo -e "${COLOR_NEGRITA}${COLOR_CYAN}╚══════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Fecha:           ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo -e "  Directorio:      ${COLOR_NEGRITA}${BACKUP_DIR}${COLOR_RESET}"
    echo -e "  Retención:       ${COLOR_NEGRITA}${BACKUP_RETENTION_DAYS} días${COLOR_RESET}"
    echo ""
}

verificar_postgres() {
    local estado
    estado=$(docker inspect --format '{{.State.Status}}' "${POSTGRES_CONTAINER}" 2>/dev/null || echo "detenido")
    if [[ "${estado}" != "running" ]]; then
        echo -e "  ${COLOR_ROJO}✘ PostgreSQL no está en ejecución. No se puede crear el volcado de base de datos.${COLOR_RESET}"
        echo -e "  ${COLOR_GRIS}Inicie los servicios primero: ./scripts/admin/start.sh${COLOR_RESET}"
        return 1
    fi
    return 0
}

crear_directorio_temporal() {
    mktemp -d /tmp/matrix-backup.XXXXXX
}

respaldar_postgres() {
    local dir_temp="$1"
    local archivo_dump="${dir_temp}/postgres/${POSTGRES_DB}.sql"

    echo -ne "  Creando volcado de PostgreSQL ... "

    if ! docker exec "${POSTGRES_CONTAINER}" pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
         --format=plain --no-owner --no-privileges > "${archivo_dump}" 2>/dev/null; then
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET}"
        return 1
    fi

    local tamano
    tamano=$(du -h "${archivo_dump}" | cut -f1)
    echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tamano})"
    return 0
}

respaldar_configuraciones() {
    local dir_temp="$1"

    echo -ne "  Copiando configuraciones ....... "

    local dir_config="${dir_temp}/config"

    # Copiar archivos de configuración principales
    cp "${COMPOSE_FILE}" "${dir_config}/docker-compose.yml" 2>/dev/null || true

    if [[ -f "${ENV_FILE}" ]]; then
        cp "${ENV_FILE}" "${dir_config}/.env" 2>/dev/null || true
    fi

    # Copiar directorio de configuraciones si existe
    if [[ -d "${PROJECT_ROOT}/config" ]]; then
        cp -r "${PROJECT_ROOT}/config" "${dir_config}/config" 2>/dev/null || true
    fi

    # Copiar nginx config si existe
    if [[ -d "${PROJECT_ROOT}/nginx" ]]; then
        cp -r "${PROJECT_ROOT}/nginx" "${dir_config}/nginx" 2>/dev/null || true
    fi

    # Copiar signing key de Synapse si existe
    if [[ -d "${PROJECT_ROOT}/data/synapse" ]]; then
        mkdir -p "${dir_config}/synapse-data"
        cp -r "${PROJECT_ROOT}/data/synapse"/* "${dir_config}/synapse-data/" 2>/dev/null || true
    fi

    echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    return 0
}

crear_metadatos() {
    local dir_temp="$1"
    local archivo="${dir_temp}/METADATA.txt"

    cat > "${archivo}" << EOF
Respaldo de Matrix Stack
=========================
Fecha:               $(date '+%Y-%m-%d %H:%M:%S')
Nombre del stack:    ${STACK_NAME}
Host:                $(hostname)
Directorio proyecto: ${PROJECT_ROOT}
Usuario:             $(whoami)
Contenedores activos:
$(docker ps --filter "name=matrix-" --format "  - {{.Names}} ({{.Image}}) - {{.Status}}" 2>/dev/null || echo "  No se pudieron listar")
EOF

    echo -e "  ${COLOR_GRIS}Metadatos guardados.${COLOR_RESET}"
}

empaquetar_respaldo() {
    local dir_temp="$1"
    local archivo_final="$2"

    echo -ne "  Empaquetando respaldo .......... "

    if ! tar -czf "${archivo_final}" -C "${dir_temp}" . 2>/dev/null; then
        echo -e "${COLOR_ROJO}ERROR${COLOR_RESET}"
        return 1
    fi

    local tamano
    tamano=$(du -h "${archivo_final}" | cut -f1)
    echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${tamano})"
    return 0
}

rotar_respaldos() {
    if [[ "${NO_ROTATE}" == "true" ]]; then
        echo -e "  Rotación deshabilitada (--no-rotate)."
        return 0
    fi

    echo -ne "  Rotando respaldos antiguos .... "

    local eliminados=0
    local ahora
    ahora=$(date +%s)
    local segundos_retencion=$(( BACKUP_RETENTION_DAYS * 86400 ))

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        echo -e "${COLOR_GRIS}N/A${COLOR_RESET} (directorio no existe)"
        return 0
    fi

    while IFS= read -r -d '' archivo; do
        local fecha_archivo
        fecha_archivo=$(stat -c %Y "${archivo}" 2>/dev/null || echo "0")
        local diferencia=$(( ahora - fecha_archivo ))

        if [[ ${diferencia} -gt ${segundos_retencion} ]]; then
            rm -f "${archivo}"
            eliminados=$((eliminados + 1))
        fi
    done < <(find "${BACKUP_DIR}" -name "matrix-backup-*.tar.gz" -print0 2>/dev/null)

    if [[ ${eliminados} -gt 0 ]]; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET} (${eliminados} eliminado(s))"
    else
        echo -e "${COLOR_GRIS}OK${COLOR_RESET} (nada que eliminar)"
    fi
}

limpiar_temporal() {
    local dir_temp="$1"
    rm -rf "${dir_temp}" 2>/dev/null || true
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
imprimir_encabezado

# Verificar PostgreSQL está disponible para el dump
if ! verificar_postgres; then
    exit 1
fi

# Crear directorio de respaldos
mkdir -p "${BACKUP_DIR}"

# Nombre del archivo de respaldo
MARCA_TIEMPO=$(date '+%Y%m%d-%H%M%S')
ARCHIVO_RESPALDO="${BACKUP_DIR}/matrix-backup-${MARCA_TIEMPO}.tar.gz"

echo -e "  ${COLOR_NEGRITA}Iniciando respaldo...${COLOR_RESET}"
echo ""

# Crear directorio temporal de trabajo
DIR_TEMP=$(crear_directorio_temporal)
trap 'limpiar_temporal "${DIR_TEMP}"' EXIT

# Crear subdirectorios
mkdir -p "${DIR_TEMP}/postgres"
mkdir -p "${DIR_TEMP}/config"

errores=0

# Paso 1: Volcado de PostgreSQL
if ! respaldar_postgres "${DIR_TEMP}"; then
    errores=$((errores + 1))
    echo -e "  ${COLOR_ROJO}El volcado de PostgreSQL falló, pero se continuará con el resto.${COLOR_RESET}"
fi

# Paso 2: Copiar configuraciones
if ! respaldar_configuraciones "${DIR_TEMP}"; then
    errores=$((errores + 1))
fi

# Paso 3: Metadatos
crear_metadatos "${DIR_TEMP}"

echo ""

# Paso 4: Empaquetar
if ! empaquetar_respaldo "${DIR_TEMP}" "${ARCHIVO_RESPALDO}"; then
    errores=$((errores + 1))
    echo -e ""
    echo -e "  ${COLOR_ROJO}✘ Error al crear el archivo de respaldo.${COLOR_RESET}"
    exit 1
fi

echo ""

# Paso 5: Rotación
rotar_respaldos

echo ""

# --- Resumen ---
echo -e "  ${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
echo ""
if [[ ${errores} -eq 0 ]]; then
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}✔ Respaldo completado exitosamente.${COLOR_RESET}"
    echo -e "  Archivo: ${COLOR_NEGRITA}${ARCHIVO_RESPALDO}${COLOR_RESET}"
else
    echo -e "  ${COLOR_AMARILLO}⚠ Respaldo completado con ${errores} error(es).${COLOR_RESET}"
    echo -e "  Archivo: ${COLOR_NEGRITA}${ARCHIVO_RESPALDO}${COLOR_RESET}"
    echo -e "  ${COLOR_AMARILLO}Algunos componentes pueden estar incompletos.${COLOR_RESET}"
fi

echo ""
exit 0