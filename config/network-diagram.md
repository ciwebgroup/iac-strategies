# WordPress Farm Network Architecture Diagram

## High-Level Infrastructure Topology

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        Users[Users Worldwide]
    end
    
    subgraph Cloudflare["☁️ Cloudflare"]
        CF_DNS[DNS]
        CF_CDN[CDN Layer<br/>- Static Assets<br/>- Page Cache<br/>- DDoS Protection]
        CF_LB[Load Balancer<br/>Health Checks]
    end
    
    subgraph DO["Digital Ocean Infrastructure"]
        subgraph Edge["Edge Layer"]
            FIP[Floating IP<br/>High Availability]
            
            subgraph Traefik_Cluster["Traefik Cluster (3+ replicas)"]
                T1[Traefik Node 1<br/>+ CrowdSec + Varnish]
                T2[Traefik Node 2<br/>+ CrowdSec + Varnish]
                T3[Traefik Node 3<br/>+ CrowdSec + Varnish]
            end
        end
        
        subgraph Swarm["Docker Swarm Cluster"]
            subgraph Managers["Manager Nodes (3)"]
                M1[Manager 1<br/>16GB/8 vCPU]
                M2[Manager 2<br/>16GB/8 vCPU]
                M3[Manager 3<br/>16GB/8 vCPU]
            end
            
            subgraph Workers["Worker Nodes (20)"]
                W1[Worker 1-20<br/>~25 sites each]
                W2[WordPress Containers<br/>Nginx + PHP-FPM + Redis]
            end
            
            subgraph Database["Database Cluster"]
                DB1[MariaDB Galera 1<br/>16GB/8 vCPU]
                DB2[MariaDB Galera 2<br/>16GB/8 vCPU]
                DB3[MariaDB Galera 3<br/>16GB/8 vCPU]
                Proxy[ProxySQL<br/>Query Router]
            end
            
            subgraph Storage["Storage Layer"]
                GFS1[GlusterFS 1<br/>+ Block Storage]
                GFS2[GlusterFS 2<br/>+ Block Storage]
            end
            
            subgraph Caching["Central Cache (Optional)"]
                Redis_Cluster[Redis Cluster<br/>3 masters + 3 replicas]
            end
            
            subgraph Monitoring["Observability Stack"]
                Prometheus[Prometheus<br/>+ Mimir]
                Loki[Loki<br/>Log Aggregation]
                Tempo[Tempo<br/>Distributed Tracing]
                Grafana[Grafana<br/>Visualization]
            end
            
            subgraph Management["Management Layer"]
                Portainer[Portainer<br/>Container Management]
                Backup[Backup Services<br/>Restic + Percona]
            end
        end
        
        subgraph External_Storage["External Storage"]
            Spaces[DO Spaces<br/>S3-Compatible<br/>Encrypted Backups]
        end
    end
    
    Users --> CF_DNS
    CF_DNS --> CF_CDN
    CF_CDN --> CF_LB
    CF_LB --> FIP
    
    FIP --> T1
    FIP --> T2
    FIP --> T3
    
    T1 --> W1
    T2 --> W1
    T3 --> W1
    
    W1 --> W2
    W2 --> Proxy
    W2 --> Redis_Cluster
    W2 --> GFS1
    W2 --> GFS2
    
    Proxy --> DB1
    Proxy --> DB2
    Proxy --> DB3
    
    DB1 <-.->|Replication| DB2
    DB2 <-.->|Replication| DB3
    DB3 <-.->|Replication| DB1
    
    GFS1 <-.->|Sync| GFS2
    
    M1 <-.->|Raft| M2
    M2 <-.->|Raft| M3
    M3 <-.->|Raft| M1
    
    W1 --> Prometheus
    W2 --> Loki
    W2 --> Tempo
    
    Prometheus --> Grafana
    Loki --> Grafana
    Tempo --> Grafana
    
    Backup --> Spaces
    DB1 --> Backup
    GFS1 --> Backup
    
    Portainer -.->|Manage| W1
    Portainer -.->|Manage| M1

    style Users fill:#e1f5ff
    style CF_CDN fill:#f9a825
    style Traefik_Cluster fill:#00d4ff
    style Workers fill:#4caf50
    style Database fill:#ff6b6b
    style Storage fill:#9c27b0
    style Monitoring fill:#ff9800
    style Management fill:#2196f3
    style Spaces fill:#607d8b
