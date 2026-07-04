# =============================================================================
# clean-images.ps1 - Limpia imágenes Docker antiguas y sin usar
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Limpieza de imágenes Docker"

Check-Docker

Log-Msg "Limpiando imágenes dangling (sin tag)..."
docker image prune -f

Write-Host ""
Log-Msg "Limpiando build cache..."
docker builder prune -f

Write-Host ""
$confirm = Read-Host "¿Eliminar TODAS las imágenes no usadas por contenedores activos? (s/N)"
if ($confirm -eq "s" -or $confirm -eq "S") {
    Log-Msg "Eliminando imágenes no usadas..."
    docker image prune -a -f
} else {
    Log-Msg "Omitiendo eliminación profunda."
}

Write-Host ""
Log-Msg "Estadísticas de espacio Docker:"
docker system df

Write-Host ""
Log-Msg "Limpieza completada."
