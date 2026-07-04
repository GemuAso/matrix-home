# =============================================================================
# setup.ps1 - Setup inicial del proyecto Matrix Docker
# -----------------------------------------------------------------------------
# Realiza verificaciones, genera signing key y certs, construye Element.
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Show-Banner
Log-Header "Setup inicial Matrix Docker Stack"

# 1. Dependencias
Log-Msg "1/7 - Verificando dependencias..."
Check-Docker
Require-Cmd "openssl"
Log-Msg "   Docker disponible"
Log-Msg "   openssl disponible"

# 2. .env
Log-Msg "2/7 - Verificando .env..."
if (-not (Test-Path (Join-Path $ProjectRoot ".env"))) {
    if (Test-Path (Join-Path $ProjectRoot ".env.example")) {
        Copy-Item (Join-Path $ProjectRoot ".env.example") (Join-Path $ProjectRoot ".env")
        Log-Warn "   .env creado desde .env.example"
        Log-Warn "   EDITA .env y cambia los valores antes de continuar."
        Log-Warn "   Presiona ENTER cuando hayas terminado, o Ctrl+C para abortar."
        Read-Host
        # Recargar
        . (Join-Path $PSScriptRoot "_common.ps1")
    } else {
        Log-Fatal "No existe .env ni .env.example"
    }
} else {
    Log-Msg "   .env existe"
}

# 3. Signing key
Log-Msg "3/7 - Verificando signing key de Synapse..."
$SigningKey = Join-Path $ProjectRoot "synapse\signing.key"
if (-not (Test-Path $SigningKey) -or (Get-Item $SigningKey).Length -eq 0) {
    Log-Msg "   Generando nueva signing key..."
    $KeyId = (1..4 | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) }) -join ''
    # Generar 32 bytes aleatorios y codificar a base64
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $b64 = [Convert]::ToBase64String($bytes)
    "ed25519 $KeyId $b64" | Out-File -FilePath $SigningKey -Encoding ASCII -NoNewline
    Add-Content -Path $SigningKey -Value ""
    Log-Msg "   Signing key generada: $SigningKey"
} else {
    Log-Msg "   Signing key existe"
}

# 4. Certificados
Log-Msg "4/7 - Generando certificados SSL..."
& (Join-Path $PSScriptRoot "generate-certs.ps1")
Log-Msg "   Certificados listos"

# 5. Validar .env
Log-Msg "5/7 - Validando secretos en .env..."
Validate-Env

# 6. Construir Element
Log-Msg "6/7 - Construyendo imagen personalizada de Element..."
Invoke-Compose build element
Log-Msg "   Imagen element construida"

# 7. Validar compose
Log-Msg "7/7 - Validando docker-compose.yml..."
Invoke-Compose config --quiet
Log-Msg "   docker-compose.yml válido"

Write-Host ""
Log-Msg "Setup completo."
Write-Host ""
Log-Msg "Próximos pasos:"
Log-Msg "  1. Edita .env con tus valores reales (contraseñas, dominios, SMTP)"
Log-Msg "  2. Si cambiaste dominios, edita homeserver.yaml, config.json, nginx/conf.d/*.conf"
Log-Msg "  3. Inicia el stack: scripts\windows\start.ps1"
Log-Msg "  4. Crea un admin: scripts\windows\create-admin.ps1 admin"
