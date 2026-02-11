# Network Topology - WordPress Farm (Sonnet 4.5 Modified Strategy)

## Architecture Changes

**This topology implements:**
- ✅ **Dedicated Cache Tier** (Opus 4.5 style) - 3 separate cache nodes
- ✅ **Comprehensive Alerting** (Slack/Email/SMS)
- ✅ **Full Automation** via orchestration scripts
- ❌ **Keeps GlusterFS** (CephFS not needed on DigitalOcean)
- ❌ **Pure DigitalOcean** (Proxmox/PVE deferred for future)

**Cost:** $3,613/month ($7.23/site) - 33 total nodes (OPTIMIZED - cache nodes downsized)

## Physical Network Layout

```
                                    INTERNET
                                        │
                                        ▼
                    ┌───────────────────────────────────────┐
                    │            CLOUDFLARE                 │
                    │   ┌─────────────────────────────────┐ │
                    │   │ • Anycast DNS                   │ │
                    │   │ • DDoS Protection               │ │
                    │   │ • WAF (OWASP Rules)             │ │
                    │   │ • CDN (Static Assets)           │ │
                    │   │ • SSL/TLS Edge (Optional)       │ │
                    │   │ • Bot Management                │ │
                    │   │ • Rate Limiting (Edge)          │ │
                    │   │ • Argo Smart Routing            │ │
                    │   └─────────────────────────────────┘ │
                    └───────────────────┬───────────────────┘
                                        │ HTTPS (443)
                                        │ Cloudflare IPs Only
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              DIGITAL OCEAN VPC (10.0.0.0/16)                                │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           PUBLIC SUBNET (10.0.1.0/24)                                 │  │
│  │                                                                                       │  │
│  │    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐                  │  │
│  │    │   Manager-01    │    │   Manager-02    │    │   Manager-03    │                  │  │
│  │    │   10.0.1.10     │    │   10.0.1.11     │    │   10.0.1.12     │                  │  │
│  │    │  (Control Plane)│    │  (Control Plane)│    │  (Control Plane)│                  │  │
│  │    │                 │    │                 │    │                 │                  │  │
│  │    │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │                  │  │
│  │    │  │ Traefik   │  │    │  │ Traefik   │  │    │  │ Traefik   │  │                  │  │
│  │    │  │ (Leader)  │  │    │  │ (Replica) │  │    │  │ (Replica) │  │                  │  │
│  │    │  │  :80,:443 │  │    │  │  :80,:443 │  │    │  │  :80,:443 │  │                  │  │
│  │    │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │                  │  │
│  │    │  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │                  │  │
│  │    │  │ CrowdSec  │  │    │  │ CrowdSec  │  │    │  │ CrowdSec  │  │                  │  │
│  │    │  │  Agent    │  │    │  │  Agent    │  │    │  │  Agent    │  │                  │  │
│  │    │  └───────────┘  │    │  └───────────┘  │    │  └───────────┘  │                  │  │
│  │    │                 │    │                 │    │                 │                  │  │
│  │    │  ⚠️  Varnish Moved to Dedicated Cache Tier (see below)        │                  │  │
│  │    └────────┬────────┘    └────────┬────────┘    └────────┬────────┘                  │  │
│  │             │                      │                      │                           │  │
│  │             └──────────────────────┼──────────────────────┘                           │  │
│  │                                    │                                                  │  │
│  │                  ┌─────────────────┴─────────────────┐                                │  │
│  │                  │  DigitalOcean Load Balancer (VIP) │                                │  │
│  │                  │    Floating IP: 203.0.113.10      │                                │  │
│  │                  │  (Round Robin / Health Checks)    │                                │  │
│  │                  └───────────────────────────────────┘                                │  │
│  │                                                                                       │  │
│  └────────────────────────────────────┬──────────────────────────────────────────────────┘  │
│                                       │                                                     │
│                          Docker Overlay Network: "traefik-public"                           │
│                                       │                                                     │
│  ┌────────────────────────────────────┼──────────────────────────────────────────────────┐  │
│  │                        CACHE SUBNET (10.0.5.0/24) - DEDICATED TIER ⭐                 │  │
│  │                     (Opus 4.5 Style - Isolated from Managers)                         │  │
│  │                                    │                                                  │  │
│  │     ┌─────────────────┐    ┌───────┴───────┐    ┌─────────────────┐                   │  │
│  │     │   Cache-01      │    │   Cache-02    │    │   Cache-03      │                   │  │
│  │     │   10.0.5.10     │    │   10.0.5.11   │    │   10.0.5.12     │                   │  │
│  │     │                 │    │               │    │                 │                   │  │
│  │     │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │     │  │  Varnish  │  │    │ │  Varnish  │ │    │  │  Varnish  │  │                   │  │
│  │     │  │  (6081)   │  │    │ │  (6081)   │ │    │  │  (6081)   │  │                   │  │
│  │     │  │   4GB ⚡   │  │    │ │   4GB ⚡   │ │    │  │   4GB ⚡   │  │                   │  │
│  │     │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │     │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │     │  │   Redis   │  │    │ │   Redis   │ │    │  │   Redis   │  │                   │  │
│  │     │  │ (Master)  │  │    │ │ (Replica) │ │    │  │ (Replica) │  │                   │  │
│  │     │  │   6379    │  │    │ │   6379    │ │    │  │   6379    │  │                   │  │
│  │     │  │   2GB     │  │    │ │   2GB     │ │    │  │   2GB     │  │                   │  │
│  │     │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │     │  ┌───────────┐  │    │ ┌───────────┐ │    │  ┌───────────┐  │                   │  │
│  │     │  │ Sentinel  │  │    │ │ Sentinel  │ │    │  │ Sentinel  │  │                   │  │
│  │     │  │  (26379)  │  │    │ │  (26379)  │ │    │  │  (26379)  │  │                   │  │
│  │     │  └───────────┘  │    │ └───────────┘ │    │  └───────────┘  │                   │  │
│  │     │                 │    │               │    │                 │                   │  │
│  │     │  8GB RAM ⚡      │    │  8GB RAM ⚡    │    │  8GB RAM ⚡      │                   │  │
│  │     │  4 vCPU         │    │  4 vCPU       │    │  4 vCPU         │                   │  │
│  │     └─────────────────┘    └───────────────┘    └─────────────────┘                   │  │
│  │                                                                                       │  │
│  │    Benefits: Better performance isolation, independent scaling, clear metrics         │  │
│  │    Cost: +$144/month (3 nodes × $48) = Total cache: 12GB Varnish + 6GB Redis ⚡        │  │
│  │    Optimization: 8GB nodes sufficient (was 16GB) - saves $144/month                   │  │
│  │                                                                                       │  │
│  └──────────────────────────────────┬────────────────────────────────────────────────────┘  │
│                                     │                                                       │
│                        Docker Overlay Network: "cache-net"                                  │
│                                     │                                                       │
│  ┌────────────────────────────────────┼──────────────────────────────────────────────────┐  │
│  │                          APP SUBNET (10.0.2.0/23) - 500 IPs                           │  │
│  │                                    │                                                  │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │  │
│  │  │  Worker-01   │ │  Worker-02   │ │  Worker-03   │ │  Worker-04   │ │  Worker-05   │ │  │
│  │  │  10.0.2.10   │ │  10.0.2.11   │ │  10.0.2.12   │ │  10.0.2.13   │ │  10.0.2.14   │ │  │
│  │  │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │  │
│  │  │              │ │              │ │              │ │              │ │              │ │  │
│  │  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │ │  │
│  │  │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │ │ WP Site  │ │ │  │
│  │  │ │  001-025 │ │ │ │  026-050 │ │ │ │  051-075 │ │ │ │  076-100 │ │ │ │ 101-125  │ │ │  │
│  │  │ │ nginx    │ │ │ │ nginx    │ │ │ │ nginx    │ │ │ │ nginx    │ │ │ │ nginx    │ │ │  │
│  │  │ │ php-fpm  │ │ │ │ php-fpm  │ │ │ │ php-fpm  │ │ │ │ php-fpm  │ │ │ │ php-fpm  │ │ │  │
│  │  │ │ redis    │ │ │ │ redis    │ │ │ │ redis    │ │ │ │ redis    │ │ │ │ redis    │ │ │  │
│  │  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │ │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ │  │
│  │                                                                                       │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │  │
│  │  │  Worker-06   │ │  Worker-07   │ │  Worker-08   │ │  Worker-09   │ │  Worker-10   │ │  │
│  │  │  10.0.2.15   │ │  10.0.2.16   │ │  10.0.2.17   │ │  10.0.2.18   │ │  10.0.2.19   │ │  │
│  │  │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │  │
│  │  │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │  │
│  │  │ 126-150      │ │ 151-175      │ │ 176-200      │ │ 201-225      │ │ 226-250      │ │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ │  │
│  │                                                                                       │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │  │
│  │  │  Worker-11   │ │  Worker-12   │ │  Worker-13   │ │  Worker-14   │ │  Worker-15   │ │  │
│  │  │  10.0.2.20   │ │  10.0.2.21   │ │  10.0.2.22   │ │  10.0.2.23   │ │  10.0.2.24   │ │  │
│  │  │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │  │
│  │  │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │  │
│  │  │ 251-275      │ │ 276-300      │ │ 301-325      │ │ 326-350      │ │ 351-375      │ │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ │  │
│  │                                                                                       │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │  │
│  │  │  Worker-16   │ │  Worker-17   │ │  Worker-18   │ │  Worker-19   │ │  Worker-20   │ │  │
│  │  │  10.0.2.25   │ │  10.0.2.26   │ │  10.0.2.27   │ │  10.0.2.28   │ │  10.0.2.29   │ │  │
│  │  │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │ (~25 sites)  │ │  │
│  │  │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │ Sites        │ │  │
│  │  │ 376-400      │ │ 401-425      │ │ 426-450      │ │ 451-475      │ │ 476-500      │ │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ │  │
│  │                                                                                       │  │
│  │                     Each WP Stack Includes:                                           │  │
│  │                     • Nginx (web server)                                              │  │
│  │                     • PHP-FPM 8.2 (with OPcache)                                      │  │
│  │                     • Redis (object cache per site or shared)                         │  │
│  │                     • Connected to GlusterFS for uploads/media                        │  │
│  │                                                                                       │  │
│  └──────────────────────────────────┬────────────────────────────────────────────────────┘  │
│                                     │                                                       │
│                        Docker Overlay Network: "wordpress-net"                              │
│                                     │                                                       │
│  ┌──────────────────────────────────┼────────────────────────────────────────────────────┐  │
│  │                       DATABASE SUBNET (10.0.3.0/24)                                   │  │
│  │                                  │                                                    │  │
│  │     ┌────────────────────────────┼────────────────────────────────────┐               │  │
│  │     │                        ProxySQL Cluster                         │               │  │
│  │     │                    10.0.3.5 (Service VIP)                       │               │  │
│  │     │              ┌─────────────┴─────────────┐                      │               │  │
│  │     │              │     Query Router          │                      │               │  │
│  │     │              │  - Read/Write Split       │                      │               │  │
│  │     │              │  - Connection Pool        │                      │               │  │
│  │     │              │  - Query Cache            │                      │               │  │
│  │     │              │  - Failover Detection     │                      │               │  │
│  │     │              └─────────────┬─────────────┘                      │               │  │
│  │     └────────────────────────────┼────────────────────────────────────┘               │  │
│  │                                  │                                                    │  │
│  │    ┌─────────────────┐    ┌──────┴──────┐    ┌─────────────────┐                      │  │
│  │    │    DB-01        │    │    DB-02    │    │    DB-03        │                      │  │
│  │    │   10.0.3.10     │    │  10.0.3.11  │    │   10.0.3.12     │                      │  │
│  │    │   (Primary)     │    │  (Replica)  │    │   (Replica)     │                      │  │
│  │    │                 │    │             │    │                 │                      │  │
│  │    │  ┌───────────┐  │    │ ┌─────────┐ │    │  ┌───────────┐  │                      │  │
│  │    │  │  MariaDB  │◄─┼────┼─┤ MariaDB ├─┼────┼──►│  MariaDB  │  │                     │  │
│  │    │  │  Galera   │  │    │ │ Galera  │ │    │  │  Galera   │  │                      │  │
│  │    │  │  10.11    │  │    │ │  10.11  │ │    │  │  10.11    │  │                      │  │
│  │    │  │  (3306)   │  │    │ │ (3306)  │ │    │  │  (3306)   │  │                      │  │
│  │    │  └───────────┘  │    │ └─────────┘ │    │  └───────────┘  │                      │  │
│  │    │                 │    │             │    │                 │                      │  │
│  │    │  Galera Ports:  │    │Galera Ports:│    │  Galera Ports:  │                      │  │
│  │    │  - 4567 (wsrep) │    │- 4567       │    │  - 4567         │                      │  │
│  │    │  - 4568 (IST)   │    │- 4568       │    │  - 4568         │                      │  │
│  │    │  - 4444 (SST)   │    │- 4444       │    │  - 4444         │                      │  │
│  │    │                 │    │             │    │                 │                      │  │
│  │    │  16GB RAM       │    │ 16GB RAM    │    │  16GB RAM       │                      │  │
│  │    │  8 vCPU         │    │ 8 vCPU      │    │  8 vCPU         │                      │  │
│  │    │  Block Storage  │    │Block Storage│    │  Block Storage  │                      │  │
│  │    └─────────────────┘    └─────────────┘    └─────────────────┘                      │  │
│  │              ▲                   ▲                   ▲                                │  │
│  │              │     Synchronous Multi-Master         │                                 │  │
│  │              │          Replication                 │                                 │  │
│  │              └───────────────────┴───────────────────┘                                │  │
│  │                                                                                       │  │
│  └──────────────────────────────────┬────────────────────────────────────────────────────┘  │
│                                     │                                                       │
│                        Docker Overlay Network: "database-net"                               │
│                                     │                                                       │
│  ┌──────────────────────────────────┼────────────────────────────────────────────────────┐  │
│  │                       STORAGE SUBNET (10.0.4.0/24)                                    │  │
│  │                                  │                                                    │  │
│  │    ┌─────────────────────────────┴───────────────────────────┐                        │  │
│  │    │                                                          │                        │  │
│  │    │                                                          │                        │  │
│  │    ▼                                                          ▼                        │  │
│  │  ┌─────────────────────────────────┐    ┌─────────────────────────────────┐           │  │
│  │  │       Storage-01                │    │       Storage-02                │           │  │
│  │  │       10.0.4.10                 │    │       10.0.4.11                 │           │  │
│  │  │                                 │    │                                 │           │  │
│  │  │    ┌─────────────────────┐      │    │      ┌─────────────────────┐    │           │  │
│  │  │    │    GlusterFS        │◄─────┼────┼─────►│    GlusterFS        │    │           │  │
│  │  │    │    Brick Server     │      │    │      │    Brick Server     │    │           │  │
│  │  │    │    (Replica 2)      │      │    │      │    (Replica 2)      │    │           │  │
│  │  │    └─────────────────────┘      │    │      └─────────────────────┘    │           │  │
│  │  │                                 │    │                                 │           │  │
│  │  │    Volumes:                     │    │      Volumes:                   │           │  │
│  │  │    • wp-uploads (2.5TB)         │    │      • wp-uploads (2.5TB)       │           │  │
│  │  │    • wp-plugins (500GB)         │    │      • wp-plugins (500GB)       │           │  │
│  │  │    • wp-themes (500GB)          │    │      • wp-themes (500GB)        │           │  │
│  │  │    • wp-cache (500GB)           │    │      • wp-cache (500GB)         │           │  │
│  │  │                                 │    │                                 │           │  │
│  │  │    16GB RAM / 8 vCPU            │    │      16GB RAM / 8 vCPU          │           │  │
│  │  │    + 2TB Block Storage          │    │      + 2TB Block Storage        │           │  │
│  │  │                                 │    │                                 │           │  │
│  │  │    GlusterFS Ports:             │    │      GlusterFS Ports:           │           │  │
│  │  │    - 24007 (management)         │    │      - 24007 (management)       │           │  │
│  │  │    - 49152-49251 (bricks)       │    │      - 49152-49251 (bricks)     │           │  │
│  │  └─────────────────────────────────┘    └─────────────────────────────────┘           │  │
│  │                                                                                       │  │
│  │                    Replication Factor: 2 (mirror across both nodes)                  │  │
│  │                    Access Mode: Distributed-Replicate Volume                         │  │
│  │                    Mount Point on Workers: /mnt/glusterfs                            │  │
│  │                                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                      OBSERVABILITY SUBNET (10.0.5.0/24)                               │  │
│  │                                                                                       │  │
│  │    ┌─────────────────────────────────────────────────────────────────────────────┐   │  │
│  │    │                      Monitoring-01 (10.0.5.10)                              │   │  │
│  │    │                         (Primary Observability Node)                        │   │  │
│  │    │                                                                             │   │  │
│  │    │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │   │  │
│  │    │  │ Grafana │  │  Mimir  │  │  Loki   │  │  Tempo  │  │  Alloy  │           │   │  │
│  │    │  │ (:3000) │  │ (:9009) │  │ (:3100) │  │ (:3200) │  │ (:4317) │           │   │  │
│  │    │  │Dashboards│  │ Metrics │  │  Logs   │  │ Traces  │  │OTel Coll│           │   │  │
│  │    │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘           │   │  │
│  │    │                                                                             │   │  │
│  │    │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐               │   │  │
│  │    │  │AlertMgr   │  │ CrowdSec  │  │Prometheus │  │  Promtail │               │   │  │
│  │    │  │ (:9093)   │  │   LAPI    │  │  (:9090)  │  │  (:9080)  │               │   │  │
│  │    │  └───────────┘  └───────────┘  └───────────┘  └───────────┘               │   │  │
│  │    │                                                                             │   │  │
│  │    │  16GB RAM / 8 vCPU + 500GB Block Storage                                    │   │  │
│  │    └─────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                                                       │  │
│  │    ┌─────────────────────────────────────────────────────────────────────────────┐   │  │
│  │    │                      Monitoring-02 (10.0.5.11)                              │   │  │
│  │    │                      (Backup Observability Node)                            │   │  │
│  │    │                                                                             │   │  │
│  │    │  ┌─────────┐  ┌─────────┐  ┌───────────┐  ┌───────────┐                    │   │  │
│  │    │  │ Grafana │  │  Loki   │  │ Portainer │  │  WP-CLI   │                    │   │  │
│  │    │  │(Replica)│  │(Replica)│  │  (:9000)  │  │   Farm    │                    │   │  │
│  │    │  └─────────┘  └─────────┘  └───────────┘  └───────────┘                    │   │  │
│  │    │                                                                             │   │  │
│  │    │  ┌────────────┐  ┌────────────┐  ┌────────────┐                            │   │  │
│  │    │  │ Backup-DB  │  │Backup-Files│  │  Registry  │                            │   │  │
│  │    │  │ (Percona)  │  │  (Restic)  │  │  (Docker)  │                            │   │  │
│  │    │  └────────────┘  └────────────┘  └────────────┘                            │   │  │
│  │    │                                                                             │   │  │
│  │    │  16GB RAM / 8 vCPU + 500GB Block Storage                                    │   │  │
│  │    └─────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                                                       │  │
│  │                      All services export metrics to Prometheus/Mimir                 │  │
│  │                      All containers send logs to Loki via Promtail                   │  │
│  │                      OpenTelemetry traces flow to Tempo                              │  │
│  │                                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │          ⚠️  NOTE: ALERTING USES EXISTING ALERTMANAGER (Above in Monitoring-01)      │  │
│  │                                                                                       │  │
│  │    Alertmanager (already deployed in monitoring stack) handles:                      │  │
│  │    • Slack notifications → Webhook (built-in)                                        │  │
│  │    • Email notifications → SendGrid SMTP (built-in)                                  │  │
│  │    • SMS notifications → Twilio webhook (optional lightweight service)               │  │
│  │    • PagerDuty integration → Webhook (optional)                                      │  │
│  │                                                                                       │  │
│  │    Configuration: /configs/alertmanager/alertmanager.yml                             │  │
│  │    No separate alerting stack needed - saves complexity!                             │  │
│  │                                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                              │
└──────────────────────────────────────────────────────────────────────────────────────────────┘

                                           │
                                           │ Automated Backups
                                           │ (Every 6 hours - DB)
                                           │ (Daily - Files)
                                           ▼
                              ┌─────────────────────────────┐
                              │    DO Spaces (S3)           │
                              │  ┌───────────────────────┐  │
                              │  │ • DB Backups (30d)    │  │
                              │  │ • File Backups (30d)  │  │
                              │  │ • Config Backups      │  │
                              │  │ • Encrypted at Rest   │  │
                              │  │ • Versioning Enabled  │  │
                              │  │ • Lifecycle Policies  │  │
                              │  └───────────────────────┘  │
                              │                             │
                              │  Region: NYC3               │
                              │  Bucket: wp-farm-backups    │
                              │  Size: ~500GB               │
                              │  Cost: $10/month            │
                              └─────────────────────────────┘
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
│  ├── Services: Traefik, Varnish, CrowdSec Bouncer                                       │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Public-facing ingress traffic from Cloudflare                             │
│                                                                                          │
│  wordpress-net (overlay, encrypted)                                                     │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.21.0.0/16                                                              │
│  ├── Services: WordPress stacks (nginx, php-fpm, per-site redis)                        │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Application layer - WordPress container communication                     │
│                                                                                          │
│  database-net (overlay, encrypted)                                                      │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.22.0.0/16                                                              │
│  ├── Services: MariaDB Galera, ProxySQL, WordPress (DB connections)                     │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Database cluster isolation and communication                              │
│                                                                                          │
│  storage-net (overlay, encrypted)                                                       │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.23.0.0/16                                                              │
│  ├── Services: GlusterFS, WordPress (for mounts)                                        │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Shared storage access - uploads, plugins, themes                          │
│                                                                                          │
│  observability-net (overlay, encrypted)                                                 │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.24.0.0/16                                                              │
│  ├── Services: All services (metrics/logs/traces export)                                │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Monitoring, logging, and tracing traffic (LGTM stack)                     │
│                                                                                          │
│  crowdsec-net (overlay, encrypted)                                                      │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.25.0.0/16                                                              │
│  ├── Services: CrowdSec LAPI, Agents, Bouncers                                          │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Security layer - threat intelligence and blocking                         │
│                                                                                          │
│  management-net (overlay, encrypted)                                                    │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.26.0.0/16                                                              │
│  ├── Services: Portainer, Backup services, WP-CLI, Registry                             │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Management and operations tools                                           │
│                                                                                          │
│  cache-net (overlay, encrypted) [REQUIRED - Dedicated Cache Tier]                       │
│  ├── Scope: Swarm-wide                                                                  │
│  ├── Subnet: 172.27.0.0/16                                                              │
│  ├── Services: Varnish, Redis Master/Replicas, Sentinel, Exporters                      │
│  ├── Encryption: IPSec (AES-GCM)                                                        │
│  └── Purpose: Dedicated cache tier isolation (Opus 4.5 architecture)                    │
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
│    ├── DDoS Mitigation (Auto - Layer 3/4/7)                                             │
│    ├── WAF Rules Check (OWASP Core Ruleset)                                             │
│    ├── Bot Detection (Challenge bad actors)                                             │
│    ├── Argo Smart Routing (Optimal path selection)                                      │
│    ├── Cache Check (Static Assets) ──────────────────────► [HIT] Return cached asset   │
│    │                                                         (~80-90% of static)         │
│    └── [MISS] Forward to Origin (Floating IP)                                           │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 2. DIGITAL OCEAN LOAD BALANCER                                                          │
│    ├── Health Check (Traefik /ping endpoint)                                            │
│    ├── Route to healthy Traefik instance ─────────────────► [FAIL] Route to backup     │
│    │                                                                                    │
│    └── Forward to Traefik (Round-robin across 3 managers)                               │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 3. TRAEFIK INGRESS (Manager Nodes)                                                      │
│    ├── SSL/TLS Termination (Let's Encrypt wildcard certs)                               │
│    ├── Cloudflare IP Verification (middleware)                                          │
│    ├── CrowdSec Bouncer Check ───────────────────────────► [BLOCKED] 403 Forbidden     │
│    │                                                         (Known bad actors)          │
│    ├── Rate Limit Check (per-IP, per-route) ─────────────► [EXCEEDED] 429 Too Many     │
│    │                                                         (Prevent abuse)             │
│    ├── Security Headers Injection:                                                       │
│    │   • Strict-Transport-Security (HSTS)                                                │
│    │   • X-Frame-Options (Clickjacking protection)                                       │
│    │   • X-Content-Type-Options (MIME sniffing)                                          │
│    │   • Content-Security-Policy (XSS protection)                                        │
│    │                                                                                    │
│    ├── Host-based Routing:                                                               │
│    │   • example.com → wp-example_com service                                            │
│    │   • blog.company.com → wp-blog_company_com service                                  │
│    │                                                                                    │
│    └── Forward to Varnish (DEDICATED cache tier - separate nodes)                       │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 4. VARNISH CACHE (Dedicated Cache Tier - 3 Separate Nodes) ⭐                          │
│    ├── Cache Key Generation:                                                             │
│    │   • URL + Query params                                                              │
│    │   • Cookies (excluding session/tracking)                                            │
│    │   • Accept-Encoding header                                                          │
│    │                                                                                    │
│    ├── Cache Lookup ─────────────────────────────────────► [HIT] Return cached page    │
│    │                                                         (~60-80% of pages)          │
│    │                                                                                    │
│    ├── [MISS] Check if cacheable:                                                        │
│    │   • Skip if logged-in user (wp-admin, woocommerce-cart cookies)                     │
│    │   • Skip if POST request                                                            │
│    │   • Skip if query string contains nocache                                           │
│    │                                                                                    │
│    └── Forward to WordPress                                                              │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 5. WORDPRESS APPLICATION (Worker Nodes)                                                 │
│    ├── nginx receives request                                                           │
│    │   • Static file check (css, js, images) ────────────► [FOUND] Serve directly      │
│    │   • Rewrite rules applied                                                           │
│    │                                                                                    │
│    ├── Forward to PHP-FPM (FastCGI)                                                      │
│    │   • PHP 8.2 with OPcache enabled (~90% opcache hit rate)                           │
│    │   • WordPress Core loads                                                            │
│    │   • Plugins/themes initialize                                                       │
│    │                                                                                    │
│    ├── Redis Object Cache Check ─────────────────────────► [HIT] Return cached object  │
│    │   (WP Redis plugin)                                    (~70-90% of queries)        │
│    │                                                                                    │
│    └── [MISS] Query Database via ProxySQL                                               │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 6. PROXYSQL (Database Query Router)                                                     │
│    ├── Connection from Pool (reuse existing DB connections)                             │
│    │   • Frontend: 5000 connections (from WP sites)                                      │
│    │   • Backend: 150-300 connections (to Galera)                                        │
│    │   • 90% reduction in DB connection overhead                                         │
│    │                                                                                    │
│    ├── Query Analysis & Routing:                                                         │
│    │   ├── SELECT queries → Any Galera node (read distribution)                          │
│    │   ├── INSERT/UPDATE/DELETE → Primary node (write consistency)                       │
│    │   └── Complex queries → Specific node based on rules                                │
│    │                                                                                    │
│    ├── Query Cache Check (ProxySQL internal) ────────────► [HIT] Return cached result  │
│    │                                                         (~20-40% cache hit)         │
│    │                                                                                    │
│    ├── Health Check Galera Nodes ────────────────────────► [DOWN] Route to healthy     │
│    │                                                                                    │
│    └── Execute Query on Galera                                                           │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ 7. MARIADB GALERA CLUSTER                                                               │
│    ├── Execute Query on selected node                                                   │
│    │                                                                                    │
│    ├── If WRITE operation:                                                               │
│    │   • Perform local write                                                             │
│    │   • Synchronous replication to other 2 nodes (wsrep)                               │
│    │   • Wait for confirmation from majority (2/3)                                       │
│    │   • Commit transaction                                                              │
│    │                                                                                    │
│    ├── If READ operation:                                                                │
│    │   • Execute on local node                                                           │
│    │   • Return results immediately                                                      │
│    │                                                                                    │
│    └── Return Results to ProxySQL                                                        │
└────────────────────────────────────────┬───────────────────────────────────────────────┘
                                         │
                                         ▼
                         RESPONSE FLOWS BACK UP THE STACK
                              WordPress → Varnish → Traefik → Cloudflare → User
                         
                         (Each layer caches for subsequent requests)
```

