# Network Topology - WordPress Farm

## Physical Network Layout

```
                                    INTERNET
                                        │
                                        ▼
                    ┌───────────────────────────────────────┐
                    │            CLOUDFLARE                  │
                    │   ┌─────────────────────────────────┐ │
                    │   │ • Anycast DNS                   │ │
                    │   │ • DDoS Protection               │ │
                    │   │ • WAF (OWASP Rules)             │ │
                    │   │ • CDN (Static Assets)           │ │
                    │   │ • SSL/TLS Termination (Optional)│ │
                    │   │ • Bot Management                │ │
                    │   │ • Rate Limiting                 │ │
                    │   └─────────────────────────────────┘ │
                    └───────────────────┬───────────────────┘
                                        │ HTTPS (443)
                                        │ Cloudflare IPs Only
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                              DIGITAL OCEAN VPC (10.0.0.0/16)                                  │
│                                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           PUBLIC SUBNET (10.0.1.0/24)                                   │  │
│  │                                                                                         │  │
│  │    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐                  │  │
│  │    │   Manager-01    │    │   Manager-02    │    │   Manager-03    │                  │  │
│  │    │   10.0.1.10     │    │   10.0.1.11     │    │   10.0.1.12     │                  │  │
│  │    │                 │    │                 │    │                 │                  │  │
│  │    │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │                  │  │
│  │    │  │ Traefik   │  │    │  │ Traefik   │  │    │  │ Traefik   │  │                  │  │
│  │    │  │ (Leader)  │  │    │  │ (Replica) │  │    │  │ (Replica) │  │                  │  │
│  │    │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │                  │  │
│  │    │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │                  │  │
│  │    │  │ CrowdSec  │  │    │  │ CrowdSec  │  │    │  │ CrowdSec  │  │                  │  │
│  │    │  │  Agent    │  │    │  │  Agent    │  │    │  │  Agent    │  │                  │  │
│  │    │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │                  │  │
│  │    └────────┬────────┘    └────────┬────────┘    └────────┬────────┘                  │  │
│  │             │                      │                      │                           │  │
│  │             └──────────────────────┼──────────────────────┘                           │  │
│  │                                    │                                                   │  │
│  │                     DigitalOcean Load Balancer                                        │  │
│  │                        (Round Robin / Least Conn)                                     │  │
│  │                                                                                        │  │
│  └────────────────────────────────────┬───────────────────────────────────────────────────┘  │
│                                       │                                                      │
│                          Docker Overlay Network: "traefik-public"                            │
│                                       │                                                      │
│  ┌────────────────────────────────────┼───────────────────────────────────────────────────┐  │
│  │                          CACHE SUBNET (10.0.2.0/24)                                    │  │
│  │                                    │                                                   │  │
│  │    ┌─────────────────┐    ┌───────┴───────┐    ┌─────────────────┐                   │  │
│  │    │   Cache-01      │    │   Cache-02    │    │   Cache-03      │                   │  │
│  │    │   10.0.2.10     │    │   10.0.2.11   │    │   10.0.2.12     │                   │  │
│  │    │                 │    │               │    │                 │                   │  │
│  │    │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │    │  │  Varnish  │  │    │ │  Varnish  │ │    │  │  Varnish  │  │                   │  │
│  │    │  │  (6081)   │  │    │ │  (6081)   │ │    │  │  (6081)   │  │                   │  │
│  │    │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │    │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │    │  │   Redis   │  │    │ │   Redis   │ │    │  │   Redis   │  │                   │  │
│  │    │  │ (Master)  │  │    │ │ (Replica) │ │    │  │ (Replica) │  │                   │  │
│  │    │  │   6379    │  │    │ │   6379    │ │    │  │   6379    │  │                   │  │
│  │    │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │    │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │    │  │ Sentinel  │  │    │ │ Sentinel  │ │    │  │ Sentinel  │  │                   │  │
│  │    │  │  (26379)  │  │    │ │  (26379)  │ │    │  │  (26379)  │  │                   │  │
│  │    │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │    └─────────────────┘    └───────────────┘    └─────────────────┘                   │  │
│  │                                                                                       │  │
│  └───────────────────────────────────┬───────────────────────────────────────────────────┘  │
│                                      │                                                      │
│                         Docker Overlay Network: "cache-net"                                 │
│                                      │                                                      │
│  ┌───────────────────────────────────┼───────────────────────────────────────────────────┐  │
│  │                        APP SUBNET (10.0.3.0/24)                                       │  │
│  │                                   │                                                   │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐│  │
│  │  │  Worker-01   │ │  Worker-02   │ │  Worker-03   │ │  Worker-04   │ │  Worker-05   ││  │
│  │  │  10.0.3.10   │ │  10.0.3.11   │ │  10.0.3.12   │ │  10.0.3.13   │ │  10.0.3.14   ││  │
│  │  │              │ │              │ │              │ │              │ │              ││  │
│  │  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ ││  │
│  │  │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ ││  │
│  │  │ │   1-10   │ │ │ │  11-20   │ │ │ │  21-30   │ │ │ │  31-40   │ │ │ │  41-50   │ ││  │
│  │  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ ││  │
│  │  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ ││  │
│  │  │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ ││  │
│  │  │ │  51-60   │ │ │ │  61-70   │ │ │ │  71-80   │ │ │ │  81-90   │ │ │ │ 91-100   │ ││  │
│  │  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ ││  │
│  │  │      ...     │ │      ...     │ │      ...     │ │      ...     │ │      ...     ││  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘│  │
│  │                                                                                       │  │
│  │                          + Worker-06 (10.0.3.15) - Overflow                          │  │
│  │                                                                                       │  │
│  └──────────────────────────────────┬────────────────────────────────────────────────────┘  │
│                                     │                                                       │
│                        Docker Overlay Network: "wordpress-net"                              │
│                                     │                                                       │
│  ┌──────────────────────────────────┼────────────────────────────────────────────────────┐  │
│  │                       DATABASE SUBNET (10.0.4.0/24)                                   │  │
│  │                                  │                                                    │  │
│  │     ┌────────────────────────────┼────────────────────────────────────┐              │  │
│  │     │                        ProxySQL                                  │              │  │
│  │     │                    10.0.4.5 (VIP)                               │              │  │
│  │     │              ┌─────────────┴─────────────┐                      │              │  │
│  │     │              │     Query Router          │                      │              │  │
│  │     │              │  - Read/Write Split       │                      │              │  │
│  │     │              │  - Connection Pool        │                      │              │  │
│  │     │              │  - Query Cache            │                      │              │  │
│  │     │              └─────────────┬─────────────┘                      │              │  │
│  │     └────────────────────────────┼────────────────────────────────────┘              │  │
│  │                                  │                                                    │  │
│  │    ┌─────────────────┐    ┌──────┴──────┐    ┌─────────────────┐                     │  │
│  │    │    DB-01        │    │    DB-02    │    │    DB-03        │                     │  │
│  │    │   10.0.4.10     │    │  10.0.4.11  │    │   10.0.4.12     │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    │  ┌───────────┐  │    │ ┌─────────┐ │    │  ┌───────────┐  │                     │  │
│  │    │  │  MariaDB  │◄─┼────┼─┤ MariaDB ├─┼────┼──►│  MariaDB  │  │                     │  │
│  │    │  │  Galera   │  │    │ │ Galera  │ │    │  │  Galera   │  │                     │  │
│  │    │  │  (3306)   │  │    │ │ (3306)  │ │    │  │  (3306)   │  │                     │  │
│  │    │  └───────────┘  │    │ └─────────┘ │    │  └───────────┘  │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    │  Galera: 4567   │    │Galera: 4567 │    │  Galera: 4567   │                     │  │
│  │    │  IST: 4568      │    │IST: 4568    │    │  IST: 4568      │                     │  │
│  │    │  SST: 4444      │    │SST: 4444    │    │  SST: 4444      │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    └─────────────────┘    └─────────────┘    └─────────────────┘                     │  │
│  │              ▲                   ▲                   ▲                                │  │
│  │              │     Synchronous Replication          │                                │  │
│  │              └───────────────────┴───────────────────┘                                │  │
│  │                                                                                       │  │
│  └──────────────────────────────────┬────────────────────────────────────────────────────┘  │
│                                     │                                                       │
│                        Docker Overlay Network: "database-net"                               │
│                                     │                                                       │
│  ┌──────────────────────────────────┼────────────────────────────────────────────────────┐  │
│  │                       STORAGE SUBNET (10.0.5.0/24)                                    │  │
│  │                                  │                                                    │  │
│  │    ┌─────────────────┐    ┌──────┴──────┐    ┌─────────────────┐                     │  │
│  │    │   Storage-01    │    │  Storage-02 │    │   Storage-03    │                     │  │
│  │    │   10.0.5.10     │    │  10.0.5.11  │    │   10.0.5.12     │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    │  ┌───────────┐  │    │ ┌─────────┐ │    │  ┌───────────┐  │                     │  │
│  │    │  │ GlusterFS │◄─┼────┼─┤GlusterFS├─┼────┼──►│ GlusterFS │  │                     │  │
│  │    │  │  (brick)  │  │    │ │ (brick) │ │    │  │  (brick)  │  │                     │  │
│  │    │  └───────────┘  │    │ └─────────┘ │    │  └───────────┘  │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    │  Volumes:       │    │             │    │                 │                     │  │
│  │    │  - wp-uploads   │    │             │    │                 │                     │  │
│  │    │  - wp-plugins   │    │             │    │                 │                     │  │
│  │    │  - wp-themes    │    │             │    │                 │                     │  │
│  │    │                 │    │             │    │                 │                     │  │
│  │    └─────────────────┘    └─────────────┘    └─────────────────┘                     │  │
│  │                                                                                       │  │
│  │                    Replication Factor: 3 (all nodes)                                 │  │
│  │                                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                      OBSERVABILITY SUBNET (10.0.6.0/24)                               │  │
│  │                                                                                       │  │
│  │    ┌─────────────────────────────────────────────────────────────────────────────┐   │  │
│  │    │                           Ops-01 (10.0.6.10)                                 │   │  │
│  │    │                                                                              │   │  │
│  │    │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐            │   │  │
│  │    │  │ Grafana │  │  Mimir  │  │  Loki   │  │  Tempo  │  │  Alloy  │            │   │  │
│  │    │  │ (:3000) │  │ (:9009) │  │ (:3100) │  │ (:3200) │  │ (:4317) │            │   │  │
│  │    │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘            │   │  │
│  │    │                                                                              │   │  │
│  │    │  ┌───────────┐  ┌───────────┐  ┌───────────┐                                │   │  │
│  │    │  │ Portainer │  │ AlertMgr  │  │ CrowdSec  │                                │   │  │
│  │    │  │  (:9000)  │  │  (:9093)  │  │   LAPI    │                                │   │  │
│  │    │  └───────────┘  └───────────┘  └───────────┘                                │   │  │
│  │    │                                                                              │   │  │
│  │    └─────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                              │
└──────────────────────────────────────────────────────────────────────────────────────────────┘

                                           │
                                           │ Backups
                                           ▼
                              ┌─────────────────────────┐
                              │    DO Spaces (S3)       │
                              │  ┌─────────────────┐    │
                              │  │ • DB Backups    │    │
                              │  │ • File Backups  │    │
                              │  │ • Config Backup │    │
                              │  │ • Disaster Rcvy │    │
                              │  └─────────────────┘    │
                              │                         │
                              │  Region: NYC3           │
                              │  Bucket: wp-farm-backup │
                              └─────────────────────────┘
```

