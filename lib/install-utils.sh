#!/usr/bin/env bash
# =============================================================================
# install-utils.sh - Funciones modulares para el instalador de Matrix
# -----------------------------------------------------------------------------
# Este archivo NO se ejecuta directamente. Se incluye con `source` desde
# install.sh u otros scripts que necesiten sus funciones.
#
# Todas las funciones son reutilizables y están pensadas para ser extendidas
# fácilmente cuando el proyecto incorpore nuevos componentes.
# =============================================================================

# -----------------------------------------------------------------------------
# Generación criptográficamente segura de secretos
# -----------------------------------------------------------------------------
generate_secret_hex() {
    # Genera 64 caracteres hex (32 bytes). Cryptográficamente seguro.
    openssl rand -hex 32 2>/dev/null
}

generate_secret_base64() {
    # Genera ~43 caracteres base64 (32 bytes). Cryptográficamente seguro.
    openssl rand -base64 32 2>/dev/null | tr -d '\n'
}

generate_secret_password() {
    # Genera contraseña de 32 caracteres: alfanumérica + símbolos.
    # Evita caracteres ambiguos (0/O, 1/l/I).
    openssl rand -base64 32 2>/dev/null | tr -d '\n/+=' | tr 'A-Z' 'a-z' | head -c 32
}

# -----------------------------------------------------------------------------
# Detección de red (solo herramientas locales, sin servicios externos)
# -----------------------------------------------------------------------------
detect_lan_ip() {
    # Detecta la IP LAN del host usando `ip route`.
    # No utiliza ningún servicio HTTP externo.
    local gateway_ip
    gateway_ip=$(ip route show default 2>/dev/null | awk '/default/ {print $3}')
    if [[ -z "${gateway_ip}" ]]; then
        return 1
    fi

    local interface
    interface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}')
    if [[ -z "${interface}" ]]; then
        return 1
    fi

    local host_ip
    host_ip=$(ip -4 addr show "${interface}" 2>/dev/null \
        | grep -oP 'inet \K[0-9]+(\.[0-9]+){3}')
    if [[ -z "${host_ip}" ]]; then
        return 1
    fi

    echo "${host_ip}"
    return 0
}

detect_tailscale_ip() {
    # Detecta la IP de Tailscale si está instalado.
    if ! command -v tailscale >/dev/null 2>&1; then
        return 1
    fi

    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null) || return 1

    if [[ -z "${ts_ip}" ]]; then
        return 1
    fi

    echo "${ts_ip}"
    return 0
}

detect_lan_cidr() {
    # Deriva el CIDR de la LAN a partir de la IP detectada.
    local ip="$1"
    local first_octet
    first_octet="${ip%%.*}"

    case "${first_octet}" in
        10)   echo "10.0.0.0/8" ;;
        172)  echo "172.16.0.0/12" ;;
        192)  echo "192.168.1.0/24" ;;
        *)    echo "${ip}/32" ;;
    esac
}

# -----------------------------------------------------------------------------
# Validación de IPv4
# -----------------------------------------------------------------------------
is_valid_ipv4() {
    local ip="$1"
    # Regex estricta para IPv4
    local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
    if [[ ! "${ip}" =~ ${regex} ]]; then
        return 1
    fi

    # Validar cada octeto
    for i in 1 2 3 4; do
        local octet="${BASH_REMATCH[$i]}"
        if (( octet > 255 )); then
            return 1
        fi
    done
    return 0
}

is_private_ipv4() {
    local ip="$1"
    is_valid_ipv4 "${ip}" || return 1

    local regex='^([0-9]{1,3})\.'
    [[ "${ip}" =~ ${regex} ]]
    local first="${BASH_REMATCH[1]}"
    local second
    second=$(echo "${ip}" | awk -F. '{print $2}')

    # 10.0.0.0/8
    if (( first == 10 )); then return 0; fi
    # 172.16.0.0/12
    if (( first == 172 )) && (( second >= 16 )) && (( second <= 31 )); then return 0; fi
    # 192.168.0.0/16
    if (( first == 192 )) && (( second == 168 )); then return 0; fi

    return 1
}