---

## Key Architectural Differences from Opus 4.5

| Aspect | Sonnet 4.5 (Modified) | Opus 4.5 (Original) |
|--------|----------------------|---------------------|
| **Worker Nodes** | 20 nodes (~25 sites each) | 6 nodes (~83 sites each) |
| **Cache Architecture** | ✅ 3 dedicated cache nodes (ADOPTED) | 3 dedicated cache nodes |
| **Storage Nodes** | 2 (GlusterFS replica 2) | 3 (GlusterFS replica 3) |
| **Monitoring Nodes** | 2 dedicated | Mixed with ops node |
| **Alerting** | Multi-channel (Slack/Email/SMS) | Basic |
| **Automation** | Full orchestration script | Partial |
| **Total Base Nodes** | **33 nodes** (+3 cache@8GB⚡) | 17 nodes |
| **Cost** | **$3,613/month** ⚡ | $1,568/month |
| **Cost per Site** | **$7.23/site** ⚡ | $3.14/site |
| **Philosophy** | Balanced - isolation + features | Cost-efficient |

**Design Rationale:**
- ✅ **Better per-site isolation** (25 vs 83 sites/node)
- ✅ **Dedicated cache tier** for performance + observability
- ✅ **Comprehensive alerting** for production readiness
- ✅ **Full automation** for operational efficiency
- ⚠️ **Higher cost** (+136% vs Opus), but more robust
- ⚠️ **More nodes to manage**, offset by automation

