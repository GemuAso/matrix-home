-- =============================================================================
-- init.sql - Inicialización de PostgreSQL para Synapse
-- -----------------------------------------------------------------------------
-- Se ejecuta automáticamente en el primer arranque del contenedor PostgreSQL
-- (cuando el directorio de datos está vacío).
-- =============================================================================

-- Extensiones requeridas por Synapse
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;