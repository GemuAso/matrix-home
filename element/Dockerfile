# =============================================================================
# Dockerfile - Element Web con configuración personalizada
# -----------------------------------------------------------------------------
# Construye una imagen Element Web con config.json y nginx config embebidos.
# Base: vectorim/element-web (image oficial, nginx + archivos estáticos)
# -----------------------------------------------------------------------------
FROM vectorim/element-web:v1.11.65

# Metadata OCI
LABEL org.opencontainers.image.title="matrix-element-custom" \
      org.opencontainers.image.description="Element Web con config para LAN Matrix" \
      org.opencontainers.image.source="https://github.com/vector-im/element-web" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="1.11.65-custom-1.0"

# Copiar configuración personalizada
COPY config.json /app/config.json

# Copiar configuración de nginx (caché, headers)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --spider http://localhost/ || exit 1

# Usuario no privilegiado (nginx en element-web usa nginx user)
USER nginx

# Exponer puerto
EXPOSE 80