---

## Port Matrix

| Service | Internal Port | External Port | Protocol | Network |
|---------|--------------|---------------|----------|---------|
| **Ingress Layer** |
| Traefik HTTP | 80 | 80 | TCP | traefik-public |
| Traefik HTTPS | 443 | 443 | TCP | traefik-public |
| Traefik Dashboard | 8080 | - | TCP | management-net |
| Traefik Metrics | 8082 | - | TCP | observability-net |
| Varnish | 6081 | - | TCP | traefik-public |
| Varnish Admin | 6082 | - | TCP | management-net |
| **Application Layer** |
| WordPress/nginx | 80 | - | TCP | wordpress-net |
| PHP-FPM | 9000 | - | TCP | internal (unix socket) |
| Redis (per-site) | 6379 | - | TCP | wordpress-net |
| **Database Layer** |
| ProxySQL | 6033 | - | TCP | database-net |
| ProxySQL Admin | 6032 | - | TCP | management-net |
| MariaDB | 3306 | - | TCP | database-net |
| Galera Cluster (wsrep) | 4567 | - | TCP/UDP | database-net |
| Galera IST | 4568 | - | TCP | database-net |
| Galera SST (rsync) | 4444 | - | TCP | database-net |
| **Storage Layer** |
| GlusterFS Management | 24007 | - | TCP | storage-net |
| GlusterFS Bricks | 49152-49251 | - | TCP | storage-net |
| **Observability Layer** |
| Grafana | 3000 | - | TCP | observability-net |
| Mimir | 9009 | - | TCP | observability-net |
| Loki | 3100 | - | TCP | observability-net |
| Tempo | 3200 | - | TCP | observability-net |
| Alloy/OTel | 4317, 4318 | - | TCP | observability-net |
| Prometheus | 9090 | - | TCP | observability-net |
| Alertmanager | 9093 | - | TCP | observability-net |
| Promtail | 9080 | - | TCP | observability-net |
| Node Exporter | 9100 | - | TCP | observability-net |
| cAdvisor | 8080 | - | TCP | observability-net |
| **Management Layer** |
| Portainer | 9000, 9443 | - | TCP | management-net |
| Docker Registry | 5000 | - | TCP | management-net |
| **Security Layer** |
| CrowdSec LAPI | 8080 | - | TCP | crowdsec-net |
| CrowdSec Metrics | 6060 | - | TCP | observability-net |
| **Optional Central Cache** |
| Redis Cluster | 6379 | - | TCP | cache-net |
| Redis Sentinel | 26379 | - | TCP | cache-net |

