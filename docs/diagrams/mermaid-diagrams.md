# Diagramas Mermaid

> Diagramas lógicos, de flujo y arquitectura del stack Matrix Docker.

---

## 1. Arquitectura general

```mermaid
graph TB
    subgraph LAN["Red LAN (192.168.x.x)"]
        Client["Clientes<br/>Navegadores Element"]
    end

    subgraph Host["Host Docker<br/>(Windows o Ubuntu)"]
        subgraph Frontend["matrix_frontend (red Docker)"]
            Nginx["Nginx Reverse Proxy<br/>:80 :443"]
            Element["Element Web<br/>:80"]
            Synapse["Matrix Synapse<br/>:8008"]
        end

        subgraph Internal["matrix_internal (red Docker)"]
            Postgres["PostgreSQL 16<br/>:5432"]
            Redis["Redis 7<br/>:6379"]
        end
    end

    Client -->|"HTTPS 443"| Nginx
    Nginx -->|"proxy_pass"| Element
    Nginx -->|"proxy_pass"| Synapse
    Synapse -->|"SQL"| Postgres
    Synapse -->|"cache/pubsub"| Redis

    style Nginx fill:#f9f,stroke:#333,stroke-width:2px
    style Synapse fill:#bbf,stroke:#333,stroke-width:2px
    style Postgres fill:#bfb,stroke:#333,stroke-width:2px
    style Redis fill:#fbb,stroke:#333,stroke-width:2px
    style Element fill:#fcb,stroke:#333,stroke-width:2px
```

---

## 2. Topología de redes Docker

```mermaid
graph LR
    subgraph External["Internet / LAN"]
        LAN["Red LAN<br/>192.168.x.x"]
    end

    subgraph Docker["Docker Host"]
        subgraph Frontend["matrix_frontend<br/>(bridge)"]
            Nginx["Nginx<br/>:80 :443"]
            Element["Element<br/>:80"]
            Synapse1["Synapse<br/>:8008"]
        end

        subgraph Internal["matrix_internal<br/>(bridge)"]
            Postgres["PostgreSQL<br/>:5432"]
            Redis["Redis<br/>:6379"]
            Synapse2["Synapse<br/>(same container)"]
        end
    end

    LAN -->|":80 :443"| Nginx
    Nginx --> Frontend
    Synapse1 -.->|"same container"| Synapse2
    Synapse2 --> Internal

    style Frontend fill:#e1f5fe
    style Internal fill:#fff3e0
```

---

## 3. Flujo de una request HTTP

```mermaid
sequenceDiagram
    participant C as Cliente
    participant N as Nginx
    participant E as Element
    participant S as Synapse
    participant R as Redis
    participant P as PostgreSQL

    Note over C,P: Request a Element Web
    C->>N: GET https://element.home.arpa/
    N->>N: Termina TLS
    N->>N: server_name = element.home.arpa
    N->>E: proxy_pass http://element:80
    E-->>N: index.html + assets
    N-->>C: 200 OK (HTML, JS, CSS)

    Note over C,P: Cliente carga config.json
    C->>N: GET https://element.home.arpa/config.json
    N->>E: proxy_pass
    E-->>N: config.json
    N-->>C: 200 OK (JSON)

    Note over C,P: Cliente se autentica
    C->>N: POST https://matrix.home.arpa/_matrix/client/v3/login
    N->>N: server_name = matrix.home.arpa
    N->>S: proxy_pass http://synapse:8008
    S->>R: GET session cache
    R-->>S: MISS
    S->>P: SELECT user WHERE name=@user
    P-->>S: user row
    S->>S: Verify bcrypt+pepper
    S->>P: INSERT access_token
    S->>R: SET session cache
    S-->>N: 200 {access_token}
    N-->>C: 200 OK (JSON)
```

---

## 4. Flujo de mensaje enviado

