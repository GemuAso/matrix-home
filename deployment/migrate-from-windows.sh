#!/usr/bin/env bash
# =============================================================================
# migrate-from-windows.sh - Migra volúmenes desde Docker Desktop (Windows)
# -----------------------------------------------------------------------------
# Este script se ejecuta en el servidor Ubuntu destino.
# Transfiere los volúmenes y configuraciones desde un archivo tar exportado
# desde Windows.
#
# Pasos previos (en Windows):
#   1. Detener el stack: scripts\windows\stop.ps1
#   2. Exportar volúmenes:
#      scripts\windows\export-volumes.ps1
#   3. Copiar matrix-migration.tar.gz y el proyecto al servidor Ubuntu
#
# Uso en Ubuntu:
#   sudo bash migrate-from-windows.sh matrix-migration.tar.gz /opt/matrix-docker
# =============================================================================

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

if [[ $# -lt 2 ]]; then
    echo "Uso: $0 <tarball-migration> <destination-dir>"
    echo "Ejemplo: $0 matrix-migration.tar.gz /opt/matrix-docker"
    exit 1
fi

TARBALL="$1"
DEST_DIR="$2"

if [[ ! -f "${TARBALL}" ]]; then
    echo "No se encontró el tarball: ${TARBALL}"
    exit 1
fi

echo "=== Migración de Docker Desktop (Windows) a Ubuntu ==="
echo "Origen:  ${TARBALL}"
echo "Destino: ${DEST_DIR}"
echo

mkdir -p "${DEST_DIR}"

# Crear directorio temporal
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

# 1. Extraer tarball
echo "[1/4] Extrayendo tarball..."
tar -xzf "${TARBALL}" -C "${TMP_DIR}"

# 2. Copiar proyecto (archivos de configuración)
if [[ -d "${TMP_DIR}/project" ]]; then
    echo "[2/4] Copiando archivos del proyecto..."
    cp -r "${TMP_DIR}/project/"* "${DEST_DIR}/"
    cp -r "${TMP_DIR}/project/".[!.]* "${DEST_DIR}/" 2>/dev/null || true
    chown -R deploy:deploy "${DEST_DIR}"
    chmod 600 "${DEST_DIR}/.env" 2>/dev/null || true
    chmod 600 "${DEST_DIR}/synapse/signing.key" 2>/dev/null || true
fi

# 3. Importar volúmenes Docker
echo "[3/4] Importando volúmenes Docker..."
for volume_tar in "${TMP_DIR}/volumes"/*.tar; do
    [[ -f "${volume_tar}" ]] || continue
    vol_name=$(basename "${volume_tar}" .tar)
    echo "  Importando volumen: ${vol_name}"

    # Crear volumen si no existe
    docker volume inspect "${vol_name}" >/dev/null 2>&1 || docker volume create "${vol_name}"

    # Restaurar contenido
    docker run --rm \
        -v "${vol_name}:/data" \
        -v "${volume_tar}:/backup.tar:ro" \
        alpine:3.20 \
        sh -c "cd /data && tar -xf /backup.tar"
done

# 4. Ajustar permisos
echo "[4/4] Ajustando permisos..."
chown -R deploy:deploy "${DEST_DIR}"
chmod 600 "${DEST_DIR}/.env" 2>/dev/null || true
chmod 600 "${DEST_DIR}/synapse/signing.key" 2>/dev/null || true
chmod 700 "${DEST_DIR}/nginx/certs" 2>/dev/null || true
chmod 600 "${DEST_DIR}/nginx/certs/"*.key 2>/dev/null || true
chmod 644 "${DEST_DIR}/nginx/certs/"*.crt 2>/dev/null || true

echo
echo "✅ Migración completada."
echo
echo "Próximos pasos:"
echo "  1. Edita ${DEST_DIR}/.env con los valores del nuevo servidor"
echo "  2. Actualiza dominios en homeserver.yaml, config.json y nginx/conf.d/*.conf"
echo "  3. Verifica docker-compose.yml: cd ${DEST_DIR} && docker compose config"
echo "  4. Inicia el stack: su deploy -c 'cd ${DEST_DIR} && bash scripts/linux/start.sh'"
echo "  5. Instala servicio systemd: sudo cp ${DEST_DIR}/deployment/matrix-docker.service /etc/systemd/system/"
echo "     sudo systemctl daemon-reload && sudo systemctl enable matrix-docker"
echo "  6. Configura firewall: sudo bash ${DEST_DIR}/deployment/setup-firewall.sh"
echo "  7. Configura backups: sudo cp ${DEST_DIR}/deployment/matrix-backup.cron /etc/cron.d/"