---

## Firewall Rules (UFW/iptables)

### Manager Nodes (Public-facing)
```bash
# Allow from Cloudflare IPs only (HTTPS)
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

# Allow HTTP for Let's Encrypt validation
ufw allow from any to any port 80 proto tcp

# Docker Swarm
ufw allow from 10.0.0.0/16 to any port 2377 proto tcp  # Swarm management
ufw allow from 10.0.0.0/16 to any port 7946           # Node communication
ufw allow from 10.0.0.0/16 to any port 4789 proto udp  # Overlay network

# SSH (from bastion only)
ufw allow from 10.0.0.5 to any port 22 proto tcp
```

### All Internal Nodes (Workers, DB, Storage, Monitoring)
```bash
# Internal VPC only
ufw allow from 10.0.0.0/16

# Docker Swarm ports
ufw allow from 10.0.0.0/16 to any port 7946   # Node communication
ufw allow from 10.0.0.0/16 to any port 4789 proto udp  # Overlay network

# Deny all other inbound
ufw default deny incoming
ufw default allow outgoing

# Enable UFW
ufw enable
```

### Database Nodes (Additional Rules)
```bash
# Allow Galera cluster communication
ufw allow from 10.0.3.0/24 to any port 3306 proto tcp   # MySQL
ufw allow from 10.0.3.0/24 to any port 4567            # Galera cluster
ufw allow from 10.0.3.0/24 to any port 4568 proto tcp   # IST
ufw allow from 10.0.3.0/24 to any port 4444 proto tcp   # SST
```

