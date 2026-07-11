#!/usr/bin/env bash
# =============================================================================
# install.sh - Instalador completo de Matrix Docker Stack v5.1.0
# -----------------------------------------------------------------------------
# Uso: sudo ./install.sh
# Compatible: Ubuntu 22.04/24.04, Debian 11+, Raspberry Pi OS, AMD64/ARM64
#
# Pasos:
#   1-7:  Validaciones (sistema, recursos, Docker, puertos, dependencias, IP, env)
#   8-10: Generación (signing key, certificados, permisos)
#   11-12: Build + despliegue
#   13-15: Verificación, diagnósticos, pruebas
# =============================================================================

set -Eeuo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${INSTALL_DIR}/lib"
source "${LIB_DIR}/install-utils.sh"

if [[ -t 1 ]]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
    C='\033[0;36m' BD='\033[1m' D='\033[2m' NC='\033[0m'
else
    R='' G='' Y='' B='' C='' BD='' D='' NC=''
fi

log()    { echo -e "${G}[$(date '+%H:%M:%S')] [INFO]${NC}  $*"; }
warn()   { echo -e "${Y}[$(date '+%H:%M:%S')] [WARN]${NC}  $*" >&2; }
error()  { echo -e "${R}[$(date '+%H:%M:%S')] [ERROR]${NC} $*" >&2; }
fatal()  { echo -e "${R}[$(date '+%H:%M:%S')] [FATAL]${NC} $*" >&2; exit 1; }
step()   { echo; echo -e "${B}${BD}--- Paso $1/$2: $3 ---${NC}"; }
ok()     { echo -e "${G}  [OK]${NC} $*"; }
fail()   { echo -e "${R}  [FALLO]${NC} $*"; }

TOTAL_STEPS=15

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
    echo -e "${C}  Version 5.1.0 | LAN Privada | Tailscale Ready${NC}"
    echo -e "${C}  Compatible: Ubuntu 22.04/24.04, Debian 11+, Raspberry Pi OS${NC}"
    echo
}

# =============================================================================
# PASO 1: Sistema operativo y arquitectura
# =============================================================================
validate_system() {
    step "1" "${TOTAL_STEPS}" "Validando sistema operativo y arquitectura"

    if [[ -f /.dockerenv ]]; then
        warn "Ejecutandose dentro de un contenedor Docker. No es lo ideal."
    fi

    local arch
    if ! arch=$(check_architecture); then
        fatal "Arquitectura no soportada: ${arch#*:}. Se requiere x86_64 o ARM64."
    fi
    ok "Arquitectura: ${arch}"

    local os_info
    if ! os_info=$(check_os); then
        fatal "Sistema operativo no soportado: ${os_info}. Se requiere Ubuntu 22.04+ o Debian 11+."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    ok "Sistema: ${PRETTY_NAME:-${os_info}}"

    if [[ $EUID -eq 0 ]]; then
        ok "Permisos de root (sudo)"
    else
        warn "Sin permisos de root. No se podran instalar dependencias faltantes."
    fi
}

# =============================================================================
# PASO 2: Recursos del sistema
# =============================================================================
validate_resources() {
    step "2" "${TOTAL_STEPS}" "Validando recursos del sistema"

    local disk_result
    disk_result=$(check_disk_space "${INSTALL_DIR}")
    if [[ "${disk_result}" == INSUFICIENTE:* ]]; then
        fatal "Espacio en disco insuficiente: ${disk_result#*:} GB. Se requieren 5 GB."
    fi
    ok "Espacio en disco: ${disk_result#*:} GB disponibles"

    local mem_result
    mem_result=$(check_memory)
    if [[ "${mem_result}" == INSUFICIENTE:* ]]; then
        fatal "RAM insuficiente: ${mem_result#*:} MB. Se requieren 2048 MB."
    fi
    if [[ "${mem_result}" == "UNKNOWN" ]]; then
        warn "No se pudo detectar RAM."
    else
        ok "RAM: ${mem_result#*:} MB"
    fi

    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "?")
    ok "CPU cores: ${cpu_cores}"
}

