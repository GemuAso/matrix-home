# Seguridad

> Modelo de amenazas, mitigaciones implementadas y recomendaciones adicionales.

---

## 1. Principios de seguridad aplicados

El stack se diseñó siguiendo estos principios:

1. **Defensa en profundidad**: múltiples capas de protección, ningún punto único de fallo.
2. **Principio de menor privilegio**: cada componente tiene solo los permisos necesarios.
3. **Aislamiento**: redes y contenedores separados según función.
4. **Secretos externalizados**: nada de credenciales en código o imágenes.
5. **Auditable**: logs estructurados, sin secrets en logs.
6. **Fail-safe**: ante la duda, denegar (pg_hba reject, Nginx 444).
7. **Minimizar superficie expuesta**: solo los puertos estrictamente necesarios.

---

## 2. Modelo de amenazas

### 2.1 Actores

| Actor | Descripción | Nivel de confianza |
|-------|-------------|-------------------|
| Administrador | Opera el stack | Total |
| Usuario autenticado | Usa Element para mensajería | Limitada a su cuenta |
| Atacante externo | En Internet, sin acceso LAN | Ninguna |
| Atacante en LAN | En la red local, sin credenciales | Ninguna |
| Usuario malicioso | Usuario autenticado con malas intenciones | Limitada pero monitorizada |

### 2.2 Superficie de ataque

```
┌─────────────────────────────────────────────┐
│  Exposición pública (Internet)              │
│  ─ Sin puertos expuestos ─                  │
│                                              │
│  Exposición LAN                              │
│  ┌─────────────────────────────────────┐   │
│  │  Host Docker                         │   │
│  │  Puertos: 80, 443                    │   │
│  │  Servicio: Nginx (con TLS)           │   │
│  └─────────────────────────────────────┘   │
│                                              │
│  Exposición interna Docker                   │
│  ┌─────────────────────────────────────┐   │
│  │  matrix_frontend                     │   │
│  │  - Synapse :8008                     │   │
│  │  - Element :80                       │   │
│  │  matrix_internal                     │   │
│  │  - PostgreSQL :5432                  │   │
│  │  - Redis :6379                       │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 2.3 Amenazas identificadas

| ID | Amenaza | Vector | Impacto | Probabilidad |
|----|---------|--------|---------|--------------|
| A1 | Atacante externo explota vuln en Nginx/Synapse | Internet | Alto | Baja (no expuesto) |
| A2 | Atacante en LAN hace brute force a Nginx | LAN | Medio | Media |
| A3 | Atacante en LAN accede a PostgreSQL | LAN | Crítico | Muy baja (no expuesto) |
| A4 | Atacante en LAN accede a Redis | LAN | Alto | Muy baja (no expuesto) |
| A5 | Usuario malicioso intenta escalar privilegios | App | Alto | Baja |
| A6 | Compromiso de credenciales admin | Social | Crítico | Media |
| A7 | Pérdida de datos por fallo hardware | Hardware | Alto | Baja |
| A8 | Robo de backups | Físico/Lógico | Alto | Baja |
| A9 | Ataque MITM en LAN | Red | Medio | Baja (TLS) |
| A10 | Vulnerabilidad en dependencia (supply chain) | Software | Alto | Media |

---

## 3. Mitigaciones implementadas

### 3.1 Aislamiento de red

**Implementación**: dos redes Docker separadas.

- `matrix_internal`: PostgreSQL + Redis + Synapse.
- `matrix_frontend`: Nginx + Element + Synapse.

PostgreSQL y Redis NO están en `matrix_frontend`, así que Nginx no puede alcanzarlos directamente. Esto significa que si un atacante compromete Nginx, no puede pivotar a la base de datos.

**Verificación**:

```bash
# Desde dentro del contenedor Nginx, no debería poder llegar a postgres
docker compose exec nginx wget -q -O- http://postgres:5432 2>&1 | head -1
# Esperado: fail o timeout
```

### 3.2 Sin exposición pública

**Implementación**: solo se publican puertos 80 y 443 al host, y estos deben estar protegidos por firewall que solo permite tráfico desde la LAN.

```bash
# En Ubuntu, con UFW:
sudo ufw default deny incoming
sudo ufw allow from 192.168.1.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 443 proto tcp
```

**Verificación**:

```bash
sudo ufw status verbose
# Debe mostrar solo allow desde LAN CIDR para 80/443
```

### 3.3 TLS terminado en Nginx

**Implementación**: certificados auto-firmados generados por script, con CA local importable en clientes.

- TLS 1.2 y 1.3 únicamente (sin TLS 1.0/1.1 inseguros).
- Ciphersuites modernas (ECDHE + AES-GCM o CHACHA20-POLY1305).
- HSTS (max-age=31536000).
- Sesiones TLS cacheadas (ssl_session_cache).

**Verificación**:

```bash
# Desde un cliente
openssl s_client -connect matrix.home.arpa:443 -tls1_3 < /dev/null 2>&1 | grep "Protocol\|Cipher"
# Debe mostrar Protocol: TLSv1.3 y cipher moderna
```

### 3.4 PostgreSQL hardened

**Implementación**:

- `pg_hba.conf` restringe conexiones a rangos Docker internos (172.16.0.0/12, 192.168.0.0/16, 10.0.0.0/8).
- `scram-sha-256` como método de autenticación (más seguro que md5).
- `password_encryption = scram-sha-256` por defecto.
- Sin puerto publicado al host.
- `ssl = off` (tráfico interno entre contenedores, no necesita SSL).

**Verificación**:

```bash
# Intentar conectar desde fuera del stack (debería fallar)
psql -h <ip-host> -U synapse_user -d synapse
# Esperado: connection refused o timeout
```

### 3.5 Redis con contraseña y comandos bloqueados

**Implementación** en `redis/redis.conf`:

```conf
requirepass <REDIS_PASSWORD>