---

## Docker Overlay Networks

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           DOCKER NETWORK TOPOLOGY                                        │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  traefik-public (overlay, encrypted)                                                    │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.20.0.0/16                                                              │
│  ├── Services: Traefik, Varnish                                                         │
│  └── Purpose: Public-facing ingress traffic                                             │
│                                                                                          │
│  cache-net (overlay, encrypted)                                                         │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.21.0.0/16                                                              │
│  ├── Services: Varnish, Redis, WordPress                                                │
│  └── Purpose: Cache layer communication                                                 │
│                                                                                          │
│  wordpress-net (overlay, encrypted)                                                     │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.22.0.0/16                                                              │
│  ├── Services: WordPress, ProxySQL                                                      │
│  └── Purpose: Application layer isolation                                               │
│                                                                                          │
│  database-net (overlay, encrypted)                                                      │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.23.0.0/16                                                              │
│  ├── Services: MariaDB, ProxySQL                                                        │
│  └── Purpose: Database cluster isolation                                                │
│                                                                                          │
│  storage-net (overlay, encrypted)                                                       │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.24.0.0/16                                                              │
│  ├── Services: GlusterFS, WordPress                                                     │
│  └── Purpose: Shared storage access                                                     │
│                                                                                          │
│  observability-net (overlay, encrypted)                                                 │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.25.0.0/16                                                              │
│  ├── Services: All services (metrics export)                                            │
│  └── Purpose: Monitoring and logging traffic                                            │
│                                                                                          │
│  crowdsec-net (overlay, encrypted)                                                      │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.26.0.0/16                                                              │
│  ├── Services: CrowdSec LAPI, Bouncers, Agents                                         │
│  └── Purpose: Security layer communication                                              │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Traffic Flow

