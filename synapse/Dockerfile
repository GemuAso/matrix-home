# =============================================================================
# Dockerfile - Imagen personalizada de Synapse
# -----------------------------------------------------------------------------
# La imagen oficial matrixdotorg/synapse:v1.118.0 (Debian-based) NO incluye:
#   - gettext-base  -> proporciona envsubst (genera homeserver.yaml desde template)
#   - curl          -> necesario para el healthcheck HTTP /health
#   - bash          -> nuestro entrypoint usa bash para mayor robustez
#
# Este Dockerfile instala estas dependencias en la capa de build.
# Se instalan UNA VEZ al construir la imagen, nunca en runtime.
#
# Compatible con: amd64 y arm64 (heredado de la imagen base).
# =============================================================================
FROM matrixdotorg/synapse:v1.118.0

LABEL org.opencontainers.image.title="matrix-synapse-custom" \
      org.opencontainers.image.description="Matrix Synapse con envsubst, curl y bash para generacion de configuracion" \
      org.opencontainers.image.version="v1.118.0-custom-5.1"

# Instalar dependencias faltantes de forma permanente
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gettext-base \
        curl \
        bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copiar el wrapper de entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

EXPOSE 8008