rename-command FLUSHALL ""   # Borrar todas las keys
rename-command FLUSHDB ""    # Borrar DB actual
rename-command CONFIG ""     # Cambiar configuración en runtime
rename-command KEYS ""       # Listar todas las keys (potencialmente peligroso)
rename-command DEBUG ""      # Comandos de debug
rename-command SHUTDOWN MATRIX_REDIS_SHUTDOWN_2026  # Renombrado
```

**Verificación**:

```bash
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" FLUSHALL
# Esperado: ERR unknown command 'FLUSHALL'
```

### 3.6 Synapse hardened

**Implementación** en `homeserver.yaml`:

```yaml
# Sin federación
federation:
  enabled: false

# Sin registro público
enable_registration: false

# Política de contraseñas fuerte
password_config:
  policy:
    enabled: true
    minimum_length: 10
    require_digit: true
    require_symbol: true
    require_lowercase: true
    require_uppercase: true

# Rate limiting agresivo para auth
rc_login:
  address:
    per_second: 0.17   # ~10/min por IP
    burst_count: 5
  failed_attempts:
    per_second: 0.17
    burst_count: 5

# URL preview deshabilitado (no sale a Internet)
url_preview_enabled: false

# Sin stats a matrix.org
report_stats: false
```

### 3.7 Nginx hardened

**Implementación**:

- `server_tokens off` (no expone versión).
- Headers de seguridad: HSTS, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy, CSP.
- Rate limiting por IP y por endpoint.
- Catch-all server que devuelve 444 (sin respuesta) para dominios no reconocidos.
- Buffer limits para prevenir DDoS.
- Timeouts cortos para prevenir slowloris.

**Verificación**:

```bash
curl -I -k https://matrix.home.arpa
# Debe mostrar headers de seguridad
```

### 3.8 Contenedores con no-new-privileges

**Implementación**: todos los servicios tienen `security_opt: - no-new-privileges:true`.

Esto previene que un proceso dentro del contenedor escale privilegios via setuid binaries.

### 3.9 Secretos externalizados

**Implementación**:

- Todas las contraseñas y tokens en `.env`.
- `.env` está en `.gitignore` (no se commitea).
- Permisos recomendados: `chmod 600 .env` (Linux).
- `homeserver.yaml` ya no contiene secretos hardcodeados. Desde v2.0.0 se usa `homeserver.yaml.template` con variables de entorno inyectadas via `envsubst` en el entrypoint del contenedor. Los secretos `SYNAPSE_FORM_SECRET` y `SYNAPSE_PASSWORD_PEPPER` se definen en `.env`.

### 3.10 Logs estructurados sin secrets

**Implementación**:

- Docker json-file driver con rotación (max-size 100m, max-file 5).
- Synapse no loguea passwords ni tokens por defecto.
- PostgreSQL no loguea statements con parámetros sensibles por defecto.

**Verificación**:

```bash
# Buscar potential secrets en logs
docker compose logs 2>&1 | grep -iE "password|token|secret" | head -5
# Debería no aparecer nada sensible
```

### 3.11 Backups protegidos

**Implementación**:

- Carpeta `backups/` en `.gitignore`.
- Permisos de archivo recomendados: `chmod 600 backups/*`.
- Rotación automática (`BACKUP_RETENTION_DAYS`).

**Recomendación adicional**: cifrar backups con gpg antes de moverlos fuera del host:

```bash
gpg --symmetric --cipher-algo AES256 backups/db_*.sql.gz
# Resultado: db_*.sql.gz.gpg
```

---

## 4. Hardening adicional del host (Ubuntu)

Para entornos productivos, aplicar:

### 4.1 SSH

```bash
sudo nano /etc/ssh/sshd_config
```

```conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
AllowUsers deploy
```

```bash
sudo systemctl restart sshd
```

### 4.2 Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# Configurar jail para Matrix
sudo tee /etc/fail2ban/jail.d/matrix.conf <<EOF
[matrix-auth]
enabled = true
filter = matrix-auth
logpath = /var/lib/docker/volumes/matrix_nginx_logs/_data/matrix-access.log
maxretry = 5
findtime = 600
bantime = 3600
EOF
```

### 4.3 Actualizaciones automáticas de seguridad

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 4.4 Auditd (auditoría de sistema)

```bash
sudo apt install -y auditd audispd-plugins
sudo systemctl enable --now auditd
```

### 4.5 AppArmor o SELinux

Verificar que AppArmor está activo (Ubuntu por defecto):

```bash
sudo apparmor_status
```

---

## 5. Rotación de secretos

### 5.1 Frecuencia recomendada

| Secreto | Frecuencia rotación | Procedimiento |
|---------|---------------------|---------------|
| `POSTGRES_PASSWORD` | 6-12 meses | Ver abajo |
| `REDIS_PASSWORD` | 6-12 meses | Ver abajo |
| `SYNAPSE_MACAROON_SECRET_KEY` | 12 meses | Invalida todas las sesiones |
| `SYNAPSE_REGISTRATION_SHARED_SECRET` | 12 meses | Cambiar en homeserver.yaml |
| `SYNAPSE_ADMIN_API_TOKEN` | 6 meses | Cambiar en homeserver.yaml |
| `password_config.pepper` | NUNCA | Invalida todos los hashes, requiere reset masivo |
| `synapse/signing.key` | 12 meses | Ver `ADMIN_GUIDE.md` sección 3.4 |
| CA local | 5-10 años | Regenerar certs |
| Certs SSL | 1 año | Regenerar |

### 5.2 Rotar POSTGRES_PASSWORD

1. Generar nueva contraseña:
   ```bash
   NEW_PASS=$(openssl rand -base64 32)
   echo "$NEW_PASS"
   ```

2. Cambiar en PostgreSQL:
   ```bash
   docker compose exec postgres psql -U synapse_user -d synapse \
       -c "ALTER USER synapse_user WITH PASSWORD '$NEW_PASS';"
   ```

3. Actualizar `.env` con nueva contraseña.

4. Actualizar `synapse/homeserver.yaml` con nueva contraseña.

5. Reiniciar:
   ```bash
   bash scripts/linux/restart.sh synapse
   ```

### 5.3 Rotar REDIS_PASSWORD

1. Generar nueva contraseña.

2. Actualizar `redis/redis.conf`.

3. Actualizar `synapse/homeserver.yaml`.

4. Actualizar `.env`.

5. Reiniciar:
   ```bash
   bash scripts/linux/restart.sh redis synapse
   ```

---

## 6. Cumplimiento normativo

### 6.1 GDPR (Reglamento General de Protección de Datos)

Si manejas datos de personas en la UE:

- **DPIA**: realiza una Evaluación de Impacto en la Protección de Datos.
- **Consentimiento**: los usuarios deben aceptar el tratamiento de sus datos.
- **Derecho al olvido**: implementar procedimiento de borrado completo:
  ```bash
  docker compose exec postgres psql -U synapse_user -d synapse \
      -c "DELETE FROM users WHERE name='@user:home.arpa';"
  # + purge media del usuario
  ```
- **Logs**: configurar retención adecuada (no indefinida).
- **Backups**: cifrar y tener política de borrado.

### 6.2 ISO 27001

El stack facilita el cumplimiento al proveer:

- Aislamiento de redes (A.13.1).
- Control de acceso (A.9).
- Cifrado en tránsito (A.10.1).
- Logs de auditoría (A.12.4).
- Backups (A.12.3).
- Gestión de incidentes (A.16) - ver `ADMIN_GUIDE.md` sección 13.

---

## 7. Vulnerabilidades conocidas y limitaciones

### 7.1 Limitaciones de seguridad actuales

1. **TLS con CA self-signed**: requiere importar CA en cada cliente. No apto para Internet público. Para acceso remoto, usar **Tailscale** VPN.
2. **Sin WAF**: Nginx no tiene Web Application Firewall. Considerar ModSecurity si se expone a Internet.
3. **Sin 2FA obligatorio**: Synapse soporta 2FA pero no se fuerza. Recomendable activar para admins.
4. **Sin cifrado de disco**: los volúmenes no están cifrados en reposo. Para entornos sensibles, usar LUKS en el host.
5. **Sin TLS entre Nginx y Synapse**: el tráfico interno va en HTTP plano. Asumiendo red Docker trusted.

### 7.2 Mejoras futuras de seguridad

- **Mutual TLS** entre Synapse y PostgreSQL.
- **Hashicorp Vault** o **Docker Secrets** para gestión avanzada de secretos.
- **NetworkPolicies** equivalentes (con Kubernetes) o reglas iptables más estrictas.
- **Audit logging** de Synapse (eventos admin).
- **Anomaly detection** con machine learning en logs.
- **Cifrado de backups** automático con `gpg` o `age`.

---

## 8. Procedimiento ante incidentes

Ver [`ADMIN_GUIDE.md` sección 13](../ADMIN_GUIDE.md) para procedimientos de emergencia.

Resumen del flujo:

1. **Detectar**: alertas via logs o reportes de usuarios.
2. **Contener**: detener servicios afectados.
3. **Erradicar**: parchear, rotar secretos, limpiar.
4. **Recuperar**: restaurar backup si es necesario.
5. **Documentar**: post-mortem con timeline, causa, acciones.
6. **Mejorar**: actualizar runbooks y controles.

---

## 9. Checklist de seguridad post-instalación

- [ ] `.env` tiene permisos 600.
- [ ] `synapse/signing.key` tiene permisos 600.
- [ ] `nginx/certs/*.key` tienen permisos 600.
- [ ] Firewall UFW activo (solo 80/443 desde LAN).
- [ ] SSH deshabilita root y password auth (Ubuntu).
- [ ] Fail2ban activo (Ubuntu).
- [ ] Backups automáticos configurados y verificados.
- [ ] Test de restauración realizado.
- [ ] CA importada en clientes principales.
- [ ] Política de contraseñas fuerte activa.
- [ ] 2FA activado en cuentas admin (vía Element).
- [ ] Logs sin secrets sensibles verificado.
- [ ] Monitoreo de espacio en disco configurado.
- [ ] Procedimiento de incidentes documentado.
