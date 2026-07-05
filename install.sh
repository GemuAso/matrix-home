#!/usr/bin/env bash
# =============================================================================
# install.sh - Instalador completo de Matrix Docker Stack
# -----------------------------------------------------------------------------
# Instalación de un solo comando para Matrix Synapse + PostgreSQL + Redis +
# Element Web + Nginx en entornos LAN privados.
#
# Uso:
#   sudo ./install.sh          (instala dependencias faltantes si es necesario)
#   ./install.sh               (si Docker ya está instalado)
#
# Compatible con: Ubuntu 20.04+, Debian 11+, ARM64, AMD64
#
# Este script:
#   1. Valida el sistema (OS, arquitectura, RAM, disco)
#   2. Detecta/instala dependencias
#   3. Detecta la IP LAN automáticamente
#   4. Genera .env con secretos criptográficamente seguros
#   5. Genera certificados TLS y signing key
#   6. Construye la imagen de Element
#   7. Levanta el stack con docker compose
#   8. Verifica que todos los servicios estén saludables
#   9. Muestra un resumen final con instrucciones
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
# Colores
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
    C='\033[0;36m' BD='\033[1m' NC='\033[0m'
else
    R='' G='' Y='' B='' C='' BD='' NC=''
fi

# -----------------------------------------------------------------------------
# Funciones de output
# -----------------------------------------------------------------------------
log()    { echo -e "${G}[$(date '+%H:%M:%S')] [INFO]${NC}  $*"; }
warn()   { echo -e "${Y}[$(date '+%H:%M:%S')] [WARN]${NC}  $*" >&2; }
error()  { echo -e "${R}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" >&2; }
fatal()  { echo -e "${R}[$(date '+%H:%M:%S')] [FATAL]${NC} $*" >&2; exit 1; }
step()   { echo; echo -e "${B}${BD}--- Paso $1: $2 ---${NC}"; }
ok()     { echo -e "${G}  [OK]${NC} $*"; }
fail()   { echo -e "${R}  [FALLO]${NC} $*"; }
banner() {
    echo
    cat <<'BANNER'

  __  __ _       _     _              ____
 |  \/  (_) __ _| | __| |   _ __ ___ |___ \
 | |\/| | |/ _` | |/ _` |  | '_ ` _ \  __) |
 | |  | | | (_| | | (_| |  | | | | | |/ __/
 |_|  |_|_|\__,_|_|\__,_|  |_| |_| |_|_____|

BANNER
    echo -e "${C}  Matrix Synapse Docker Stack - Instalador Automático${NC}"
    echo -e "${C}  Versión 4.0.0 | LAN Privada | Tailscale Ready${NC}"
    echo
}

# =============================================================================
# PASO 1: Sistema operativo y arquitectura
# =============================================================================
validate_system() {
    step "1/10" "Validando sistema operativo y arquitectura"

    # Arquitectura
    local arch
    if ! arch=$(check_architecture); then
        local bad_arch="${arch#*:}"
        fatal "Arquitectura no soportada: ${bad_arch}. Se requiere x86_64 o ARM64."
    fi
    ok "Arquitectura: ${arch}"

    # SO
    local os_info
    if ! os_info=$(check_os); then
        local os_id="${os_info%%:*}"
        local os_ver="${os_info#*:}"
        error "Sistema operativo no soportado: ${os_id} ${os_ver}"
        fatal "Se requiere Ubuntu 20.04+ o Debian 11+."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    ok "Sistema: ${PRETTY_NAME:-${os_info}}"

    # Permisos de root (para instalar dependencias)
    if [[ $EUID -ne 0 ]]; then
        warn "No se ejecuta como root. No se podrán instalar dependencias faltantes."
        warn "Si falta alguna dependencia, la instalación fallará."
        warn "Ejecuta: sudo ./install.sh"
    fi
}

# =============================================================================
# PASO 2: Recursos del sistema
# =============================================================================
validate_resources() {
    step "2/10" "Validando recursos del sistema"

    # Disco
    local disk_result
    disk_result=$(check_disk_space "${INSTALL_DIR}")
    if [[ "${disk_result}" == INSUFICIENTE:* ]]; then
        local available_gb="${disk_result#*:}"
        fatal "Espacio en disco insuficiente: ${available_gb} GB disponibles. Se requieren al menos 5 GB."
    fi
    local disk_gb="${disk_result#*:}"
    ok "Espacio en disco: ${disk_gb} GB disponibles"

    # RAM
    local mem_result
    mem_result=$(check_memory)
    if [[ "${mem_result}" == INSUFICIENTE:* ]]; then
        local mem_mb="${mem_result#*:}"
        fatal "Memoria RAM insuficiente: ${mem_mb} MB. Se requieren al menos 2048 MB."
    fi
    if [[ "${mem_result}" == "UNKNOWN" ]]; then
        warn "No se pudo detectar la memoria RAM. Continuando..."
    else
        local mem_mb="${mem_result#*:}"
        ok "Memoria RAM: ${mem_mb} MB"
    fi
}

# =============================================================================
# PASO 3: Dependencias
# =============================================================================
validate_dependencies() {
    step "3/10" "Verificando e instalando dependencias"

    local deps_needed=false

    # Verificar cada dependencia
    for cmd in docker openssl curl git ip; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            ok "${cmd}"
        else
            fail "${cmd} no encontrado"
            deps_needed=true
        fi
    done

    # Docker Compose
    if docker compose version >/dev/null 2>&1; then
        ok "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        warn "docker-compose v1 detectado (se recomienda v2)"
        deps_needed=true
    else
        fail "docker compose no encontrado"
        deps_needed=true
    fi

    # Docker daemon
    if docker info >/dev/null 2>&1; then
        ok "Docker daemon corriendo"
    else
        fail "Docker daemon no está corriendo"
        deps_needed=true
    fi

    # Instalar dependencias faltantes
    if [[ "${deps_needed}" == "true" ]]; then
        if [[ $EUID -ne 0 ]]; then
            fatal "Faltan dependencias y no hay permisos de root. Ejecuta: sudo ./install.sh"
        fi

        local install_result
        install_result=$(install_dependencies)
        if [[ "${install_result}" == INSTALAR:* ]]; then
            local packages="${install_result#*:}"
            log "Instalando: ${packages}"
            # shellcheck disable=SC2086
            apt-get update -qq && apt-get install -y -qq ${packages} >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                fatal "Error al instalar dependencias. Revisa la conexión a Internet y ejecuta manualmente: apt-get install ${packages}"
            fi
            ok "Dependencias instaladas"

            # Si Docker fue recién instalado, habilitar el servicio
            if ! docker info >/dev/null 2>&1; then
                log "Iniciando Docker..."
                systemctl enable --now docker >/dev/null 2>&1 || true
                sleep 3
                if ! docker info >/dev/null 2>&1; then
                    fatal "Docker se instaló pero no se pudo iniciar. Revisa: systemctl status docker"
                fi
            fi
            ok "Docker daemon activo"
        fi
    fi
}

# =============================================================================
# PASO 4: Detectar IP
# =============================================================================
detect_ip_address() {
    step "4/10" "Detectando dirección IP de la red"

    local lan_ip=""
    local ts_ip=""

    # Detectar LAN
    if lan_ip=$(detect_lan_ip); then
        ok "IP LAN detectada: ${lan_ip}"
    else
        warn "No se pudo detectar la IP LAN automáticamente"
    fi

    # Detectar Tailscale
    if ts_ip=$(detect_tailscale_ip); then
        ok "IP Tailscale detectada: ${ts_ip}"
    else
        log "Tailscale no está instalado o no está conectado"
    fi

    # Selección de IP
    local selected_ip=""
    if [[ -n "${lan_ip}" && -z "${ts_ip}" ]]; then
        # Solo LAN
        selected_ip="${lan_ip}"
        echo
        log "IP LAN detectada: ${lan_ip}"
        read -rp "¿Desea utilizar esta IP? [S/n]: " confirm
        if [[ "${confirm}" =~ ^[Nn] ]]; then
            selected_ip=""
        fi
    elif [[ -n "${lan_ip}" && -n "${ts_ip}" ]]; then
        # Ambas disponibles
        echo
        log "Se detectaron las siguientes IP:"
        log "  LAN:      ${lan_ip}"
        log "  Tailscale: ${ts_ip}"
        echo
        read -rp "¿Cuál desea utilizar? (1=LAN, 2=Tailscale) [1]: " choice
        case "${choice}" in
            2) selected_ip="${ts_ip}" ;;
            *) selected_ip="${lan_ip}" ;;
        esac
    fi

    # Si no se pudo detectar o el usuario rechazó, pedir manualmente
    if [[ -z "${selected_ip}" ]]; then
        echo
        while true; do
            read -rp "Ingrese la IP del servidor (ej: 192.168.1.100): " selected_ip
            local validation
            validation=$(validate_ip "${selected_ip}")
            if [[ "${validation}" == "OK" ]]; then
                break
            else
                local reason="${validation#*:}"
                error "IP ${reason}. Intente de nuevo."
            fi
        done
    fi

    HOST_IP="${selected_ip}"
    ok "IP seleccionada: ${HOST_IP}"
}

