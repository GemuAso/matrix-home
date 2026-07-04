# Backups

Esta carpeta contiene los respaldos generados por los scripts:

- `scripts/linux/backup-db.sh` (Linux)
- `scripts/windows/backup-db.ps1` (Windows)

## Tipos de archivos

| Patrón | Descripción |
|--------|-------------|
| `db_YYYYMMDD_HHMMSS.sql.gz` | Respaldo de la base de datos PostgreSQL (formato custom de pg_dump, comprimido) |
| `db_<nombre>_YYYYMMDD_HHMMSS.sql.gz` | Respaldo nombrado (cuando se pasa un nombre al script) |
| `config_YYYYMMDD_HHMMSS.tar.gz` | Respaldo de archivos de configuración |
| `media_YYYYMMDD_HHMMSS.tar.gz` | Respaldo del repositorio de media de Synapse |
| `pre_restore_YYYYMMDD_HHMMSS.sql.gz` | Backup automático previo a una restauración |

## Rotación

Los scripts eliminan automáticamente los backups con más de `BACKUP_RETENTION_DAYS` días (por defecto: 7). Ajusta este valor en `.env` si necesitas más o menos retención.

## Restauración

Ver `/docs/10-restauracion.md` para instrucciones detalladas.

## Importante

- Esta carpeta NO debe commitearse a Git (ver `.gitignore`).
- Los backups contienen datos sensibles: protégelos con permisos de archivo adecuados.
- Considera cifrar los backups si se almacenan fuera del servidor (ver recomendaciones en `/docs/09-backups.md`).
