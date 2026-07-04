# =============================================================================
# status.ps1 - Muestra el estado completo del stack
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Estado de Matrix Docker Stack"

Check-Docker

Write-Host ""
Write-Host "1. Contenedores" -ForegroundColor Blue
Write-Host "----------------------------------------"
Invoke-Compose ps

Write-Host ""
Write-Host "2. Uso de recursos (stats)" -ForegroundColor Blue
Write-Host "----------------------------------------"
Invoke-Compose stats --no-stream 2>$null
if (-not $?) { Log-Warn "No se pudieron obtener stats (¿contenedores detenidos?)" }

Write-Host ""
Write-Host "3. Volúmenes" -ForegroundColor Blue
Write-Host "----------------------------------------"
docker volume ls --filter "name=matrix_" --format "table {{.Name}}`t{{.Driver}}"

Write-Host ""
Write-Host "4. Redes" -ForegroundColor Blue
Write-Host "----------------------------------------"
docker network ls --filter "name=matrix_" --format "table {{.Name}}`t{{.Driver}}`t{{.Scope}}"

Write-Host ""
Write-Host "5. Imágenes" -ForegroundColor Blue
Write-Host "----------------------------------------"
docker images --filter "reference=matrix-element*" --filter "reference=matrixdotorg/*" --filter "reference=postgres:*" --filter "reference=redis:*" --filter "reference=nginx:*" --format "table {{.Repository}}`t{{.Tag}}`t{{.Size}}`t{{.CreatedSince}}"

Write-Host ""
Write-Host "6. Espacio Docker" -ForegroundColor Blue
Write-Host "----------------------------------------"
docker system df

Write-Host ""
Write-Host "7. Healthchecks" -ForegroundColor Blue
Write-Host "----------------------------------------"
foreach ($svc in @("postgres", "redis", "synapse", "element", "nginx")) {
    $status = (Invoke-Compose ps $svc 2>$null) -join " "
    if ($status -match "healthy") { $state = "healthy" }
    elseif ($status -match "running") { $state = "running (no healthy yet)" }
    elseif ($status -match "exited") { $state = "exited" }
    else { $state = "not found" }
    Write-Host ("  {0,-12} : {1}" -f $svc, $state)
}

Write-Host ""
Write-Host "8. URLs de acceso" -ForegroundColor Blue
Write-Host "----------------------------------------"
Write-Host "  Element:  https://$($env:NGINX_ELEMENT_DOMAIN)"
Write-Host "  Matrix:   https://$($env:NGINX_MATRIX_DOMAIN)"
Write-Host ""
Write-Host "  Para verificación de health:"
Write-Host "  curl -k https://$($env:NGINX_MATRIX_DOMAIN)/health"
