#!/usr/bin/env bash
# =============================================================================
# install.sh - Instalador completo de Matrix Docker Stack v5.0.0
# -----------------------------------------------------------------------------
# Instalacion de un solo comando para Matrix Synapse + PostgreSQL + Redis +
# Element Web + Nginx en entornos LAN privados.
#
# Uso:
#   sudo ./install.sh
#
# Compatible con: Ubuntu 22.04/24.04 LTS, Debian 11+, Raspberry Pi OS 64-bit
# Arquitecturas: AMD64 (x86_64), ARM64 (aarch64)
#
# Este script realiza:
#   1. Validacion de sistema operativo y arquitectura
#   2. Validacion de recursos (disco, RAM, swap)
#   3. Validacion de Docker y Docker Compose
#   4. Validacion de puertos disponibles
#   5. Instalacion de dependencias faltantes
#   6. Deteccion automatica de IP LAN y Tailscale
#   7. Seleccion de IP por el usuario
#   8. Generacion de .env con secretos criptograficos
#   9. Generacion de signing.key
#  10. Generacion de certificados TLS
#  11. Validacion de permisos y archivos
#  12. Construccion de imagenes personalizadas
#  13. Despliegue del stack
#  14. Verificacion de servicios + pruebas automaticas
#  15. Resumen final
#
# Licencia: Apache-2.0
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Ruta base del proyecto
# -----------------------------------------------------------------------------
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${INSTALL_DIR}/lib"
source "${LIB_DIR}/install-utils.sh"

# -----------------------------------------------------------------------------
# Colores (solo si stdout es una terminal)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
    C='\033[0;36m' BD='\033[1m' D='\033[2m' NC='\033[0m'
else
    R='' G='' Y='' B='' C='' BD='' D='' NC=''
fi

# -----------------------------------------------------------------------------
# Funciones de output
# -----------------------------------------------------------------------------
log()    { echo -e "${G}[$(date '+%H:%M:%S')] [INFO]${NC}  $*"; }
warn()   { echo -e "${Y}[$(date '+%H:%M:%S')] [WARN]${NC}  $*" >&2; }
error()  { echo -e "${R}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" >&2; }
fatal()  { echo -e "${R}[$(date '+%H:%M:%S')] [FATAL]${NC} $*" >&2; exit 1; }
step()   { echo; echo -e "${B}${BD}--- Paso $1/$2: $3 ---${NC}"; }
ok()     { echo -e "${G}  [OK]${NC} $*"; }
fail()   { echo -e "${R}  [FALLO]${NC} $*"; }
skip()   { echo -e "${Y}  [SKIP]${NC} $*"; }

TOTAL_STEPS=14

banner() {
    echo
    cat <<'BANNER'

  __  __ _       _     _              ____
 |  \/  (_) __ _| | __| |   _ __ ___ |___ \
 | |\/| | |/ _` | |/ _` |  | '_ ` _ \  __) |
 | |  | | | (_| | | (_| |  | | | | | |/ __/
 |_|  |_|_|\__,_|_|\__,_|  |_| |_| |_|_____|

BANNER
    echo -e "${C}  Matrix Synapse Docker Stack - Instalador Automatico${NC}"
    echo -e "${C}  Version 5.0.0 | LAN Privada | Tailscale Ready${NC}"
    echo -e "${C}  Compatible: Ubuntu 22.04/24.04, Debian 11+, Raspberry Pi OS${NC}"
    echo
}

# =============================================================================
# PASO 1: Sistema operativo y arquitectura
# =============================================================================
validate_system() {
    step "1" "${TOTAL_STEPS}" "Validando sistema operativo y arquitectura"

    # Verificar que no estamos en un contenedor Docker (no tiene sentido)
    if [[ -f /.dockerenv ]]; then
        warn "Parece que este script se esta ejecutando dentro de un contenedor Docker."
        warn "Este instalador esta disenado para ejecutarse en el host."
        read -rp "¿Continuar de todos modos? [s/N]: " confirm
        if [[ ! "${confirm}" =~ ^[SsYy] ]]; then
            fatal "Instalacion cancelada."
        fi
    fi

    # Arquitectura
    local arch
    if ! arch=$(check_architecture); then
        local bad_arch="${arch#*:}"
        error "Arquitectura no soportada: ${bad_arch}"
        fatal "Se requiere x86_64 (amd64) o ARM64 (aarch64)."
    fi
    ok "Arquitectura: ${arch}"

    # SO
    local os_info
    if ! os_info=$(check_os); then
        local os_id="${os_info%%:*}"
        local os_ver="${os_info#*:}"
        error "Sistema operativo no soportado: ${os_id} ${os_ver}"
        fatal "Se requiere Ubuntu 22.04+ o Debian 11+ o Raspberry Pi OS 64-bit."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    ok "Sistema: ${PRETTY_NAME:-${os_info}}"

    # Verificar kernel minimo (5.4 para soporte adecuado de Docker)
    local kernel_major kernel_minor
    kernel_major=$(uname -r | awk -F. '{print $1}')
    kernel_minor=$(uname -r | awk -F. '{print $2}')
    if (( kernel_major < 5 )); then
        warn "Kernel version $(uname -r) es anterior a 5.4. Docker puede tener limitaciones."
    else
        ok "Kernel: $(uname -r)"
    fi

    # Permisos de root
    if [[ $EUID -ne 0 ]]; then
        warn "No se ejecuta como root. No se podran instalar dependencias faltantes."
        warn "Si falta alguna dependencia, la instalacion fallara."
        warn "Ejecuta: sudo ./install.sh"
        # No es fatal - podemos continuar si todo esta instalado
    else
        ok "Permisos de root (sudo)"
    fi
}

# =============================================================================
# PASO 2: Recursos del sistema
# =============================================================================
validate_resources() {
    step "2" "${TOTAL_STEPS}" "Validando recursos del sistema"

    # Disco
    local disk_result
    disk_result=$(check_disk_space "${INSTALL_DIR}")
    if [[ "${disk_result}" == INSUFICIENTE:* ]]; then
        local available_gb="${disk_result#*:}"
        error "Espacio en disco insuficiente: ${available_gb} GB disponibles."
        fatal "Se requieren al menos 5 GB. Libera espacio o usa otro disco."
    fi
    local disk_gb="${disk_result#*:}"
    ok "Espacio en disco: ${disk_gb} GB disponibles"

    # RAM
    local mem_result
    mem_result=$(check_memory)
    if [[ "${mem_result}" == INSUFICIENTE:* ]]; then
        local mem_mb="${mem_result#*:}"
        error "Memoria RAM insuficiente: ${mem_mb} MB."
        fatal "Se requieren al menos 2048 MB (2 GB). Se recomiendan 4 GB."
    fi
    if [[ "${mem_result}" == "UNKNOWN" ]]; then
        warn "No se pudo detectar la memoria RAM. Continuando..."
    else
        local mem_mb="${mem_result#*:}"
        ok "Memoria RAM: ${mem_mb} MB"
    fi

    # Swap (recomendado para Raspberry Pi)
    local swap_kb
    swap_kb=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -n "${swap_kb}" ]] && (( swap_kb > 0 )); then
        local swap_mb=$((swap_kb / 1024))
        ok "Swap: ${swap_mb} MB"
    else
        warn "No se detecto swap. Recomendado para Raspberry Pi o hosts con poca RAM."
        warn "Para crear swap: sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    fi

    # CPU cores
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "desconocido")
    ok "CPU cores: ${cpu_cores}"
}

