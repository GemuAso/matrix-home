#!/usr/bin/env bash
# =============================================================================
# generate-certs.sh - Genera certificados SSL auto-firmados para LAN
# -----------------------------------------------------------------------------
# Genera:
#   - CA raiz (ca.crt, ca.key) - valida 10 anos
#   - Cert para matrix.home.arpa (matrix.crt, matrix.key) - 1 ano
#   - Cert para element.home.arpa (element.crt, element.key) - 1 ano
#   - Cert default para catch-all (default.crt, default.key) - 1 ano
#
# Los archivos se guardan en nginx/certs/ con nombres fijos.
# Importa ca.crt en los clientes para evitar warnings del navegador.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Generacion de certificados SSL auto-firmados"

# -----------------------------------------------------------------------------
# Validar .env
# -----------------------------------------------------------------------------
MATRIX_DOMAIN="${NGINX_MATRIX_DOMAIN:-matrix.home.arpa}"
ELEMENT_DOMAIN="${NGINX_ELEMENT_DOMAIN:-element.home.arpa}"

CERTS_DIR="${PROJECT_ROOT}/nginx/certs"
mkdir -p "${CERTS_DIR}"

require_cmd openssl

log "Dominios:"
log "  Matrix:  ${MATRIX_DOMAIN}"
log "  Element: ${ELEMENT_DOMAIN}"
echo

# -----------------------------------------------------------------------------
# Generar CA raiz
# -----------------------------------------------------------------------------
CA_KEY="${CERTS_DIR}/ca.key"
CA_CRT="${CERTS_DIR}/ca.crt"

if [[ -f "${CA_KEY}" && -f "${CA_CRT}" ]]; then
    warn "CA ya existe. Si quieres regenerar, borra ${CA_KEY} y ${CA_CRT} primero."
else
    log "Generando CA raiz..."
    openssl genrsa -out "${CA_KEY}" 4096
    openssl req -new -x509 -key "${CA_KEY}" -out "${CA_CRT}" \
        -days 3650 -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=Matrix LAN CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    chmod 600 "${CA_KEY}"
    log "CA generada: ${CA_CRT} (valida 10 anos)"
fi

# -----------------------------------------------------------------------------
# Funcion para generar cert firmado por la CA (con nombre FIJO)
# -----------------------------------------------------------------------------
generate_signed_cert() {
    local domain="$1"
    local cert_name="$2"
    local key="${CERTS_DIR}/${cert_name}.key"
    local csr="${CERTS_DIR}/${cert_name}.csr"
    local crt="${CERTS_DIR}/${cert_name}.crt"

    if [[ -f "${key}" && -f "${crt}" ]]; then
        warn "Cert para ${domain} ya existe. Saltando."
        return 0
    fi

    log "Generando cert para ${domain}..."
    openssl genrsa -out "${key}" 2048
    openssl req -new -key "${key}" -out "${csr}" \
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=${domain}"

    # Extensiones SAN (Subject Alternative Names)
    cat > "${CERTS_DIR}/${cert_name}.ext" <<EXT_EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${domain}
DNS.2 = localhost
IP.1 = 127.0.0.1
EXT_EOF

    openssl x509 -req -in "${csr}" -CA "${CA_CRT}" -CAkey "${CA_KEY}" \
        -CAcreateserial -out "${crt}" -days 365 -sha256 \
        -extfile "${CERTS_DIR}/${cert_name}.ext"

    rm -f "${csr}" "${CERTS_DIR}/${cert_name}.ext"
    chmod 600 "${key}"
    log "Cert generado: ${crt} (valido 1 ano) -> ${domain}"
}

generate_signed_cert "${MATRIX_DOMAIN}" "matrix"
generate_signed_cert "${ELEMENT_DOMAIN}" "element"

# -----------------------------------------------------------------------------
# Cert default para el catch-all server
# -----------------------------------------------------------------------------
if [[ ! -f "${CERTS_DIR}/default.key" ]] || [[ ! -f "${CERTS_DIR}/default.crt" ]]; then
    log "Generando cert default..."
    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "${CERTS_DIR}/default.key" \
        -out "${CERTS_DIR}/default.crt" \
        -x509 -days 365 \
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=default"
    chmod 600 "${CERTS_DIR}/default.key"
fi

# -----------------------------------------------------------------------------
# Permisos
# -----------------------------------------------------------------------------
chmod 644 "${CERTS_DIR}"/*.crt
chmod 600 "${CERTS_DIR}"/*.key

echo
log "Certificados generados en ${CERTS_DIR}"
log "   Para evitar warnings en el navegador:"
log "   Importa ${CA_CRT} en el trust store de cada cliente."
log "   - Linux:   sudo cp ${CA_CRT} /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
log "   - Windows: Doble clic en ca.crt -> Instalar certificado -> Equipo local -> Entidades de certificacion raiz de confianza"
log "   - macOS:   Anadir a Llavero -> Marcar como confiable"