```mermaid
sequenceDiagram
    participant S1 as Sender
    participant N as Nginx
    participant Sy as Synapse
    participant R as Redis
    participant P as PostgreSQL
    participant S2 as Receiver

    S1->>N: PUT /_matrix/client/v3/rooms/!room/send/...
    N->>Sy: proxy_pass

    Note over Sy: 1. Verify access_token
    Sy->>R: GET token cache
    R-->>Sy: HIT (valid)

    Note over Sy: 2. Verify membership
    Sy->>P: SELECT membership
    P-->>Sy: join

    Note over Sy: 3. Assign event_id
    Note over Sy: 4. Sign event with signing.key

    Note over Sy: 5. Persist
    Sy->>P: INSERT events
    P-->>Sy: OK

    Note over Sy: 6. Notify via pubsub
    Sy->>R: PUBLISH room:!room

    Note over S2: Receiver has open /sync
    S2->>N: GET /_matrix/client/v3/sync
    N->>Sy: proxy_pass (long-polling)
    Sy->>R: SUBSCRIBE room:!room
    R-->>Sy: message event
    Sy-->>N: 200 (sync response with new event)
    N-->>S2: 200 OK (JSON)

    Sy-->>N: 200 {event_id}
    N-->>S1: 200 OK (JSON)
```

---

## 5. Diagrama de dependencias de servicios

```mermaid
graph TB
    Postgres["PostgreSQL<br/>(sin dependencias)"]
    Redis["Redis<br/>(sin dependencias)"]
    Element["Element Web<br/>(sin dependencias)"]

    Postgres -->|"healthy"| Synapse
    Redis -->|"healthy"| Synapse

    Synapse -->|"healthy"| Nginx
    Element -->|"healthy"| Nginx

    style Postgres fill:#bfb
    style Redis fill:#fbb
    style Synapse fill:#bbf
    style Element fill:#fcb
    style Nginx fill:#f9f
```

**Orden de arranque**: PostgreSQL → Redis → Synapse → Element → Nginx

---

## 6. Flujo de backup

```mermaid
flowchart TD
    Start([Inicio backup]) --> CheckStack{Stack OK?}
    CheckStack -->|No| Fail[/Backup fallido/]
    CheckStack -->|Sí| CheckPG{PostgreSQL healthy?}

    CheckPG -->|No| Fail
    CheckPG -->|Sí| Dump[pg_dump --format=custom]

    Dump --> Tar[tar.gz de configs]
    Tar --> VerifySize{Tamaño > 100 bytes?}

    VerifySize -->|No| Fail
    VerifySize -->|Sí| Rotate[Rotar backups antiguos]

    Rotate --> Done([Backup completo])

    style Start fill:#9f9
    style Done fill:#9f9
    style Fail fill:#f99
```

---

## 7. Flujo de restauración

```mermaid
flowchart TD
    Start([Inicio restore]) --> CheckFile{Archivo existe?}
    CheckFile -->|No| Fail[/Fail/]
    CheckFile -->|Sí| CheckPG{PostgreSQL healthy?}

    CheckPG -->|No| Fail
    CheckPG -->|Sí| PreventBackup[Backup preventivo]

    PreventBackup --> Confirm{Confirmación SI RESTAURAR?}
    Confirm -->|No| Cancel[/Cancelado/]
    Confirm -->|Sí| Restore[pg_restore --clean]

    Restore --> Verify{Tablas cargadas?}
    Verify -->|No| Fail
    Verify -->|Sí| RestartSynapse[Reiniciar Synapse]

    RestartSynapse --> Done([Restore completo])

    style Start fill:#9f9
    style Done fill:#9f9
    style Fail fill:#f99
    style Cancel fill:#ff9
```

---

## 8. Flujo de migración Windows → Ubuntu