# =============================================================================
# PASO 3: Docker y Docker Compose
# =============================================================================
validate_docker() {
    step "3" "${TOTAL_STEPS}" "Validando Docker y Docker Compose"

    # Docker daemon
    if docker info >/dev/null 2>&1; then
        ok "Docker daemon corriendo"

        # Version de Docker
        local docker_ver
        docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "desconocida")
        ok "Docker version: ${docker_ver}"

        # Verificar que Docker Compose este disponible (como plugin v2)
        if docker compose version >/dev/null 2>&1; then
            local compose_ver
            compose_ver=$(docker compose version --short 2>/dev/null || echo "desconocida")
            ok "Docker Compose: v${compose_ver}"
        elif command -v docker-compose >/dev/null 2>&1; then
            error "Se detecto docker-compose v1 (standalone)."
            error "Este proyecto requiere Docker Compose v2 (plugin)."
            fatal "Instala el plugin: sudo apt-get install docker-compose-plugin"
        else
            error "Docker Compose no esta instalado."
            fatal "Instala: sudo apt-get install docker-compose-plugin"
        fi

        # Verificar storage driver
        local storage_driver
        storage_driver=$(docker info -f '{{.Driver}}' 2>/dev/null || echo "desconocido")
        ok "Storage driver: ${storage_driver}"

        # Verificar que no haya contenedores conflictivos corriendo
        check_conflicting_containers
    else
        error "Docker daemon no esta corriendo."
        if [[ $EUID -eq 0 ]]; then
            log "Intentando iniciar Docker..."
            systemctl enable --now docker >/dev/null 2>&1 || true
            sleep 3
            if docker info >/dev/null 2>&1; then
                ok "Docker daemon iniciado correctamente"
            else
                fatal "No se pudo iniciar Docker. Revisa: systemctl status docker"
            fi
        else
            fatal "Ejecuta con sudo: sudo ./install.sh"
        fi
    fi
}

check_conflicting_containers() {
    local conflicting=0
    for name in matrix-postgres matrix-redis matrix-synapse matrix-nginx matrix-element; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            warn "Contenedor existente: ${name} (ya esta corriendo)"
            conflicting=$((conflicting + 1))
        fi
    done
    if [[ ${conflicting} -gt 0 ]]; then
        echo
        warn "Se encontraron ${conflicting} contenedores del stack ya corriendo."
        read -rp "¿Deseas detenerlos y reinstalar? [s/N]: " confirm
        if [[ "${confirm}" =~ ^[SsYy] ]]; then
            log "Deteniendo stack existente..."
            (cd "${INSTALL_DIR}" && docker compose down --remove-orphans 2>/dev/null) || true
            ok "Stack anterior detenido"
        else
            fatal "Instalacion cancelada. Los contenedores existentes no fueron modificados."
        fi
    fi
}

