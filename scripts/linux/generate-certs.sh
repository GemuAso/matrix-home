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
# TODOS los certificados incluyen SAN unificado:
#   DNS: matrix.home.arpa, element.home.arpa, localhost
#   IP:  127.0.0.1
#
# Esto permite que cualquier cert funcione para cualquier dominio del stack.
# Los archivos se guardan en nginx/certs/ con nombres fijos.
# Importa ca.crt en los clientes para evitar warnings del navegador.
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Generacion de certificados SSL auto-firmados"

# -----------------------------------------------------------------------------
# Validar .env y dominios
# -----------------------------------------------------------------------------
MATRIX_DOMAIN="${NGINX_MATRIX_DOMAIN:-matrix.home.arpa}"
ELEMENT_DOMAIN="${NGINX_ELEMENT_DOMAIN:-element.home.arpa}"

CERTS_DIR="${PROJECT_ROOT}/nginx/certs"
mkdir -p "${CERTS_DIR}"

require_cmd openssl

log "Dominios:"
log "  Matrix:  ${MATRIX_DOMAIN}"
log "  Element: ${ELEMENT_DOMAIN}"
log "  SAN unificado: ${MATRIX_DOMAIN}, ${ELEMENT_DOMAIN}, localhost, 127.0.0.1"
echo

# -----------------------------------------------------------------------------
# Generar CA raiz
# -----------------------------------------------------------------------------
CA_KEY="${CERTS_DIR}/ca.key"
CA_CRT="${CERTS_DIR}/ca.crt"

if [[ -f "${CA_KEY}" && -f "${CA_CRT}" ]]; then
    warn "CA ya existe. Si quieres regenerar, borra ${CA_KEY} y ${CACrt:-ca.crt} primero."
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
# Funcion para generar cert firmado por la CA con SAN unificado
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

    log "Generando cert para ${domain} (SAN unificado)..."
    openssl genrsa -out "${key}" 2048
    openssl req -new -key "${key}" -out "${csr}" \
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=${domain}"

    # Extensiones SAN - TODOS los dominios en cada certificado
    cat > "${CERTS_DIR}/${cert_name}.ext" <<EXT_EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${MATRIX_DOMAIN}
DNS.2 = ${ELEMENT_DOMAIN}
DNS.3 = localhost
IP.1  = 127.0.0.1
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
# Cert default para el catch-all server (tambien con SAN unificado)
# -----------------------------------------------------------------------------
if [[ ! -f "${CERTS_DIR}/default.key" ]] || [[ ! -f "${CERTS_DIR}/default.crt" ]]; then
    log "Generando cert default (SAN unificado)..."

    DEFAULT_KEY="${CERTS_DIR}/default.key"
    DEFAULT_CSR="${CERTS_DIR}/default.csr"
    DEFAULT_CRT="${CERTS_DIR}/default.crt"
    DEFAULT_EXT="${CERTS_DIR}/default.ext"

    openssl genrsa -out "${DEFAULT_KEY}" 2048
    openssl req -new -key "${DEFAULT_KEY}" -out "${DEFAULT_CSR}" \
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=default"

    cat > "${DEFAULT_EXT}" <<EXT_EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${MATRIX_DOMAIN}
DNS.2 = ${ELEMENT_DOMAIN}
DNS.3 = localhost
IP.1  = 127.0.0.1
EXT_EOF

    openssl x509 -req -in "${DEFAULT_CSR}" -CA "${CA_CRT}" -CAkey "${CA_KEY}" \
        -CAcreateserial -out "${DEFAULT_CRT}" -days 365 -sha256 \
        -extfile "${DEFAULT_EXT}"

    rm -f "${DEFAULT_CSR}" "${DEFAULT_EXT}"
    chmod 600 "${DEFAULT_KEY}"
    log "Cert default generado: ${DEFAULT_CRT} (valido 1 ano)"
fi

# -----------------------------------------------------------------------------
# Permisos
# -----------------------------------------------------------------------------
chmod 644 "${CERTS_DIR}"/*.crt 2>/dev/null || true
chmod 600 "${CERTS_DIR}"/*.key 2>/dev/null || true

echo
log "Certificados generados en ${CERTS_DIR}"
log "   SAN en todos los certificados: ${MATRIX_DOMAIN}, ${ELEMENT_DOMAIN}, localhost, 127.0.0.1"
log "   Para evitar warnings en el navegador:"
log "   Importa ${CA_CRT} en el trust store de cada cliente."
log "   - Linux:   sudo cp ${CA_CRT} /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
log "   - Windows: Doble clic en ca.crt -> Instalar certificado -> Equipo local -> Entidades de certificacion raiz de confianza"
log "   - macOS:   Anadir a Llavero -> Marcar como confiable"