# =============================================================================
# PASO 3: Docker y Docker Compose
# =============================================================================
validate_docker() {
    step "3" "${TOTAL_STEPS}" "Validando Docker y Docker Compose"

    if ! docker info >/dev/null 2>&1; then
        if [[ $EUID -eq 0 ]]; then
            log "Iniciando Docker..."
            systemctl enable --now docker >/dev/null 2>&1 || true
            sleep 3
            if ! docker info >/dev/null 2>&1; then
                fatal "No se pudo iniciar Docker. Revisa: systemctl status docker"
            fi
            ok "Docker daemon iniciado"
        else
            fatal "Docker no esta corriendo. Ejecuta con sudo: sudo ./install.sh"
        fi
    else
        ok "Docker daemon corriendo"
    fi

    local docker_ver
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "?")
    ok "Docker version: ${docker_ver}"

    if docker compose version >/dev/null 2>&1; then
        ok "Docker Compose: $(docker compose version --short 2>/dev/null)"
    else
        fatal "Docker Compose v2 no esta instalado. Instala: sudo apt-get install docker-compose-plugin"
    fi

    # Verificar contenedores existentes
    local existing=0
    for name in matrix-postgres matrix-redis matrix-synapse matrix-nginx matrix-element; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
            existing=$((existing + 1))
        fi
    done
    if [[ ${existing} -gt 0 ]]; then
        warn "Se encontraron ${existing} contenedores del stack existentes."
        read -rp "  ¿Detenerlos y reinstalar? [s/N]: " confirm
        if [[ "${confirm}" =~ ^[SsYy] ]]; then
            (cd "${INSTALL_DIR}" && docker compose down --remove-orphans 2>/dev/null) || true
            ok "Stack anterior detenido"
        else
            fatal "Instalacion cancelada."
        fi
    fi
}

# =============================================================================
# PASO 4: Puertos
# =============================================================================
validate_ports() {
    step "4" "${TOTAL_STEPS}" "Validando puertos disponibles"

    # Cargar .env existente si hay
    if [[ -f "${INSTALL_DIR}/.env" ]]; then
        set -a
        source "${INSTALL_DIR}/.env" 2>/dev/null || true
        set +a
    fi

    local http_port="${NGINX_HTTP_PORT:-80}"
    local https_port="${NGINX_HTTPS_PORT:-443}"
    local ports_ok=true

    for port_info in "${http_port}:HTTP" "${https_port}:HTTPS"; do
        local port="${port_info%%:*}"
        local desc="${port_info##*:}"
        local result
        result=$(check_port_free "${port}" 2>/dev/null) || true
        if [[ "${result}" == OCUPADO* ]]; then
            fail "Puerto ${port} (${desc}) en uso"
            ports_ok=false
        else
            ok "Puerto ${port} (${desc}) disponible"
        fi
    done

    if [[ "${ports_ok}" == "false" ]]; then
        fatal "Hay puertos en uso. Liberalos antes de continuar."
    fi
}

# =============================================================================
# PASO 5: Dependencias
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

    # xxd necesario para generar la signing key
    if command -v xxd >/dev/null 2>&1; then
        ok "xxd"
    else
        fail "xxd no encontrado"
        deps_ok=false
    fi

    if [[ "${deps_ok}" == "false" ]]; then
        if [[ $EUID -ne 0 ]]; then
            fatal "Faltan dependencias. Ejecuta con sudo: sudo ./install.sh"
        fi
        local install_result
        install_result=$(install_dependencies)
        if [[ "${install_result}" == INSTALAR:* ]]; then
            local packages="${install_result#*:}"
            log "Instalando: ${packages}"
            # shellcheck disable=SC2086
            apt-get update -qq && apt-get install -y -qq ${packages} >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                fatal "Error al instalar dependencias. Revisa la conexion."
            fi
            ok "Dependencias instaladas"
        fi
    fi
}

