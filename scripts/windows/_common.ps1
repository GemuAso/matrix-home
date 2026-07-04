# =============================================================================
# _common.ps1 - Funciones y variables compartidas por todos los scripts
# -----------------------------------------------------------------------------
# Este archivo NO se ejecuta directamente. Se incluye con . (dot-source) desde
# otros scripts de la carpeta scripts/windows/.
# =============================================================================

# Strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Detectar la raíz del proyecto (2 niveles arriba de este archivo)
# scripts/windows/_common.ps1 -> ../../ = raíz del proyecto
# -----------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

# -----------------------------------------------------------------------------
# Cargar .env si existe
# -----------------------------------------------------------------------------
$EnvFile = Join-Path $ProjectRoot ".env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split '=', 2
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()
                # Quitar comillas si las hay
                if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                Set-Item -Path "Env:$key" -Value $value
            }
        }
    }
} else {
    Write-Host "[WARN] No se encontró .env en $EnvFile" -ForegroundColor Yellow
    Write-Host "       Copia .env.example a .env y ajusta los valores." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Funciones de logging
# -----------------------------------------------------------------------------
function Log-Msg {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [INFO]  $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [WARN]  $Message" -ForegroundColor Yellow
}

function Log-Err {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [ERROR] $Message" -ForegroundColor Red
}

function Log-Fatal {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [FATAL] $Message" -ForegroundColor Red
    exit 1
}

function Log-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Blue
}

# -----------------------------------------------------------------------------
# Verificar que un comando está disponible
# -----------------------------------------------------------------------------
function Require-Cmd {
    param([string]$Cmd)
    if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
        Log-Fatal "Comando requerido no encontrado: $Cmd. Instálalo antes de continuar."
    }
}

# -----------------------------------------------------------------------------
# Verificar Docker y Docker Compose
# -----------------------------------------------------------------------------
function Check-Docker {
    Require-Cmd "docker"
    # Verificar que Docker daemon esté corriendo
    try {
        $null = docker info 2>&1
    } catch {
        Log-Fatal "Docker daemon no está corriendo. Inicia Docker Desktop antes de continuar."
    }

    $composeOk = docker compose version 2>$null
    if (-not $composeOk) {
        $composeV1 = Get-Command "docker-compose" -ErrorAction SilentlyContinue
        if ($composeV1) {
            Log-Warn "Se detectó docker-compose v1. Se recomienda docker compose v2."
        } else {
            Log-Fatal "Docker Compose no está instalado. Instala 'docker compose plugin'."
        }
    }
}

# -----------------------------------------------------------------------------
# Ejecutar docker compose en el directorio del proyecto
# -----------------------------------------------------------------------------
function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    Push-Location $ProjectRoot
    try {
        & docker compose @Args
    } finally {
        Pop-Location
    }
}

# -----------------------------------------------------------------------------
# Verificar que el stack esté corriendo
# -----------------------------------------------------------------------------
function Test-StackRunning {
    $services = Invoke-Compose ps --services --filter "status=running" 2>$null
    return ($services -ne $null -and $services.Count -gt 0)
}

function Require-StackRunning {
    if (-not (Test-StackRunning)) {
        Log-Fatal "El stack no está corriendo. Ejecuta: scripts\windows\start.ps1"
    }
}

# -----------------------------------------------------------------------------
# Variables obligatorias en .env
# -----------------------------------------------------------------------------
$RequiredEnvVars = @(
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB",
    "REDIS_PASSWORD",
    "SYNAPSE_SERVER_NAME",
    "SYNAPSE_PUBLIC_URL",
    "SYNAPSE_REGISTRATION_SHARED_SECRET",
    "SYNAPSE_MACAROON_SECRET_KEY",
    "SYNAPSE_FORM_SECRET",
    "SYNAPSE_PASSWORD_PEPPER",
    "ELEMENT_URL",
    "NGINX_MATRIX_DOMAIN",
    "NGINX_ELEMENT_DOMAIN"
)

# -----------------------------------------------------------------------------
# Validar variables obligatorias en .env
# -----------------------------------------------------------------------------
function Validate-RequiredVars {
    $missing = 0
    foreach ($var in $RequiredEnvVars) {
        $val = [System.Environment]::GetEnvironmentVariable($var)
        if ([string]::IsNullOrEmpty($val)) {
            Log-Err "Variable obligatoria vacía o no definida: $var"
            $missing++
        }
    }
    if ($missing -gt 0) {
        Log-Fatal "Faltan $missing variables obligatorias en .env. Revisa el archivo."
    }
    Log-Msg "   Todas las variables obligatorias están definidas ($($RequiredEnvVars.Count) variables)"
}

