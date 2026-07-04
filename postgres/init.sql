-- =============================================================================
-- init.sql - Inicialización de la base de datos PostgreSQL para Synapse
-- -----------------------------------------------------------------------------
-- Este script se ejecuta automáticamente en el primer arranque del contenedor
-- PostgreSQL (cuando el directorio de datos está vacío).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extensiones requeridas por Synapse
-- -----------------------------------------------------------------------------
-- citext: para comparación case-insensitive en usernames
-- pg_trgm: para búsqueda fuzzy en user directory
-- CREATE EXTENSION se ejecuta en la base de datos de Synapse

-- Asegurar codificación UTF8 y locale C (ya hecho via POSTGRES_INITDB_ARGS)
-- Verificar configuración
SELECT 'Inicializando base de datos para Matrix Synapse' AS mensaje;

-- -----------------------------------------------------------------------------
-- Crear extensiones en la base de datos de Synapse
-- (se ejecuta solo si la DB fue creada por POSTGRES_DB)
-- -----------------------------------------------------------------------------
\echo 'Creando extensiones en la base de datos synapse...'

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- -----------------------------------------------------------------------------
-- Configurar timezone por defecto
-- -----------------------------------------------------------------------------
SET TIME ZONE 'America/Bogota';

-- -----------------------------------------------------------------------------
-- Ajustes de parámetros iniciales (también están en postgresql.conf)
-- -----------------------------------------------------------------------------
ALTER DATABASE synapse SET timezone TO 'America/Bogota';
ALTER DATABASE synapse SET client_encoding TO 'UTF8';
ALTER DATABASE synapse SET default_text_search_config TO 'pg_catalog.english';

-- -----------------------------------------------------------------------------
-- Mensaje de finalización
-- -----------------------------------------------------------------------------
\echo 'Base de datos synapse inicializada correctamente.'
\echo 'Extensiones citext y pg_trgm creadas.'
