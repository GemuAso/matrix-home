# =============================================================================
# create-admin.ps1 - Crea un usuario administrador en Matrix Synapse
# -----------------------------------------------------------------------------
# Uso:
#   .\scripts\windows\create-admin.ps1 <username>
#   .\scripts\windows\create-admin.ps1 admin
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Creación de usuario administrador"

Check-Docker
Require-StackRunning

if ($args.Count -lt 1) {
    Log-Fatal "Uso: create-admin.ps1 <username>"
}

$Username = $args[0]
$ServerName = if ($env:SYNAPSE_SERVER_NAME) { $env:SYNAPSE_SERVER_NAME } else { "home.arpa" }

Log-Msg "Creando usuario admin: @$Username`:$ServerName"

Invoke-Compose exec -it synapse `
    register_new_matrix_user `
    --user $Username `
    --admin `
    --yes `
    "http://localhost:8008"

Write-Host ""
Log-Msg "Usuario administrador creado: @$Username`:$ServerName"
Write-Host ""
Log-Msg "Ahora puedes iniciar sesión en Element con:"
Log-Msg "   Servidor: $($env:SYNAPSE_PUBLIC_URL)"
Log-Msg "   Usuario:  @$Username`:$ServerName"
Log-Msg "   Contraseña: la que acabas de definir"
