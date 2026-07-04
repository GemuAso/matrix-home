#!/bin/sh
# =============================================================================
# Redis Entrypoint Wrapper
# -----------------------------------------------------------------------------
# Generates redis.conf from template using environment variable,
# then starts Redis server.
# =============================================================================

set -e

TEMPLATE_FILE="/usr/local/etc/redis/redis.conf.template"
CONFIG_FILE="/usr/local/etc/redis/redis.conf"

if [[ -f "${TEMPLATE_FILE}" ]]; then
    echo "[redis-entrypoint] Generating redis.conf from template..."
    sed "s|__REDIS_PASSWORD__|${REDIS_PASSWORD}|g" \
        "${TEMPLATE_FILE}" > "${CONFIG_FILE}"
    echo "[redis-entrypoint] redis.conf generated successfully."
else
    echo "[redis-entrypoint] WARNING: Template not found at ${TEMPLATE_FILE}"
    echo "[redis-entrypoint] Using existing redis.conf if present."
fi

# Execute Redis server
exec redis-server "${CONFIG_FILE}" "$@"
