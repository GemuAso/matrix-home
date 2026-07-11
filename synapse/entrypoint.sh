#!/bin/bash
# =============================================================================
# Synapse Entrypoint Wrapper
# -----------------------------------------------------------------------------
# Genera homeserver.yaml desde template usando envsubst,
# verifica que la configuración sea válida, e inicia Synapse.
# =============================================================================

set -e

TEMPLATE_FILE="/data/homeserver.yaml.template"
CONFIG_FILE="/data/homeserver.yaml"
SIGNING_KEY="/data/homeserver.signing.key"

echo "[synapse-entrypoint] === Iniciando wrapper de Synapse ==="

# -----------------------------------------------------------------------------
# Verificar archivos necesarios
# -----------------------------------------------------------------------------
if [ ! -f "${TEMPLATE_FILE}" ]; then
    echo "[synapse-entrypoint] FATAL: No se encontro ${TEMPLATE_FILE}"
    echo "[synapse-entrypoint] Asegurate de montar synapse/homeserver.yaml.template en /data/homeserver.yaml.template"
    exit 1
fi

if [ ! -f "${SIGNING_KEY}" ]; then
    echo "[synapse-entrypoint] FATAL: No se encontro ${SIGNING_KEY}"
    echo "[synapse-entrypoint] Asegurate de montar synapse/signing.key en /data/homeserver.signing.key"
    exit 1
fi

echo "[synapse-entrypoint] Template encontrado: ${TEMPLATE_FILE}"
echo "[synapse-entrypoint] Signing key encontrado: ${SIGNING_KEY}"

# -----------------------------------------------------------------------------
# Verificar que envsubst está disponible
# -----------------------------------------------------------------------------
if ! command -v envsubst >/dev/null 2>&1; then
    echo "[synapse-entrypoint] FATAL: envsubst no encontrado. La imagen personalizada no se construyo correctamente."
    echo "[synapse-entrypoint] Ejecuta: docker compose build --no-cache synapse"
    exit 1
fi

# -----------------------------------------------------------------------------
# Generar homeserver.yaml desde template
# -----------------------------------------------------------------------------
echo "[synapse-entrypoint] Generando homeserver.yaml desde template..."

envsubst \
    '${SYNAPSE_SERVER_NAME} ${SYNAPSE_PUBLIC_URL} ${SYNAPSE_LOG_CONFIG} ${POSTGRES_USER} ${POSTGRES_PASSWORD} ${POSTGRES_DB} ${REDIS_PASSWORD} ${SYNAPSE_REGISTRATION_SHARED_SECRET} ${SYNAPSE_MACAROON_SECRET_KEY} ${SYNAPSE_FORM_SECRET} ${SYNAPSE_PASSWORD_PEPPER} ${SMTP_HOST} ${SMTP_PORT} ${SMTP_USER} ${SMTP_PASS} ${SMTP_FROM} ${SMTP_FROM_NAME} ${ELEMENT_URL}' \
    < "${TEMPLATE_FILE}" > "${CONFIG_FILE}"

# Verificar que la generación tuvo éxito
if [ ! -s "${CONFIG_FILE}" ]; then
    echo "[synapse-entrypoint] FATAL: homeserver.yaml generado está vacío."
    exit 1
fi

# Contar variables sin sustituir (indicador de configuración incompleta)
UNSUBSTITUTED=$(grep -c '\${[A-Z_]*}' "${CONFIG_FILE}" 2>/dev/null || echo "0")
if [ "${UNSUBSTITUTED}" -gt 0 ]; then
    echo "[synapse-entrypoint] WARN: Se encontraron ${UNSUBSTITUTED} variables sin sustituir en homeserver.yaml"
fi

# Verificar sintaxis YAML básica (que el archivo tenga server_name)
if ! grep -q 'server_name:' "${CONFIG_FILE}"; then
    echo "[synapse-entrypoint] FATAL: homeserver.yaml no contiene 'server_name:'. La generacion fallo."
    exit 1
fi

echo "[synapse-entrypoint] homeserver.yaml generado correctamente ($(wc -l < "${CONFIG_FILE}") lineas)"
echo "[synapse-entrypoint] Iniciando Synapse homeserver..."

# -----------------------------------------------------------------------------
# Ejecutar Synapse
# -----------------------------------------------------------------------------
exec python -m synapse.app.homeserver --config-path "${CONFIG_FILE}" "$@"