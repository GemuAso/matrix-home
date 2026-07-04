# Config

Esta carpeta está reservada para archivos de configuración adicionales o compartidos que apliquen a múltiples servicios.

## Uso sugerido

- Configuraciones de monitoring (Prometheus, Grafana)
- Configuraciones de logging centralizado (Loki, Fluentd)
- Configuraciones de backup adicionales
- Plantillas de configuración

Actualmente no contiene archivos obligatorios. Las configuraciones de cada servicio están en sus respectivas carpetas:

- `synapse/` - Configuración de Matrix Synapse
- `postgres/` - Configuración de PostgreSQL
- `redis/` - Configuración de Redis
- `element/` - Configuración de Element Web
- `nginx/` - Configuración de Nginx reverse proxy