# -----------------------------------------------------------------------------
# Validar que .env tenga valores reales
# -----------------------------------------------------------------------------
function Validate-Env {
    $problems = 0
    $pgPass = [System.Environment]::GetEnvironmentVariable("POSTGRES_PASSWORD")
    $redisPass = [System.Environment]::GetEnvironmentVariable("REDIS_PASSWORD")
    $regSecret = [System.Environment]::GetEnvironmentVariable("SYNAPSE_REGISTRATION_SHARED_SECRET")
    $macaroon = [System.Environment]::GetEnvironmentVariable("SYNAPSE_MACAROON_SECRET_KEY")
    $formSecret = [System.Environment]::GetEnvironmentVariable("SYNAPSE_FORM_SECRET")
    $pepper = [System.Environment]::GetEnvironmentVariable("SYNAPSE_PASSWORD_PEPPER")

    if ($pgPass -match "ChangeMe|CambiaEsta|cambiar_por") {
        Log-Warn "POSTGRES_PASSWORD parece ser valor de ejemplo. Cámbialo en .env"
        $problems++
    }
    if ($redisPass -match "cambiar_por") {
        Log-Warn "REDIS_PASSWORD parece ser valor de ejemplo. Cámbialo en .env"
        $problems++
    }
    if ($regSecret -match "cambiar_por") {
        Log-Warn "SYNAPSE_REGISTRATION_SHARED_SECRET parece ser valor de ejemplo."
        $problems++
    }
    if ($macaroon -match "cambiar_por") {
        Log-Warn "SYNAPSE_MACAROON_SECRET_KEY parece ser valor de ejemplo."
        $problems++
    }
    if ($formSecret -match "cambiar_por") {
        Log-Warn "SYNAPSE_FORM_SECRET parece ser valor de ejemplo."
        $problems++
    }
    if ($pepper -match "cambiar_por") {
        Log-Warn "SYNAPSE_PASSWORD_PEPPER parece ser valor de ejemplo."
        $problems++
    }
    if ($problems -gt 0) {
        Log-Warn "Se encontraron $problems variables con valores de ejemplo."
        Log-Warn "El stack puede funcionar pero NO es seguro para producción."
    }
}

# -----------------------------------------------------------------------------
# Verificar disponibilidad de puertos
# -----------------------------------------------------------------------------
function Test-PortInUse {
    param([int]$Port)
    try {
        $connection = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
        $connection.Start()
        $connection.Stop()
        return $false
    } catch {
        return $true
    }
}

function Check-AllPorts {
    $httpPort = if ($env:NGINX_HTTP_PORT) { [int]$env:NGINX_HTTP_PORT } else { 80 }
    $httpsPort = if ($env:NGINX_HTTPS_PORT) { [int]$env:NGINX_HTTPS_PORT } else { 443 }

    Log-Msg "Verificando puertos requeridos..."

    if (Test-PortInUse -Port $httpPort) {
        Log-Fatal "Puerto $httpPort (HTTP) ya está en uso. Libéralo antes de continuar."
    }
    Log-Msg "   Puerto $httpPort disponible (HTTP)"

    if (Test-PortInUse -Port $httpsPort) {
        Log-Fatal "Puerto $httpsPort (HTTPS) ya está en uso. Libéralo antes de continuar."
    }
    Log-Msg "   Puerto $httpsPort disponible (HTTPS)"
}

# -----------------------------------------------------------------------------
# Verificar permisos de carpetas críticas
# -----------------------------------------------------------------------------
function Check-Permissions {
    $dirs = @(
        (Join-Path $ProjectRoot "nginx\certs"),
        (Join-Path $ProjectRoot "synapse"),
        (Join-Path $ProjectRoot "backups")
    )

    Log-Msg "Verificando permisos de carpetas..."
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            } catch {
                Log-Fatal "No se pudo crear el directorio: $dir"
            }
        }
    }
    Log-Msg "   Permisos de carpetas correctos"
}

# -----------------------------------------------------------------------------
# Esperar a que un servicio esté saludable
# -----------------------------------------------------------------------------
function Wait-ForHealth {
    param([string]$Service, [int]$Timeout = 120)
    Log-Msg "Esperando a que $Service esté saludable (timeout: ${Timeout}s)..."
    $elapsed = 0
    $healthy = $false
    while (-not $healthy -and $elapsed -lt $Timeout) {
        $output = Invoke-Compose ps $Service 2>$null
        if ($output -match "healthy") {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host -NoNewline "."
    }
    Write-Host ""
    if ($healthy) {
        Log-Msg "$Service está saludable."
    } else {
        Log-Err "Timeout esperando $Service"
        return $false
    }
    return $true
}

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
function Show-Banner {
    Write-Host @'

  __  __ _       _     _              ____
 |  \/  (_) __ _| | __| |   _ __ ___ |___ \
 | |\/| | |/ _` | |/ _` |  | '_ ` _ \  __) |
 | |  | | | (_| | | (_| |  | | | | | |/ __/
 |_|  |_|_|\__,_|_|\__,_|  |_| |_| |_|_____|

'@ -ForegroundColor Cyan
    Write-Host "Matrix Synapse Docker Stack - LAN" -ForegroundColor Cyan
    Write-Host "Versión: 3.0.0" -ForegroundColor Cyan
    Write-Host ""
}