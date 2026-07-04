#!/usr/bin/env bash
# =============================================================================
# status.sh - Muestra el estado completo del stack
# -----------------------------------------------------------------------------
# Información mostrada:
#   - Estado de cada contenedor (running, health, ports)
#   - Uso de recursos (CPU, memoria)
#   - Espacio en disco de volúmenes
#   - Versión de imágenes
# =============================================================================

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

header "Estado de Matrix Docker Stack"

check_docker

echo
echo -e "${BLUE}${BOLD}1. Contenedores${NC}"
echo "----------------------------------------"
dc ps

echo
echo -e "${BLUE}${BOLD}2. Uso de recursos (stats)${NC}"
echo "----------------------------------------"
dc stats --no-stream 2>/dev/null || warn "No se pudieron obtener stats (¿contenedores detenidos?)"

echo
echo -e "${BLUE}${BOLD}3. Volúmenes${NC}"
echo "----------------------------------------"
docker volume ls --filter "name=matrix_" --format "table {{.Name}}\t{{.Driver}}"

echo
echo -e "${BLUE}${BOLD}4. Redes${NC}"
echo "----------------------------------------"
docker network ls --filter "name=matrix_" --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"

echo
echo -e "${BLUE}${BOLD}5. Imágenes${NC}"
echo "----------------------------------------"
docker images --filter "reference=matrix-element*" --filter "reference=matrixdotorg/*" --filter "reference=postgres:*" --filter "reference=redis:*" --filter "reference=nginx:*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"

echo
echo -e "${BLUE}${BOLD}6. Espacio Docker${NC}"
echo "----------------------------------------"
docker system df

echo
echo -e "${BLUE}${BOLD}7. Healthchecks${NC}"
echo "----------------------------------------"
for svc in postgres redis synapse element nginx; do
    STATUS=$(dc ps "${svc}" 2>/dev/null | tail -n +2 | awk '{print $NF}' || echo "n/a")
    printf "  %-12s : %s\n" "${svc}" "${STATUS}"
done

echo
echo -e "${BLUE}${BOLD}8. URLs de acceso${NC}"
echo "----------------------------------------"
echo "  Element:  https://${NGINX_ELEMENT_DOMAIN:-element.home.arpa}"
echo "  Matrix:   https://${NGINX_MATRIX_DOMAIN:-matrix.home.arpa}"
echo
echo "  Para verificación de health:"
echo "  curl -k https://${NGINX_MATRIX_DOMAIN:-matrix.home.arpa}/health"