### Storage Nodes (Additional Rules)
```bash
# Allow GlusterFS communication
ufw allow from 10.0.4.0/24 to any port 24007 proto tcp      # GlusterFS daemon
ufw allow from 10.0.4.0/24 to any port 49152:49251 proto tcp  # GlusterFS bricks
```

---

## Node Distribution Summary

### Total Infrastructure (500 Sites) - MODIFIED ARCHITECTURE

| Node Type | Quantity | Purpose | Monthly Cost |
|-----------|----------|---------|--------------|
| **Manager Nodes** | 3 | Swarm control plane + Traefik (NO Varnish) | $288 |
| **Cache Nodes** ⭐⚡ | 3 | Varnish + Redis + Sentinel (8GB nodes) | $144 |
| **Worker Nodes** | 20 | WordPress applications (~25 sites each) | $1,920 |
| **Database Nodes** | 3 | MariaDB Galera cluster + ProxySQL | $288 |
| **Storage Nodes** | 2 | GlusterFS distributed storage | $192 |
| **Monitoring Nodes** | 2 | LGTM stack + management + alerting | $192 |
| **Total Compute** | **33 nodes** (+3 cache) | All services | **$3,024** |
| **Block Storage** | 5TB | Database + Storage + Monitoring | $500 |
| **Load Balancer** | 1 | DO LB for HA | $12 |
| **Spaces** | 500GB | Backups | $10 |
| **Floating IPs** | 2 | Failover IPs | $12 |
| **Snapshots** | 100GB | System backups | $5 |
| **Alerting Services** | - | SendGrid (email) + Twilio (SMS) | $50 |
| **TOTAL** | - | - | **$3,613/month** |

