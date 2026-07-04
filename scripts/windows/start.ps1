# =============================================================================
# start.ps1 - Inicia el stack completo de Matrix
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Iniciando Matrix Docker Stack"

Check-Docker

# Verificar .env
if (-not (Test-Path (Join-Path $ProjectRoot ".env"))) {
    Log-Fatal "No existe .env. Ejecuta primero: scripts\windows\setup.ps1"
}

# Verificar signing key
$SigningKey = Join-Path $ProjectRoot "synapse\signing.key"
if (-not (Test-Path $SigningKey)) {
    Log-Warn "Signing key no encontrada. Generando..."
    $KeyId = (1..4 | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) }) -join ''
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $b64 = [Convert]::ToBase64String($bytes)
    "ed25519 $KeyId $b64" | Out-File -FilePath $SigningKey -Encoding ASCII -NoNewline
    Add-Content -Path $SigningKey -Value ""
    Log-Msg "Signing key generada automáticamente."
}

# Verificar certificados
$CertsDir = Join-Path $ProjectRoot "nginx\certs"
$MatrixCrt = Join-Path $CertsDir "matrix.crt"
$ElementCrt = Join-Path $CertsDir "element.crt"
if (-not ((Test-Path $MatrixCrt) -and (Test-Path $ElementCrt))) {
    Log-Warn "Certificados no encontrados. Generando..."
    & (Join-Path $PSScriptRoot "generate-certs.ps1")
}

# Verificar Element construido
$elementImage = docker image inspect matrix-element:custom 2>$null
if (-not $elementImage) {
    Log-Msg "Construyendo imagen de Element..."
    Invoke-Compose build element
}

Log-Msg "Iniciando servicios..."
Invoke-Compose up -d

Write-Host ""
Log-Msg "Servicios iniciados. Esperando healthchecks..."

Wait-ForHealth "postgres" 60 | Out-Null
Wait-ForHealth "redis" 30 | Out-Null
Wait-ForHealth "synapse" 120 | Out-Null
Wait-ForHealth "element" 30 | Out-Null
Wait-ForHealth "nginx" 30 | Out-Null

Write-Host ""
Log-Header "Estado final"
Invoke-Compose ps

Write-Host ""
Log-Msg "Stack iniciado correctamente."
Write-Host ""
Log-Msg "URLs de acceso:"
Log-Msg "  Element:  https://$($env:NGINX_ELEMENT_DOMAIN)"
Log-Msg "  Matrix:   https://$($env:NGINX_MATRIX_DOMAIN)"
Write-Host ""
Log-Msg "Para crear el primer administrador:"
Log-Msg "  scripts\windows\create-admin.ps1 <username>"