is_reserved_ipv4() {
    local ip="$1"
    is_valid_ipv4 "${ip}" || return 0  # Si no es válida, la rechazamos

    # Loopback: 127.0.0.0/8
    [[ "${ip}" == 127.* ]] && return 0
    # Multicast: 224.0.0.0/4
    local first="${ip%%.*}"
    (( first >= 224 )) && (( first <= 239 )) && return 0
    # 0.0.0.0
    [[ "${ip}" == "0.0.0.0" ]] && return 0
    # Link-local: 169.254.0.0/16
    [[ "${ip}" == 169.254.* ]] && return 0

    return 1
}

validate_ip() {
    local ip="$1"
    if ! is_valid_ipv4 "${ip}"; then
        echo "INVALIDA: formato IPv4 no válido"
        return 1
    fi
    if is_reserved_ipv4 "${ip}"; then
        echo "INVALIDA: es una IP reservada, loopback, multicast o link-local"
        return 1
    fi
    if ! is_private_ipv4 "${ip}"; then
        echo "INVALIDA: no es una IP de red privada (RFC 1918)"
        return 1
    fi
    echo "OK"
    return 0
}

# -----------------------------------------------------------------------------
# Validaciones del sistema
# -----------------------------------------------------------------------------
check_architecture() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64)
            echo "x86_64"
            return 0
            ;;
        aarch64|arm64)
            echo "arm64"
            return 0
            ;;
        *)
            echo "UNSOPORTED:${arch}"
            return 1
            ;;
    esac
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo "UNKNOWN"
        return 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    echo "${ID}:${VERSION_ID}"
    case "${ID}" in
        ubuntu)
            # Verificar que sea 20.04+
            local major
            major=$(echo "${VERSION_ID}" | awk -F. '{print $1}')
            if (( major >= 20 )); then
                return 0
            else
                return 1
            fi
            ;;
        debian)
            local deb_major
            deb_major=$(echo "${VERSION_ID}" | awk -F. '{print $1}')
            if (( deb_major >= 11 )); then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

check_disk_space() {
    # Requiere al menos 5 GB libres en la partición del proyecto.
    local min_gb=5
    local available_kb
    available_kb=$(df -k --output=avail "$(dirname "$1")" 2>/dev/null | tail -1)
    local available_gb=$((available_kb / 1024 / 1024))

    if (( available_gb < min_gb )); then
        echo "INSUFICIENTE:${available_gb}"
        return 1
    fi
    echo "OK:${available_gb}"
    return 0
}

check_memory() {
    # Requiere al menos 2 GB de RAM.
    local min_mb=2048
    local total_kb
    total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -z "${total_kb}" ]]; then
        echo "UNKNOWN"
        return 0  # No bloquear si no se puede detectar
    fi
    local total_mb=$((total_kb / 1024))

    if (( total_mb < min_mb )); then
        echo "INSUFICIENTE:${total_mb}"
        return 1
    fi
    echo "OK:${total_mb}"
    return 0
}