# =============================================================================
# PASO 4: Puertos
# =============================================================================
validate_ports() {
    step "4" "${TOTAL_STEPS}" "Validando puertos disponibles"

    local http_port="${NGINX_HTTP_PORT:-80}"
    local https_port="${NGINX_HTTPS_PORT:-443}"
    local ports_ok=true

    # Cargar .env existente si hay para leer los puertos
    if [[ -f "${INSTALL_DIR}/.env" ]]; then
        # shellcheck disable=SC1090
        source "${INSTALL_DIR}/.env" 2>/dev/null || true
        http_port="${NGINX_HTTP_PORT:-80}"
        https_port="${NGINX_HTTPS_PORT:-443}"
    fi

    # Verificar puertos con ss o netstat
    for port_info in "${http_port}:HTTP" "${https_port}:HTTPS"; do
        local port="${port_info%%:*}"
        local desc="${port_info##*:}"
        if command -v ss >/dev/null 2>&1; then
            if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                # Verificar si es nuestro propio nginx
                local pid
                pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K[0-9]+' | head -1)
                if [[ -n "${pid}" ]]; then
                    local proc_name
                    proc_name=$(cat "/proc/${pid}/comm" 2>/dev/null || echo "")
                    if [[ "${proc_name}" == "nginx" ]]; then
                        warn "Puerto ${port} (${desc}) usado por nginx (posiblemente del stack anterior)"
                        continue
                    fi
                fi
                fail "Puerto ${port} (${desc}) en uso por otro proceso"
                error "   Solucion: sudo lsof -i :${port}  # para identificar el proceso"
                error "   O cambia NGINX_HTTP_PORT / NGINX_HTTPS_PORT en .env"
                ports_ok=false
            else
                ok "Puerto ${port} (${desc}) disponible"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
                fail "Puerto ${port} (${desc}) en uso"
                ports_ok=false
            else
                ok "Puerto ${port} (${desc}) disponible"
            fi
        else
            warn "No se encontraron ss ni netstat. No se pueden verificar puertos."
            break
        fi
    done

    if [[ "${ports_ok}" == "false" ]]; then
        fatal "Hay puertos en uso. Liberalos antes de continuar."
    fi
}

# =============================================================================
# PASO 5: Dependencias del sistema
# =============================================================================
validate_dependencies() {
    step "5" "${TOTAL_STEPS}" "Instalando dependencias faltantes"

    local deps_ok=true

    for cmd in openssl curl ip; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            ok "${cmd}"
        else
            fail "${cmd} no encontrado"
            deps_ok=false
        fi
    done

    # git es opcional (no se requiere para la instalacion)
    if command -v git >/dev/null 2>&1; then
        ok "git"
    else
        warn "git no encontrado (opcional, no requerido para la instalacion)"
    fi

    # xxd es necesario para generar la signing key (fallback)
    if command -v xxd >/dev/null 2>&1; then
        ok "xxd"
    else
        fail "xxd no encontrado (paquete xxd o vim-common)"
        deps_ok=false
    fi

    if [[ "${deps_ok}" == "false" ]]; then
        if [[ $EUID -ne 0 ]]; then
            fatal "Faltan dependencias y no hay permisos de root. Ejecuta: sudo ./install.sh"
        fi

        local install_result
        install_result=$(install_dependencies)
        if [[ "${install_result}" == INSTALAR:* ]]; then
            local packages="${install_result#*:}"
            log "Instalando dependencias: ${packages}"
            # shellcheck disable=SC2086
            apt-get update -qq && apt-get install -y -qq ${packages} >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                fatal "Error al instalar dependencias. Revisa la conexion a Internet."
            fi
            ok "Dependencias instaladas"

            # Verificar de nuevo
            for cmd in openssl curl ip xxd; do
                if command -v "${cmd}" >/dev/null 2>&1; then
                    ok "${cmd} verificado"
                else
                    fatal "${cmd} no se pudo instalar. Instalalo manualmente: apt-get install ${cmd}"
                fi
            done
        fi
    fi
}