```mermaid
flowchart TD
    subgraph Windows["Windows (origen)"]
        WStop[Detener stack]
        WBackup[Backup final]
        WExport[Exportar volúmenes]
        WTransfer[Transferir tarball]
    end

    subgraph Transfer["Transferencia"]
        SCP[scp / rsync / USB]
    end

    subgraph Ubuntu["Ubuntu (destino)"]
        UPrepare[Preparar servidor]
        UInstallDocker[Instalar Docker]
        UFirewall[Configurar firewall]
        UImport[Importar volúmenes]
        UAdjust[Ajustar .env y dominios]
        UStart[Iniciar stack]
        UVerify[Verificar]
        USystemd[Configurar systemd]
    end

    WStop --> WBackup --> WExport --> WTransfer
    WTransfer --> SCP
    SCP --> UImport

    UPrepare --> UInstallDocker --> UFirewall --> UImport
    UImport --> UAdjust --> UStart --> UVerify --> USystemd

    style Windows fill:#e3f2fd
    style Ubuntu fill:#fff3e0
    style Transfer fill:#f3e5f5
```

---

## 9. Modelo de datos principal

```mermaid
erDiagram
    users ||--o{ access_tokens : has
    users ||--o{ devices : owns
    users ||--o{ room_memberships : has
    rooms ||--o{ room_memberships : contains
    rooms ||--o{ events : has
    events ||--o{ event_edges : references
    rooms ||--o{ state_events : has
    users ||--o{ local_media_repository : uploads
    users ||--o{ user_ips : connects_from

    users {
        text name PK "user_id @user:server"
        text password_hash "bcrypt+pepper"
        bigint creation_ts
        smallint admin "0/1"
        smallint deactivated "0/1"
    }

    access_tokens {
        bigint id PK
        text user_id FK
        text token "macaroon"
        bigint last_used
    }

    rooms {
        text room_id PK
        text creator
        bigint creation_ts
    }

    events {
        text event_id PK
        text room_id FK
        text type
        text sender
        bigint origin_server_ts
        bytea content
    }
```

---

## 10. Diagrama de estados de servicios

```mermaid
stateDiagram-v2
    [*] --> Created: docker compose up
    Created --> Running: start
    Running --> Healthy: healthcheck OK
    Running --> Unhealthy: healthcheck fail
    Healthy --> Unhealthy: healthcheck fail
    Unhealthy --> Healthy: healthcheck OK
    Running --> Stopped: docker compose stop
    Healthy --> Stopped: docker compose stop
    Unhealthy --> Stopped: docker compose stop
    Stopped --> Running: docker compose start
    Stopped --> [*]: docker compose down

    note right of Healthy
        Todos los servicios
        deben estar healthy
        para operation OK
    end note

    note right of Unhealthy
        Investigar logs
        de inmediato
    end note
```

---

## 11. Flujo de actualización

```mermaid
flowchart TD
    Start([Inicio update]) --> Backup[Backup previo]
    Backup --> ReadNotes[Leer changelog]
    ReadNotes --> Announce[Anunciar mantenimiento]
    Announce --> Pull[update-images.sh]
    Pull --> Apply[update-containers.sh]
    Apply --> Wait[Esperar healthchecks]
    Wait --> Verify{Healthy?}
    Verify -->|No| Rollback[Rollback]
    Verify -->|Sí| Monitor[Monitorear 24h]
    Monitor --> Done([Update completo])

    Rollback --> Done2([Revertido])

    style Start fill:#9f9
    style Done fill:#9f9
    style Done2 fill:#ff9
    style Rollback fill:#f99
```

---

## 12. Matriz de puertos y accesos