```

## Detailed Network Flow

```mermaid
sequenceDiagram
    participant User
    participant Cloudflare
    participant Traefik
    participant Varnish
    participant Nginx
    participant PHP
    participant Redis
    participant Database
    
    User->>Cloudflare: HTTPS Request
    Cloudflare->>Cloudflare: CDN Cache Check
    
    alt Cache Hit (Static)
        Cloudflare-->>User: Cached Response
    else Cache Miss
        Cloudflare->>Traefik: Forward Request
        Traefik->>Traefik: Route & Security Check
        Traefik->>Varnish: HTTP Cache Layer
        
        alt Varnish Cache Hit
            Varnish-->>Traefik: Cached Page
            Traefik-->>Cloudflare: Response
            Cloudflare-->>User: Response + Cache
        else Varnish Miss
            Varnish->>Nginx: Forward to WordPress
            Nginx->>PHP: FastCGI Request
            PHP->>Redis: Object Cache Check
            
            alt Redis Hit
                Redis-->>PHP: Cached Data
            else Redis Miss
                PHP->>Database: Query via ProxySQL
                Database-->>PHP: Data
                PHP->>Redis: Store in Cache
            end
            
            PHP-->>Nginx: Rendered HTML
            Nginx-->>Varnish: Response + Cache
            Varnish->>Traefik: Response
            Traefik-->>Cloudflare: Response
            Cloudflare-->>User: Response
        end
    end
```

## Docker Swarm Network Architecture

```mermaid
graph LR
    subgraph External["External Network"]
        Internet[Internet Traffic]
    end
    
    subgraph Traefik_Net["traefik-public Network"]
        T[Traefik Routers]
        N1[Nginx Site 1]
        N2[Nginx Site 2]
        N500[Nginx Site 500]
    end
    
    subgraph Site1["wp-site-1 Network"]
        N1_int[Nginx]
        PHP1[PHP-FPM]
        R1[Redis]
    end
    
    subgraph Site2["wp-site-2 Network"]
        N2_int[Nginx]
        PHP2[PHP-FPM]
        R2[Redis]
    end
    
    subgraph Site500["wp-site-500 Network"]
        N500_int[Nginx]
        PHP500[PHP-FPM]
        R500[Redis]
    end
    
    subgraph Shared["shared-services Network"]
        ProxySQL[ProxySQL]
        Central_Redis[Central Redis<br/>Optional]
    end
    
    subgraph DB_Net["database Network"]
        DB_Cluster[Galera Cluster<br/>3 nodes]
    end
    
    subgraph Monitor_Net["monitoring Network"]
        Prom[Prometheus]
        L[Loki]
        G[Grafana]
        Exporters[node-exporter<br/>cAdvisor]
    end
    
    Internet --> T
    T --> N1
    T --> N2
    T --> N500
    
    N1 -.-> N1_int
    N1_int --> PHP1
    PHP1 --> R1
    
    N2 -.-> N2_int
    N2_int --> PHP2
    PHP2 --> R2
    
    N500 -.-> N500_int
    N500_int --> PHP500
    PHP500 --> R500
    
    PHP1 --> ProxySQL
    PHP2 --> ProxySQL
    PHP500 --> ProxySQL
    
    ProxySQL --> DB_Cluster
    
    PHP1 --> Central_Redis
    PHP2 --> Central_Redis
    
    Exporters --> Prom
    PHP1 --> L
    PHP2 --> L
    Prom --> G
    L --> G

    style Traefik_Net fill:#00d4ff
    style Site1 fill:#4caf50
    style Site2 fill:#4caf50
    style Site500 fill:#4caf50
    style Shared fill:#ff9800
    style DB_Net fill:#ff6b6b
    style Monitor_Net fill:#9c27b0