# =============================================================================
# PASO 6: Deteccion de IP
# =============================================================================
detect_ip_address() {
    step "6" "${TOTAL_STEPS}" "Detectando direccion IP"

    local lan_ip=""
    local ts_ip=""

    # Detectar LAN
    if lan_ip=$(detect_lan_ip); then
        ok "IP LAN detectada: ${lan_ip}"
    else
        warn "No se pudo detectar la IP LAN automaticamente"
    fi

    # Detectar Tailscale
    if ts_ip=$(detect_tailscale_ip); then
        ok "IP Tailscale detectada: ${ts_ip}"
    else
        log "Tailscale no instalado o no conectado"
    fi

    # Listar todas las interfaces para contexto
    echo
    log "Interfaces de red disponibles:"
    ip -4 addr show 2>/dev/null | grep -oP 'inet \K[0-9]+(\.[0-9]+){3}' | while read -r iface_ip; do
        if is_private_ipv4 "${iface_ip}" 2>/dev/null; then
            echo -e "  ${C}${iface_ip}${NC}"
        fi
    done || true
    echo

    # Seleccion de IP
    local selected_ip=""
    if [[ -n "${lan_ip}" && -z "${ts_ip}" ]]; then
        log "IP LAN detectada: ${lan_ip}"
        read -rp "¿Desea utilizar esta IP? [S/n]: " confirm
        if [[ "${confirm}" =~ ^[Nn] ]]; then
            selected_ip=""
        else
            selected_ip="${lan_ip}"
        fi
    elif [[ -n "${lan_ip}" && -n "${ts_ip}" ]]; then
        log "Se detectaron multiples IP:"
        log "  1) LAN:      ${lan_ip}"
        log "  2) Tailscale: ${ts_ip}"
        echo
        read -rp "¿Cual desea utilizar? [1]: " choice
        case "${choice}" in
            2) selected_ip="${ts_ip}" ;;
            *) selected_ip="${lan_ip}" ;;
        esac
    fi

    # Si no se pudo detectar, pedir manualmente
    if [[ -z "${selected_ip}" ]]; then
        echo
        warn "No se pudo detectar automaticamente la IP."
        while true; do
            read -rp "Ingrese la IP del servidor (ej: 192.168.1.100): " selected_ip
            if [[ -z "${selected_ip}" ]]; then
                error "La IP no puede estar vacia."
                continue
            fi
            local validation
            validation=$(validate_ip "${selected_ip}")
            if [[ "${validation}" == "OK" ]]; then
                break
            else
                local reason="${validation#*:}"
                error "IP invalida: ${reason}. Intente de nuevo."
                error "La IP debe ser privada (RFC 1918): 10.x.x.x, 172.16-31.x.x, 192.168.x.x"
            fi
        done
    fi

    HOST_IP="${selected_ip}"
    ok "IP seleccionada: ${HOST_IP}"
}

# =============================================================================
# PASO 7: Generar .env
# =============================================================================
generate_env() {
    step "7" "${TOTAL_STEPS}" "Generando configuracion (.env)"

    local env_file="${INSTALL_DIR}/.env"

    if [[ -f "${env_file}" ]]; then
        warn "El archivo .env ya existe."
        # Mostrar info del archivo existente
        local env_date
        env_date=$(grep '# Fecha:' "${env_file}" 2>/dev/null | head -1 | awk '{print $NF}' || echo "desconocida")
        log "Generado el: ${env_date}"
        log "IP del servidor: $(grep '^HOST_IP=' "${env_file}" 2>/dev/null | cut -d= -f2 || echo 'desconocida')"
        echo
        read -rp "¿Sobrescribir con nueva configuracion? [s/N]: " overwrite
        if [[ ! "${overwrite}" =~ ^[SsYy] ]]; then
            log "Manteniendo .env existente. Cargando variables..."
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
            return 0
        fi
    fi

    log "Generando .env con secretos criptograficamente seguros..."
    generate_env_file "${env_file}" "${HOST_IP}"

    # Cargar el archivo generado
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a

    ok ".env generado exitosamente"
    ok "  POSTGRES_PASSWORD:   ${POSTGRES_PASSWORD:0:8}...(${#POSTGRES_PASSWORD} chars)"
    ok "  REDIS_PASSWORD:      ${REDIS_PASSWORD:0:8}...(${#REDIS_PASSWORD} chars)"
    ok "  REGISTRATION_SECRET: ${SYNAPSE_REGISTRATION_SHARED_SECRET:0:8}...(${#SYNAPSE_REGISTRATION_SHARED_SECRET} chars)"
    ok "  MACAROON_SECRET:     ${SYNAPSE_MACAROON_SECRET_KEY:0:8}...(${#SYNAPSE_MACAROON_SECRET_KEY} chars)"
    ok "  ADMIN_API_TOKEN:     ${SYNAPSE_ADMIN_API_TOKEN:0:8}...(${#SYNAPSE_ADMIN_API_TOKEN} chars)"
    ok "  FORM_SECRET:         ${SYNAPSE_FORM_SECRET:0:8}...(${#SYNAPSE_FORM_SECRET} chars)"
    ok "  PASSWORD_PEPPER:     ${SYNAPSE_PASSWORD_PEPPER:0:8}...(${#SYNAPSE_PASSWORD_PEPPER} chars)"
    ok "  HOST_IP:             ${HOST_IP}"
}

# =============================================================================
# PASO 8: Generar signing key
# =============================================================================
generate_signing_key() {
    step "8" "${TOTAL_STEPS}" "Generando signing key de Synapse"

    local signing_key="${INSTALL_DIR}/synapse/signing.key"

    if [[ -f "${signing_key}" && -s "${signing_key}" ]]; then
        ok "Signing key ya existe (conservada)"
        return 0
    fi

    mkdir -p "${INSTALL_DIR}/synapse"

    # Metodo 1: Generacion con openssl (self-contained, sin depender de Docker)
    # Genera una ed25519 signing key compatible con Synapse
    log "Generando signing key (ed25519)..."
    local key_id seed b64_seed
    key_id=$(openssl rand -hex 2)
    seed=$(openssl rand -hex 32)
    b64_seed=$(echo -n "${seed}" | xxd -r -p | base64 | tr -d '\n')
    echo "ed25519 ${key_id} ${b64_seed}" > "${signing_key}"

    if [[ -f "${signing_key}" && -s "${signing_key}" ]]; then
        chmod 600 "${signing_key}"
        ok "Signing key generada correctamente"
    else
        fatal "No se pudo generar la signing key. Revisa los permisos de ${INSTALL_DIR}/synapse/"
    fi
}

