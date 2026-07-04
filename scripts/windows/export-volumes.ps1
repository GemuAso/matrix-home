# =============================================================================
# export-volumes.ps1 - Exporta volúmenes Docker para migración
# -----------------------------------------------------------------------------
# Ejecuta en Windows ANTES de migrar a Ubuntu.
# Genera un tarball con:
#   - Todos los archivos del proyecto (sin logs, sin backups antiguos)
#   - Volúmenes Docker: matrix_synapse_data, matrix_postgres_data, matrix_redis_data
#
# Uso:
#   .\scripts\windows\export-volumes.ps1
#   .\scripts\windows\export-volumes.ps1 -OutputPath C:\temp\matrix-migration.tar.gz
# =============================================================================

param(
    [string]$OutputPath = ".\matrix-migration.tar.gz"
)

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Exportación de volúmenes para migración"

Check-Docker

# Resolución de ruta absoluta
$OutputPath = (Resolve-Path -Path (Split-Path -Parent $OutputPath)).Path + "\" + (Split-Path -Leaf $OutputPath)

Log-Msg "Archivo destino: $OutputPath"

# Verificar que tar esté disponible (Windows 10+ lo incluye)
$tarCmd = Get-Command tar -ErrorAction SilentlyContinue
if (-not $tarCmd) {
    Log-Fatal "tar no está disponible. En Windows 10 1803+ viene incluido. Actualiza Windows."
}

# 1. Crear directorio temporal
$TmpDir = Join-Path $env:TEMP "matrix-migration-$(Get-Random)"
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TmpDir "project") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TmpDir "volumes") -Force | Out-Null

try {
    # 2. Detener el stack (opcional, pero recomendado)
    Log-Msg "Deteniendo el stack antes de exportar..."
    Invoke-Compose stop

    # 3. Copiar archivos del proyecto
    Log-Msg "Copiando archivos del proyecto..."
    $excludePatterns = @("backups\*.sql.gz", "backups\*.tar.gz", "*.log", "node_modules")
    $sourceFiles = Get-ChildItem -Path $ProjectRoot -Force | Where-Object {
        $_.Name -notin @("node_modules", ".git")
    }
    foreach ($file in $sourceFiles) {
        $dest = Join-Path $TmpDir "project" $file.Name
        Copy-Item -Path $file.FullName -Destination $dest -Recurse -Force
    }

    # 4. Exportar volúmenes
    $volumes = @("matrix_synapse_data", "matrix_postgres_data", "matrix_redis_data")
    foreach ($vol in $volumes) {
        Log-Msg "Exportando volumen: $vol"
        $volTar = Join-Path $TmpDir "volumes" "$vol.tar"

        # Verificar que el volumen existe
        $exists = docker volume inspect $vol 2>$null
        if (-not $exists) {
            Log-Warn "Volumen $vol no existe. Saltando."
            continue
        }

        # Usar alpine para crear el tar del volumen
        docker run --rm `
            -v "${vol}:/data:ro" `
            -v "${TmpDir}:/backup" `
            alpine:3.20 `
            tar -cf "/backup/volumes/$vol.tar" -C /data .
    }

    # 5. Crear tarball final
    Log-Msg "Creando tarball final: $OutputPath"
    Push-Location $TmpDir
    try {
        & tar -czf $OutputPath project volumes
        if ($LASTEXITCODE -ne 0) {
            Log-Fatal "Error creando tarball"
        }
    } finally {
        Pop-Location
    }

    # 6. Verificar
    $size = (Get-Item $OutputPath).Length
    $humanSize = if ($size -gt 1GB) { "{0:N2} GB" -f ($size/1GB) } elseif ($size -gt 1MB) { "{0:N2} MB" -f ($size/1MB) } else { "{0:N2} KB" -f ($size/1KB) }
    Log-Msg "Tarball creado: $OutputPath ($humanSize)"

    Write-Host ""
    Log-Msg "Exportación completada."
    Write-Host ""
    Log-Msg "Próximos pasos:"
    Log-Msg "  1. Copia $OutputPath al servidor Ubuntu (scp o USB)"
    Log-Msg "  2. Copia también el proyecto (sin volúmenes) o clónalo desde Git"
    Log-Msg "  3. En Ubuntu ejecuta:"
    Log-Msg "     sudo bash deployment/migrate-from-windows.sh matrix-migration.tar.gz /opt/matrix-docker"
    Write-Host ""
    Log-Warn "Recordar: actualizar .env, dominios en homeserver.yaml, config.json y nginx/conf.d/*.conf"
} finally {
    # Limpieza
    Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
