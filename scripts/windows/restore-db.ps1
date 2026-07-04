# =============================================================================
# restore-db.ps1 - Restaura un backup de base de datos
# -----------------------------------------------------------------------------
# Uso:
#   .\scripts\windows\restore-db.ps1 <archivo.sql.gz>
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Restauración de base de datos"

Check-Docker

if ($args.Count -lt 1) {
    Log-Fatal "Uso: restore-db.ps1 <archivo.sql.gz>"
}

$BackupFile = $args[0]
if (-not (Test-Path $BackupFile)) {
    $BackupFile = Join-Path $ProjectRoot "backups\$BackupFile"
}
if (-not (Test-Path $BackupFile)) {
    Log-Fatal "Archivo no encontrado: $($args[0])"
}

Log-Msg "Archivo a restaurar: $BackupFile"
$size = (Get-Item $BackupFile).Length
Log-Msg "Tamaño: $size bytes"

# Verificar PostgreSQL
$pgStatus = Invoke-Compose ps postgres 2>$null
if (-not ($pgStatus -match "healthy")) {
    Log-Fatal "PostgreSQL no está saludable. Inicia el stack primero."
}

# Backup automático antes de restaurar
Log-Warn "Se realizará un backup automático antes de restaurar."
Log-Warn "Presiona ENTER para continuar, o Ctrl+C para abortar."
Read-Host

$AutoBackupName = "pre_restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Log-Msg "Creando backup preventivo: $AutoBackupName"
& (Join-Path $PSScriptRoot "backup-db.ps1") $AutoBackupName

# Confirmar
Write-Host ""
Log-Warn "ESTO BORRARÁ Y RECREARÁ LA BASE DE DATOS '$($env:POSTGRES_DB)'"
Log-Warn "Todos los datos actuales se perderán."
$confirm = Read-Host "Confirma escribiendo 'SI RESTAURAR'"
if ($confirm -ne "SI RESTAURAR") {
    Log-Msg "Operación cancelada."
    exit 0
}

# Restaurar
Log-Msg "Restaurando base de datos..."
$restoreCmd = "pg_restore -U `"$env:POSTGRES_USER`" -d `"$env:POSTGRES_DB`" --clean --if-exists --no-owner --no-privileges --verbose"

if ($BackupFile -like "*.gz") {
    # Backup comprimido
    $tempFile = Join-Path $env:TEMP "restore_temp_$(Get-Random).bin"
    try {
        # Descomprimir y restaurar
        $bytes = [System.IO.File]::ReadAllBytes($BackupFile)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
        $outMs = New-Object System.IO.MemoryStream
        $gz.CopyTo($outMs)
        [System.IO.File]::WriteAllBytes($tempFile, $outMs.ToArray())
        $gz.Close()
        $ms.Close()

        # Copiar al contenedor y restaurar
        Get-Content $tempFile -Encoding Byte -ReadCount 0 | Invoke-Compose exec -T postgres bash -c $restoreCmd
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
} else {
    Get-Content $BackupFile -Encoding Byte -ReadCount 0 | Invoke-Compose exec -T postgres bash -c $restoreCmd
}

Write-Host ""
Log-Msg "Verificando restauración..."
$countCmd = "psql -U `"$env:POSTGRES_USER`" -d `"$env:POSTGRES_DB`" -t -c `"SELECT count(*) FROM information_schema.tables WHERE table_schema='public';`""
$tables = Invoke-Compose exec -T postgres bash -c $countCmd 2>$null
$tables = $tables.Trim()
Log-Msg "Tablas en la base restaurada: $tables"

Write-Host ""
Log-Msg "Restauración completada."
Log-Msg "Reinicia Synapse para que cargue los datos: scripts\windows\restart.ps1 synapse"