```mermaid
graph TB
    subgraph LAN["Red LAN"]
        Client["Clientes LAN<br/>192.168.x.x"]
    end

    subgraph Host["Host Docker"]
        subgraph Ports["Puertos publicados"]
            P80["80 TCP"]
            P443["443 TCP"]
        end

        subgraph Internal["Servicios internos"]
            P5432["PostgreSQL :5432"]
            P6379["Redis :6379"]
            P8008["Synapse :8008"]
            P80e["Element :80"]
        end
    end

    Client -->|"HTTP"| P80
    Client -->|"HTTPS"| P443

    P80 --> Nginx
    P443 --> Nginx

    Nginx --> P80e
    Nginx --> P8008

    P8008 --> P5432
    P8008 --> P6379

    P5432 -.->|"NO accesible<br/>desde LAN"| Client
    P6379 -.->|"NO accesible<br/>desde LAN"| Client
    P8008 -.->|"NO accesible<br/>desde LAN"| Client
    P80e -.->|"NO accesible<br/>desde LAN"| Client

    style P80 fill:#9f9
    style P443 fill:#9f9
    style P5432 fill:#f99
    style P6379 fill:#f99
    style P8008 fill:#f99
    style P80e fill:#f99
```

---

## 13. Estrategia de backup

```mermaid
graph LR
    subgraph Daily["Diario (cron 02:00)"]
        BD[Backup BD]
        Cfg[Backup configs]
    end

    subgraph Weekly["Semanal"]
        Manual[Backup manual verificación]
        Clean[Limpieza imágenes]
    end

    subgraph Monthly["Mensual"]
        Test[Test de restauración]
        Vacuum[VACUUM ANALYZE]
    end

    subgraph Retention["Retención"]
        Local["Local<br/>7-30 días"]
        NAS["NAS<br/>30-90 días"]
        Offsite["Offsite cifrado<br/>90+ días"]
    end

    BD --> Local
    Cfg --> Local
    BD --> NAS
    Cfg --> NAS
    NAS --> Offsite

    style Daily fill:#e1f5fe
    style Weekly fill:#fff3e0
    style Monthly fill:#fce4ec
    style Retention fill:#f3e5f5
```

---

## 14. Procedimiento de emergencia

```mermaid
flowchart TD
    Detect([Detección incidente]) --> Assess{Evaluación}
    Assess -->|Servicio caído| Restart[Reiniciar servicio]
    Assess -->|Datos corruptos| Restore[Restaurar backup]
    Assess -->|Compromiso seguridad| Rotate[Rotar secretos]

    Restart --> Verify1{Recuperado?}
    Verify1 -->|Sí| Done([Resuelto])
    Verify1 -->|No| FullRestart[Reiniciar stack completo]

    FullRestart --> Verify2{Recuperado?}
    Verify2 -->|Sí| Done
    Verify2 -->|No| DR[Disaster Recovery]

    Restore --> Verify3{Datos OK?}
    Verify3 -->|Sí| Done
    Verify3 -->|No| DR

    Rotate --> Invalidate[Invalidar sesiones]
    Invalidate --> Audit[Auditar logs]
    Audit --> Done

    DR --> NewHost[Aprovisionar nuevo host]
    NewHost --> RestoreAll[Restaurar todo]
    RestoreAll --> Done

    style Detect fill:#f99
    style Done fill:#9f9
    style DR fill:#fbb
```

---

## 15. Ciclo de vida de un mensaje

```mermaid
sequenceDiagram
    participant U as Usuario
    participant E as Element
    participant N as Nginx
    participant S as Synapse
    participant R as Redis
    participant P as PostgreSQL

    Note over U,P: 1. Usuario escribe mensaje
    U->>E: Escribe "Hola"
    E->>N: PUT /_matrix/client/v3/rooms/!room/send/m.room.message/...

    Note over N,S: 2. Nginx enruta a Synapse
    N->>S: proxy_pass

    Note over S,P: 3. Synapse procesa
    S->>S: Verify token (Redis cache)
    S->>P: Verify membership
    S->>S: Assign event_id
    S->>S: Sign with signing.key
    S->>P: INSERT events table

    Note over S,R: 4. Synapse notifica
    S->>R: PUBLISH event

    Note over S,E: 5. Otros dispositivos reciben
    S->>R: SUBSCRIBE (via /sync long-poll)
    R-->>S: new event
    S-->>N: 200 sync response
    N-->>E: 200 OK (JSON)

    Note over U,E: 6. Element muestra mensaje
    E->>U: Render "Hola"

    Note over S,P: 7. Synapse confirma al sender
    S-->>N: 200 {event_id}
    N-->>E: 200 OK
    E->>U: Tick verde (enviado)
```