# =============================================================================
# PASO 6: Detección de IP
# =============================================================================
detect_ip_address() {
    step "6" "${TOTAL_STEPS}" "Detectando direccion IP"

    local lan_ip="" ts_ip=""

    if lan_ip=$(detect_lan_ip); then
        ok "IP LAN: ${lan_ip}"
    else
        warn "No se pudo detectar IP LAN automaticamente"
    fi

    if ts_ip=$(detect_tailscale_ip); then
        ok "IP Tailscale: ${ts_ip}"
    fi

    echo
    local selected_ip=""
    if [[ -n "${lan_ip}" && -z "${ts_ip}" ]]; then
        read -rp "Usar IP LAN ${lan_ip}? [S/n]: " confirm
        [[ "${confirm}" =~ ^[Nn] ]] || selected_ip="${lan_ip}"
    elif [[ -n "${lan_ip}" && -n "${ts_ip}" ]]; then
        log "  1) LAN:      ${lan_ip}"
        log "  2) Tailscale: ${ts_ip}"
        echo
        read -rp "¿Cual desea utilizar? [1]: " choice
        [[ "${choice}" == "2" ]] && selected_ip="${ts_ip}" || selected_ip="${lan_ip}"
    fi

    if [[ -z "${selected_ip}" ]]; then
        while true; do
            read -rp "Ingrese la IP del servidor: " selected_ip
            [[ -z "${selected_ip}" ]] && continue
            local validation
            validation=$(validate_ip "${selected_ip}")
            [[ "${validation}" == "OK" ]] && break
            error "IP invalida: ${validation#*:}. Intente de nuevo."
        done
    fi

    HOST_IP="${selected_ip}"
    ok "IP seleccionada: ${HOST_IP}"
}

# =============================================================================
# PASO 7: Generar .env
# =============================================================================
generate_env() {
    step "7" "${TOTAL_STEPS}" "Generando .env desde .env.example"

    local env_file="${INSTALL_DIR}/.env"
    local example_file="${INSTALL_DIR}/.env.example"

    if [[ ! -f "${example_file}" ]]; then
        fatal "No se encontro .env.example en ${INSTALL_DIR}"
    fi

    if [[ -f "${env_file}" ]]; then
        warn ".env ya existe."
        read -rp "  ¿Sobrescribir? [s/N]: " overwrite
        if [[ ! "${overwrite}" =~ ^[SsYy] ]]; then
            log "Manteniendo .env existente."
            set -a; source "${env_file}"; set +a
            return 0
        fi
    fi

    log "Generando .env (plantilla: .env.example)..."
    generate_env_file "${env_file}" "${HOST_IP}" "${example_file}"

    # Verificar que no quedaron marcadores
    local remaining
    remaining=$(grep -c '__GENERATE__\|__DYNAMIC__' "${env_file}" 2>/dev/null || echo "0")
    if (( remaining > 0 )); then
        error "Quedaron ${remaining} marcadores sin reemplazar en .env"
        grep '__GENERATE__\|__DYNAMIC__' "${env_file}" 2>/dev/null || true
        fatal "La generacion de .env fallo."
    fi

    set -a; source "${env_file}"; set +a
    ok ".env generado correctamente (7 secretos, 3 dinamicos)"
}

# =============================================================================
# PASO 8: Generar signing key
# =============================================================================
generate_signing_key() {
    step "8" "${TOTAL_STEPS}" "Generando signing key"

    local signing_key="${INSTALL_DIR}/synapse/signing.key"
    if [[ -f "${signing_key}" && -s "${signing_key}" ]]; then
        ok "Signing key ya existe (conservada)"
        return 0
    fi

    mkdir -p "${INSTALL_DIR}/synapse"
    log "Generando signing key (ed25519)..."
    local key_id seed b64_seed
    key_id=$(openssl rand -hex 2)
    seed=$(openssl rand -hex 32)
    b64_seed=$(echo -n "${seed}" | xxd -r -p | base64 | tr -d '\n')
    echo "ed25519 ${key_id} ${b64_seed}" > "${signing_key}"

    if [[ -f "${signing_key}" && -s "${signing_key}" ]]; then
        chmod 600 "${signing_key}"
        ok "Signing key generada"
    else
        fatal "No se pudo generar la signing key."
    fi
}

