#!/usr/bin/env bash
# =============================================================================
# install-docker-ubuntu.sh - Instala Docker y Docker Compose en Ubuntu Server
# -----------------------------------------------------------------------------
# Script de preparación para servidor Ubuntu (20.04 / 22.04 / 24.04 LTS).
# Instala:
#   - Docker Engine (último estable)
#   - Docker Compose plugin v2
#   - Configuración de systemd
#   - Usuario deploy (no-root) con acceso a Docker
# -----------------------------------------------------------------------------
# Uso: sudo bash install-docker-ubuntu.sh
# =============================================================================

set -Eeuo pipefail

# Verificar root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

echo "=== Instalación de Docker en Ubuntu Server ==="
echo

# 1. Actualizar paquetes
echo "[1/7] Actualizando paquetes..."
apt-get update -qq
apt-get upgrade -y -qq

# 2. Instalar dependencias
echo "[2/7] Instalando dependencias..."
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    openssl \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-transport-https \
    software-properties-common

# 3. Agregar repositorio oficial de Docker
echo "[3/7] Agregando repositorio de Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq

# 4. Instalar Docker
echo "[4/7] Instalando Docker Engine + Compose..."
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 5. Habilitar y arrancar Docker
echo "[5/7] Habilitando Docker en systemd..."
systemctl enable docker
systemctl enable containerd
systemctl start docker

# 6. Configuración de Docker daemon
echo "[6/7] Configurando Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "5"
    },
    "live-restore": true,
    "userland-proxy": false,
    "icc": false,
    "no-new-privileges": true,
    "default-ulimits": {
        "nofile": {
            "Hard": 65535,
            "Name": "nofile",
            "Soft": 65535
        }
    }
}
EOF
systemctl reload docker

# 7. Crear usuario deploy
echo "[7/7] Creando usuario 'deploy'..."
if ! id -u deploy >/dev/null 2>&1; then
    useradd -m -s /bin/bash deploy
    usermod -aG docker deploy
    echo "Usuario 'deploy' creado y agregado al grupo docker."
else
    usermod -aG docker deploy
    echo "Usuario 'deploy' ya existe. Agregado al grupo docker."
fi

# Verificar instalación
echo
echo "=== Verificación ==="
docker --version
docker compose version
echo
echo "✅ Docker instalado correctamente."
echo
echo "Próximos pasos:"
echo "  1. Copia el proyecto a /opt/matrix-docker (como usuario deploy)"
echo "  2. Ejecuta scripts/linux/setup.sh"
echo "  3. Instala el servicio systemd:"
echo "     sudo cp deployment/matrix-docker.service /etc/systemd/system/"
echo "     sudo systemctl enable matrix-docker"
echo "  4. Configura firewall: sudo bash deployment/setup-firewall.sh"
echo "  5. Configura backups automáticos: sudo cp deployment/matrix-backup.cron /etc/cron.d/"