**Cost per site:** $7.23/month  
**Cost increase vs original:** +$194/month (+5.7%) ⚡ OPTIMIZED  
**Target capacity:** 500 sites  
**Current density:** ~25 sites per worker node  
**Headroom:** ~20% capacity buffer for growth

**What Changed (OPTIMIZED):**
- ✅ Added 3 cache nodes 8GB (+$144/mo) ⚡ Downsized from 16GB
- ✅ Added alerting services (+$50/mo) - Slack/Email/SMS
- ✅ Managers simplified (removed Varnish) - Better isolation
- ✅ Removed redundant alerting stack - Use existing Alertmanager
- ✅ Total: +$194/month (was +$338) - saved $144 via optimization!

---

## Scaling Strategies

### Horizontal Scaling (Add More Workers)

```bash
# Provision new worker node
doctl compute droplet create wp-worker-21 \
  --size s-8vcpu-16gb \
  --region nyc3 \
  --image ubuntu-22-04-x64 \
  --vpc-uuid $VPC_UUID

# Join to swarm
docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377

# Label the node
docker node update --label-add app=wordpress wp-worker-21

# Services automatically rebalance across new node
```

### Capacity Planning (Modified Architecture with Dedicated Cache)

| Sites | Managers | Workers | Cache | DB | Storage | Monitor | Monthly Cost | Cost/Site |
|-------|----------|---------|-------|----|---------|---------| -------------|-----------|
| 100 | 3 | 4 | 3 | 3 | 2 | 2 | $1,794 | $17.94 |
| 250 | 3 | 10 | 3 | 3 | 2 | 2 | $2,570 | $10.28 |
| **500** | **3** | **20** | **3** | **3** | **2** | **2** | **$3,613** | **$7.23** |
| 750 | 3 | 30 | 3 | 3 | 2 | 2 | $4,994 | $6.66 |
| 1000 | 3 | 40 | 4 | 5 | 3 | 2 | $6,546 | $6.55 |

