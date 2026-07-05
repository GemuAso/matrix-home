# =============================================================================
# Dockerfile - Synapse con herramientas adicionales
# -----------------------------------------------------------------------------
# La imagen oficial matrixdotorg/synapse (Debian-based) NO incluye:
#   - envsubst (paquete gettext-base)  -> necesario para generar homeserver.yaml
#   - curl  (paquete curl)             -> necesario para healthcheck
#   - bash  -> el entrypoint usa bash
#
# Este Dockerfile resuelve estos problemas instalando las dependencias faltantes
# en la capa de build. Las dependencias se instalan UNA VEZ al construir la
# imagen, no en cada arranque del contenedor.
#
# Arquitectura: multi-arch (amd64 + arm64) heredada de la imagen base.
# =============================================================================

FROM matrixdotorg/synapse:v1.118.0

LABEL org.opencontainers.image.title="matrix-synapse-custom" \
      org.opencontainers.image.description="Matrix Synapse con envsubst para generacion de configuracion" \
      org.opencontainers.image.source="https://github.com/matrix-org/synapse" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="v1.118.0-custom-5.0"

# Instalar dependencias faltantes de forma permanente en la imagen
# gettext-base: proporciona envsubst para generar homeserver.yaml desde template
# curl: necesario para el healthcheck HTTP
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gettext-base \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Healthcheck (tambien definido en docker-compose.yml, pero tenerlo aqui
# permite que funcione si se usa la imagen standalone)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -fSs http://localhost:8008/health || exit 1

EXPOSE 8008