# -----------------------------------------------------------------------------
# Instalación de dependencias (solo Ubuntu/Debian)
# -----------------------------------------------------------------------------
install_dependencies() {
    local to_install=()
    local cmds=("docker" "docker compose" "openssl" "curl" "git" "ip")

    for cmd_spec in "${cmds[@]}"; do
        if [[ "${cmd_spec}" == "docker compose" ]]; then
            if ! docker compose version >/dev/null 2>&1; then
                to_install+=("docker-compose-plugin")
            fi
        elif ! command -v "${cmd_spec}" >/dev/null 2>&1; then
            case "${cmd_spec}" in
                docker) to_install+=("docker.io" "docker-compose-plugin") ;;
                ip)    to_install+=("iproute2") ;;
                *)     to_install+=("${cmd_spec}") ;;
            esac
        fi
    done

    if (( ${#to_install[@]} == 0 )); then
        return 0
    fi

    echo "INSTALAR:${to_install[*]}"
    return 0
}

# -----------------------------------------------------------------------------
# Generación del archivo .env completo
# -----------------------------------------------------------------------------
generate_env_file() {
    local target_file="$1"
    local host_ip="$2"

    local pg_pass redis_pass reg_secret macaroon_secret form_secret \
          pepper admin_token

    pg_pass=$(generate_secret_password)
    redis_pass=$(generate_secret_hex)
    reg_secret=$(generate_secret_hex)
    macaroon_secret=$(generate_secret_hex)
    form_secret=$(generate_secret_hex)
    pepper=$(generate_secret_hex)
    admin_token=$(generate_secret_hex)

    cat > "${target_file}" <<ENV_EOF
# =============================================================================
# .env - Generado automáticamente por install.sh
# Fecha: $(date -Iseconds)
# IP del servidor: ${host_ip}
# -----------------------------------------------------------------------------
# NO edites este archivo manualmente a menos que sepas lo que haces.
# Los secretos fueron generados con openssl rand (criptográficamente seguros).
# =============================================================================

# -----------------------------------------------------------------------------
# Configuracion general
# -----------------------------------------------------------------------------
TZ=America/Bogota

# -----------------------------------------------------------------------------
# Matrix Synapse - Identidad del servidor
# -----------------------------------------------------------------------------
SYNAPSE_SERVER_NAME=home.arpa
SYNAPSE_PUBLIC_URL=https://matrix.home.arpa
SYNAPSE_REPORT_STATS=false
SYNAPSE_LOG_CONFIG=/data/homeserver.log.config

# -----------------------------------------------------------------------------
# Matrix Synapse - Registro de usuarios
# -----------------------------------------------------------------------------
SYNAPSE_ENABLE_REGISTRATION=false
SYNAPSE_REGISTRATION_SHARED_SECRET=${reg_secret}
SYNAPSE_MACAROON_SECRET_KEY=${macaroon_secret}
SYNAPSE_ADMIN_API_TOKEN=${admin_token}
SYNAPSE_FORM_SECRET=${form_secret}
SYNAPSE_PASSWORD_PEPPER=${pepper}

# -----------------------------------------------------------------------------
# PostgreSQL - Base de datos
# -----------------------------------------------------------------------------
POSTGRES_USER=synapse_user
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=synapse
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# -----------------------------------------------------------------------------
# Redis - Cache y pubsub
# -----------------------------------------------------------------------------
REDIS_PASSWORD=${redis_pass}

# -----------------------------------------------------------------------------
# SMTP - Correo electronico para notificaciones
# -----------------------------------------------------------------------------
SMTP_HOST=smtp.home.arpa
SMTP_PORT=587
SMTP_USER=noresponder@home.arpa
SMTP_PASS=
SMTP_FROM=noresponder@home.arpa
SMTP_FROM_NAME=Matrix Notificaciones
SMTP_TLS=true
SMTP_REQUIRE_TLS=true
SMTP_THROTTLE_PERHOUR=50

# -----------------------------------------------------------------------------
# Element Web
# -----------------------------------------------------------------------------
ELEMENT_URL=https://element.home.arpa

# -----------------------------------------------------------------------------
# Nginx - Reverse Proxy
# -----------------------------------------------------------------------------
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
NGINX_MATRIX_DOMAIN=matrix.home.arpa
NGINX_ELEMENT_DOMAIN=element.home.arpa

# -----------------------------------------------------------------------------
# Backups
# -----------------------------------------------------------------------------
BACKUP_RETENTION_DAYS=7
BACKUP_DIR=./backups

# -----------------------------------------------------------------------------
# Red LAN
# -----------------------------------------------------------------------------
LAN_CIDR=$(detect_lan_cidr "${host_ip}")
HOST_IP=${host_ip}
ENV_EOF

    chmod 600 "${target_file}"
}