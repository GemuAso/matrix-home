#!/usr/bin/env bash
# =============================================================================
# uninstall.sh - Desinstalador profesional del stack Matrix
# =============================================================================
# Ofrece 5 niveles de eliminación con confirmación en cada paso:
#
#   1. Eliminar solo contenedores (se conservan datos, redes y volúmenes)
#   2. Eliminar contenedores y redes (se conservan volúmenes y datos)
#   3. Eliminar contenedores, redes y volúmenes (eliminación completa de datos)
#   4. Eliminar todo, incluyendo archivos generados (.env, certificados, claves)
#   5. Crear respaldo antes de eliminar (luego opción 3)
#
# Uso:
#   ./scripts/admin/uninstall.sh
# =============================================================================

set -Eeuo pipefail

# --- Detección del directorio raíz del proyecto ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- Colores (solo si hay terminal) ---
if [[ -t 1 ]]; then
    COLOR_ROJO='\033[0;31m'
    COLOR_ROJO_BRILLANTE='\033[1;31m'
    COLOR_VERDE='\033[0;32m'
    COLOR_AMARILLO='\033[1;33m'
    COLOR_CYAN='\033[0;36m'
    COLOR_GRIS='\033[0;90m'
    COLOR_NEGRITA='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_ROJO=''
    COLOR_ROJO_BRILLANTE=''
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

# Archivos y directorios que se eliminan en la opción 4
ARCHIVOS_GENERADOS=(
    "${PROJECT_ROOT}/.env"
)

DIRECTORIOS_GENERADOS=(
    "${PROJECT_ROOT}/certs"
    "${PROJECT_ROOT}/data"
    "${PROJECT_ROOT}/backups"
)

# --- Funciones auxiliares ---

imprimir_encabezado() {
    clear 2>/dev/null || true
    echo -e "${COLOR_ROJO_BRILLANTE}${COLOR_NEGRITA}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                     ║"
    echo "║              ⚠  DESINSTALADOR DEL STACK MATRIX  ⚠                  ║"
    echo "║                                                                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo ""
    echo -e "  Proyecto:  ${COLOR_NEGRITA}${PROJECT_ROOT}${COLOR_RESET}"
    echo -e "  Stack:     ${COLOR_NEGRITA}${STACK_NAME}${COLOR_RESET}"
    echo -e "  Fecha:     ${COLOR_NEGRITA}$(date '+%Y-%m-%d %H:%M:%S')${COLOR_RESET}"
    echo ""
}

mostrar_menu() {
    echo -e "  ${COLOR_NEGRITA}Seleccione el nivel de eliminación:${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_NEGRITA}1)${COLOR_RESET} Eliminar solo contenedores"
    echo -e "       ${COLOR_GRIS}Los datos en volúmenes, redes y archivos se conservan.${COLOR_RESET}"
    echo -e "       ${COLOR_GRIS}Puede reiniciar el stack con ./scripts/admin/start.sh${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_NEGRITA}2)${COLOR_RESET} Eliminar contenedores y redes"
    echo -e "       ${COLOR_GRIS}Los volúmenes de datos se conservan.${COLOR_RESET}"
    echo -e "       ${COLOR_GRIS}Se recrearán las redes al iniciar de nuevo.${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_ROJO}${COLOR_NEGRITA}3)${COLOR_RESET} Eliminar contenedores, redes y volúmenes${COLOR_RESET}"
    echo -e "       ${COLOR_ROJO}⚠ Los datos de la base de datos y configuraciones se eliminan.${COLOR_RESET}"
    echo -e "       ${COLOR_ROJO}⚠ Esta operación NO se puede deshacer.${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_ROJO_BRILLANTE}${COLOR_NEGRITA}4)${COLOR_RESET} Eliminar TODO (contenedores, redes, volúmenes y archivos)${COLOR_RESET}"
    echo -e "       ${COLOR_ROJO_BRILLANTE}⚠ Se eliminan .env, certificados, claves de firma y datos.${COLOR_RESET}"
    echo -e "       ${COLOR_ROJO_BRILLANTE}⚠ El proyecto quedará en estado inicial.${COLOR_RESET}"
    echo -e "       ${COLOR_ROJO_BRILLANTE}⚠ Esta operación NO se puede deshacer.${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_VERDE}${COLOR_NEGRITA}5)${COLOR_RESET} Crear respaldo y luego eliminar (nivel 3)${COLOR_RESET}"
    echo -e "       ${COLOR_VERDE}Crea un respaldo completo antes de eliminar datos.${COLOR_RESET}"
    echo ""
    echo -e "    ${COLOR_GRIS}    0) Cancelar${COLOR_RESET}"
    echo ""
    echo -ne "  ${COLOR_NEGRITA}Opción [0-5]: ${COLOR_RESET}"
}