# =============================================================================
# PASO 5: Generar .env
# =============================================================================
generate_env() {
    step "5/10" "Generando configuración (.env)"

    local env_file="${INSTALL_DIR}/.env"

    if [[ -f "${env_file}" ]]; then
        warn "El archivo .env ya existe."
        read -rp "¿Sobrescribir con nueva configuración? [s/N]: " overwrite
        if [[ ! "${overwrite}" =~ ^[SsYy] ]]; then
            log "Manteniendo .env existente. Cargando variables..."
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
            return 0
        fi
    fi

    log "Generando .env con secretos criptográficamente seguros..."
    generate_env_file "${env_file}" "${HOST_IP}"

    # Cargar el archivo generado
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a

    ok ".env generado con 7 secretos únicos"
    ok "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:0:8}...(${#POSTGRES_PASSWORD} chars)"
    ok "REDIS_PASSWORD: ${REDIS_PASSWORD:0:8}...(${#REDIS_PASSWORD} chars)"
    ok "HOST_IP: ${HOST_IP}"
}

# =============================================================================
# PASO 6: Generar claves y certificados
# =============================================================================
generate_keys_and_certs() {
    step "6/10" "Generando claves y certificados TLS"

    # Signing key de Synapse
    local signing_key="${INSTALL_DIR}/synapse/signing.key"
    if [[ -f "${signing_key}" && -s "${signing_key}" ]]; then
        ok "Signing key de Synapse ya existe (conservada)"
    else
        log "Generando signing key de Synapse..."
        mkdir -p "${INSTALL_DIR}/synapse"

        # Intentar método oficial
        local synapse_image="matrixdotorg/synapse:v1.118.0"
        if docker image inspect "${synapse_image}" >/dev/null 2>&1; then
            log "Usando método oficial de Synapse..."
            docker run --rm \
                -v "${INSTALL_DIR}/synapse":/signing \
                "${synapse_image}" \
                generate_signing_key -O /signing 2>/dev/null || true
        fi

        # Fallback manual
        if [[ ! -f "${signing_key}" ]] || [[ ! -s "${signing_key}" ]]; then
            log "Usando generación manual (ed25519)..."
            local key_id seed b64_seed
            key_id=$(openssl rand -hex 2)
            seed=$(openssl rand -hex 32)
            b64_seed=$(echo -n "${seed}" | xxd -r -p | base64 | tr -d '\n')
            echo "ed25519 ${key_id} ${b64_seed}" > "${signing_key}"
        fi

        chmod 600 "${signing_key}"
        ok "Signing key generada"
    fi

    # Certificados TLS
    local certs_dir="${INSTALL_DIR}/nginx/certs"
    local all_certs_exist=true
    for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
        if [[ ! -f "${certs_dir}/${f}" ]]; then
            all_certs_exist=false
            break
        fi
    done

    if [[ "${all_certs_exist}" == "true" ]]; then
        warn "Certificados TLS ya existen (conservados)"
        warn "Para regenerar, borra: ${certs_dir}/*.key y *.crt antes de ejecutar install.sh"
    else
        log "Generando certificados TLS auto-firmados..."
        bash "${INSTALL_DIR}/scripts/linux/generate-certs.sh"

        # Verificar que se generaron
        local missing=0
        for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
            if [[ ! -f "${certs_dir}/${f}" ]]; then
                error "Falta: ${certs_dir}/${f}"
                missing=$((missing+1))
            fi
        done
        if [[ ${missing} -gt 0 ]]; then
            fatal "No se pudieron generar ${missing} certificados. Revisa los logs."
        fi
        ok "8 certificados TLS generados (SAN: matrix.home.arpa, element.home.arpa, localhost)"
    fi
}