# =============================================================================
# PASO 9: Generar certificados TLS
# =============================================================================
generate_certs() {
    step "9" "${TOTAL_STEPS}" "Generando certificados TLS"

    local certs_dir="${INSTALL_DIR}/nginx/certs"
    mkdir -p "${certs_dir}"

    # Verificar si ya existen todos los certificados
    local all_certs_exist=true
    for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
        if [[ ! -f "${certs_dir}/${f}" ]]; then
            all_certs_exist=false
            break
        fi
    done

    if [[ "${all_certs_exist}" == "true" ]]; then
        ok "Certificados TLS ya existen (conservados)"
        warn "Para regenerar: rm ${certs_dir}/*.key ${certs_dir}/*.crt y ejecuta install.sh"
        return 0
    fi

    log "Generando certificados TLS auto-firmados..."

    # Ejecutar script de generacion de certificados
    if bash "${INSTALL_DIR}/scripts/linux/generate-certs.sh"; then
        # Verificar que se generaron
        local missing=0
        for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
            if [[ ! -f "${certs_dir}/${f}" ]]; then
                error "Falta: certs/${f}"
                missing=$((missing + 1))
            fi
        done
        if [[ ${missing} -gt 0 ]]; then
            fatal "No se pudieron generar ${missing} archivos de certificado."
        fi
        ok "8 archivos de certificado generados (SAN: matrix.home.arpa, element.home.arpa, localhost, 127.0.0.1)"
    else
        fatal "Error al generar certificados. Revisa los logs."
    fi
}

# =============================================================================
# PASO 10: Validar permisos y archivos
# =============================================================================
validate_files_and_permissions() {
    step "10" "${TOTAL_STEPS}" "Validando permisos y archivos criticos"

    local problems=0

    # Verificar .env
    if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
        fail ".env no existe"
        problems=$((problems + 1))
    else
        # Permisos de .env
        local env_perms
        env_perms=$(stat -c '%a' "${INSTALL_DIR}/.env" 2>/dev/null || echo "000")
        if [[ "${env_perms}" != "600" ]]; then
            warn ".env tiene permisos ${env_perms}, corrigiendo a 600"
            chmod 600 "${INSTALL_DIR}/.env"
        fi
        ok ".env existe (permisos: 600)"
    fi

    # Verificar signing key
    if [[ ! -f "${INSTALL_DIR}/synapse/signing.key" ]] || [[ ! -s "${INSTALL_DIR}/synapse/signing.key" ]]; then
        fail "synapse/signing.key no existe o esta vacio"
        problems=$((problems + 1))
    else
        local sk_perms
        sk_perms=$(stat -c '%a' "${INSTALL_DIR}/synapse/signing.key" 2>/dev/null || echo "000")
        if [[ "${sk_perms}" != "600" ]]; then
            chmod 600 "${INSTALL_DIR}/synapse/signing.key"
        fi
        ok "synapse/signing.key existe (permisos: 600)"
    fi

    # Verificar certificados
    local cert_files=(ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key)
    local certs_dir="${INSTALL_DIR}/nginx/certs"
    local missing_certs=0
    for f in "${cert_files[@]}"; do
        if [[ ! -f "${certs_dir}/${f}" ]]; then
            missing_certs=$((missing_certs + 1))
        fi
    done
    if [[ ${missing_certs} -gt 0 ]]; then
        fail "Faltan ${missing_certs} archivos de certificado"
        problems=$((problems + 1))
    else
        # Permisos de claves
        find "${certs_dir}" -name '*.key' -exec chmod 600 {} \; 2>/dev/null || true
        find "${certs_dir}" -name '*.crt' -exec chmod 644 {} \; 2>/dev/null || true
        ok "Certificados TLS completos (${#cert_files[@]} archivos)"
    fi

    # Verificar archivos de configuracion del proyecto
    local config_files=(
        "docker-compose.yml"
        "synapse/homeserver.yaml.template"
        "synapse/entrypoint.sh"
        "synapse/log.config"
        "synapse/Dockerfile"
        "redis/redis.conf.template"
        "redis/entrypoint.sh"
        "element/Dockerfile"
        "element/config.json"
        "element/nginx.conf"
        "nginx/nginx.conf"
        "nginx/conf.d/matrix.home.arpa.conf"
        "nginx/conf.d/element.home.arpa.conf"
        "nginx/conf.d/00-default.conf"
        "nginx/snippets/security-headers.conf"
        "nginx/snippets/proxy-params.conf"
        "nginx/well-known/matrix/server.json"
        "nginx/well-known/matrix/client.json"
        "postgres/init.sql"
        "postgres/postgresql.conf"
        "postgres/pg_hba.conf"
    )
    local missing_configs=0
    for f in "${config_files[@]}"; do
        if [[ ! -f "${INSTALL_DIR}/${f}" ]]; then
            error "Falta archivo de configuracion: ${f}"
            missing_configs=$((missing_configs + 1))
        fi
    done
    if [[ ${missing_configs} -gt 0 ]]; then
        fail "Faltan ${missing_configs} archivos de configuracion del proyecto"
        problems=$((problems + 1))
    else
        ok "Archivos de configuracion completos (${#config_files[@]} archivos)"
    fi

    # Permisos de escritura en directorios necesarios
    for dir in "${INSTALL_DIR}/nginx/certs" "${INSTALL_DIR}/synapse" "${INSTALL_DIR}/backups"; do
        if [[ -e "${dir}" ]] && [[ ! -w "${dir}" ]]; then
            error "Sin permisos de escritura en ${dir}"
            problems=$((problems + 1))
        fi
    done

    if [[ ${problems} -gt 0 ]]; then
        fatal "Se encontraron ${problems} problemas. Corrigelos antes de continuar."
    fi
}