**Note:** Cost per site decreases with scale (economies of scale)

**Comparison to Original Sonnet 4.5:**
- 500 sites: $3,613 vs $3,419 = +$194/month (+5.7%) ⚡ OPTIMIZED
- Benefits: Dedicated cache tier + comprehensive alerting + full automation

**Comparison to Opus 4.5:**
- 500 sites: $3,613 vs $1,568 = +$2,045/month (+130%)
- Benefits: Lower density (25 vs 83 sites/node), more headroom, more isolation

**Optimizations Applied:**
- ⚡ Cache nodes downsized 16GB→8GB (saves $144/month)
- ⚡ Removed redundant alerting stack (simplified architecture)
- ⚡ Use existing Alertmanager (in monitoring stack)

---

## High Availability Features

### Service-Level HA
- ✅ Health checks every 10 seconds
- ✅ Automatic container restart on failure
- ✅ Load balancing across healthy replicas
- ✅ Sticky sessions for WordPress admin
- ✅ Circuit breakers prevent cascade failures

### Infrastructure-Level HA
- ✅ 3 Swarm managers (tolerates 1 failure, Raft quorum)
- ✅ Galera multi-master (no single point of failure)
- ✅ GlusterFS replica 2 (survives 1 storage node failure)
- ✅ Floating IPs with automatic failover
- ✅ Redis Sentinel (if using central Redis)