```
                                    USER REQUEST
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 1. CLOUDFLARE EDGE                                                                      │
│    ├── DNS Resolution (Anycast)                                                         │
│    ├── DDoS Mitigation                                                                  │
│    ├── WAF Rules Check                                                                  │
│    ├── Bot Detection                                                                    │
│    ├── Cache Check (Static Assets) ──────────────────────► [HIT] Return cached asset   │
│    │                                                                                    │
│    └── [MISS] Forward to Origin                                                         │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 2. TRAEFIK INGRESS                                                                      │
│    ├── SSL/TLS Termination (Let's Encrypt)                                             │
│    ├── Cloudflare IP Verification                                                       │
│    ├── CrowdSec Bouncer Check ───────────────────────────► [BLOCKED] 403 Forbidden     │
│    ├── Rate Limit Check ─────────────────────────────────► [EXCEEDED] 429 Too Many     │
│    ├── Security Headers Injection                                                       │
│    ├── Host-based Routing (site1.com → site1 service)                                  │
│    │                                                                                    │
│    └── Forward to Varnish                                                               │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 3. VARNISH CACHE                                                                        │
│    ├── Cache Key Generation (URL + Cookies + Headers)                                  │
│    ├── Cache Lookup ─────────────────────────────────────► [HIT] Return cached page    │
│    │                                                                                    │
│    └── [MISS] Forward to WordPress                                                      │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 4. WORDPRESS APPLICATION                                                                │
│    ├── nginx receives request                                                           │
│    ├── PHP-FPM processes request                                                        │
│    ├── Redis Object Cache Check ─────────────────────────► [HIT] Return cached object  │
│    │                                                                                    │
│    └── [MISS] Query Database                                                            │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 5. PROXYSQL                                                                             │
│    ├── Connection from Pool                                                             │
│    ├── Query Analysis                                                                   │
│    ├── Read/Write Routing:                                                              │
│    │   ├── SELECT → Read Replica                                                        │
│    │   └── INSERT/UPDATE/DELETE → Primary                                               │
│    │                                                                                    │
│    └── Query Execution                                                                  │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 6. MARIADB GALERA                                                                       │
│    ├── Execute Query                                                                    │
│    ├── Synchronous Replication (if write)                                              │
│    │                                                                                    │
│    └── Return Results                                                                   │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
                              RESPONSE BACK TO USER
                           (Cached at each layer for next request)
```