---

## 16. Diagrama de seguridad multicapa

```mermaid
graph TB
    subgraph Layer1["Capa 1: Perímetro"]
        FW["Firewall UFW<br/>Solo 80/443 desde LAN"]
    end

    subgraph Layer2["Capa 2: Transporte"]
        TLS["TLS 1.2/1.3<br/>Ciphersuites modernas"]
        HSTS["HSTS header"]
    end

    subgraph Layer3["Capa 3: Reverse Proxy"]
        Nginx["Nginx<br/>server_tokens off"]
        Rate["Rate limiting"]
        Headers["Security headers<br/>CSP, X-Frame-Options, etc."]
    end

    subgraph Layer4["Capa 4: Aplicación"]
        Synapse["Synapse"]
        AuthPolicy["Política contraseñas fuerte"]
        RegOff["Registro deshabilitado"]
        FedOff["Federación deshabilitada"]
    end

    subgraph Layer5["Capa 5: Datos"]
        PG["PostgreSQL<br/>scram-sha-256"]
        HBA["pg_hba restrictivo"]
        Redis["Redis con password"]
        Cmds["Comandos peligrosos off"]
    end

    subgraph Layer6["Capa 6: Contenedor"]
        NoPriv["no-new-privileges"]
        ReadOnly["read_only cuando posible"]
        UserNonRoot["usuarios no-root"]
    end

    FW --> TLS --> Nginx --> Synapse --> PG
    TLS --> HSTS
    Nginx --> Rate
    Nginx --> Headers
    Synapse --> AuthPolicy
    Synapse --> RegOff
    Synapse --> FedOff
    PG --> HBA
    Redis --> Cmds

    style Layer1 fill:#ffebee
    style Layer2 fill:#fff3e0
    style Layer3 fill:#fff9c4
    style Layer4 fill:#c8e6c9
    style Layer5 fill:#b2dfdb
    style Layer6 fill:#bbdefb
```

---

## 17. Flujo de certificados SSL

```mermaid
flowchart TD
    Start([Setup inicial]) --> GenCA[Generar CA local]
    GenCA --> GenCert1[Generar cert matrix.home.arpa]
    GenCert1 --> GenCert2[Generar cert element.home.arpa]
    GenCert2 --> GenDefault[Generar cert default]
    GenDefault --> Perms[Permisos 600 keys, 644 certs]
    Perms --> Mount[Mount en Nginx]
    Mount --> Reload[Nginx reload]

    subgraph Clientes["En cada cliente"]
        CopyCA[Copiar ca.crt]
        ImportTrust[Importar en trust store]
    end

    Reload -.->|Manual| CopyCA
    CopyCA --> ImportTrust

    subgraph Renewal["Renovación anual"]
        Expire[Cert próximo a expirar]
        Regen[Regenerar certs]
        Reimport[Re-importar CA si cambió]
    end

    ImportTrust -.->|1 año| Expire
    Expire --> Regen --> Reimport

    style Start fill:#9f9
    style Reload fill:#9f9
    style ImportTrust fill:#ff9
```

---

## 18. Diagrama de volúmenes Docker