# =============================================================================
# PASO 9: Generar certificados
# =============================================================================
generate_certs() {
    step "9" "${TOTAL_STEPS}" "Generando certificados TLS"

    local certs_dir="${INSTALL_DIR}/nginx/certs"
    mkdir -p "${certs_dir}"

    local all_exist=true
    for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
        [[ ! -f "${certs_dir}/${f}" ]] && all_exist=false && break
    done

    if [[ "${all_exist}" == "true" ]]; then
        ok "Certificados TLS ya existen (conservados)"
        return 0
    fi

    log "Generando certificados TLS..."
    bash "${INSTALL_DIR}/scripts/linux/generate-certs.sh"

    local missing=0
    for f in ca.crt ca.key matrix.crt matrix.key element.crt element.key default.crt default.key; do
        [[ ! -f "${certs_dir}/${f}" ]] && error "Falta: certs/${f}" && missing=$((missing + 1))
    done
    [[ ${missing} -gt 0 ]] && fatal "No se pudieron generar ${missing} certificados."

    find "${certs_dir}" -name '*.key' -exec chmod 600 {} \; 2>/dev/null || true
    find "${certs_dir}" -name '*.crt' -exec chmod 644 {} \; 2>/dev/null || true
    ok "8 certificados TLS generados"
}

# =============================================================================
# PASO 10: Validar archivos y permisos PRE-BUILD
# =============================================================================
validate_prebuild() {
    step "10" "${TOTAL_STEPS}" "Validando archivos pre-build"

    local errors=0

    # .env
    if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
        fail ".env no existe"; errors=$((errors + 1))
    elif [[ "$(stat -c '%a' "${INSTALL_DIR}/.env" 2>/dev/null)" != "600" ]]; then
        chmod 600 "${INSTALL_DIR}/.env"
        ok ".env permisos corregidos a 600"
    else
        ok ".env existe (600)"
    fi

    # signing.key
    if [[ ! -f "${INSTALL_DIR}/synapse/signing.key" ]] || [[ ! -s "${INSTALL_DIR}/synapse/signing.key" ]]; then
        fail "synapse/signing.key no existe o esta vacio"; errors=$((errors + 1))
    else
        ok "synapse/signing.key existe"
    fi

    # Dockerfiles
    for df in synapse/Dockerfile element/Dockerfile; do
        if [[ ! -f "${INSTALL_DIR}/${df}" ]]; then
            fail "${df} no existe"; errors=$((errors + 1))
        else
            ok "${df} existe"
        fi
    done

    # Entrypoints
    for ep in synapse/entrypoint.sh redis/entrypoint.sh; do
        if [[ ! -f "${INSTALL_DIR}/${ep}" ]]; then
            fail "${ep} no existe"; errors=$((errors + 1))
        else
            ok "${ep} existe"
        fi
    done

    # Templates
    if [[ ! -f "${INSTALL_DIR}/synapse/homeserver.yaml.template" ]]; then
        fail "synapse/homeserver.yaml.template no existe"; errors=$((errors + 1))
    else
        ok "homeserver.yaml.template existe"
    fi

    # Configs Nginx
    for f in nginx/nginx.conf nginx/conf.d/matrix.home.arpa.conf nginx/conf.d/element.home.arpa.conf nginx/conf.d/00-default.conf; do
        if [[ ! -f "${INSTALL_DIR}/${f}" ]]; then
            fail "${f} no existe"; errors=$((errors + 1))
        fi
    done
    [[ ${errors} -eq 0 ]] && ok "Todos los archivos de Nginx existen"

    # PostgreSQL
    for f in postgres/postgresql.conf postgres/pg_hba.conf postgres/init.sql; do
        if [[ ! -f "${INSTALL_DIR}/${f}" ]]; then
            fail "${f} no existe"; errors=$((errors + 1))
        fi
    done
    [[ ${errors} -eq 0 ]] && ok "Todos los archivos de PostgreSQL existen"

    # docker-compose.yml sintaxis
    if (cd "${INSTALL_DIR}" && docker compose config --quiet 2>&1); then
        ok "docker-compose.yml sintaxis valida"
    else
        fail "docker-compose.yml tiene errores de sintaxis"; errors=$((errors + 1))
    fi

    [[ ${errors} -gt 0 ]] && fatal "Se encontraron ${errors} errores. Corrigelos antes de continuar."
}

