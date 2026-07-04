# =============================================================================
# create-user.ps1 - Crea un usuario normal (no admin) en Matrix Synapse
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Creación de usuario"

Check-Docker
Require-StackRunning

if ($args.Count -lt 1) {
    Log-Fatal "Uso: create-user.ps1 <username>"
}

$Username = $args[0]
$ServerName = if ($env:SYNAPSE_SERVER_NAME) { $env:SYNAPSE_SERVER_NAME } else { "home.arpa" }

Log-Msg "Creando usuario: @$Username`:$ServerName"

Invoke-Compose exec -it synapse `
    register_new_matrix_user `
    --user $Username `
    --no-admin `
    --yes `
    "http://localhost:8008"

Write-Host ""
Log-Msg "Usuario creado: @$Username`:$ServerName"
Write-Host ""
Log-Msg "El usuario puede iniciar sesión en Element:"
Log-Msg "   URL: https://$($env:NGINX_ELEMENT_DOMAIN)"
Log-Msg "   Usuario: @$Username`:$ServerName"
