# =============================================================================
# update-images.ps1 - Descarga las últimas versiones de las imágenes
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Actualizando imágenes Docker"

Check-Docker

Log-Msg "Descargando últimas versiones de imágenes..."
Invoke-Compose pull

Write-Host ""
Log-Msg "Reconstruyendo imagen de Element (si hay cambios)..."
Invoke-Compose build --pull element

Write-Host ""
Log-Msg "Imágenes actualizadas."
Write-Host ""
Log-Warn "Las imágenes se descargaron pero los contenedores NO se reiniciaron."
Log-Msg "Para aplicar los cambios: scripts\windows\update-containers.ps1"
