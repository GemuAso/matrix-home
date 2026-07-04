# =============================================================================
# stop.ps1 - Detiene el stack completo de Matrix
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Deteniendo Matrix Docker Stack"

Check-Docker

if (-not (Test-StackRunning)) {
    Log-Warn "El stack no parece estar corriendo."
    Log-Msg "Deteniendo igualmente por si hay contenedores parados..."
}

Log-Msg "Deteniendo servicios..."
Invoke-Compose stop

Write-Host ""
Log-Msg "Stack detenido."
Write-Host ""
Log-Msg "Para iniciarlo de nuevo: scripts\windows\start.ps1"
Log-Msg "Para detener y eliminar contenedores: docker compose down"
Log-Msg "Para eliminar también volúmenes (PELIGROSO): docker compose down -v"