confirmar() {
    local mensaje="$1"
    echo ""
    echo -ne "  ${COLOR_ROJO_BRILLANTE}${COLOR_NEGRITA}⚠ ${mensaje}${COLOR_RESET} "
    echo -ne "${COLOR_ROJO_BRILLANTE}[escriba ELIMINAR para confirmar]: ${COLOR_RESET}"
    local respuesta
    read -r respuesta
    if [[ "${respuesta}" == "ELIMINAR" ]]; then
        return 0
    fi
    return 1
}

confirmar_simple() {
    local mensaje="$1"
    echo -ne "  ${COLOR_AMARILLO}${mensaje} [s/N]: ${COLOR_RESET}"
    local respuesta
    read -r respuesta
    case "${respuesta}" in
        s|S|sí|Sí|SÍ|si|Si|SI) return 0 ;;
        *) return 1 ;;
    esac
}

verificar_stack_existe() {
    # Verificar si hay algún recurso del stack
    local contenedores redes volumenes
    contenedores=$(docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '{{.Names}}' 2>/dev/null | wc -l)
    redes=$(docker network ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | wc -l)
    volumenes=$(docker volume ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | wc -l)

    if [[ ${contenedores} -eq 0 && ${redes} -eq 0 && ${volumenes} -eq 0 ]]; then
        echo -e "  ${COLOR_GRIS}No se encontraron recursos del stack ${STACK_NAME}.${COLOR_RESET}"
        echo -e "  ${COLOR_GRIS}No hay nada que eliminar.${COLOR_RESET}"
        return 1
    fi
    return 0
}

mostrar_recursos() {
    echo -e "  ${COLOR_NEGRITA}Recursos actuales del stack:${COLOR_RESET}"
    echo ""

    # Contenedores
    local contenedores
    contenedores=$(docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '    {{.Names}} - {{.Status}}' 2>/dev/null || true)
    if [[ -n "${contenedores}" ]]; then
        echo -e "  ${COLOR_NEGRITA}Contenedores:${COLOR_RESET}"
        echo -e "${contenedores}"
        echo ""
    fi

    # Redes
    local redes
    redes=$(docker network ls --filter "name=matrix-stack" --format '    {{.Name}}' 2>/dev/null || true)
    if [[ -n "${redes}" ]]; then
        echo -e "  ${COLOR_NEGRITA}Redes:${COLOR_RESET}"
        echo -e "${redes}"
        echo ""
    fi

    # Volúmenes
    local volumenes
    volumenes=$(docker volume ls --filter "name=matrix-stack" --format '    {{.Name}}' 2>/dev/null || true)
    if [[ -n "${volumenes}" ]]; then
        echo -e "  ${COLOR_NEGRITA}Volúmenes:${COLOR_RESET}"
        echo -e "${volumenes}"
        echo ""
    fi
}

# --- Opciones de eliminación ---

opcion_1_eliminar_contenedores() {
    echo ""
    echo -e "  ${COLOR_NEGRITA}── Eliminando contenedores ──${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_AMARILLO}Se detendrán y eliminarán todos los contenedores del stack.${COLOR_RESET}"
    echo -e "  ${COLOR_AMARILLO}Los datos en volúmenes se conservarán intactos.${COLOR_RESET}"

    if ! confirmar_simple "¿Desea continuar?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
        return 0
    fi

    echo ""
    echo -ne "  Deteniendo contenedores... "

    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down --remove-orphans 2>&1; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    else
        # Fallback: intentar eliminar manualmente
        echo -e "${COLOR_AMARILLO}Usando método alternativo...${COLOR_RESET}"
        docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '{{.Names}}' 2>/dev/null | \
            while read -r contenedor; do
                docker rm -f "${contenedor}" 2>/dev/null || true
            done
        echo -e "  ${COLOR_VERDE}OK${COLOR_RESET}"
    fi

    echo ""
    echo -e "  ${COLOR_VERDE}✔ Contenedores eliminados.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Puede reiniciar con: ./scripts/admin/start.sh${COLOR_RESET}"
}