---

## Port Matrix

| Service | Internal Port | External Port | Protocol | Network |
|---------|--------------|---------------|----------|---------|
| Traefik HTTP | 80 | 80 | TCP | traefik-public |
| Traefik HTTPS | 443 | 443 | TCP | traefik-public |
| Traefik Dashboard | 8080 | - | TCP | observability-net |
| Traefik Metrics | 8082 | - | TCP | observability-net |
| Varnish | 6081 | - | TCP | cache-net |
| Varnish Admin | 6082 | - | TCP | cache-net |
| Redis | 6379 | - | TCP | cache-net |
| Redis Sentinel | 26379 | - | TCP | cache-net |
| WordPress/nginx | 80 | - | TCP | wordpress-net |
| PHP-FPM | 9000 | - | TCP | internal |
| ProxySQL | 6033 | - | TCP | database-net |
| ProxySQL Admin | 6032 | - | TCP | database-net |
| MariaDB | 3306 | - | TCP | database-net |
| Galera Cluster | 4567 | - | TCP/UDP | database-net |
| Galera IST | 4568 | - | TCP | database-net |
| Galera SST | 4444 | - | TCP | database-net |
| GlusterFS | 24007 | - | TCP | storage-net |
| GlusterFS Bricks | 49152-49251 | - | TCP | storage-net |
| Grafana | 3000 | - | TCP | observability-net |
| Mimir | 9009 | - | TCP | observability-net |
| Loki | 3100 | - | TCP | observability-net |
| Tempo | 3200 | - | TCP | observability-net |
| Alloy/OTel | 4317, 4318 | - | TCP | observability-net |
| Portainer | 9000, 9443 | - | TCP | observability-net |
| CrowdSec LAPI | 8080 | - | TCP | crowdsec-net |
| Node Exporter | 9100 | - | TCP | observability-net |
| cAdvisor | 8080 | - | TCP | observability-net |