# =============================================================================
# PASO 11: Construir imagenes
# =============================================================================
build_images() {
    step "11" "${TOTAL_STEPS}" "Construyendo imagenes personalizadas"

    log "Construyendo imagen de Synapse (puede tardar minutos en primer build)..."
    if (cd "${INSTALL_DIR}" && docker compose build --no-cache synapse 2>&1); then
        ok "Imagen matrix-synapse:custom construida"
    else
        error "Fallo al construir imagen de Synapse."
        show_service_diagnostic "synapse" "build"
        fatal "No se pudo construir la imagen. Revisa los errores arriba."
    fi

    log "Construyendo imagen de Element Web..."
    if (cd "${INSTALL_DIR}" && docker compose build --no-cache element 2>&1); then
        ok "Imagen matrix-element:custom construida"
    else
        error "Fallo al construir imagen de Element."
        fatal "Revisa la conexion a Internet y los logs del build."
    fi
}

# =============================================================================
# PASO 12: Despliegue
# =============================================================================
deploy_stack() {
    step "12" "${TOTAL_STEPS}" "Desplegando servicios"

    log "Ejecutando docker compose up -d..."
    if (cd "${INSTALL_DIR}" && docker compose up -d 2>&1); then
        ok "docker compose up -d ejecutado"
    else
        fatal "Error al levantar servicios. Revisa: docker compose config"
    fi
}

# =============================================================================
# Función de diagnóstico automático
# =============================================================================
show_service_diagnostic() {
    local svc="$1"
    local reason="${2:-desconocida}"
    local container="matrix-${svc}"

    echo
    echo -e "${R}========================================${NC}"
    echo -e "${R} DIAGNOSTICO: ${container}${NC}"
    echo -e "${R}========================================${NC}"
    echo

    # Estado del contenedor
    echo -e "${BD}--- Estado del contenedor ---${NC}"
    docker ps -a --filter "name=${container}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Contenedor no encontrado"
    echo

    # Inspección detallada
    echo -e "${BD}--- Inspeccion ---${NC}"
    local state exit_code
    state=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null || echo "missing")
    exit_code=$(docker inspect --format='{{.State.ExitCode}}' "${container}" 2>/dev/null || echo "?")
    echo "  Estado:    ${state}"
    echo "  Exit code: ${exit_code}"
    echo "  Razon:     ${reason}"
    echo

    # Últimos logs
    echo -e "${BD}--- Últimos 30 lineas de log ---${NC}"
    docker logs --tail 30 "${container}" 2>&1 | sed 's/^/  /' || echo "  No se pudieron obtener logs"
    echo

    # Solución sugerida
    echo -e "${BD}--- Posible solucion ---${NC}"
    case "${svc}" in
        postgres)
            echo "  1. Revisa postgres/postgresql.conf (no debe tener server_version)"
            echo "  2. docker compose logs matrix-postgres"
            echo "  3. Si el volumen esta corrupto: docker compose down -v && sudo ./install.sh"
            ;;
        redis)
            echo "  1. docker compose logs matrix-redis"
            echo "  2. Verifica que redis/redis.conf.template y redis/entrypoint.sh existen"
            ;;
        synapse)
            echo "  1. Verifica que la imagen se construyo: docker images | grep synapse"
            echo "  2. docker compose logs matrix-synapse"
            echo "  3. Verifica que signing.key existe: ls -la synapse/signing.key"
            echo "  4. Verifica que .env no tenga valores __GENERATE__"
            echo "  5. Rebuild: docker compose build --no-cache synapse"
            ;;
        element)
            echo "  1. docker compose logs matrix-element"
            echo "  2. Rebuild: docker compose build --no-cache element"
            ;;
        nginx)
            echo "  1. docker compose logs matrix-nginx"
            echo "  2. Verifica certificados: ls -la nginx/certs/"
            echo "  3. docker compose exec nginx nginx -t"
            ;;
    esac
    echo
    echo -e "${R}========================================${NC}"
    echo
}