```mermaid
graph TB
    subgraph Volumes["Volúmenes con nombre"]
        V1["matrix_synapse_data<br/>/data"]
        V2["matrix_postgres_data<br/>/var/lib/postgresql/data"]
        V3["matrix_redis_data<br/>/data"]
        V4["matrix_element_cache<br/>/var/cache/nginx"]
        V5["matrix_nginx_logs<br/>/var/log/nginx"]
    end

    subgraph BindMounts["Bind mounts (configs)"]
        B1["synapse/homeserver.yaml"]
        B2["synapse/log.config"]
        B3["synapse/signing.key"]
        B4["postgres/postgresql.conf"]
        B5["postgres/pg_hba.conf"]
        B6["postgres/init.sql"]
        B7["redis/redis.conf"]
        B8["nginx/nginx.conf"]
        B9["nginx/conf.d/"]
        B10["nginx/certs/"]
        B11["nginx/snippets/"]
        B12["element/config.json"]
    end

    V1 -->|usa| Synapse["Synapse container"]
    V2 -->|usa| Postgres["PostgreSQL container"]
    V3 -->|usa| Redis["Redis container"]
    V4 -->|usa| Element["Element container"]
    V5 -->|usa| Nginx["Nginx container"]

    B1 -.->|mount ro| Synapse
    B2 -.->|mount ro| Synapse
    B3 -.->|mount ro| Synapse
    B4 -.->|mount ro| Postgres
    B5 -.->|mount ro| Postgres
    B6 -.->|mount ro| Postgres
    B7 -.->|mount ro| Redis
    B8 -.->|mount ro| Nginx
    B9 -.->|mount ro| Nginx
    B10 -.->|mount ro| Nginx
    B11 -.->|mount ro| Nginx
    B12 -.->|build| Element

    style Volumes fill:#e1f5fe
    style BindMounts fill:#fff3e0
```

---

## 19. Escalabilidad futura

```mermaid
graph TB
    subgraph Current["v2.0.0 - Single Node (LAN + Tailscale)"]
        Nginx1["Nginx"]
        Synapse1["Synapse (single)"]
        PG1["PostgreSQL (single)"]
        Redis1["Redis (single)"]
    end

    subgraph Future["v3.0.0 - Scaled (futuro)"]
        LB["Load Balancer<br/>HAProxy"]
        Nginx2["Nginx x2"]
        SynapseW["Synapse Workers<br/>- synchrotron<br/>- federation_sender<br/>- media_repository"]
        PGM["PostgreSQL Master"]
        PGS["PostgreSQL Replicas"]
        RedisCluster["Redis Cluster<br/>3 nodes"]
        Shared["Shared Storage<br/>NFS/S3"]
    end

    Nginx1 --> Synapse1 --> PG1
    Synapse1 --> Redis1

    LB --> Nginx2
    Nginx2 --> SynapseW
    SynapseW --> PGM
    PGM --> PGS
    SynapseW --> RedisCluster
    SynapseW --> Shared

    style Current fill:#c8e6c9
    style Future fill:#ffebee
```

---

## 20. Matriz de responsabilidades del administrador

```mermaid
graph TB
    Admin[Administrador Matrix]

    Admin --> Daily[Tareas Diarias]
    Admin --> Weekly[Tareas Semanales]
    Admin --> Monthly[Tareas Mensuales]
    Admin --> Quarterly[Tareas Trimestrales]

    Daily --> D1[Verificar estado]
    Daily --> D2[Revisar logs]
    Daily --> D3[Confirmar backup]

    Weekly --> W1[Backup manual]
    Weekly --> W2[Limpiar imágenes]
    Weekly --> W3[Auditar accesos]

    Monthly --> M1[Actualizar imágenes]
    Monthly --> M2[VACUUM ANALYZE]
    Monthly --> M3[Test de restore]
    Monthly --> M4[Revisar usuarios]

    Quarterly --> Q1[Drill de DR]
    Quarterly --> Q2[Rotar signing key]
    Quarterly --> Q3[Auditoría seguridad]
    Quarterly --> Q4[Review métricas]

    style Admin fill:#bbdefb
    style Daily fill:#c8e6c9
    style Weekly fill:#fff9c4
    style Monthly fill:#ffe0b2
    style Quarterly fill:#ffccbc
```