opcion_2_eliminar_contenedores_redes() {
    echo ""
    echo -e "  ${COLOR_NEGRITA}── Eliminando contenedores y redes ──${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_AMARILLO}Se eliminarán contenedores y redes del stack.${COLOR_RESET}"
    echo -e "  ${COLOR_AMARILLO}Los volúmenes de datos se conservarán.${COLOR_RESET}"

    if ! confirmar_simple "¿Desea continuar?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
        return 0
    fi

    echo ""
    echo -ne "  Eliminando contenedores y redes... "

    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down --remove-orphans 2>&1; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    else
        echo -e "${COLOR_AMARILLO}Usando método alternativo...${COLOR_RESET}"
        # Eliminar contenedores
        docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '{{.Names}}' 2>/dev/null | \
            while read -r contenedor; do
                docker rm -f "${contenedor}" 2>/dev/null || true
            done
        # Eliminar redes
        docker network ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | \
            while read -r red; do
                docker network rm "${red}" 2>/dev/null || true
            done
        echo -e "  ${COLOR_VERDE}OK${COLOR_RESET}"
    fi

    echo ""
    echo -e "  ${COLOR_VERDE}✔ Contenedores y redes eliminados.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Los volúmenes se conservan. Puede reinstalar y reutilizar los datos.${COLOR_RESET}"
}

opcion_3_eliminar_todo_docker() {
    echo ""
    echo -e "  ${COLOR_ROJO}${COLOR_NEGRITA}── Eliminación completa de datos del stack ──${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_ROJO}╔═══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}║  ⚠  ESTO ELIMINARÁ TODOS LOS DATOS DEL STACK MATRIX          ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}║     Incluyendo la base de datos PostgreSQL y Redis.           ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO}╚═══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""

    if ! confirmar "¿Está SEGURO de que desea eliminar TODOS los datos?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada. Sus datos están a salvo.${COLOR_RESET}"
        return 0
    fi

    echo ""
    echo -ne "  Eliminando contenedores, redes y volúmenes... "

    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down -v --remove-orphans 2>&1; then
        echo -e "${COLOR_VERDE}OK${COLOR_RESET}"
    else
        echo -e "${COLOR_AMARILLO}Usando método alternativo...${COLOR_RESET}"
        # Eliminar contenedores
        docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '{{.Names}}' 2>/dev/null | \
            while read -r contenedor; do
                docker rm -f "${contenedor}" 2>/dev/null || true
            done
        # Eliminar redes
        docker network ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | \
            while read -r red; do
                docker network rm "${red}" 2>/dev/null || true
            done
        # Eliminar volúmenes
        docker volume ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | \
            while read -r vol; do
                docker volume rm "${vol}" 2>/dev/null || true
            done
        echo -e "  ${COLOR_VERDE}OK${COLOR_RESET}"
    fi

    echo ""
    echo -e "  ${COLOR_VERDE}✔ Stack Matrix eliminado completamente de Docker.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Los archivos del proyecto (.env, configs) se conservaron.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}Para reinstalar, configure .env y ejecute ./scripts/admin/start.sh${COLOR_RESET}"
}

opcion_4_eliminar_todo_incluyendo_archivos() {
    echo ""
    echo -e "  ${COLOR_ROJO_BRILLANTE}${COLOR_NEGRITA}── ELIMINACIÓN TOTAL DEL PROYECTO ──${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_ROJO_BRILLANTE}╔═══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║  ⚠⚠⚠  ESTO ELIMINARÁ ABSOLUTAMENTE TODO  ⚠⚠⚠              ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║  Se eliminará:                                                ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Todos los contenedores, redes y volúmenes de Docker       ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Archivo .env con todas las configuraciones               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Certificados SSL/TLS                                    ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Claves de firma de Synapse                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Todos los datos persistentes                             ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║    • Respaldos anteriores                                     ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║  Esta operación es IRREVERSIBLE.                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}║                                                               ║${COLOR_RESET}"
    echo -e "  ${COLOR_ROJO_BRILLANTE}╚═══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""

    # Mostrar archivos que se eliminarán
    echo -e "  ${COLOR_NEGRITA}Archivos/directorios que se eliminarán:${COLOR_RESET}"
    for archivo in "${ARCHIVOS_GENERADOS[@]}"; do
        if [[ -e "${archivo}" ]]; then
            echo -e "    ${COLOR_ROJO}✘${COLOR_RESET} ${archivo}"
        fi
    done
    for directorio in "${DIRECTORIOS_GENERADOS[@]}"; do
        if [[ -e "${directorio}" ]]; then
            echo -e "    ${COLOR_ROJO}✘${COLOR_RESET} ${directorio}/"
        fi
    done
    echo ""

    if ! confirmar "¿Está ABSOLUTAMENTE SEGURO de que desea eliminar TODO?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada. Nada fue eliminado.${COLOR_RESET}"
        return 0
    fi

    echo ""

    # Paso 1: Eliminar recursos de Docker
    echo -ne "  Paso 1/2: Eliminando recursos Docker... "
    docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down -v --remove-orphans 2>/dev/null || true

    # Fallback para limpiar cualquier recurso residual
    docker ps -a --filter "label=com.docker.compose.project=matrix-stack" --format '{{.Names}}' 2>/dev/null | \
        while read -r c; do docker rm -f "${c}" 2>/dev/null || true; done
    docker network ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | \
        while read -r r; do docker network rm "${r}" 2>/dev/null || true; done
    docker volume ls --filter "name=matrix-stack" --format '{{.Name}}' 2>/dev/null | \
        while read -r v; do docker volume rm "${v}" 2>/dev/null || true; done
    echo -e "${COLOR_VERDE}OK${COLOR_RESET}"

    # Paso 2: Eliminar archivos generados
    echo -ne "  Paso 2/2: Eliminando archivos generados... "

    for archivo in "${ARCHIVOS_GENERADOS[@]}"; do
        rm -f "${archivo}" 2>/dev/null || true
    done

    for directorio in "${DIRECTORIOS_GENERADOS[@]}"; do
        rm -rf "${directorio}" 2>/dev/null || true
    done

    echo -e "${COLOR_VERDE}OK${COLOR_RESET}"

    echo ""
    echo -e "  ${COLOR_VERDE}✔ Eliminación total completada.${COLOR_RESET}"
    echo -e "  ${COLOR_GRIS}El proyecto quedó en estado inicial. Configure .env para reinstalar.${COLOR_RESET}"
}

