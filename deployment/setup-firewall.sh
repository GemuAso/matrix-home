#!/usr/bin/env bash
# =============================================================================
# setup-firewall.sh - Configura UFW para proteger el servidor Matrix
# -----------------------------------------------------------------------------
# Políticas:
#   - Denegar todo el tráfico entrante por defecto
#   - Permitir todo el tráfico saliente
#   - Permitir SSH (puerto 22) solo desde la LAN
#   - Permitir HTTP/HTTPS (80/443) solo desde la LAN
#   - Denegar todo lo demás
#
# Uso: sudo bash setup-firewall.sh [LAN_CIDR]
#   sudo bash setup-firewall.sh 192.168.1.0/24
# =============================================================================

set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

LAN_CIDR="${1:-192.168.1.0/24}"

echo "=== Configuración de firewall UFW ==="
echo "LAN permitida: $LAN_CIDR"
echo

# Verificar UFW instalado
if ! command -v ufw >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq ufw
fi

# Políticas por defecto
echo "[1/5] Configurando políticas por defecto..."
ufw default deny incoming
ufw default allow outgoing

# SSH solo desde LAN
echo "[2/5] Permitiendo SSH solo desde LAN..."
ufw allow from "$LAN_CIDR" to any port 22 proto tcp comment 'SSH from LAN'

# HTTP/HTTPS solo desde LAN
echo "[3/5] Permitiendo HTTP/HTTPS solo desde LAN..."
ufw allow from "$LAN_CIDR" to any port 80 proto tcp comment 'HTTP from LAN'
ufw allow from "$LAN_CIDR" to any port 443 proto tcp comment 'HTTPS from LAN'

# Loopback
echo "[4/5] Permitiendo loopback..."
ufw allow in on lo

# Habilitar UFW
echo "[5/5] Habilitando UFW..."
ufw --force enable

echo
echo "=== Estado de UFW ==="
ufw status verbose

echo
echo "✅ Firewall configurado."
echo
echo "Para verificar reglas:    sudo ufw status numbered"
echo "Para agregar regla:       sudo ufw allow from <IP> to any port <PUERTO>"
echo "Para eliminar regla:      sudo ufw delete <NÚMERO>"
echo "Para deshabilitar:        sudo ufw disable"