# =============================================================================
# PASO 11: Construir imagenes personalizadas
# =============================================================================
build_images() {
    step "11" "${TOTAL_STEPS}" "Construyendo imagenes personalizadas"

    # Construir imagen de Synapse (necesaria: incluye envsubst y curl)
    log "Construyendo imagen de Synapse con envsubst y curl..."
    log "Esto puede tardar varios minutos en la primera vez (descarga de capas base)"
    if (cd "${INSTALL_DIR}" && docker compose build synapse 2>&1); then
        ok "Imagen matrix-synapse:custom construida"
    else
        fatal "Error al construir la imagen de Synapse. Revisa la conexion a Internet y los logs."
    fi

    # Construir imagen de Element
    log "Construyendo imagen de Element Web..."
    if (cd "${INSTALL_DIR}" && docker compose build element 2>&1); then
        ok "Imagen matrix-element:custom construida"
    else
        fatal "Error al construir la imagen de Element. Revisa la conexion a Internet."
    fi
}

# =============================================================================
# PASO 12: Despliegue
# =============================================================================
deploy_stack() {
    step "12" "${TOTAL_STEPS}" "Desplegando servicios"

    log "Validando docker-compose.yml..."
    if (cd "${INSTALL_DIR}" && docker compose config --quiet 2>&1); then
        ok "docker-compose.yml valido"
    else
        fatal "Error en docker-compose.yml. No se puede continuar."
    fi

    log "Levantando servicios (primer arranque puede tardar 3-5 minutos)..."
    if (cd "${INSTALL_DIR}" && docker compose up -d 2>&1); then
        ok "docker compose up -d ejecutado"
    else
        fatal "Error al levantar los servicios."
    fi
}

# =============================================================================
# PASO 13: Verificar servicios
# =============================================================================
verify_services() {
    step "13" "${TOTAL_STEPS}" "Verificando estado de los servicios"

    local services=("postgres" "redis" "synapse" "element" "nginx")
    local all_ok=true
    local service_timeouts
    service_timeouts="postgres:120 redis:60 synapse:180 element:60 nginx:60"

    for svc in "${services[@]}"; do
        local svc_name="matrix-${svc}"
        log "Esperando a ${svc_name}..."

        # Obtener timeout especifico por servicio
        local timeout=120
        for st in ${service_timeouts}; do
            local st_name="${st%%:*}"
            local st_timeout="${st##*:}"
            if [[ "${st_name}" == "${svc}" ]]; then
                timeout="${st_timeout}"
                break
            fi
        done

        local elapsed=0
        while true; do
            local state
            state=$(docker inspect --format='{{.State.Health.Status}}' "${svc_name}" 2>/dev/null || echo "missing")

            if [[ "${state}" == "healthy" ]]; then
                ok "${svc_name} - healthy"
                break
            elif [[ "${state}" == "unhealthy" ]]; then
                fail "${svc_name} - UNHEALTHY"
                echo
                error "Servicio: ${svc_name}"
                error "Estado: unhealthy"
                echo
                local svc_logs
                svc_logs=$(docker logs --tail 20 "${svc_name}" 2>&1)
                echo -e "${Y}  Ultimos logs de ${svc_name}:${NC}"
                echo "${svc_logs}" | sed 's/^/    /'
                echo
                case "${svc}" in
                    postgres)
                        error "Posible solucion: Verifica que los volumenes no esten corruptos."
                        error "  docker compose down -v  # elimina volumenes (se pierden datos)"
                        error "  sudo ./install.sh      # reinstala todo"
                        ;;
                    redis)
                        error "Posible solucion: Verifica la configuracion de Redis."
                        error "  docker compose logs redis"
                        ;;
                    synapse)
                        error "Posible solucion: Verifica que el homeserver.yaml se genero correctamente."
                        error "  docker compose exec synapse cat /data/homeserver.yaml | head -20"
                        error "  docker compose logs synapse"
                        ;;
                    element)
                        error "Posible solucion: Verifica la imagen de Element."
                        error "  docker compose build --no-cache element"
                        ;;
                    nginx)
                        error "Posible solucion: Verifica la configuracion de Nginx y los certificados."
                        error "  docker compose exec nginx nginx -t"
                        error "  docker compose logs nginx"
                        ;;
                esac
                all_ok=false
                break
            elif (( elapsed >= timeout )); then
                fail "${svc_name} - TIMEOUT (${timeout}s)"
                echo
                error "El servicio ${svc_name} no se volvio healthy en ${timeout} segundos."
                error "Posible solucion:"
                error "  docker compose logs ${svc_name}  # revisar logs"
                error "  docker compose restart ${svc_name}  # reiniciar servicio"
                all_ok=false
                break
            fi

            sleep 5
            elapsed=$((elapsed + 5))
            printf "."
        done
        echo
    done

    if [[ "${all_ok}" == "false" ]]; then
        echo
        fatal "Algunos servicios fallaron. La instalacion no se completo exitosamente."
    fi

    return 0
}

