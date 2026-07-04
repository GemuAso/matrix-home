# =============================================================================
# generate-certs.ps1 - Genera certificados SSL auto-firmados para LAN
# -----------------------------------------------------------------------------
# Genera CA raiz y certs para matrix.home.arpa y element.home.arpa.
# Los certificados se guardan con nombres fijos: matrix.crt, element.crt.
# =============================================================================

. (Join-Path $PSScriptRoot "_common.ps1")

Log-Header "Generacion de certificados SSL auto-firmados"

# Cargar dominios desde .env
$MatrixDomain = if ($env:NGINX_MATRIX_DOMAIN) { $env:NGINX_MATRIX_DOMAIN } else { "matrix.home.arpa" }
$ElementDomain = if ($env:NGINX_ELEMENT_DOMAIN) { $env:NGINX_ELEMENT_DOMAIN } else { "element.home.arpa" }

$CertsDir = Join-Path $ProjectRoot "nginx\certs"
if (-not (Test-Path $CertsDir)) {
    New-Item -ItemType Directory -Path $CertsDir -Force | Out-Null
}

Require-Cmd "openssl"

Log-Msg "Dominios:"
Log-Msg "  Matrix:  $MatrixDomain"
Log-Msg "  Element: $ElementDomain"
Write-Host ""

# -----------------------------------------------------------------------------
# Generar CA raiz
# -----------------------------------------------------------------------------
$CAKey = Join-Path $CertsDir "ca.key"
$CACrt = Join-Path $CertsDir "ca.crt"

if ((Test-Path $CAKey) -and (Test-Path $CACrt)) {
    Log-Warn "CA ya existe. Si quieres regenerar, borra $CAKey y $CACrt primero."
} else {
    Log-Msg "Generando CA raiz..."
    & openssl genrsa -out $CAKey 4096
    & openssl req -new -x509 -key $CAKey -out $CACrt `
        -days 3650 -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=Matrix LAN CA" `
        -addext "basicConstraints=critical,CA:TRUE,pathlen:1" `
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    Log-Msg "CA generada: $CACrt (valida 10 anos)"
}

# -----------------------------------------------------------------------------
# Funcion para generar cert firmado por la CA (nombre fijo)
# -----------------------------------------------------------------------------
function New-SignedCert {
    param([string]$Domain, [string]$CertName)

    $Key = Join-Path $CertsDir "$CertName.key"
    $Csr = Join-Path $CertsDir "$CertName.csr"
    $Crt = Join-Path $CertsDir "$CertName.crt"

    if ((Test-Path $Key) -and (Test-Path $Crt)) {
        Log-Warn "Cert para $Domain ya existe. Saltando."
        return
    }

    Log-Msg "Generando cert para $Domain..."
    & openssl genrsa -out $Key 2048
    & openssl req -new -key $Key -out $Csr `
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=$Domain"

    $ExtFile = Join-Path $CertsDir "$CertName.ext"
    @"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $Domain
DNS.2 = localhost
IP.1 = 127.0.0.1
"@ | Out-File -FilePath $ExtFile -Encoding ASCII

    & openssl x509 -req -in $Csr -CA $CACrt -CAkey $CAKey `
        -CAcreateserial -out $Crt -days 365 -sha256 `
        -extfile $ExtFile

    Remove-Item $Csr -ErrorAction SilentlyContinue
    Remove-Item $ExtFile -ErrorAction SilentlyContinue
    Log-Msg "Cert generado: $Crt (valido 1 ano) -> $Domain"
}

New-SignedCert $MatrixDomain "matrix"
New-SignedCert $ElementDomain "element"

# -----------------------------------------------------------------------------
# Cert default para el catch-all
# -----------------------------------------------------------------------------
$DefaultKey = Join-Path $CertsDir "default.key"
$DefaultCrt = Join-Path $CertsDir "default.crt"
if (-not ((Test-Path $DefaultKey) -and (Test-Path $DefaultCrt))) {
    Log-Msg "Generando cert default..."
    & openssl req -new -newkey rsa:2048 -nodes `
        -keyout $DefaultKey `
        -out $DefaultCrt `
        -x509 -days 365 `
        -subj "/C=CO/ST=Bogota/L=Bogota/O=Matrix LAN/CN=default"
}

Write-Host ""
Log-Msg "Certificados generados en $CertsDir"
Log-Msg "Para evitar warnings en el navegador:"
Log-Msg "  Windows: Doble clic en $CACrt -> Instalar certificado -> Equipo local -> Entidades de certificacion raiz de confianza"