# =============================================================================
# PASO 7: Construir imagen de Element
# =============================================================================
build_element() {
    step "7/10" "Construyendo imagen personalizada de Element Web"

    if docker image inspect matrix-element:custom >/dev/null 2>&1; then
        ok "Imagen matrix-element:custom ya existe"
        return 0
    fi

    log "Construyendo imagen (esto puede tardar un par de minutos)..."
    if (cd "${INSTALL_DIR}" && docker compose build element 2>&1); then
        ok "Imagen element construida"
    else
        fatal "Error al construir la imagen de Element. Revisa la conexión a Internet."
    fi
}

# =============================================================================
# PASO 8: Validar configuración y levantar stack
# =============================================================================
start_stack() {
    step "8/10" "Validando configuración y levantando servicios"

    log "Validando docker-compose.yml..."
    if (cd "${INSTALL_DIR}" && docker compose config --quiet 2>&1); then
        ok "docker-compose.yml válido"
    else
        fatal "Error en docker-compose.yml. No se puede continuar."
    fi

    log "Levantando servicios (esto puede tardar 3-5 minutos en el primer arranque)..."
    if (cd "${INSTALL_DIR}" && docker compose up -d 2>&1); then
        ok "Comando docker compose up -d ejecutado"
    else
        fatal "Error al levantar los servicios. Ejecuta manualmente: cd ${INSTALL_DIR} && docker compose up -d"
    fi
}

