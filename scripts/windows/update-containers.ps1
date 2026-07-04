# =============================================================================
# update-containers.ps1 - Recrea contenedores con imágenes actualizadas
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Actualizando contenedores"

Check-Docker

Log-Msg "Verificando nuevas imágenes..."
Invoke-Compose pull --ignore-pull-failures

Log-Msg "Recreando contenedores (si la imagen cambió)..."
Invoke-Compose up -d

Write-Host ""
Log-Msg "Esperando healthchecks..."
Wait-ForHealth "postgres" 60 | Out-Null
Wait-ForHealth "redis" 30 | Out-Null
Wait-ForHealth "synapse" 120 | Out-Null
Wait-ForHealth "element" 30 | Out-Null
Wait-ForHealth "nginx" 30 | Out-Null

Write-Host ""
Log-Header "Estado final"
Invoke-Compose ps

Write-Host ""
Log-Msg "Contenedores actualizados."
Log-Msg "Verifica los logs si hay problemas: scripts\windows\logs.ps1"
