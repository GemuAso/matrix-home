# =============================================================================
# logs.ps1 - Ver logs de los servicios
# -----------------------------------------------------------------------------
# Uso:
#   .\scripts\windows\logs.ps1                              # Todos (last 20)
#   .\scripts\windows\logs.ps1 synapse                      # Solo synapse (follow)
#   .\scripts\windows\logs.ps1 synapse --tail 200
#   .\scripts\windows\logs.ps1 synapse --since 1h
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Logs de Matrix Docker Stack"

Check-Docker

$Services = @("postgres", "redis", "synapse", "element", "nginx")

if ($args.Count -eq 0) {
    Log-Msg "Últimos logs de todos los servicios:"
    Write-Host ""
    foreach ($svc in $Services) {
        Write-Host "--- $svc ---" -ForegroundColor Blue
        Invoke-Compose logs --tail 20 $svc
        Write-Host ""
    }
    exit 0
}

Log-Msg "Mostrando logs de: $($args -join ' ')"
Write-Host ""
Invoke-Compose logs @args