```

## Security Layer Architecture

```mermaid
graph TB
    subgraph Internet["🌐 Internet Threats"]
        Attackers[Malicious Traffic<br/>DDoS, Bots, Scanners]
        Legitimate[Legitimate Users]
    end
    
    subgraph Layer1["Security Layer 1: Cloudflare"]
        CF_DDoS[DDoS Protection<br/>Automatic Mitigation]
        CF_WAF[Web Application Firewall<br/>OWASP Rules]
        CF_BotMgmt[Bot Management<br/>Challenge/Block]
        CF_RateLimit[Rate Limiting<br/>Per IP/Endpoint]
    end
    
    subgraph Layer2["Security Layer 2: Digital Ocean"]
        DO_FW[DO Firewall<br/>Port Restrictions<br/>IP Allowlists]
        DO_VPC[VPC Isolation<br/>Private Networking]
    end
    
    subgraph Layer3["Security Layer 3: CrowdSec"]
        CS_Agent[CrowdSec Agents<br/>on Traefik Nodes]
        CS_Bouncer[Traefik Bouncer<br/>IP Ban/Allow]
        CS_API[Local Security API<br/>Threat Intelligence]
        CS_Community[Community Blocklists<br/>Shared Intelligence]
    end
    
    subgraph Layer4["Security Layer 4: Traefik"]
        T_Middleware[Security Middleware<br/>- Headers<br/>- HSTS<br/>- CSP]
        T_RateLimit[Rate Limiting<br/>Per Service]
        T_CircuitBreaker[Circuit Breakers<br/>Prevent Cascade]
        T_Auth[Authentication<br/>BasicAuth/OAuth]
    end
    
    subgraph Layer5["Security Layer 5: Application"]
        WP_Hardening[WordPress Hardening<br/>- Disable XML-RPC<br/>- Limit Login<br/>- File Permissions]
        Network_Isolation[Network Isolation<br/>Per-Site Networks]
        Secrets[Secrets Management<br/>Docker Swarm Secrets]
    end
    
    subgraph Layer6["Security Layer 6: Infrastructure"]
        Encrypted_Overlay[Encrypted Networks<br/>--opt encrypted]
        Firewall_Rules[Host Firewalls<br/>iptables/nftables]
        SSH_Hardening[SSH Hardening<br/>Key-only, No Root]
    end
    
    Attackers --> CF_DDoS
    Legitimate --> CF_DDoS
    
    CF_DDoS --> CF_WAF
    CF_WAF --> CF_BotMgmt
    CF_BotMgmt --> CF_RateLimit
    
    CF_RateLimit --> DO_FW
    DO_FW --> DO_VPC
    
    DO_VPC --> CS_Agent
    CS_Agent <--> CS_API
    CS_API <--> CS_Community
    CS_Agent --> CS_Bouncer
    
    CS_Bouncer --> T_Middleware
    T_Middleware --> T_RateLimit
    T_RateLimit --> T_CircuitBreaker
    T_CircuitBreaker --> T_Auth
    
    T_Auth --> WP_Hardening
    WP_Hardening --> Network_Isolation
    Network_Isolation --> Secrets
    
    Secrets --> Encrypted_Overlay
    Encrypted_Overlay --> Firewall_Rules
    Firewall_Rules --> SSH_Hardening
    
    SSH_Hardening --> Applications[Protected Applications]

    style Layer1 fill:#f9a825
    style Layer2 fill:#00d4ff
    style Layer3 fill:#4caf50
    style Layer4 fill:#2196f3
    style Layer5 fill:#9c27b0
    style Layer6 fill:#ff6b6b
    style Applications fill:#4caf50
```

## Observability Data Flow

```mermaid
graph LR
    subgraph Sources["Data Sources"]
        WP_Containers[WordPress<br/>Containers]
        Traefik_Logs[Traefik<br/>Access Logs]
        DB_Metrics[Database<br/>Metrics]
        Node_Stats[Node<br/>Statistics]
        App_Traces[Application<br/>Traces]
    end
    
    subgraph Collection["Collection Layer"]
        node_exporter[node-exporter<br/>System Metrics]
        cAdvisor[cAdvisor<br/>Container Metrics]
        Promtail[Promtail<br/>Log Shipping]
        OTel_Collector[OTel Collector<br/>Trace Collection]
    end
    
    subgraph Storage["Storage Layer"]
        Prometheus[Prometheus<br/>Short-term Metrics]
        Mimir[Mimir<br/>Long-term Metrics]
        Loki[Loki<br/>Log Storage]
        Tempo[Tempo<br/>Trace Storage]
    end
    
    subgraph Analysis["Analysis & Visualization"]
        Grafana[Grafana<br/>Unified Dashboard]
        AlertManager[AlertManager<br/>Alerting]
    end
    
    subgraph Notifications["Notification Channels"]
        Email[Email]
        Slack[Slack/Discord]
        PagerDuty[PagerDuty]
    end
    
    Node_Stats --> node_exporter
    WP_Containers --> cAdvisor
    WP_Containers --> Promtail
    Traefik_Logs --> Promtail
    DB_Metrics --> node_exporter
    App_Traces --> OTel_Collector
    
    node_exporter --> Prometheus
    cAdvisor --> Prometheus
    Promtail --> Loki
    OTel_Collector --> Tempo
    
    Prometheus --> Mimir
    Prometheus --> Grafana
    Mimir --> Grafana
    Loki --> Grafana
    Tempo --> Grafana
    
    Grafana --> AlertManager
    
    AlertManager --> Email
    AlertManager --> Slack
    AlertManager --> PagerDuty

    style Sources fill:#e3f2fd
    style Collection fill:#f3e5f5
    style Storage fill:#fff3e0
    style Analysis fill:#e8f5e9
    style Notifications fill:#ffebee