opcion_5_respaldo_y_eliminar() {
    echo ""
    echo -e "  ${COLOR_VERDE}${COLOR_NEGRITA}── Crear respaldo antes de eliminar ──${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_VERDE}Se creará un respaldo completo antes de proceder con la eliminación.${COLOR_RESET}"
    echo -e "  ${COLOR_VERDE}Luego se ejecutará la eliminación de nivel 3 (datos incluidos).${COLOR_RESET}"
    echo ""

    if ! confirmar_simple "¿Desea crear el respaldo y luego eliminar?"; then
        echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
        return 0
    fi

    echo ""

    # Ejecutar script de respaldo
    local script_backup="${SCRIPT_DIR}/backup.sh"
    if [[ -x "${script_backup}" ]]; then
        echo -e "  ${COLOR_NEGRITA}Ejecutando respaldo...${COLOR_RESET}"
        echo ""

        if bash "${script_backup}"; then
            echo ""
            echo -e "  ${COLOR_VERDE}✔ Respaldo creado correctamente.${COLOR_RESET}"
            echo ""
        else
            echo ""
            echo -e "  ${COLOR_ROJO}✘ Error al crear el respaldo.${COLOR_RESET}"
            echo ""
            if ! confirmar_simple "¿Desea continuar con la eliminación sin respaldo?"; then
                echo -e "  ${COLOR_GRIS}Operación cancelada.${COLOR_RESET}"
                return 0
            fi
            echo ""
        fi
    else
        echo -e "  ${COLOR_AMARILLO}⚠ No se encontró el script de respaldo en: ${script_backup}${COLOR_RESET}"
        echo -e "  ${COLOR_GRIS}Omitiendo paso de respaldo.${COLOR_RESET}"
        echo ""
    fi

    # Proceder con eliminación nivel 3
    opcion_3_eliminar_todo_docker
}

# --- Verificar que Docker está disponible ---
if ! command -v docker &>/dev/null; then
    echo -e "${COLOR_ROJO}ERROR: Docker no está instalado o no se encuentra en el PATH.${COLOR_RESET}"
    exit 1
fi

# --- Programa principal ---
imprimir_encabezado

# Mostrar recursos actuales
mostrar_recursos

# Verificar si hay algo que eliminar
if ! verificar_stack_existe; then
    # Aún así ofrecer la opción 4 para limpiar archivos
    echo ""
    echo -e "  ${COLOR_AMARILLO}Aunque no hay recursos de Docker, aún puede eliminar archivos generados (opción 4).${COLOR_RESET}"
    echo ""
fi

# Mostrar menú
mostrar_menu
read -r opcion

case "${opcion}" in
    1)
        opcion_1_eliminar_contenedores
        ;;
    2)
        opcion_2_eliminar_contenedores_redes
        ;;
    3)
        opcion_3_eliminar_todo_docker
        ;;
    4)
        opcion_4_eliminar_todo_incluyendo_archivos
        ;;
    5)
        opcion_5_respaldo_y_eliminar
        ;;
    0|"")
        echo ""
        echo -e "  ${COLOR_GRIS}Operación cancelada. No se eliminó nada.${COLOR_RESET}"
        ;;
    *)
        echo ""
        echo -e "  ${COLOR_ROJO}Opción no válida: ${opcion}${COLOR_RESET}"
        exit 1
        ;;
esac

echo ""
echo -e "  ${COLOR_GRIS}─────────────────────────────────────────────────────────────────${COLOR_RESET}"
echo ""
exit 0