# =============================================================================
# PASO 14: Pruebas automaticas y resumen
# =============================================================================
run_tests_and_summary() {
    step "14" "${TOTAL_STEPS}" "Ejecutando pruebas automaticas"

    local tests_passed=0
    local tests_failed=0
    local test_results=()

    # Test 1: Docker
    if docker info >/dev/null 2>&1; then
        test_results+=("${G}✓${NC} Docker")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Docker")
        ((tests_failed++))
    fi

    # Test 2: Docker Compose
    if docker compose version >/dev/null 2>&1; then
        test_results+=("${G}✓${NC} Docker Compose")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Docker Compose")
        ((tests_failed++))
    fi

    # Test 3: .env existe y tiene secretos
    if [[ -f "${INSTALL_DIR}/.env" ]] && grep -q 'POSTGRES_PASSWORD=' "${INSTALL_DIR}/.env" && ! grep -q '__GENERATE__' "${INSTALL_DIR}/.env"; then
        test_results+=("${G}✓${NC} Secrets (.env)")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Secrets (.env)")
        ((tests_failed++))
    fi

    # Test 4: Signing key
    if [[ -f "${INSTALL_DIR}/synapse/signing.key" ]] && [[ -s "${INSTALL_DIR}/synapse/signing.key" ]]; then
        test_results+=("${G}✓${NC} Signing Key")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Signing Key")
        ((tests_failed++))
    fi

    # Test 5: Certificados
    if [[ -f "${INSTALL_DIR}/nginx/certs/ca.crt" ]] && [[ -f "${INSTALL_DIR}/nginx/certs/matrix.crt" ]]; then
        test_results+=("${G}✓${NC} Certificados TLS")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Certificados TLS")
        ((tests_failed++))
    fi

    # Test 6: PostgreSQL healthy
    local pg_state
    pg_state=$(docker inspect --format='{{.State.Health.Status}}' matrix-postgres 2>/dev/null || echo "missing")
    if [[ "${pg_state}" == "healthy" ]]; then
        test_results+=("${G}✓${NC} PostgreSQL")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} PostgreSQL (${pg_state})")
        ((tests_failed++))
    fi

    # Test 7: Redis healthy
    local redis_state
    redis_state=$(docker inspect --format='{{.State.Health.Status}}' matrix-redis 2>/dev/null || echo "missing")
    if [[ "${redis_state}" == "healthy" ]]; then
        test_results+=("${G}✓${NC} Redis")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Redis (${redis_state})")
        ((tests_failed++))
    fi

    # Test 8: Synapse healthy
    local syn_state
    syn_state=$(docker inspect --format='{{.State.Health.Status}}' matrix-synapse 2>/dev/null || echo "missing")
    if [[ "${syn_state}" == "healthy" ]]; then
        test_results+=("${G}✓${NC} Synapse")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Synapse (${syn_state})")
        ((tests_failed++))
    fi

    # Test 9: Element healthy
    local elem_state
    elem_state=$(docker inspect --format='{{.State.Health.Status}}' matrix-element 2>/dev/null || echo "missing")
    if [[ "${elem_state}" == "healthy" ]]; then
        test_results+=("${G}✓${NC} Element Web")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Element Web (${elem_state})")
        ((tests_failed++))
    fi

    # Test 10: Nginx healthy
    local nginx_state
    nginx_state=$(docker inspect --format='{{.State.Health.Status}}' matrix-nginx 2>/dev/null || echo "missing")
    if [[ "${nginx_state}" == "healthy" ]]; then
        test_results+=("${G}✓${NC} Nginx")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Nginx (${nginx_state})")
        ((tests_failed++))
    fi

    # Test 11: Healthcheck de Nginx via HTTP
    if docker exec matrix-nginx wget -q --spider http://localhost/healthz 2>/dev/null; then
        test_results+=("${G}✓${NC} Healthcheck Nginx")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Healthcheck Nginx")
        ((tests_failed++))
    fi

    # Test 12: Matrix API health endpoint via Docker network
    if docker exec matrix-synapse curl -fSs http://localhost:8008/health 2>/dev/null | grep -q "OK"; then
        test_results+=("${G}✓${NC} Matrix API")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Matrix API")
        ((tests_failed++))
    fi

    # Test 13: Permisos de .env
    local env_perms
    env_perms=$(stat -c '%a' "${INSTALL_DIR}/.env" 2>/dev/null || echo "000")
    if [[ "${env_perms}" == "600" ]]; then
        test_results+=("${G}✓${NC} Permisos .env (600)")
        ((tests_passed++))
    else
        test_results+=("${R}✗${NC} Permisos .env (${env_perms})")
        ((tests_failed++))
    fi

    # Test 14: Configuracion de Synapse generada correctamente
    if docker exec matrix-synapse test -f /data/homeserver.yaml 2>/dev/null; then
        # Verificar que no tenga variables sin sustituir
        if ! docker exec matrix-synapse grep -q '\${[A-Z_]*}' /data/homeserver.yaml 2>/dev/null; then
            test_results+=("${G}✓${NC} Configuracion Synapse")
            ((tests_passed++))
        else
            test_results+=("${Y}!${NC} Configuracion Synapse (variables sin sustituir)")
            ((tests_failed++))
        fi
    else
        test_results+=("${R}✗${NC} Configuracion Synapse (no generada)")
        ((tests_failed++))
    fi

    # Mostrar resultados
    echo
    echo -e "${BD}  Resultado de las pruebas:${NC}"
    echo -e "  ${D}-------------------------------------------${NC}"
    for result in "${test_results[@]}"; do
        echo -e "  ${result}"
    done
    echo -e "  ${D}-------------------------------------------${NC}"
    echo -e "  ${BD}Total: ${tests_passed} aprobadas, ${tests_failed} fallidas${NC}"
    echo

    if [[ ${tests_failed} -gt 0 ]]; then
        fatal "${tests_failed} pruebas fallaron. Revisa los errores arriba."
    fi

    # Resumen final
    show_summary
}

