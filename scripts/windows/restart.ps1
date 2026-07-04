# =============================================================================
# restart.ps1 - Reinicia el stack completo o un servicio específico
# -----------------------------------------------------------------------------
# Uso:
#   .\scripts\windows\restart.ps1                          # Reinicia todo
#   .\scripts\windows\restart.ps1 synapse                  # Reinicia synapse
#   .\scripts\windows\restart.ps1 nginx synapse            # Reinicia varios
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Reiniciando Matrix Docker Stack"

Check-Docker

if ($args.Count -eq 0) {
    Log-Msg "Reiniciando todos los servicios..."
    Invoke-Compose restart
    Write-Host ""
    Log-Msg "Esperando healthchecks..."
    Wait-ForHealth "postgres" 60 | Out-Null
    Wait-ForHealth "redis" 30 | Out-Null
    Wait-ForHealth "synapse" 120 | Out-Null
    Wait-ForHealth "element" 30 | Out-Null
    Wait-ForHealth "nginx" 30 | Out-Null
} else {
    foreach ($svc in $args) {
        Log-Msg "Reiniciando $svc..."
        Invoke-Compose restart $svc
        Wait-ForHealth $svc 120 | Out-Null
    }
}

Write-Host ""
Log-Header "Estado final"
Invoke-Compose ps
Write-Host ""
Log-Msg "Reinicio completado."