---

## Firewall Rules (UFW/iptables)

### Manager Nodes
```bash
# Allow from Cloudflare IPs only
ufw allow from 173.245.48.0/20 to any port 443 proto tcp
ufw allow from 103.21.244.0/22 to any port 443 proto tcp
ufw allow from 103.22.200.0/22 to any port 443 proto tcp
ufw allow from 103.31.4.0/22 to any port 443 proto tcp
ufw allow from 141.101.64.0/18 to any port 443 proto tcp
ufw allow from 108.162.192.0/18 to any port 443 proto tcp
ufw allow from 190.93.240.0/20 to any port 443 proto tcp
ufw allow from 188.114.96.0/20 to any port 443 proto tcp
ufw allow from 197.234.240.0/22 to any port 443 proto tcp
ufw allow from 198.41.128.0/17 to any port 443 proto tcp
ufw allow from 162.158.0.0/15 to any port 443 proto tcp
ufw allow from 104.16.0.0/13 to any port 443 proto tcp
ufw allow from 104.24.0.0/14 to any port 443 proto tcp
ufw allow from 172.64.0.0/13 to any port 443 proto tcp
ufw allow from 131.0.72.0/22 to any port 443 proto tcp

# Docker Swarm
ufw allow from 10.0.0.0/16 to any port 2377 proto tcp  # Swarm management
ufw allow from 10.0.0.0/16 to any port 7946           # Node communication
ufw allow from 10.0.0.0/16 to any port 4789 proto udp  # Overlay network

# SSH (from bastion only)
ufw allow from 10.0.0.5 to any port 22 proto tcp
```

### All Internal Nodes
```bash
# Internal VPC only
ufw allow from 10.0.0.0/16

# Deny all other inbound
ufw default deny incoming
ufw default allow outgoing
```