# =============================================================================
# Resumen final
# =============================================================================
show_summary() {
    local ts_line=""
    if command -v tailscale >/dev/null 2>&1; then
        local ts_ip
        ts_ip=$(detect_tailscale_ip 2>/dev/null || echo "")
        if [[ -n "${ts_ip}" ]]; then
            ts_line=$(echo -e "  ${G}✓${NC} Tailscale:  https://${ts_ip}")
        fi
    fi

    echo
    echo -e "${G}${BD}========================================${NC}"
    echo
    echo -e "${G}${BD}  INSTALACION COMPLETADA EXITOSAMENTE${NC}"
    echo
    echo -e "${BD}  Servidor:${NC}  ${HOST_IP}"
    echo
    echo -e "${BD}  Servicios:${NC}"
    echo -e "  ${G}✓${NC} PostgreSQL 16"
    echo -e "  ${G}✓${NC} Redis 7"
    echo -e "  ${G}✓${NC} Matrix Synapse v1.118.0 (custom)"
    echo -e "  ${G}✓${NC} Element Web v1.11.65"
    echo -e "  ${G}✓${NC} Nginx 1.27"
    echo
    echo -e "${BD}  Accesos:${NC}"
    echo -e "  https://matrix.home.arpa  (servidor)"
    echo -e "  https://element.home.arpa  (cliente web)"
    echo "${ts_line}"
    echo
    echo -e "${BD}  Configurar DNS en los clientes:${NC}"
    echo "  ${HOST_IP}  matrix.home.arpa"
    echo "  ${HOST_IP}  element.home.arpa"
    echo
    echo -e "${BD}  Importar certificado CA en los clientes:${NC}"
    echo "  Linux:   sudo cp nginx/certs/ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
    echo "  Windows: Doble clic en nginx/certs/ca.crt -> Instalar -> Entidades de certificacion raiz"
    echo
    echo -e "${BD}  Crear usuario administrador:${NC}"
    echo "  docker compose exec synapse register_new_matrix_user -c http://localhost:8008 -a admin"
    echo
    echo -e "${BD}  Comandos de administracion:${NC}"
    echo "  sudo ./scripts/admin/status.sh      # Estado del stack"
    echo "  sudo ./scripts/admin/healthcheck.sh  # Healthcheck detallado"
    echo "  sudo ./scripts/admin/restart.sh      # Reiniciar servicios"
    echo "  sudo ./scripts/admin/stop.sh         # Detener servicios"
    echo "  sudo ./scripts/admin/start.sh        # Iniciar servicios"
    echo "  sudo ./scripts/admin/logs.sh         # Ver logs"
    echo "  sudo ./scripts/admin/backup.sh       # Crear backup"
    echo "  sudo ./scripts/admin/restore.sh      # Restaurar backup"
    echo "  sudo ./scripts/admin/update.sh       # Actualizar imagenes"
    echo "  sudo ./uninstall.sh                  # Desinstalar"
    echo
    echo -e "${G}${BD}========================================${NC}"
    echo
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    banner

    validate_system
    validate_resources
    validate_docker
    validate_ports
    validate_dependencies
    detect_ip_address
    generate_env
    generate_signing_key
    generate_certs
    validate_files_and_permissions
    build_images
    deploy_stack
    verify_services
    run_tests_and_summary
}

main "$@"