# =============================================================================
# PASO 13: Verificar servicios (con detección de Created/Dead/Unhealthy)
# =============================================================================
verify_services() {
    step "13" "${TOTAL_STEPS}" "Verificando estado de los servicios"

    local services=("postgres" "redis" "synapse" "element" "nginx")
    local all_ok=true

    for svc in "${services[@]}"; do
        local container="matrix-${svc}"
        log "Verificando ${container}..."

        # Timeout por servicio
        local timeout=180
        case "${svc}" in
            postgres) timeout=120 ;;
            redis)   timeout=60  ;;
            synapse) timeout=300 ;;  # Mas tiempo: primer arranque genera DB
            element) timeout=60  ;;
            nginx)   timeout=60  ;;
        esac

        local elapsed=0
        while true; do
            local state
            state=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "missing")

            if [[ "${state}" == "healthy" ]]; then
                ok "${container} - healthy"
                break
            fi

            # Detectar estados erroneos
            local raw_state
            raw_state=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null || echo "missing")

            if [[ "${raw_state}" == "created" ]]; then
                fail "${container} - estado 'created' (nunca inicio)"
                show_service_diagnostic "${svc}" "Contenedor creado pero nunca inicio. Posible causa: dependencia no saludable, imagen no existe, o error en entrypoint."
                all_ok=false
                break
            fi

            if [[ "${raw_state}" == "dead" ]]; then
                fail "${container} - estado 'dead'"
                show_service_diagnostic "${svc}" "Contenedor en estado 'dead'. Posible causa: crash en entrypoint o sin memoria."
                all_ok=false
                break
            fi

            if [[ "${state}" == "unhealthy" ]]; then
                fail "${container} - unhealthy"
                show_service_diagnostic "${svc}" "Contenedor arranco pero el healthcheck falla."
                all_ok=false
                break
            fi

            if [[ "${raw_state}" == "exited" ]]; then
                local exit_code
                exit_code=$(docker inspect --format='{{.State.ExitCode}}' "${container}" 2>/dev/null || echo "?")
                fail "${container} - exited (code ${exit_code})"
                show_service_diagnostic "${svc}" "Contenedor salio con codigo ${exit_code}."
                all_ok=false
                break
            fi

            if [[ "${raw_state}" == "restarting" ]]; then
                # Permitir algunos restarts pero no infinitos
                local restart_count
                restart_count=$(docker inspect --format='{{.RestartCount}}' "${container}" 2>/dev/null || echo "0")
                if (( restart_count > 5 )); then
                    fail "${container} - reiniciando continuamente (${restart_count} restarts)"
                    show_service_diagnostic "${svc}" "El contenedor se reinicia en bucle. Muy probablemente el entrypoint falla."
                    all_ok=false
                    break
                fi
            fi

            # Timeout
            if (( elapsed >= timeout )); then
                fail "${container} - timeout (${timeout}s)"
                show_service_diagnostic "${svc}" "El servicio no alcanzo estado 'healthy' en ${timeout}s."
                all_ok=false
                break
            fi

            sleep 5
            elapsed=$((elapsed + 5))
            printf "."
        done
        echo
    done

    [[ "${all_ok}" == "false" ]] && fatal "Servicios fallaron. Revisa los diagnosticos arriba."
}

