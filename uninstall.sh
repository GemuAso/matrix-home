#!/usr/bin/env bash
# =============================================================================
# uninstall.sh v5.1 - Desinstalador profesional del stack Matrix Docker
# =============================================================================
# Ofrece 5 niveles de eliminación con confirmación progresiva:
#
#   1. Eliminar solo contenedores          (conserva redes, volúmenes, archivos)
#   2. Eliminar contenedores + redes       (conserva volúmenes, archivos)
#   3. Eliminar contenedores + redes + volúmenes  (PÉRDIDA DE DATOS)
#   4. Eliminación TOTAL                   (Docker + archivos generados)
#   5. Respaldo completo → luego opción 3
#
# Requisitos de confirmación:
#   Opciones 1-2:  confirmación simple (s/N)
#   Opciones 3-4:  doble confirmación + escribir "ELIMINAR"
#   Opción 5:     confirmación simple → backup → confirmación ELIMINAR (nivel 3)
#
# Uso:
#   cd /home/z/my-project/matrix-project/matrix-docker
#   ./uninstall.sh
#
# Version: 5.1.0
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# 1. DETECCIÓN DEL DIRECTORIO RAÍZ
# =============================================================================
# El script vive en PROJECT_ROOT, por lo que SCRIPT_DIR == PROJECT_ROOT.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# =============================================================================
# 2. COLORES (solo si stdout es una terminal TTY)
# =============================================================================
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[0;31m'
    C_RED_B='\033[1;31m'
    C_GREEN='\033[0;32m'
    C_GREEN_B='\033[1;32m'
    C_YELLOW='\033[0;33m'
    C_YELLOW_B='\033[1;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_CYAN_B='\033[1;36m'
    C_GRAY='\033[0;90m'
else
    C_RESET=''  C_BOLD=''   C_DIM=''
    C_RED=''    C_RED_B=''  C_GREEN=''
    C_GREEN_B='' C_YELLOW='' C_YELLOW_B=''
    C_BLUE=''   C_CYAN=''   C_CYAN_B=''
    C_GRAY=''
fi

# =============================================================================
# 3. CARGA DE .ENV (no falla si no existe)
# =============================================================================
ENV_FILE="${PROJECT_ROOT}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}" 2>/dev/null || true
    set +a
fi

# =============================================================================
# 4. CONFIGURACIÓN FIJA DEL STACK
# =============================================================================

STACK_NAME="matrix-stack"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# -- Contenedores esperados --
CONTAINERS=(
    "matrix-postgres"
    "matrix-redis"
    "matrix-synapse"
    "matrix-element"
    "matrix-nginx"
)

# -- Imágenes personalizadas --
IMAGES=(
    "matrix-synapse:custom"
    "matrix-element:custom"
)

# -- Redes --
NETWORKS=(
    "matrix_internal"
    "matrix_frontend"
)

# -- Volúmenes --
VOLUMES=(
    "matrix_synapse_data"
    "matrix_postgres_data"
    "matrix_redis_data"
    "matrix_element_cache"
    "matrix_nginx_logs"
)

# -- Archivos generados (eliminados en opción 4) --
GENERATED_FILES=(
    "${PROJECT_ROOT}/.env"
    "${PROJECT_ROOT}/synapse/signing.key"
)

# -- Directorio de certificados (eliminado en opción 4) --
CERTS_DIR="${PROJECT_ROOT}/nginx/certs"

# -- Patrones de certificados a enumerar (glob) --
CERT_PATTERNS=(
    "*.crt"
    "*.key"
    "*.srl"
    "*.csr"
    "*.ext"
    "*.pem"
)

# -- Directorio de respaldos --
BACKUP_DIR="${PROJECT_ROOT}/backups"

# =============================================================================
# 5. FUNCIONES AUXILIARES
# =============================================================================

# -- Comprobar si Docker está disponible y el daemon corre --
check_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "  ${C_RED}✘ Docker no está instalado o no se encuentra en el PATH.${C_RESET}"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        echo -e "  ${C_RED}✘ El daemon de Docker no está en ejecución.${C_RESET}"
        echo -e "  ${C_GRAY}Inicie Docker e intente de nuevo.${C_RESET}"
        exit 1
    fi
}

# -- Contar cuántos de un array de nombres existen como recurso Docker --
# Uso: _count_existing "ps -a" "name" name1 name2 ...
_count_existing() {
    local docker_cmd="$1"; shift
    local filter_key="$1"; shift
    local total=0
    for name in "$@"; do
        if docker "${docker_cmd}" --filter "${filter_key}=${name}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
            total=$((total + 1))
        fi
    done
    echo "${total}"
}

# -- Enumerar recursos existentes del stack para mostrar --
enumerate_containers() {
    local found=()
    for c in "${CONTAINERS[@]}"; do
        local info
        info="$(docker ps -a --filter "name=^${c}$" --format '{{.Names}}  ({{.Status}})' 2>/dev/null || true)"
        if [[ -n "${info}" ]]; then
            found+=("  ${C_RED}✘${C_RESET} ${info}")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        printf '%s\n' "${found[@]}"
    else
        echo -e "  ${C_GREEN}  (ninguno encontrado)${C_RESET}"
    fi
}

enumerate_networks() {
    local found=()
    for n in "${NETWORKS[@]}"; do
        if docker network ls --filter "name=^${n}$" --format '{{.Name}}' 2>/dev/null | grep -q .; then
            found+=("  ${C_RED}✘${C_RESET} ${n}")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        printf '%s\n' "${found[@]}"
    else
        echo -e "  ${C_GREEN}  (ninguna encontrada)${C_RESET}"
    fi
}

enumerate_volumes() {
    local found=()
    for v in "${VOLUMES[@]}"; do
        if docker volume ls --filter "name=^${v}$" --format '{{.Name}}' 2>/dev/null | grep -q .; then
            found+=("  ${C_RED}✘${C_RESET} ${v}")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        printf '%s\n' "${found[@]}"
    else
        echo -e "  ${C_GREEN}  (ninguno encontrado)${C_RESET}"
    fi
}

enumerate_images() {
    local found=()
    for img in "${IMAGES[@]}"; do
        if docker image inspect "${img}" &>/dev/null; then
            found+=("  ${C_RED}✘${C_RESET} ${img}")
        fi
    done
    if [[ ${#found[@]} -gt 0 ]]; then
        printf '%s\n' "${found[@]}"
    else
        echo -e "  ${C_GREEN}  (ninguna encontrada)${C_RESET}"
    fi
}

enumerate_generated_files() {
    local found=()
    for f in "${GENERATED_FILES[@]}"; do
        if [[ -e "${f}" ]]; then
            found+=("  ${C_RED}✘${C_RESET} ${f}")
        fi
    done
    # Archivos de certificados
    if [[ -d "${CERTS_DIR}" ]]; then
        for pat in "${CERT_PATTERNS[@]}"; do
            # shellcheck disable=SC2086
            for f in "${CERTS_DIR}"/${pat}; do
                [[ -e "${f}" ]] && found+=("  ${C_RED}✘${C_RESET} ${f}")
            done
        done
    fi
    if [[ ${#found[@]} -gt 0 ]]; then
        printf '%s\n' "${found[@]}"
    else
        echo -e "  ${C_GREEN}  (ninguno encontrado)${C_RESET}"
    fi
}

# -- ¿Hay algún recurso del stack presente? --
any_resources_exist() {
    local c n v
    c=$(_count_existing "ps -a" "name" "${CONTAINERS[@]}")
    n=$(_count_existing "network ls" "name" "${NETWORKS[@]}")
    v=$(_count_existing "volume ls" "name" "${VOLUMES[@]}")
    if [[ $((c + n + v)) -eq 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# 6. BANNER
# =============================================================================

show_banner() {
    clear 2>/dev/null || true
    echo -e "${C_RED_B}${C_BOLD}"
    cat <<'BANNER'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                         ║
║                  ⚠   DESINSTALADOR  MATRIX  STACK   ⚠                  ║
║                          v5.1.0                                         ║
║                                                                         ║
╚═══════════════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${C_RESET}"
    echo -e "  Proyecto:  ${C_BOLD}${PROJECT_ROOT}${C_RESET}"
    echo -e "  Stack:     ${C_BOLD}${STACK_NAME}${C_RESET}"
    echo -e "  Compose:   ${C_BOLD}${COMPOSE_FILE}${C_RESET}"
    echo -e "  Fecha:     ${C_BOLD}$(date '+%Y-%m-%d %H:%M:%S')${C_RESET}"
    echo ""
}

# =============================================================================
# 7. MENÚ PRINCIPAL
# =============================================================================

show_menu() {
    echo -e "  ${C_BOLD}Seleccione el nivel de eliminación:${C_RESET}"
    echo ""
    echo -e "    ${C_BOLD}1)${C_RESET} Detener y eliminar solo los contenedores"
    echo -e "       ${C_GRAY}Se conservan redes, volúmenes y archivos generados.${C_RESET}"
    echo -e "       ${C_GRAY}Puede reiniciar con: docker compose -p ${STACK_NAME} up -d${C_RESET}"
    echo ""
    echo -e "    ${C_BOLD}2)${C_RESET} Detener y eliminar contenedores y redes"
    echo -e "       ${C_GRAY}Se conservan los volúmenes de datos y archivos generados.${C_RESET}"
    echo -e "       ${C_GRAY}Las redes se recrearán al iniciar de nuevo.${C_RESET}"
    echo ""
    echo -e "    ${C_RED}${C_BOLD}3)${C_RESET}${C_RED} Detener y eliminar contenedores, redes y volúmenes${C_RESET}"
    echo -e "       ${C_RED}⚠  PÉRDIDA DE DATOS: base de datos, caché, configuraciones.${C_RESET}"
    echo -e "       ${C_RED}⚠  Esta operación NO se puede deshacer.${C_RESET}"
    echo ""
    echo -e "    ${C_RED_B}${C_BOLD}4)${C_RESET}${C_RED_B} Eliminación TOTAL (Docker + archivos generados)${C_RESET}"
    echo -e "       ${C_RED_B}⚠  Se eliminan contenedores, redes, volúmenes, .env, certificados${C_RESET}"
    echo -e "       ${C_RED_B}⚠  y la clave de firma de Synapse (signing.key).${C_RESET}"
    echo -e "       ${C_RED_B}⚠  El proyecto quedará en estado completamente inicial.${C_RESET}"
    echo -e "       ${C_RED_B}⚠  Esta operación es IRREVERSIBLE.${C_RESET}"
    echo ""
    echo -e "    ${C_GREEN_B}${C_BOLD}5)${C_RESET}${C_GREEN} Crear respaldo completo y luego eliminar (nivel 3)${C_RESET}"
    echo -e "       ${C_GREEN}Se crea un archivo .tar.gz en ./backups/ antes de eliminar.${C_RESET}"
    echo ""
    echo -e "    ${C_GRAY}    0) Cancelar (no se elimina nada)${C_RESET}"
    echo ""
    echo -ne "  ${C_BOLD}Opción [0-5]: ${C_RESET}"
}

# =============================================================================
# 8. FUNCIONES DE CONFIRMACIÓN
# =============================================================================

# Confirmación simple: s/N
confirm_yes() {
    local msg="${1:-¿Desea continuar?}"
    echo -ne "  ${C_YELLOW_B}${msg} [s/N]: ${C_RESET}"
    local resp
    read -r resp
    case "${resp}" in
        s|S|sí|Sí|SÍ|si|Si|SI|y|Y|yes|Yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# Doble confirmación + palabra clave "ELIMINAR"
confirm_eliminar() {
    local msg="${1:-¿Está seguro?}"

    # -- Primera confirmación: simple --
    echo ""
    echo -ne "  ${C_RED_B}${C_BOLD}⚠  PRIMERA CONFIRMACIÓN${C_RESET}"
    echo ""
    if ! confirm_yes "${msg}"; then
        return 1
    fi

    echo ""
    # -- Segunda confirmación: escribir ELIMINAR --
    echo -e "  ${C_RED_B}${C_BOLD}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "  ${C_RED_B}${C_BOLD}║                                                               ║${C_RESET}"
    echo -e "  ${C_RED_B}${C_BOLD}║  SEGUNDA CONFIRMACIÓN — escriba ELIMINAR para proceder        ║${C_RESET}"
    echo -e "  ${C_RED_B}${C_BOLD}║  Cualquier otra entrada cancelará la operación.               ║${C_RESET}"
    echo -e "  ${C_RED_B}${C_BOLD}║                                                               ║${C_RESET}"
    echo -e "  ${C_RED_B}${C_BOLD}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -ne "  ${C_RED_B}${C_BOLD}Escriba ELIMINAR para confirmar: ${C_RESET}"
    local resp
    read -r resp
    if [[ "${resp}" == "ELIMINAR" ]]; then
        return 0
    fi
    echo -e "  ${C_YELLOW}  No se escribió «ELIMINAR». Operación cancelada de forma segura.${C_RESET}"
    return 1
}

# =============================================================================
# 9. FUNCIONES DE ELIMINACIÓN (operaciones Docker reutilizables)
# =============================================================================

remove_containers() {
    echo -e "  ${C_DIM}── Eliminando contenedores ──${C_RESET}"

    # Intentar primero con docker compose (más limpio)
    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down --remove-orphans 2>/dev/null; then
        echo -e "  ${C_GREEN}✔ docker compose down ejecutado correctamente.${C_RESET}"
    else
        echo -e "  ${C_YELLOW}⚠ docker compose down falló, usando método manual...${C_RESET}"
        for c in "${CONTAINERS[@]}"; do
            if docker ps -a --filter "name=^${c}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
                echo -e "    Deteniendo/eliminando: ${c}"
                docker rm -f "${c}" 2>/dev/null || true
            fi
        done
    fi
}

remove_networks() {
    echo -e "  ${C_DIM}── Eliminando redes ──${C_RESET}"
    for n in "${NETWORKS[@]}"; do
        if docker network ls --filter "name=^${n}$" --format '{{.Name}}' 2>/dev/null | grep -q .; then
            echo -e "    Eliminando red: ${n}"
            docker network rm "${n}" 2>/dev/null || true
        fi
    done
}

remove_volumes() {
    echo -e "  ${C_DIM}── Eliminando volúmenes ──${C_RESET}"
    # Primero intentar con docker compose down -v
    if docker compose -f "${COMPOSE_FILE}" -p "${STACK_NAME}" down -v --remove-orphans 2>/dev/null; then
        echo -e "  ${C_GREEN}✔ docker compose down -v ejecutado correctamente.${C_RESET}"
    fi
    # Limpieza manual de volúmenes residuales (por si compose no los gestiona)
    for v in "${VOLUMES[@]}"; do
        if docker volume ls --filter "name=^${v}$" --format '{{.Name}}' 2>/dev/null | grep -q .; then
            echo -e "    Eliminando volumen: ${v}"
            docker volume rm "${v}" 2>/dev/null || true
        fi
    done
}

remove_images() {
    echo -e "  ${C_DIM}── Eliminando imágenes personalizadas ──${C_RESET}"
    for img in "${IMAGES[@]}"; do
        if docker image inspect "${img}" &>/dev/null; then
            echo -e "    Eliminando imagen: ${img}"
            docker image rm "${img}" 2>/dev/null || true
        fi
    done
}

remove_generated_files() {
    echo -e "  ${C_DIM}── Eliminando archivos generados ──${C_RESET}"

    for f in "${GENERATED_FILES[@]}"; do
        if [[ -e "${f}" ]]; then
            echo -e "    Eliminando: ${f}"
            rm -f "${f}" 2>/dev/null || true
        fi
    done

    # Eliminar archivos de certificados
    if [[ -d "${CERTS_DIR}" ]]; then
        for pat in "${CERT_PATTERNS[@]}"; do
            # shellcheck disable=SC2086
            for f in "${CERTS_DIR}"/${pat}; do
                if [[ -e "${f}" ]]; then
                    echo -e "    Eliminando: ${f}"
                    rm -f "${f}" 2>/dev/null || true
                fi
            done
        done
        # Si el directorio de certs quedó vacío, eliminarlo
        if [[ -d "${CERTS_DIR}" ]] && [[ -z "$(ls -A "${CERTS_DIR}" 2>/dev/null)" ]]; then
            rmdir "${CERTS_DIR}" 2>/dev/null || true
            echo -e "    Directorio vacío eliminado: ${CERTS_DIR}"
        fi
    fi
}

# =============================================================================
# 10. CREAR RESPALDO COMPLETO (opción 5)
# =============================================================================

create_backup() {
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_name="matrix-backup-${timestamp}.tar.gz"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    local tmp_manifest

    mkdir -p "${BACKUP_DIR}" 2>/dev/null || true

    echo -e "  ${C_BOLD}Creando respaldo completo del stack...${C_RESET}"
    echo ""

    # -- Paso 1: Volcar volúmenes de Docker a archivos temporales --
    local dump_dir="${BACKUP_DIR}/.dump-${timestamp}"
    mkdir -p "${dump_dir}" 2>/dev/null || true

    echo -e "  ${C_DIM}[1/3] Exportando volúmenes Docker...${C_RESET}"
    for v in "${VOLUMES[@]}"; do
        if docker volume ls --filter "name=^${v}$" --format '{{.Name}}' 2>/dev/null | grep -q .; then
            local safe_name
            safe_name="${v//[^a-zA-Z0-9_]/_}"
            echo -e "    Exportando volumen: ${v} → ${safe_name}.tar"
            docker run --rm \
                -v "${v}:/source:ro" \
                -v "${dump_dir}:/backup" \
                alpine tar czf "/backup/${safe_name}.tar.gz" -C /source . 2>/dev/null || true
        fi
    done

    # -- Paso 2: Recopilar archivos del proyecto --
    echo -e "  ${C_DIM}[2/3] Empaquetando archivos del proyecto...${C_RESET}"

    local tar_args=()

    # .env
    [[ -f "${PROJECT_ROOT}/.env" ]] && tar_args+=("${PROJECT_ROOT}/.env")

    # Clave de firma
    [[ -f "${PROJECT_ROOT}/synapse/signing.key" ]] && tar_args+=("${PROJECT_ROOT}/synapse/signing.key")

    # Certificados
    if [[ -d "${CERTS_DIR}" ]] && [[ -n "$(ls -A "${CERTS_DIR}" 2>/dev/null)" ]]; then
        tar_args+=("${CERTS_DIR}")
    fi

    # Volúmenes exportados
    if [[ -d "${dump_dir}" ]] && [[ -n "$(ls -A "${dump_dir}" 2>/dev/null)" ]]; then
        tar_args+=("${dump_dir}")
    fi

    if [[ ${#tar_args[@]} -gt 0 ]]; then
        tar czf "${backup_path}" \
            --transform="s,^${PROJECT_ROOT}/,," \
            "${tar_args[@]}" 2>/dev/null || true
    else
        # Crear un manifiesto mínimo aunque no haya archivos
        tmp_manifest="${BACKUP_DIR}/.manifest-${timestamp}.txt"
        {
            echo "# Manifiesto de respaldo Matrix Stack"
            echo "# Fecha: $(date -Iseconds)"
            echo "# Proyecto: ${PROJECT_ROOT}"
            echo "# Stack: ${STACK_NAME}"
            echo "# Nota: No se encontraron archivos para respaldar."
        } > "${tmp_manifest}"
        tar czf "${backup_path}" \
            --transform="s,^${BACKUP_DIR}/,," \
            "${tmp_manifest}" 2>/dev/null || true
        rm -f "${tmp_manifest}" 2>/dev/null || true
    fi

    # -- Paso 3: Limpiar temporales y mostrar resultado --
    echo -e "  ${C_DIM}[3/3] Limpiando archivos temporales...${C_RESET}"
    rm -rf "${dump_dir}" 2>/dev/null || true

    if [[ -f "${backup_path}" ]]; then
        local size
        size="$(du -h "${backup_path}" 2>/dev/null | cut -f1)"
        echo ""
        echo -e "  ${C_GREEN_B}✔ Respaldo creado con éxito:${C_RESET}"
        echo -e "    ${C_BOLD}${backup_path}${C_RESET}"
        echo -e "    Tamaño: ${C_BOLD}${size}${C_RESET}"
        echo ""
        return 0
    else
        echo ""
        echo -e "  ${C_RED}✘ No se pudo crear el archivo de respaldo.${C_RESET}"
        echo ""
        return 1
    fi
}

# =============================================================================
# 11. OPCIONES DEL MENÚ
# =============================================================================

# -----------------------------------------------------------------------
# OPCIÓN 1: Solo contenedores
# -----------------------------------------------------------------------
do_option_1() {
    echo ""
    echo -e "  ${C_BOLD}═══ OPCIÓN 1: Eliminar solo contenedores ═══${C_RESET}"
    echo ""
    echo -e "  ${C_YELLOW}Se detendrán y eliminarán los siguientes contenedores:${C_RESET}"
    echo ""
    enumerate_containers
    echo ""
    echo -e "  ${C_GREEN}Se conservarán:${C_RESET} redes, volúmenes, imágenes y archivos generados."
    echo ""

    if ! confirm_yes "¿Desea eliminar los contenedores?"; then
        echo -e "  ${C_GRAY}Operación cancelada. No se eliminó nada.${C_RESET}"
        return 0
    fi

    echo ""
    remove_containers

    echo ""
    echo -e "  ${C_GREEN}✔ Contenedores eliminados correctamente.${C_RESET}"
    echo -e "  ${C_GRAY}Puede reiniciar con: docker compose -p ${STACK_NAME} up -d${C_RESET}"
}

# -----------------------------------------------------------------------
# OPCIÓN 2: Contenedores + redes
# -----------------------------------------------------------------------
do_option_2() {
    echo ""
    echo -e "  ${C_BOLD}═══ OPCIÓN 2: Eliminar contenedores y redes ═══${C_RESET}"
    echo ""
    echo -e "  ${C_YELLOW}Se eliminarán:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}Contenedores:${C_RESET}"
    enumerate_containers
    echo ""
    echo -e "  ${C_BOLD}Redes:${C_RESET}"
    enumerate_networks
    echo ""
    echo -e "  ${C_GREEN}Se conservarán:${C_RESET} volúmenes, imágenes y archivos generados."
    echo ""

    if ! confirm_yes "¿Desea eliminar contenedores y redes?"; then
        echo -e "  ${C_GRAY}Operación cancelada. No se eliminó nada.${C_RESET}"
        return 0
    fi

    echo ""
    remove_containers
    echo ""
    remove_networks

    echo ""
    echo -e "  ${C_GREEN}✔ Contenedores y redes eliminados correctamente.${C_RESET}"
    echo -e "  ${C_GRAY}Los volúmenes se conservan. Puede reinstalar reutilizando los datos.${C_RESET}"
}

# -----------------------------------------------------------------------
# OPCIÓN 3: Contenedores + redes + volúmenes (PÉRDIDA DE DATOS)
# -----------------------------------------------------------------------
do_option_3() {
    echo ""
    echo -e "  ${C_RED_B}${C_BOLD}═══ OPCIÓN 3: Eliminar contenedores, redes y VOLÚMENES ═══${C_RESET}"
    echo ""
    echo -e "  ${C_RED}╔════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "  ${C_RED}║  ⚠  ESTO ELIMINARÁ TODOS LOS DATOS DEL STACK MATRIX              ║${C_RESET}"
    echo -e "  ${C_RED}║     (base de datos PostgreSQL, caché Redis, configuraciones)      ║${C_RESET}"
    echo -e "  ${C_RED}╚════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  ${C_RED}Se eliminarán:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}Contenedores:${C_RESET}"
    enumerate_containers
    echo ""
    echo -e "  ${C_BOLD}Redes:${C_RESET}"
    enumerate_networks
    echo ""
    echo -e "  ${C_RED}${C_BOLD}Volúmenes (DATOS):${C_RESET}"
    enumerate_volumes
    echo ""
    echo -e "  ${C_RED}⚠  Los archivos generados (.env, certificados, signing.key) se conservarán.${C_RESET}"
    echo ""

    if ! confirm_eliminar "¿Está SEGURO de que desea eliminar TODOS LOS DATOS del stack?"; then
        echo -e "  ${C_GREEN}✔ Operación cancelada. Sus datos están intactos.${C_RESET}"
        return 0
    fi

    echo ""
    remove_containers
    echo ""
    remove_networks
    echo ""
    remove_volumes

    echo ""
    echo -e "  ${C_GREEN}✔ Stack eliminado completamente de Docker.${C_RESET}"
    echo -e "  ${C_GRAY}Los archivos del proyecto se conservaron (.env, certificados, signing.key).${C_RESET}"
    echo -e "  ${C_GRAY}Para reinstalar: configure .env y ejecute docker compose -p ${STACK_NAME} up -d${C_RESET}"
}

# -----------------------------------------------------------------------
# OPCIÓN 4: Eliminación TOTAL
# -----------------------------------------------------------------------
do_option_4() {
    echo ""
    echo -e "  ${C_RED_B}${C_BOLD}═══ OPCIÓN 4: ELIMINACIÓN TOTAL DEL PROYECTO ═══${C_RESET}"
    echo ""
    echo -e "  ${C_RED_B}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "  ${C_RED_B}║                                                                      ║${C_RESET}"
    echo -e "  ${C_RED_B}║  ⚠⚠⚠   ESTO ELIMINARÁ ABSOLUTAMENTE TODO   ⚠⚠⚠                   ║${C_RESET}"
    echo -e "  ${C_RED_B}║                                                                      ║${C_RESET}"
    echo -e "  ${C_RED_B}║  Se eliminará:                                                       ║${C_RESET}"
    echo -e "  ${C_RED_B}║    • Todos los contenedores, redes y volúmenes de Docker             ║${C_RESET}"
    echo -e "  ${C_RED_B}║    • Imágenes personalizadas (matrix-synapse:custom, etc.)           ║${C_RESET}"
    echo -e "  ${C_RED_B}║    • Archivo .env con todas las configuraciones y secretos           ║${C_RESET}"
    echo -e "  ${C_RED_B}║    • Certificados SSL/TLS del directorio nginx/certs/                ║${C_RESET}"
    echo -e "  ${C_RED_B}║    • Clave de firma de Synapse (synapse/signing.key)                 ║${C_RESET}"
    echo -e "  ${C_RED_B}║                                                                      ║${C_RESET}"
    echo -e "  ${C_RED_B}║  Esta operación es IRREVERSIBLE.                                     ║${C_RESET}"
    echo -e "  ${C_RED_B}║                                                                      ║${C_RESET}"
    echo -e "  ${C_RED_B}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  ${C_RED_B}Detalle de lo que se eliminará:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}Contenedores:${C_RESET}"
    enumerate_containers
    echo ""
    echo -e "  ${C_BOLD}Redes:${C_RESET}"
    enumerate_networks
    echo ""
    echo -e "  ${C_RED}${C_BOLD}Volúmenes:${C_RESET}"
    enumerate_volumes
    echo ""
    echo -e "  ${C_BOLD}Imágenes personalizadas:${C_RESET}"
    enumerate_images
    echo ""
    echo -e "  ${C_RED}${C_BOLD}Archivos generados:${C_RESET}"
    enumerate_generated_files
    echo ""

    if ! confirm_eliminar "¿Está ABSOLUTAMENTE SEGURO de que desea eliminar TODO el proyecto?"; then
        echo -e "  ${C_GREEN}✔ Operación cancelada. Nada fue eliminado.${C_RESET}"
        return 0
    fi

    echo ""

    # Paso 1: Recursos Docker
    echo -e "  ${C_BOLD}Paso 1/4: Eliminando contenedores...${C_RESET}"
    remove_containers
    echo ""

    echo -e "  ${C_BOLD}Paso 2/4: Eliminando redes...${C_RESET}"
    remove_networks
    echo ""

    echo -e "  ${C_BOLD}Paso 3/4: Eliminando volúmenes...${C_RESET}"
    remove_volumes
    echo ""

    echo -e "  ${C_BOLD}Paso 4/4: Eliminando imágenes personalizadas...${C_RESET}"
    remove_images
    echo ""

    echo -e "  ${C_BOLD}Paso 5/5: Eliminando archivos generados...${C_RESET}"
    remove_generated_files
    echo ""

    echo -e "  ${C_GREEN}✔ Eliminación TOTAL completada.${C_RESET}"
    echo -e "  ${C_GRAY}El proyecto quedó en estado completamente inicial.${C_RESET}"
    echo -e "  ${C_GRAY}Para reinstalar desde cero: ejecute install.sh${C_RESET}"
}

# -----------------------------------------------------------------------
# OPCIÓN 5: Respaldo → luego opción 3
# -----------------------------------------------------------------------
do_option_5() {
    echo ""
    echo -e "  ${C_GREEN_B}${C_BOLD}═══ OPCIÓN 5: Respaldo completo → Eliminación (nivel 3) ═══${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}Se realizará lo siguiente:${C_RESET}"
    echo -e "    1. Crear un archivo .tar.gz con todos los datos en ${C_BOLD}${BACKUP_DIR}/${C_RESET}"
    echo -e "    2. Luego ejecutar la eliminación de nivel 3 (contenedores + redes + volúmenes)"
    echo ""
    echo -e "  ${C_YELLOW}Se respaldará:${C_RESET}"
    echo ""
    echo -e "    ${C_BOLD}Volúmenes Docker:${C_RESET}"
    enumerate_volumes
    echo ""
    echo -e "    ${C_BOLD}Archivos generados:${C_RESET}"
    enumerate_generated_files
    echo ""

    if ! confirm_yes "¿Desea crear el respaldo y luego eliminar los datos?"; then
        echo -e "  ${C_GRAY}Operación cancelada. No se eliminó nada.${C_RESET}"
        return 0
    fi

    echo ""

    # -- Crear respaldo --
    if ! create_backup; then
        echo -e "  ${C_RED}✘ Error al crear el respaldo.${C_RESET}"
        echo ""
        if ! confirm_yes "¿Desea continuar con la eliminación SIN respaldo?"; then
            echo -e "  ${C_GRAY}Operación cancelada. Sus datos están intactos.${C_RESET}"
            return 0
        fi
        echo -e "  ${C_YELLOW}⚠ Continuando sin respaldo...${C_RESET}"
        echo ""
    fi

    # -- Ejecutar nivel 3 (sin volver a mostrar el menú) --
    echo -e "  ${C_YELLOW_B}${C_BOLD}── Procediendo con eliminación nivel 3 ──${C_RESET}"

    # Mostrar lo que se va a eliminar
    echo ""
    echo -e "  ${C_RED}Se eliminarán ahora:${C_RESET}"
    enumerate_containers
    enumerate_networks
    enumerate_volumes
    echo ""

    if ! confirm_eliminar "¿Confirma la eliminación de todos los datos del stack?"; then
        echo -e "  ${C_GREEN}✔ Operación cancelada. Sus datos y el respaldo están intactos.${C_RESET}"
        return 0
    fi

    echo ""
    remove_containers
    echo ""
    remove_networks
    echo ""
    remove_volumes

    echo ""
    echo -e "  ${C_GREEN}✔ Eliminación completada. El respaldo fue guardado correctamente.${C_RESET}"
    echo -e "  ${C_GRAY}Para restaurar, extraiga el archivo .tar.gz del directorio backups/.${C_RESET}"
}

# =============================================================================
# 12. PROGRAMA PRINCIPAL
# =============================================================================

# -- Verificar Docker --
check_docker

# -- Mostrar banner --
show_banner

# -- Mostrar estado actual de los recursos --
echo -e "  ${C_BOLD}Estado actual de los recursos del stack:${C_RESET}"
echo ""
echo -e "  ${C_BOLD}Contenedores:${C_RESET}"
enumerate_containers
echo ""
echo -e "  ${C_BOLD}Redes:${C_RESET}"
enumerate_networks
echo ""
echo -e "  ${C_BOLD}Volúmenes:${C_RESET}"
enumerate_volumes
echo ""

# Si no hay recursos Docker, informar pero permitir opciones 4 y 5
if ! any_resources_exist; then
    echo -e "  ${C_YELLOW}⚠  No se encontraron recursos activos de Docker para este stack.${C_RESET}"
    echo -e "  ${C_GRAY}Aún puede usar la opción 4 para limpiar archivos generados,${C_RESET}"
    echo -e "  ${C_GRAY}o la opción 5 para crear un respaldo de los archivos existentes.${C_RESET}"
    echo ""
fi

# -- Mostrar menú y leer opción --
show_menu
read -r opcion

# -- Ejecutar la opción seleccionada --
case "${opcion}" in
    1)
        do_option_1
        ;;
    2)
        do_option_2
        ;;
    3)
        do_option_3
        ;;
    4)
        do_option_4
        ;;
    5)
        do_option_5
        ;;
    0|"")
        echo ""
        echo -e "  ${C_GRAY}Operación cancelada por el usuario. No se eliminó nada.${C_RESET}"
        ;;
    *)
        echo ""
        echo -e "  ${C_RED}✘ Opción no válida: «${opcion}»${C_RESET}"
        echo -e "  ${C_GRAY}Seleccione un número del 0 al 5.${C_RESET}"
        exit 1
        ;;
esac

echo ""
echo -e "  ${C_GRAY}─────────────────────────────────────────────────────────────────────${C_RESET}"
echo ""
exit 0