```

## Caching Architecture

```mermaid
graph TD
    User[User Request]
    
    subgraph Tier1["Tier 1: CDN - Cloudflare Edge"]
        CF_Edge[Edge Cache<br/>Static Assets<br/>TTL: 1 hour - 1 week]
    end
    
    subgraph Tier2["Tier 2: HTTP Cache - Varnish"]
        Varnish[Varnish Cache<br/>Full Page Cache<br/>TTL: 1 hour<br/>Logged-out users only]
    end
    
    subgraph Tier3["Tier 3: Application - WordPress"]
        subgraph Tier3a["Tier 3a: Object Cache - Redis"]
            Redis[Redis Object Cache<br/>DB Query Results<br/>Transients<br/>Sessions<br/>TTL: 12 hours]
        end
        
        subgraph Tier3b["Tier 3b: OPcache"]
            OPcache[PHP OPcache<br/>Bytecode Cache<br/>TTL: 60s revalidate]
        end
        
        WP_Core[WordPress Core]
        DB[Database]
    end
    
    User -->|Request| CF_Edge
    
    CF_Edge -->|Cache Miss| Varnish
    CF_Edge -.->|Cache Hit| User
    
    Varnish -->|Cache Miss| WP_Core
    Varnish -.->|Cache Hit| CF_Edge
    
    WP_Core -->|Query| Redis
    Redis -.->|Cache Hit| WP_Core
    Redis -->|Cache Miss| DB
    
    WP_Core --> OPcache
    OPcache -.->|Bytecode| WP_Core
    
    DB -.->|Data| Redis
    Redis -.->|Cached Data| WP_Core
    WP_Core -.->|HTML| Varnish
    Varnish -.->|Cached Page| CF_Edge
    CF_Edge -.->|Final Response| User

    style CF_Edge fill:#f9a825
    style Varnish fill:#00d4ff
    style Redis fill:#ff6b6b
    style OPcache fill:#4caf50
    style DB fill:#9c27b0
```

## Disaster Recovery Flow

```mermaid
graph TB
    subgraph Production["Production Environment"]
        Live_Sites[500 Live Sites]
        Live_DB[Live Databases]
        Live_Files[Uploaded Files]
    end
    
    subgraph Backup_Schedule["Automated Backup Schedule"]
        Daily_DB[Daily DB Backups<br/>2:00 AM]
        Incremental_DB[Incremental DB<br/>Every 6 hours]
        Daily_Files[Daily File Backups<br/>3:00 AM]
        Config_Backup[Config Backups<br/>On Change]
    end
    
    subgraph Backup_Storage["Backup Storage"]
        DO_Spaces[Digital Ocean Spaces<br/>S3-Compatible]
        Encrypted[GPG Encrypted]
        Replicated[Cross-Region<br/>Replication]
    end
    
    subgraph DR_Scenarios["Disaster Recovery Scenarios"]
        Single_Site[Single Site Failure]
        Node_Failure[Node Failure]
        Region_Outage[Region Outage]
        Data_Corruption[Data Corruption]
    end
    
    subgraph Recovery_Process["Recovery Process"]
        Detect[Detect Failure<br/>Monitoring Alerts]
        Assess[Assess Impact<br/>RTO: 1 hour<br/>RPO: 6 hours]
        Restore_DB[Restore Database]
        Restore_Files[Restore Files]
        Verify[Verify & Test]
        Resume[Resume Operations]
    end
    
    Live_Sites --> Daily_DB
    Live_DB --> Daily_DB
    Live_DB --> Incremental_DB
    Live_Files --> Daily_Files
    Live_Sites --> Config_Backup
    
    Daily_DB --> DO_Spaces
    Incremental_DB --> DO_Spaces
    Daily_Files --> DO_Spaces
    Config_Backup --> DO_Spaces
    
    DO_Spaces --> Encrypted
    Encrypted --> Replicated
    
    Single_Site --> Detect
    Node_Failure --> Detect
    Region_Outage --> Detect
    Data_Corruption --> Detect
    
    Detect --> Assess
    Assess --> Restore_DB
    Assess --> Restore_Files
    Restore_DB --> Verify
    Restore_Files --> Verify
    Verify --> Resume
    
    Replicated -.->|Restore from| Restore_DB
    Replicated -.->|Restore from| Restore_Files

    style Production fill:#4caf50
    style Backup_Schedule fill:#2196f3
    style Backup_Storage fill:#ff9800
    style DR_Scenarios fill:#ff6b6b
    style Recovery_Process fill:#9c27b0