### Network-Level HA
- ✅ Cloudflare DDoS protection
- ✅ Multiple Traefik replicas
- ✅ DO Load Balancer health checks
- ✅ Encrypted overlay networks
- ✅ Automatic DNS failover

---

## Summary

This **MODIFIED Sonnet 4.5** network topology incorporates best practices from multiple strategies:

### Architecture Enhancements
1. **Scalability**: 20 worker nodes supporting 500 sites with room to grow
2. **High Availability**: Multi-node redundancy at every layer
3. **Performance**: Multi-tier caching with dedicated cache nodes (Opus 4.5 style)
   - Cloudflare CDN → Traefik → **Dedicated Varnish Tier** → WordPress → Redis → OPcache
4. **Security**: CrowdSec, encrypted networks, Cloudflare WAF
5. **Observability**: Full LGTM stack with metrics, logs, and traces
6. **Alerting**: Multi-channel (Slack, Email, SMS) for 24/7 awareness
7. **Automation**: Complete orchestration via `manage-infrastructure.sh`
8. **Manageability**: Portainer, automated backups, centralized monitoring

### Key Improvements from Original Sonnet 4.5
- ✅ **Dedicated cache tier** (3 nodes) - Better performance isolation
- ✅ **Comprehensive alerting** - Slack, Email, SMS
- ✅ **Full automation** - One-command deployment
- ✅ **Better observability** - Isolated metrics per tier

### Infrastructure Specs
- **Total Nodes:** 33 (Managers: 3, Workers: 20, Cache: 3@8GB⚡, DB: 3, Storage: 2, Monitor: 2)
- **Total Cost:** $3,613/month ($7.23/site) ⚡ OPTIMIZED
- **Cost Increase:** +$194/month vs original (+5.7%) - Down from +$338 via optimizations
- **Target Uptime:** 99.9%
- **Recovery Time:** < 5 seconds (automated failover)
- **Deployment Time:** ~45 minutes (fully automated)

### Best For
- Production WordPress farms requiring enterprise-grade features
- Teams valuing observability and operational excellence
- Organizations with 24/7 monitoring requirements
- Deployments where $194/month (+5.7%) is acceptable for better reliability


