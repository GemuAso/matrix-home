# =============================================================================
# setup.ps1 - Setup inicial del proyecto Matrix Docker
# -----------------------------------------------------------------------------
# Realiza:
#   1. Verifica dependencias (Docker, Docker Compose, OpenSSL)
#   2. Verifica/Crea .env desde .env.example
#   3. Validación completa antes de continuar:
#      - Variables obligatorias en .env
#      - Valores de ejemplo detectados
#      - Puertos disponibles (80, 443)
#      - Permisos de carpetas
#   4. Genera signing key de Synapse (si no existe)
#   5. Genera certificados SSL auto-firmados (si no existen)
#   6. Construye imagen personalizada de Element
#   7. Verifica docker-compose.yml
#   8. Validación final pre-arranque
#
# IMPORTANTE: Tras ejecutar este script, el proyecto está listo para:
#   docker compose up -d
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Show-Banner
Log-Header "Setup inicial Matrix Docker Stack v3.0.0"

# =============================================================================
# 1. Dependencias
# =============================================================================
Log-Msg "1/8 - Verificando dependencias..."
Require-Cmd "openssl"
Check-Docker
Log-Msg "   Docker y Docker Compose disponibles"
Log-Msg "   openssl disponible"

# =============================================================================
# 2. .env
# =============================================================================
Log-Msg "2/8 - Verificando .env..."
if (-not (Test-Path (Join-Path $ProjectRoot ".env"))) {
    if (Test-Path (Join-Path $ProjectRoot ".env.example")) {
        Copy-Item (Join-Path $ProjectRoot ".env.example") (Join-Path $ProjectRoot ".env")
        Log-Warn "   .env creado desde .env.example"
        Log-Warn "   ============================================"
        Log-Warn "   EDITA .env y cambia los valores antes de continuar."
        Log-Warn "   Debes cambiar AL MENOS las contraseñas y secretos."
        Log-Warn "   ============================================"
        Log-Warn "   Presiona ENTER cuando hayas terminado, o Ctrl+C para abortar."
        Read-Host
        # Recargar
        . (Join-Path $PSScriptRoot "_common.ps1")
    } else {
        Log-Fatal "No existe .env ni .env.example. No se puede continuar."
    }
} else {
    Log-Msg "   .env existe"
    # Recargar para asegurar que tenemos las últimas variables
    . (Join-Path $PSScriptRoot "_common.ps1")
}

# =============================================================================
# 3. Validar variables obligatorias
# =============================================================================
Log-Msg "3/8 - Validando variables obligatorias en .env..."
Validate-RequiredVars

# =============================================================================
# 4. Validar que no sean valores de ejemplo
# =============================================================================
Log-Msg "4/8 - Detectando valores de ejemplo..."
Validate-Env

# =============================================================================
# 5. Verificar permisos de carpetas
# =============================================================================
Log-Msg "5/8 - Verificando permisos..."
Check-Permissions

# =============================================================================
# 6. Verificar puertos disponibles
# =============================================================================
Log-Msg "6/8 - Verificando puertos..."
Check-AllPorts

# =============================================================================
# 7. Generar archivos faltantes
# =============================================================================

# 7a. Signing key
Log-Msg "7/8 - Verificando/Generando archivos críticos..."
Log-Msg "   Signing key de Synapse..."
$SigningKey = Join-Path $ProjectRoot "synapse\signing.key"
if (-not (Test-Path $SigningKey) -or (Get-Item $SigningKey).Length -eq 0) {
    Log-Msg "   Generando nueva signing key..."

    # Intentar método oficial de Synapse (docker run generate_signing_key)
    $SynapseImage = "matrixdotorg/synapse:v1.118.0"
    $imageExists = docker image inspect $SynapseImage 2>$null
    if ($imageExists) {
        Log-Msg "   Usando método oficial de Synapse (generate_signing_key)..."
        $signingDir = Join-Path $ProjectRoot "synapse"
        docker run --rm -v "${signingDir}:C:\signing" $SynapseImage generate_signing_key -O C:\signing 2>$null
    }

    # Si el método oficial falló o no hay imagen, generar manualmente
    if (-not (Test-Path $SigningKey) -or (Get-Item $SigningKey).Length -eq 0) {
        Log-Msg "   Usando generación manual (fallback)..."
        $KeyId = (1..4 | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) }) -join ''
        # Generar 32 bytes aleatorios y codificar a base64
        $bytes = New-Object byte[] 32
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $b64 = [Convert]::ToBase64String($bytes)
        "ed25519 $KeyId $b64" | Out-File -FilePath $SigningKey -Encoding ASCII -NoNewline
        Add-Content -Path $SigningKey -Value ""
    }
    Log-Msg "   Signing key generada: $SigningKey"
} else {
    Log-Msg "   Signing key ya existe"
}

# 7b. Certificados SSL
Log-Msg "   Certificados SSL..."
& (Join-Path $PSScriptRoot "generate-certs.ps1")

# =============================================================================
# 8. Validación final y build
# =============================================================================
Log-Msg "8/8 - Validación final..."

# Verificar que los archivos críticos existen ahora
if (-not (Test-Path $SigningKey) -or (Get-Item $SigningKey).Length -eq 0) {
    Log-Fatal "signing.key no se generó correctamente. Revisa los logs arriba."
}

# Verificar certificados
$certFiles = @("ca.crt", "ca.key", "matrix.crt", "matrix.key", "element.crt", "element.key", "default.crt", "default.key")
$certsOk = $true
foreach ($cf in $certFiles) {
    $certPath = Join-Path $ProjectRoot "nginx\certs\$cf"
    if (-not (Test-Path $certPath)) {
        Log-Err "Falta certificado: nginx\certs\$cf"
        $certsOk = $false
    }
}
if (-not $certsOk) {
    Log-Fatal "Algunos certificados no se generaron correctamente. Revisa los logs arriba."
}
Log-Msg "   Todos los archivos críticos verificados"

# Construir Element
Log-Msg "   Construyendo imagen personalizada de Element..."
Invoke-Compose build element
Log-Msg "   Imagen element construida"

# Validar compose
Log-Msg "   Validando docker-compose.yml..."
Invoke-Compose config --quiet
Log-Msg "   docker-compose.yml válido"

Write-Host ""
Log-Msg "Setup completo. Todos los archivos críticos han sido generados/validados."
Write-Host ""
Log-Msg "El proyecto está listo para iniciar con:"
Write-Host ""
Log-Msg "  docker compose up -d"
Write-Host ""
Log-Msg "O usando el script de inicio:"
Write-Host ""
Log-Msg "  .\scripts\windows\start.ps1"
Write-Host ""
Log-Msg "Después de iniciar, crea el primer administrador:"
Write-Host ""
Log-Msg "  .\scripts\windows\create-admin.ps1 admin"
Write-Host ""