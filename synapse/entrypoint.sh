#!/bin/sh
# =============================================================================
# Synapse Entrypoint Wrapper
# -----------------------------------------------------------------------------
# Generates homeserver.yaml from template using envsubst,
# then starts the Synapse homeserver.
#
# NOTA: Este script usa /bin/sh (no bash) porque la imagen base Synapse
# puede no tener bash. Sin embargo, nuestro Dockerfile personalizado
# instala bash, asi que es seguro usar bash tambien.
#
# Se usa sh por compatibilidad maxima y porque envsubst no necesita bash.
# =============================================================================

set -e

TEMPLATE_FILE="/data/homeserver.yaml.template"
CONFIG_FILE="/data/homeserver.yaml"

if [ -f "${TEMPLATE_FILE}" ]; then
    echo "[synapse-entrypoint] Generating homeserver.yaml from template..."

    # envsubst solo sustituye variables de entorno que esten definidas.
    # Se listan explicitamente todas las variables requeridas para evitar
    # sustituciones no deseadas.
    envsubst \
        '${SYNAPSE_SERVER_NAME} ${SYNAPSE_PUBLIC_URL} ${SYNAPSE_LOG_CONFIG} ${POSTGRES_USER} ${POSTGRES_PASSWORD} ${POSTGRES_DB} ${REDIS_PASSWORD} ${SYNAPSE_REGISTRATION_SHARED_SECRET} ${SYNAPSE_MACAROON_SECRET_KEY} ${SYNAPSE_FORM_SECRET} ${SYNAPSE_PASSWORD_PEPPER} ${SMTP_HOST} ${SMTP_PORT} ${SMTP_USER} ${SMTP_PASS} ${SMTP_FROM} ${SMTP_FROM_NAME} ${ELEMENT_URL}' \
        < "${TEMPLATE_FILE}" > "${CONFIG_FILE}"

    # Eliminar lineas con variables vacias no sustituidas (por si acaso)
    # Esto previene errores de YAML por valores como "${VARIABLE}"
    sed -i '/\${[A-Z_]*}/d' "${CONFIG_FILE}" 2>/dev/null || true

    echo "[synapse-entrypoint] homeserver.yaml generated successfully."
else
    echo "[synapse-entrypoint] WARNING: Template not found at ${TEMPLATE_FILE}"
    echo "[synapse-entrypoint] Using existing homeserver.yaml if present."
fi

# Execute the Synapse homeserver
exec python -m synapse.app.homeserver --config-path "${CONFIG_FILE}" "$@"