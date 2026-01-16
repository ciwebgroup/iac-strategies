# 🚀 WordPress Farm Infrastructure

A production-grade, high-availability WordPress hosting platform for 500+ sites using Docker Swarm, Traefik, and the LGTM observability stack.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Infrastructure Components](#infrastructure-components)
- [Deployment Guide](#deployment-guide)
- [Site Management](#site-management)
- [Monitoring & Observability](#monitoring--observability)
- [Security](#security)
- [Backup & Recovery](#backup--recovery)
- [Scaling](#scaling)
- [Cost Estimates](#cost-estimates)

---

## Overview

This repository contains a complete infrastructure-as-code solution for hosting a WordPress farm with:

- ✅ **High Availability** - Multi-node cluster with automatic failover
- ✅ **Load Balancing** - Traefik with intelligent routing
- ✅ **Multi-Layer Caching** - Cloudflare + Varnish + Redis
- ✅ **Security** - CrowdSec, WAF, rate limiting, and hardening
- ✅ **Observability** - Full LGTM stack (Loki, Grafana, Tempo, Mimir)
- ✅ **Automated Backups** - Database and file backups to S3
- ✅ **Easy Management** - Portainer UI and CLI tools

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               CLOUDFLARE                                     │
│                    (DNS, CDN, DDoS Protection, WAF)                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DOCKER SWARM CLUSTER                                │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  EDGE: Traefik (3x) + CrowdSec                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  CACHE: Varnish (3x) + Redis Sentinel (3x)                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  APP: WordPress Containers (nginx + PHP-FPM) × N                       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  DATA: MariaDB Galera (3x) + ProxySQL (2x)                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  OPS: Grafana + Mimir + Loki + Tempo + Portainer                       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed documentation.

---

## Quick Start

### Prerequisites

- 3+ Digital Ocean Droplets (16GB / 8 CPU recommended)
- Cloudflare account (free tier works)
- Domain name pointed to Cloudflare

### 1. Initialize the First Manager Node

```bash
# Clone the repository
git clone <repo-url> /var/opt/wordpress-farm
cd /var/opt/wordpress-farm

# Make scripts executable
chmod +x scripts/*.sh

# Initialize the Swarm cluster
./scripts/init-cluster.sh
```

### 2. Join Additional Nodes

On each additional node, run the join command provided by `init-cluster.sh`:

```bash
# For manager nodes:
docker swarm join --token <manager-token> <manager-ip>:2377

# For worker nodes:
docker swarm join --token <worker-token> <manager-ip>:2377
```

### 3. Label Nodes

```bash
# App workers
docker node update --label-add app=true <node-id>

# Cache nodes
docker node update --label-add cache=true <node-id>

# Database nodes (label each with unique db-node number)
docker node update --label-add db=true --label-add db-node=1 <node-id>

# Ops node
docker node update --label-add ops=true <node-id>
```

### 4. Configure Environment

```bash
cp config/env.example .env
nano .env  # Fill in your values
```

### 5. Deploy Stacks

```bash
# Deploy in order (dependencies)
docker stack deploy -c docker/compose/crowdsec.yml crowdsec
docker stack deploy -c docker/compose/traefik.yml traefik
docker stack deploy -c docker/compose/database.yml database
docker stack deploy -c docker/compose/cache.yml cache
docker stack deploy -c docker/compose/observability.yml observability
docker stack deploy -c docker/compose/management.yml management
```

### 6. Create Your First Site

```bash
./scripts/site-create.sh mysite.com --admin-email admin@mysite.com
```

---

## Infrastructure Components

### Edge Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| Traefik | Reverse proxy, SSL termination | 3 (global on managers) |
| CrowdSec | Collaborative threat detection | Global + 1 LAPI |

### Cache Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| Varnish | Full page cache | 3 |
| Redis | Object cache, sessions | 3 (1 master + 2 replicas) |
| Redis Sentinel | HA failover | 3 |

### Application Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| WordPress | Custom image (nginx + PHP-FPM) | 1 per site (scalable) |

### Database Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| MariaDB Galera | Multi-master database | 3 |
| ProxySQL | Connection pooling, query routing | 2 |

### Observability Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| Grafana | Dashboards & visualization | 1 |
| Mimir | Metrics storage (Prometheus-compatible) | 1 |
| Loki | Log aggregation | 1 |
| Tempo | Distributed tracing | 1 |
| Alloy | Telemetry collector | Global |
| Node Exporter | System metrics | Global |
| cAdvisor | Container metrics | Global |

### Management Layer
| Component | Purpose | Replicas |
|-----------|---------|----------|
| Portainer | Container management UI | 1 |
| Backup Service | Automated backups | 2 (DB + Files) |
| WP-CLI | WordPress management | 1 |

---

## Site Management

### Create a New Site

```bash
./scripts/site-create.sh example.com \
  --admin-email admin@example.com \
  --title "My Website" \
  --scale 2
```

### Scale a Site

```bash
docker service scale wp-example_com_wordpress-example_com=3
```

### Remove a Site

```bash
docker stack rm wp-example_com
# Then remove database and files manually
```

### Update All Sites

```bash
# Update WordPress core
docker exec $(docker ps -q -f name=wp-cli) wp core update --all-sites

# Update plugins
docker exec $(docker ps -q -f name=wp-cli) wp plugin update --all --all-sites
```

---

## Monitoring & Observability

### Grafana Dashboards

Access Grafana at `https://grafana.yourdomain.com`

Pre-configured dashboards:
- Cluster Overview
- Traefik Metrics
- WordPress Performance
- Database Health
- Cache Hit Rates
- Security Events

### Alerting

Configure alerts in `docker/configs/alertmanager/alertmanager.yml`:
- Slack integration
- Email notifications
- PagerDuty integration

---

## Security

### Multi-Layer Defense

1. **Cloudflare** - DDoS, WAF, Bot Management
2. **Traefik** - Rate limiting, IP whitelisting
3. **CrowdSec** - Collaborative threat intelligence
4. **Application** - WordPress hardening plugins

### Hardening Applied

- XML-RPC disabled
- Login rate limiting
- Security headers (HSTS, CSP, X-Frame)
- File editing disabled
- Version information hidden
- Author enumeration blocked

---

## Backup & Recovery

### Automatic Backups

- **Database**: Every 6 hours
- **Files**: Daily at 2 AM
- **Retention**: 30 days

### Manual Backup

```bash
# Database backup
docker exec $(docker ps -q -f name=backup-db) /backup.sh

# File backup
docker exec $(docker ps -q -f name=backup-files) /backup.sh
```

### Restore

```bash
# See scripts/restore.sh for full restore procedure
./scripts/restore.sh example.com 2024-01-15
```

---

## Scaling

### Horizontal Scaling

```bash
# Add more app workers
docker node update --label-add app=true <new-node-id>

# Scale specific site
docker service scale wp-site_wordpress=5
```

### Vertical Scaling

Upgrade droplet sizes in Digital Ocean, then restart services.

### Capacity Guidelines

| Sites | App Workers | DB Nodes | Cache Nodes |
|-------|-------------|----------|-------------|
| 100 | 3 | 3 | 2 |
| 250 | 4 | 3 | 2 |
| 500 | 6 | 3 | 3 |
| 1000+ | 10+ | 5+ | 4+ |

---

## Cost Estimates

### 500 Sites Configuration (Digital Ocean)

| Component | Nodes | Spec | Monthly |
|-----------|-------|------|---------|
| Managers | 3 | 16GB/8vCPU | $288 |
| App Workers | 6 | 16GB/8vCPU | $576 |
| Database | 3 | 16GB/8vCPU | $288 |
| Cache | 3 | 16GB/8vCPU | $288 |
| Observability | 1 | 16GB/8vCPU | $96 |
| Spaces (1TB) | - | - | $20 |
| Load Balancer | 1 | - | $12 |
| **Total** | **17** | - | **~$1,568** |

**Cost per site: ~$3.14/month**

---

## Directory Structure

```
wordpress-farm/
├── ARCHITECTURE.md          # Detailed architecture documentation
├── README.md                 # This file
├── config/
│   └── env.example          # Environment template
├── diagrams/
│   └── NETWORK-TOPOLOGY.md  # Network topology diagrams
├── docker/
│   ├── compose/             # Docker Swarm stack files
│   │   ├── cache.yml
│   │   ├── crowdsec.yml
│   │   ├── database.yml
│   │   ├── management.yml
│   │   ├── observability.yml
│   │   ├── traefik.yml
│   │   └── wordpress-template.yml
│   ├── configs/             # Service configurations
│   │   ├── traefik/
│   │   ├── varnish/
│   │   └── ...
│   └── images/              # Custom Docker images
│       └── wordpress/
└── scripts/
    ├── init-cluster.sh      # Cluster initialization
    └── site-create.sh       # Site creation automation
```

---

## Support

For issues and feature requests, please open a GitHub issue.

---

## License

MIT License - See LICENSE file for details.