# =============================================================================
# PASO 14: Pruebas automáticas
# =============================================================================
run_tests() {
    step "14" "${TOTAL_STEPS}" "Ejecutando pruebas automaticas"

    local passed=0 failed=0
    local results=()

    # Helper
    add_pass() { results+=("${G}✓${NC} $1"); ((passed++)); }
    add_fail() { results+=("${R}✗${NC} $1 ($2)"); ((failed++)); }

    docker info >/dev/null 2>&1 && add_pass "Docker" || add_fail "Docker" "daemon no corriendo"
    docker compose version >/dev/null 2>&1 && add_pass "Docker Compose" || add_fail "Docker Compose" "no instalado"

    # .env sin marcadores
    if [[ -f "${INSTALL_DIR}/.env" ]] && ! grep -q '__GENERATE__\|__DYNAMIC__' "${INSTALL_DIR}/.env" 2>/dev/null; then
        add_pass "Secretos (.env)"
    else
        add_fail "Secretos (.env)" "marcadores sin reemplazar"
    fi

    [[ -f "${INSTALL_DIR}/synapse/signing.key" ]] && [[ -s "${INSTALL_DIR}/synapse/signing.key" ]] && add_pass "Signing Key" || add_fail "Signing Key" "no existe o vacio"

    [[ -f "${INSTALL_DIR}/nginx/certs/ca.crt" ]] && add_pass "Certificados TLS" || add_fail "Certificados TLS" "falta ca.crt"

    # Health de cada servicio
    for svc in postgres redis synapse element nginx; do
        local st
        st=$(docker inspect --format='{{.State.Health.Status}}' "matrix-${svc}" 2>/dev/null || echo "missing")
        [[ "${st}" == "healthy" ]] && add_pass "${svc^}" || add_fail "${svc^}" "estado: ${st}"
    done

    # Nginx healthz via HTTP
    docker exec matrix-nginx wget -q --spider http://localhost/healthz 2>/dev/null && add_pass "Nginx /healthz" || add_fail "Nginx /healthz" "no responde"

    # Synapse /health via curl
    docker exec matrix-synapse curl -fSs http://localhost:8008/health 2>/dev/null | grep -q "OK" && add_pass "Matrix API /health" || add_fail "Matrix API /health" "no responde o no contiene OK"

    # Config Synapse sin variables sin sustituir
    if docker exec matrix-synapse test -f /data/homeserver.yaml 2>/dev/null; then
        if ! docker exec matrix-synapse grep -q '\${[A-Z_]*}' /data/homeserver.yaml 2>/dev/null; then
            add_pass "Config Synapse valida"
        else
            add_fail "Config Synapse" "variables sin sustituir"
        fi
    else
        add_fail "Config Synapse" "homeserver.yaml no existe"
    fi

    # Permisos
    [[ "$(stat -c '%a' "${INSTALL_DIR}/.env" 2>/dev/null)" == "600" ]] && add_pass "Permisos .env" || add_fail "Permisos .env" "no es 600"

    # Mostrar resultados
    echo
    echo -e "${BD}  Resultado de las pruebas:${NC}"
    echo -e "  ${D}-------------------------------------------${NC}"
    for r in "${results[@]}"; do echo -e "  ${r}"; done
    echo -e "  ${D}-------------------------------------------${NC}"
    echo -e "  ${BD}Total: ${passed} aprobadas, ${failed} fallidas${NC}"
    echo

    [[ ${failed} -gt 0 ]] && fatal "${failed} pruebas fallaron. La instalacion no es exitosa."
}

# =============================================================================
# PASO 15: Resumen final
# =============================================================================
show_summary() {
    local ts_line=""
    if command -v tailscale >/dev/null 2>&1; then
        local ts_ip
        ts_ip=$(detect_tailscale_ip 2>/dev/null || echo "")
        [[ -n "${ts_ip}" ]] && ts_line=$(echo -e "  ${G}✓${NC} Tailscale:  https://${ts_ip}")
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
    echo -e "  ${G}✓${NC} Element Web"
    echo -e "  ${G}✓${NC} Nginx"
    echo
    echo -e "${BD}  Accesos:${NC}"
    echo -e "  https://matrix.home.arpa  (servidor)"
    echo -e "  https://element.home.arpa  (cliente)"
    echo "${ts_line}"
    echo
    echo -e "${BD}  DNS en clientes:${NC}"
    echo "  ${HOST_IP}  matrix.home.arpa"
    echo "  ${HOST_IP}  element.home.arpa"
    echo
    echo -e "${BD}  Certificado CA:${NC}"
    echo "  Linux:   sudo cp nginx/certs/ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
    echo "  Windows: Doble clic en nginx/certs/ca.crt -> Instalar -> Raiz de confianza"
    echo
    echo -e "${BD}  Crear admin:${NC}"
    echo "  docker compose exec synapse register_new_matrix_user -c http://localhost:8008 -a admin"
    echo
    echo -e "${BD}  Administracion:${NC}"
    echo "  sudo ./scripts/admin/healthcheck.sh"
    echo "  sudo ./scripts/admin/backup.sh"
    echo "  sudo ./scripts/admin/restart.sh"
    echo "  sudo ./uninstall.sh"
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
    validate_prebuild
    build_images
    deploy_stack
    verify_services
    run_tests
    show_summary
}

main "$@"