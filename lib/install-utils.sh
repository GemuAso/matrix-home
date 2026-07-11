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
    # Determina el CIDR real de la LAN usando `ip route` sobre la
    # interfaz que tiene la ruta por defecto. Ya no se basa en adivinar
    # a partir del primer octeto; en su lugar consulta la tabla de rutas
    # del kernel para obtener la red exacta (p.ej. 192.168.50.0/24).
    #
    # Parámetro opcional $1: dirección IP del host (se usa como reserva
    # si no se puede determinar el CIDR por ruta).
    local ip="$1"
    local interface cidr

    # Obtener la interfaz de la ruta por defecto
    interface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}')
    if [[ -n "${interface}" ]]; then
        # Buscar la ruta de red conectada (proto kernel / scope link)
        # que pertenece a esa interfaz. El formato típico es:
        #   192.168.50.0/24 dev eth0 proto kernel scope link src 192.168.50.10
        cidr=$(ip route show dev "${interface}" scope link proto kernel 2>/dev/null \
            | awk '{print $1}' | head -1)

        # Filtrar solo entradas que parezcan un CIDR válido (contienen /)
        if [[ -n "${cidr}" ]] && [[ "${cidr}" == */* ]]; then
            echo "${cidr}"
            return 0
        fi

        # Reserva: usar `ip addr` para obtener la IP con su máscara de prefijo
        # p.ej. "192.168.50.10/24" -> derivar "192.168.50.0/24"
        local addr_with_prefix
        addr_with_prefix=$(ip -4 addr show "${interface}" 2>/dev/null \
            | grep -oP 'inet \K[0-9]+(\.[0-9]+){3}/[0-9]+' | head -1)
        if [[ -n "${addr_with_prefix}" ]]; then
            local prefix="${addr_with_prefix#*/}"
            local host_part="${addr_with_prefix%/*}"
            # Calcular la dirección de red aplicando la máscara
            local IFS='.'
            # shellcheck disable=SC2206
            local octets=(${host_part})
            IFS=' '
            case "${prefix}" in
                8)  echo "${octets[0]}.0.0.0/${prefix}" ;;
                16) echo "${octets[0]}.${octets[1]}.0.0/${prefix}" ;;
                24) echo "${octets[0]}.${octets[1]}.${octets[2]}.0/${prefix}" ;;
                *)  echo "${host_part}/${prefix}" ;;
            esac
            return 0
        fi
    fi

    # Último recurso: derivar del primer octeto (comportamiento original)
    if [[ -n "${ip}" ]]; then
        local first_octet="${ip%%.*}"
        case "${first_octet}" in
            10)   echo "10.0.0.0/8" ;;
            172)  echo "172.16.0.0/12" ;;
            192)  echo "192.168.1.0/24" ;;
            *)    echo "${ip}/32" ;;
        esac
        return 0
    fi

    # Sin información suficiente
    echo "0.0.0.0/0"
    return 1
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
            # Verificar que sea 22.04+
            local major
            major=$(echo "${VERSION_ID}" | awk -F. '{print $1}')
            if (( major >= 22 )); then
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
        raspbian)
            # Raspberry Pi OS (basado en Debian)
            local rpi_major
            rpi_major=$(echo "${VERSION_ID}" | awk -F. '{print $1}')
            if (( rpi_major >= 11 )); then
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
# Instalación de dependencias (solo Ubuntu/Debian/Raspberry Pi OS)
# -----------------------------------------------------------------------------
install_dependencies() {
    local to_install=()
    local cmds=("docker" "docker compose" "openssl" "curl" "git" "ip" "xxd")

    for cmd_spec in "${cmds[@]}"; do
        if [[ "${cmd_spec}" == "docker compose" ]]; then
            if ! docker compose version >/dev/null 2>&1; then
                to_install+=("docker-compose-plugin")
            fi
        elif ! command -v "${cmd_spec}" >/dev/null 2>&1; then
            case "${cmd_spec}" in
                docker) to_install+=("docker.io" "docker-compose-plugin") ;;
                ip)    to_install+=("iproute2") ;;
                xxd)   # Puede estar en vim-common o en el paquete xxd (Debian 12+)
                       to_install+=("xxd") ;;
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
# Validación de puertos
# -----------------------------------------------------------------------------
check_port_free() {
    # Verifica si un puerto TCP está libre (no en uso).
    # Usa `ss` preferiblemente; si no está disponible, recurre a `netstat`.
    #
    # Parámetro $1: número de puerto (1-65535)
    #
    # Devuelve:
    #   0 y "LIBRE"       si el puerto no está en uso
    #   1 y "OCUPADO:..." si el puerto ya está en uso por un proceso
    #   2 y "INVALIDO"    si el número de puerto no es válido
    local port="$1"

    # Validar que sea un número de puerto válido
    if ! [[ "${port}" =~ ^[0-9]+$ ]] || (( port < 1 )) || (( port > 65535 )); then
        echo "INVALIDO"
        return 2
    fi

    local listener_info=""

    # Intentar primero con `ss` (disponible en sistemas modernos)
    if command -v ss >/dev/null 2>&1; then
        listener_info=$(ss -tlnH 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {print $0; exit}')
    # Reserva con `netstat`
    elif command -v netstat >/dev/null 2>&1; then
        listener_info=$(netstat -tln 2>/dev/null | awk -v p="${port}" '$4 ~ ":"p"$" {print $0; exit}')
    else
        # Ninguna herramienta disponible: no se puede determinar, asumir libre
        echo "LIBRE:desconocido"
        return 0
    fi

    if [[ -n "${listener_info}" ]]; then
        echo "OCUPADO:${port} - ${listener_info}"
        return 1
    fi

    echo "LIBRE"
    return 0
}

# -----------------------------------------------------------------------------
# Validación de versión de Docker
# -----------------------------------------------------------------------------
check_docker_version() {
    # Verifica que Docker esté instalado y su versión sea suficiente.
    # La versión mínima recomendada es 20.10.x (soporte completo de
    # docker compose v2 y características de red modernas).
    #
    # Devuelve:
    #   0 y "OK:<versión>"              si la versión es suficiente
    #   1 y "ANTIGUA:<versión>:<mínima>" si la versión es muy vieja
    #   2 y "NO_INSTALADO"              si Docker no está disponible
    local min_major=20
    local min_minor=10

    if ! command -v docker >/dev/null 2>&1; then
        echo "NO_INSTALADO"
        return 2
    fi

    local version_str
    version_str=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    if [[ -z "${version_str}" ]]; then
        # Si no se puede obtener la versión del servidor, intentar con el cliente
        version_str=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
    fi
    if [[ -z "${version_str}" ]]; then
        echo "NO_INSTALADO"
        return 2
    fi

    # Extraer versión mayor y menor (p.ej. "24.0.7" -> mayor=24, menor=0)
    local ver_major ver_minor
    ver_major=$(echo "${version_str}" | awk -F. '{print $1}')
    ver_minor=$(echo "${version_str}" | awk -F. '{print $2}')

    # Asegurar que son números (si contienen caracteres extra, la comparación
    # aritmética en bash los ignora)
    ver_major=$((ver_major + 0))
    ver_minor=$((ver_minor + 0))

    if (( ver_major > min_major )) || \
       { (( ver_major == min_major )) && (( ver_minor >= min_minor )); }; then
        echo "OK:${version_str}"
        return 0
    else
        echo "ANTIGUA:${version_str}:${min_major}.${min_minor}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Ayudantes de permisos de archivos
# -----------------------------------------------------------------------------
ensure_permissions() {
    # Establece permisos correctos sobre uno o más archivos.
    # Útil para asegurar que archivos sensibles (claves, .env, configuración)
    # tengan los permisos adecuados después de la instalación.
    #
    # Uso:
    #   ensure_permissions 600 /ruta/al/archivo_secreto
    #   ensure_permissions 750 /ruta/al/directorio
    #
    # Parámetros:
    #   $1      - permisos en formato octal (p.ej. 600, 640, 750)
    #   $2 ...  - rutas a archivos o directorios
    #
    # Devuelve:
    #   0 si todos los cambios tuvieron éxito
    #   1 si algún archivo no existe o no se pudo cambiar
    local perms="$1"
    shift
    local errores=0

    # Validar formato octal
    if ! [[ "${perms}" =~ ^[0-7]{3,4}$ ]]; then
        echo "ERROR: permisos '${perms}' no válidos (se espera formato octal, p.ej. 600)"
        return 1
    fi

    for ruta in "$@"; do
        if [[ ! -e "${ruta}" ]]; then
            echo "ERROR: no existe '${ruta}'"
            errores=$((errores + 1))
            continue
        fi
        if ! chmod "${perms}" "${ruta}" 2>/dev/null; then
            echo "ERROR: no se pudieron establecer permisos ${perms} en '${ruta}'"
            errores=$((errores + 1))
        fi
    done

    if (( errores > 0 )); then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Generación del archivo .env a partir de .env.example (UNICA plantilla)
# -----------------------------------------------------------------------------
# Copia .env.example y reemplaza:
#   __GENERATE__  → secreto criptografico (cada uno unico)
#   __DYNAMIC__   → valor detectado en tiempo de ejecucion (IP, CIDR, fecha)
#
# Todos los demas valores provienen exclusivamente de .env.example.
# No existe ninguna segunda fuente de configuracion.
# -----------------------------------------------------------------------------
generate_env_file() {
    local target_file="$1"
    local host_ip="$2"
    local example_file="$3"

    # Verificar que .env.example existe
    if [[ ! -f "${example_file}" ]]; then
        echo "ERROR: No se encontro ${example_file}"
        return 1
    fi

    # Generar secretos unicos para cada marcador __GENERATE__
    # Cada variable recibe su propio generador apropiado al tipo de uso
    local pg_pass redis_pass reg_secret macaroon_secret form_secret \
          pepper admin_token

    pg_pass=$(generate_secret_password)       # Password alfanumerica
    redis_pass=$(generate_secret_hex)          # Hex para compatibilidad Redis
    reg_secret=$(generate_secret_hex)
    macaroon_secret=$(generate_secret_hex)
    form_secret=$(generate_secret_hex)
    pepper=$(generate_secret_hex)
    admin_token=$(generate_secret_hex)

    # Copiar .env.example como base
    cp "${example_file}" "${target_file}"

    # Reemplazar cada marcador __GENERATE__ individualmente
    # (no usar un bucle generico para evitar sustituciones parciales)
    sed -i "s|^POSTGRES_PASSWORD=__GENERATE__$|POSTGRES_PASSWORD=${pg_pass}|"       "${target_file}"
    sed -i "s|^REDIS_PASSWORD=__GENERATE__$|REDIS_PASSWORD=${redis_pass}|"         "${target_file}"
    sed -i "s|^SYNAPSE_REGISTRATION_SHARED_SECRET=__GENERATE__$|SYNAPSE_REGISTRATION_SHARED_SECRET=${reg_secret}|" "${target_file}"
    sed -i "s|^SYNAPSE_MACAROON_SECRET_KEY=__GENERATE__$|SYNAPSE_MACAROON_SECRET_KEY=${macaroon_secret}|"     "${target_file}"
    sed -i "s|^SYNAPSE_ADMIN_API_TOKEN=__GENERATE__$|SYNAPSE_ADMIN_API_TOKEN=${admin_token}|"                 "${target_file}"
    sed -i "s|^SYNAPSE_FORM_SECRET=__GENERATE__$|SYNAPSE_FORM_SECRET=${form_secret}|"                         "${target_file}"
    sed -i "s|^SYNAPSE_PASSWORD_PEPPER=__GENERATE__$|SYNAPSE_PASSWORD_PEPPER=${pepper}|"                     "${target_file}"

    # Reemplazar marcadores dinamicos
    local lan_cidr
    lan_cidr=$(detect_lan_cidr "${host_ip}")
    sed -i "s|^LAN_CIDR=__DYNAMIC__$|LAN_CIDR=${lan_cidr}|"     "${target_file}"
    sed -i "s|^HOST_IP=__DYNAMIC__$|HOST_IP=${host_ip}|"       "${target_file}"
    sed -i "s|^INSTALL_DATE=__DYNAMIC__$|INSTALL_DATE=$(date -Iseconds)|" "${target_file}"

    # Verificar que no quedaron marcadores sin reemplazar
    local remaining
    remaining=$(grep -c '__GENERATE__\|__DYNAMIC__' "${target_file}" 2>/dev/null || true)
    if (( remaining > 0 )); then
        echo "WARN: Quedaron ${remaining} marcadores sin reemplazar en .env"
        grep '__GENERATE__\|__DYNAMIC__' "${target_file}" 2>/dev/null || true
    fi

    # Agregar cabecera con metadatos (sin sobreescribir el archivo)
    local header_temp
    header_temp=$(mktemp)
    cat > "${header_temp}" <<HEADER_EOF
# =============================================================================
# .env - Generado automaticamente por install.sh
# Fecha: $(date -Iseconds)
# IP del servidor: ${host_ip}
# Version: 5.1.0
# -----------------------------------------------------------------------------
# NO edites este archivo manualmente a menos que sepas lo que haces.
# Los secretos fueron generados con openssl rand (criptograficamente seguros).
# La plantilla original es .env.example - no existen dos fuentes de verdad.
# =============================================================================

HEADER_EOF

    # Insertar cabecera al inicio
    cat "${header_temp}" "${target_file}" > "${target_file}.tmp"
    mv "${target_file}.tmp" "${target_file}"
    rm -f "${header_temp}"

    chmod 600 "${target_file}"
}