# =============================================================================
# PASO 9: Verificar servicios
# =============================================================================
verify_services() {
    step "9/10" "Verificando estado de los servicios"

    local services=("postgres" "redis" "synapse" "element" "nginx")
    local all_ok=true
    local timeout=180
    local elapsed=0

    for svc in "${services[@]}"; do
        local svc_name="matrix-${svc}"
        log "Esperando a ${svc_name}..."

        while true; do
            local state
            state=$(docker inspect --format='{{.State.Health.Status}}' "${svc_name}" 2>/dev/null || echo "missing")

            if [[ "${state}" == "healthy" ]]; then
                ok "${svc_name}"
                break
            elif [[ "${state}" == "unhealthy" ]]; then
                fail "${svc_name} - unhealthy"
                local svc_logs
                svc_logs=$(docker logs --tail 10 "${svc_name}" 2>&1)
                echo -e "${Y}  Últimos logs:${NC}"
                echo "${svc_logs}" | sed 's/^/    /'
                all_ok=false
                break
            elif (( elapsed >= timeout )); then
                fail "${svc_name} - timeout (${timeout}s)"
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
        warn "Algunos servicios no están saludables."
        warn "Revisa los logs con: cd ${INSTALL_DIR} && docker compose logs"
        warn "O reintenta: cd ${INSTALL_DIR} && docker compose restart"
        return 1
    fi

    return 0
}

# =============================================================================
# PASO 10: Resumen final
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
    echo -e "${B}${BD}========================================${NC}"
    echo
    echo -e "${G}${BD}  INSTALACIÓN FINALIZADA${NC}"
    echo
    echo -e "${BD}  Servidor:${NC}  ${HOST_IP}"
    echo
    echo -e "${BD}  Servicios:${NC}"
    echo -e "  ${G}✓${NC} PostgreSQL 16"
    echo -e "  ${G}✓${NC} Redis 7"
    echo -e "  ${G}✓${NC} Matrix Synapse v1.118.0"
    echo -e "  ${G}✓${NC} Nginx 1.27"
    echo -e "  ${G}✓${NC} Element Web v1.11.65"
    echo
    echo -e "${BD}  Accesos:${NC}"
    echo -e "  https://matrix.home.arpa"
    echo -e "  https://element.home.arpa"
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
    echo "  cd ${INSTALL_DIR}"
    echo "  docker compose exec synapse register_new_matrix_user -c http://localhost:8008 -a admin"
    echo
    echo -e "${BD}  Backups:${NC}"
    echo "  cd ${INSTALL_DIR} && bash scripts/linux/backup-db.sh"
    echo
    echo -e "${BD}  Logs:${NC}"
    echo "  cd ${INSTALL_DIR} && docker compose logs -f synapse"
    echo
    echo -e "${B}${BD}========================================${NC}"
    echo
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    banner

    validate_system
    validate_resources
    validate_dependencies
    detect_ip_address
    generate_env
    generate_keys_and_certs
    build_element
    start_stack

    # Verificar servicios (no fatal si falla, solo advierte)
    if verify_services; then
        show_summary
    else
        echo
        warn "La instalación completó pero algunos servicios requieren atención."
        warn "Revisa la sección anterior para ver los errores."
        echo
        warn "Comandos útiles:"
        warn "  cd ${INSTALL_DIR} && docker compose ps"
        warn "  cd ${INSTALL_DIR} && docker compose logs"
        echo
    fi
}

main "$@"