# =============================================================================
# backup-db.ps1 - Respaldo completo de la base de datos PostgreSQL
# -----------------------------------------------------------------------------
# Uso:
#   .\scripts\windows\backup-db.ps1                  # Backup con timestamp
#   .\scripts\windows\backup-db.ps1 mi_backup        # Backup con nombre custom
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Respaldo de base de datos"

Check-Docker

if (-not $env:POSTGRES_USER -or -not $env:POSTGRES_DB) {
    Log-Fatal "POSTGRES_USER o POSTGRES_DB no definidos en .env"
}

# Crear directorio de backups
$BackupDir = Join-Path $ProjectRoot "backups"
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# Nombre del backup
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ($args.Count -ge 1) {
    $BackupName = "db_$($args[0])_$Timestamp"
} else {
    $BackupName = "db_$Timestamp"
}

$GzFile = Join-Path $BackupDir "$BackupName.sql.gz"

Log-Msg "Generando backup: $BackupName"

# Verificar que postgres esté corriendo
$pgStatus = Invoke-Compose ps postgres 2>$null
if (-not ($pgStatus -match "healthy")) {
    Log-Fatal "PostgreSQL no está saludable. Inicia el stack primero."
}

# -----------------------------------------------------------------------------
# Dump SQL (custom format)
# -----------------------------------------------------------------------------
Log-Msg "Ejecutando pg_dump..."
$dumpCmd = "pg_dump -U `"$env:POSTGRES_USER`" -d `"$env:POSTGRES_DB`" --format=custom --compress=9 --no-owner --no-privileges --verbose"
Invoke-Compose exec -T postgres bash -c $dumpCmd | Out-File -FilePath $GzFile -Encoding ASCII

# Validar tamaño
$size = (Get-Item $GzFile).Length
if ($size -lt 100) {
    Log-Err "El backup parece estar vacío ($size bytes)"
    Remove-Item $GzFile -Force
    Log-Fatal "Backup fallido"
}

$humanSize = if ($size -gt 1MB) { "{0:N2} MB" -f ($size/1MB) } elseif ($size -gt 1KB) { "{0:N2} KB" -f ($size/1KB) } else { "$size bytes" }
Log-Msg "Backup de BD completado: $GzFile ($humanSize)"

# -----------------------------------------------------------------------------
# Backup de configuraciones
# -----------------------------------------------------------------------------
Log-Msg "Respaldando configuraciones..."
$TarFile = Join-Path $BackupDir "config_$BackupName.tar.gz"
$tarPaths = @(
    "docker-compose.yml", ".env",
    "synapse\homeserver.yaml", "synapse\log.config", "synapse\signing.key",
    "postgres\postgresql.conf", "postgres\pg_hba.conf", "postgres\init.sql",
    "redis\redis.conf",
    "element\config.json", "element\nginx.conf", "element\Dockerfile",
    "nginx\nginx.conf", "nginx\conf.d", "nginx\snippets", "nginx\well-known"
)

# Verificar tar disponible (Windows 10+ incluye tar)
$tarAvailable = Get-Command tar -ErrorAction SilentlyContinue
if ($tarAvailable) {
    Push-Location $ProjectRoot
    try {
        & tar -czf $TarFile $tarPaths 2>$null
        Log-Msg "Backup de config completado: $TarFile"
    } catch {
        Log-Warn "No se pudo crear el tar de configuración: $_"
    } finally {
        Pop-Location
    }
} else {
    Log-Warn "tar no disponible. Saltando backup de configuraciones."
}

# -----------------------------------------------------------------------------
# Rotación de backups antiguos
# -----------------------------------------------------------------------------
$retention = if ($env:BACKUP_RETENTION_DAYS) { [int]$env:BACKUP_RETENTION_DAYS } else { 7 }
Log-Msg "Rotando backups con más de $retention días..."
$cutoff = (Get-Date).AddDays(-$retention)
Get-ChildItem -Path $BackupDir -Filter "db_*.sql.gz" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $BackupDir -Filter "config_*.tar.gz" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host ""
Log-Msg "Backup completo."
Write-Host ""
Log-Msg "Archivos generados:"
Get-ChildItem -Path $BackupDir -Filter "*$BackupName*" | ForEach-Object {
    Write-Host "  $($_.Name) - $($_.Length) bytes"
}