```

## Deployment Pipeline

```mermaid
graph LR
    subgraph Development["Development"]
        Dev[Developer]
        Git[Git Repository<br/>Feature Branch]
    end
    
    subgraph CI["CI/CD Pipeline"]
        Build[Build Images<br/>Docker Build]
        Test[Run Tests<br/>Unit + Integration]
        Scan[Security Scan<br/>Trivy]
        Push[Push to Registry<br/>Private Registry]
    end
    
    subgraph Staging["Staging Environment"]
        Stage_Deploy[Deploy to Staging<br/>docker stack deploy]
        Stage_Test[Automated Testing<br/>Smoke Tests]
    end
    
    subgraph Production["Production Deployment"]
        Prod_Deploy[Blue-Green Deploy<br/>Zero Downtime]
        Health_Check[Health Checks<br/>10s intervals]
        Rollback[Auto Rollback<br/>On Failure]
    end
    
    subgraph Monitoring["Post-Deploy Monitoring"]
        Monitor[Monitor Metrics<br/>Error Rates]
        Alert[Alert on Issues]
        Success[Deployment Success]
    end
    
    Dev --> Git
    Git -->|Push| Build
    Build --> Test
    Test --> Scan
    Scan -->|Pass| Push
    Scan -->|Fail| Dev
    
    Push --> Stage_Deploy
    Stage_Deploy --> Stage_Test
    Stage_Test -->|Pass| Prod_Deploy
    Stage_Test -->|Fail| Dev
    
    Prod_Deploy --> Health_Check
    Health_Check -->|Healthy| Monitor
    Health_Check -->|Unhealthy| Rollback
    Rollback --> Alert
    
    Monitor --> Success
    Monitor -->|Issues| Alert
    Alert -->|Critical| Rollback

    style Development fill:#e3f2fd
    style CI fill:#f3e5f5
    style Staging fill:#fff3e0
    style Production fill:#e8f5e9
    style Monitoring fill:#ffebee
```

## Site Provisioning Workflow

```mermaid
sequenceDiagram
    participant Admin
    participant API
    participant Swarm
    participant DNS
    participant Traefik
    participant Database
    participant Backup
    participant Monitoring
    
    Admin->>API: Create New Site Request
    API->>API: Generate Site ID & Config
    API->>Swarm: Deploy Stack (Nginx + PHP + Redis)
    Swarm-->>API: Deployment Started
    
    API->>Database: Create DB & User
    Database-->>API: Credentials
    
    API->>DNS: Configure DNS (Cloudflare)
    DNS-->>API: DNS Updated
    
    Swarm->>Traefik: Service Discovery
    Traefik->>Traefik: Configure Routes & SSL
    Traefik-->>Swarm: Route Active
    
    API->>Backup: Configure Backup Jobs
    Backup-->>API: Backup Scheduled
    
    API->>Monitoring: Add to Monitoring
    Monitoring-->>API: Metrics Collection Active
    
    API-->>Admin: Site Provisioned (URL)
    Admin->>Traefik: Access Site
    Traefik-->>Admin: WordPress Install Screen
```


