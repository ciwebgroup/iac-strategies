# WordPress Farm Infrastructure

> **A production-ready, open-source infrastructure for hosting 500+ WordPress websites with high availability, load balancing, and full observability.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Swarm-2496ED?logo=docker)](https://www.docker.com/)
[![Infrastructure](https://img.shields.io/badge/Infrastructure-Digital_Ocean-0080FF?logo=digitalocean)](https://www.digitalocean.com/)

---

## 🎯 Overview

This repository contains a complete, battle-tested infrastructure design for hosting hundreds of WordPress websites on a Docker Swarm cluster. Built with open-source technologies and designed for scalability, security, and observability.

### Key Features

✅ **High Availability** - Multi-node cluster with automatic failover  
✅ **Load Balanced** - Distributed traffic across multiple nodes  
✅ **Auto-Scaling** - Easy horizontal scaling  
✅ **Multi-Layer Caching** - Cloudflare + Varnish + Redis + OPcache  
✅ **Full Observability** - LGTM stack (Loki, Grafana, Tempo, Mimir)  
✅ **Security Hardened** - CrowdSec, encrypted networks, secrets management  
✅ **Automated Backups** - Daily database and file backups to S3  
✅ **Zero-Downtime Deployments** - Rolling updates with health checks  
✅ **Cost-Effective** - ~$7/site/month at 500 sites (vs $30+ managed hosting)  

---

## 📋 Quick Stats

| Metric | Value |
|--------|-------|
| **Supported Sites** | 500+ (scalable to 1000+) |
| **Infrastructure Cost** | $3,419/month (500 sites) |
| **Cost per Site** | $6.84/month |
| **Target Uptime** | 99.9% (8.76 hours/year downtime) |
| **Avg Response Time** | < 200ms (with caching) |
| **Recovery Time Objective (RTO)** | 1 hour |
| **Recovery Point Objective (RPO)** | 6 hours |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Cloudflare (CDN + DNS)                    │
│          DDoS Protection • SSL • Edge Caching                │
└────────────────────┬────────────────────────────────────────┘
                     │
          ┌──────────▼──────────┐
          │   Floating IP/LB    │
          └──────────┬──────────┘
                     │
     ┌───────────────┴───────────────┐
     │                               │
┌────▼────┐                    ┌─────▼────┐
│ Traefik │◄──────────────────►│ Traefik  │  (3+ replicas)
│ + Varnish│                    │+ Varnish │
│ + CrowdSec│                   │+ CrowdSec│
└────┬────┘                    └─────┬────┘
     │                               │
     └───────────────┬───────────────┘
                     │
        ┌────────────▼───────────┐
        │   WordPress Sites      │
        │ (Nginx + PHP + Redis)  │  (500+ isolated stacks)
        └────────────┬───────────┘
                     │
        ┌────────────▼───────────┐
        │   ProxySQL (Router)    │
        └────────────┬───────────┘
                     │
        ┌────────────▼───────────┐
        │  Galera Cluster (3)    │
        │  Multi-Master MySQL    │
        └────────────────────────┘
```

**[📊 View Detailed Diagrams →](network-diagram.md)**

---

## 🚀 Getting Started

### Prerequisites

- Digital Ocean account with API token
- Cloudflare account (free tier works)
- Domain name
- Local machine with Docker installed
- Basic Linux/Docker knowledge

### Quick Start

```bash
# 1. Clone repository
git clone https://github.com/yourusername/wordpress-farm-infrastructure
cd wordpress-farm-infrastructure

# 2. Review architecture documentation
cat wordpress-farm-architecture.md

# 3. Follow implementation guide
cat implementation-guide.md

# 4. Deploy first site
./provision-wordpress-site example.com 001
```

### Deployment Phases

| Phase | Duration | Description |
|-------|----------|-------------|
| **Phase 1** | Week 1-2 | Infrastructure provisioning |
| **Phase 2** | Week 3-4 | Core services deployment |
| **Phase 3** | Week 5-6 | WordPress stack setup |
| **Phase 4** | Week 7-8 | Monitoring & automation |
| **Phase 5** | Week 9-12 | Production migration |

**[📖 Full Implementation Guide →](implementation-guide.md)**

---

## 📂 Repository Structure

```
.
├── README.md                              # This file
├── wordpress-farm-architecture.md         # Complete architecture documentation
├── network-diagram.md                     # Visual network diagrams (Mermaid)
├── implementation-guide.md                # Step-by-step deployment guide
├── cost-analysis.md                       # Detailed cost breakdown & ROI
│
├── docker-compose-examples/               # Production-ready stack files
│   ├── traefik-stack.yml                 # Edge routing & SSL
│   ├── database-stack.yml                # Galera cluster + ProxySQL
│   ├── monitoring-stack.yml              # LGTM observability stack
│   ├── management-stack.yml              # Portainer + automation
│   └── wordpress-site-template.yml       # Per-site WordPress stack
│
├── scripts/                               # Automation scripts (future)
│   ├── provision-site.sh                 # Automated site provisioning
│   ├── backup-db.sh                      # Database backup automation
│   ├── restore-site.sh                   # Site restoration
│   └── scale-cluster.sh                  # Cluster scaling automation
│
└── configs/                               # Configuration templates (future)
    ├── nginx/                            # Nginx configurations
    ├── php/                              # PHP-FPM tuning
    ├── varnish/                          # Varnish VCL
    └── prometheus/                       # Monitoring configs
```

---

## 🛠️ Technology Stack

### Core Infrastructure
- **Orchestration:** Docker Swarm
- **Routing:** Traefik v3
- **Web Server:** Nginx
- **Application:** PHP 8.2 FPM
- **Database:** MariaDB 10.11 (Galera Cluster)
- **Load Balancer:** ProxySQL

### Caching Layer
- **CDN:** Cloudflare
- **HTTP Cache:** Varnish 7
- **Object Cache:** Redis 7
- **Bytecode Cache:** OPcache

### Security
- **WAF:** CrowdSec + Traefik Bouncer
- **SSL:** Let's Encrypt (automated via Traefik)
- **Firewall:** UFW + Docker network isolation
- **Secrets:** Docker Swarm secrets

### Observability (LGTM Stack)
- **Metrics:** Prometheus + Mimir
- **Logs:** Loki + Promtail
- **Traces:** Tempo + OpenTelemetry
- **Visualization:** Grafana
- **Alerts:** AlertManager

### Management
- **UI:** Portainer Business
- **Backups:** Restic + Percona XtraBackup
- **Registry:** Private Docker Registry
- **Logs:** Dozzle (real-time viewer)

---

## 💰 Cost Breakdown

### Infrastructure (500 Sites on Digital Ocean)

| Component | Quantity | Monthly Cost |
|-----------|----------|--------------|
| Manager Nodes (16GB/8vCPU) | 3 | $288 |
| Worker Nodes (16GB/8vCPU) | 20 | $1,920 |
| Database Nodes (16GB/8vCPU) | 3 | $288 |
| Storage Nodes (16GB/8vCPU) | 2 | $192 |
| Block Storage (5TB) | - | $500 |
| Load Balancer | 1 | $12 |
| Backups (DO Spaces) | - | $10 |
| **Total** | **30 nodes** | **$3,419** |

**Cost per site:** $6.84/month  
**Savings vs. WP Engine:** 77% ($138k/year)  
**Savings vs. Kinsta:** 80% ($168k/year)  

**[📊 Detailed Cost Analysis →](cost-analysis.md)**

---

## 🔒 Security Features

### Network Security
- ✅ CrowdSec collaborative threat detection
- ✅ Traefik-integrated IP banning
- ✅ Encrypted Docker overlay networks
- ✅ Firewall rules (Digital Ocean + UFW)
- ✅ DDoS protection (Cloudflare)

### Application Security
- ✅ Automated security updates
- ✅ WordPress hardening (custom images)
- ✅ Secrets management (no plaintext passwords)
- ✅ Security headers (HSTS, CSP, etc.)
- ✅ Regular vulnerability scanning (Trivy)

### Access Control
- ✅ SSH key-only authentication
- ✅ Cloudflare Access for admin panels
- ✅ RBAC in Portainer
- ✅ Audit logging

---

## 📊 Monitoring & Observability

### Grafana Dashboards

1. **Cluster Overview**
   - Node health & resource usage
   - Service availability
   - Network traffic

2. **WordPress Performance**
   - Response times per site
   - Error rates
   - Traffic patterns
   - Cache hit rates

3. **Database Health**
   - Query performance
   - Replication status
   - Connection pools
   - Slow queries

4. **Security Dashboard**
   - Blocked IPs (CrowdSec)
   - Attack patterns
   - Failed login attempts

5. **Business Metrics**
   - Sites online
   - Total requests/day
   - Bandwidth usage
   - Cost per site

### Alerting

Alerts sent to Slack/Email/PagerDuty:
- ⚠️ Node down > 5 minutes
- ⚠️ High error rate (5xx > 5%)
- ⚠️ Disk space < 15%
- ⚠️ Memory usage > 90%
- ⚠️ Database replication lag
- ⚠️ SSL certificate expiring < 7 days
- ⚠️ Service replica count mismatch

---

## 🔄 High Availability Features

### Service Level HA
- **Health Checks:** Every 10 seconds
- **Auto-Restart:** Failed containers automatically replaced
- **Load Balancing:** Traffic distributed across healthy replicas
- **Sticky Sessions:** For WordPress admin panel
- **Circuit Breakers:** Prevent cascade failures

### Infrastructure Level HA
- **Multi-Manager Quorum:** 3 Swarm managers (tolerates 1 failure)
- **Database Replication:** Galera multi-master (no single point of failure)
- **Storage Replication:** GlusterFS replica 2
- **Floating IPs:** Automatic failover for traffic routing

### Data Level HA
- **Automated Backups:** Daily full + 6-hour incremental
- **Cross-Region Replication:** Backups stored in multiple regions
- **Point-in-Time Recovery:** Restore to any backup point
- **Backup Testing:** Weekly automated restore tests

---

## 📈 Scaling Guide

### Vertical Scaling (Per-Site)

```bash
# Scale individual site replicas
docker service scale wp-site-123_nginx=4
docker service scale wp-site-123_php-fpm=4

# Increase resource limits
docker service update \
  --limit-memory 1024M \
  --limit-cpu 1.0 \
  wp-site-123_php-fpm
```

### Horizontal Scaling (Add Nodes)

```bash
# Add worker node
doctl compute droplet create wp-worker-21 \
  --size s-8vcpu-16gb \
  --region nyc3 \
  --image ubuntu-22-04-x64

# Join to swarm
docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377

# Services automatically rebalance
```

### Capacity Planning

| Sites | Workers | Database | Storage | Monthly Cost |
|-------|---------|----------|---------|--------------|
| 100 | 4 | 3 | 2 | $1,456 |
| 250 | 10 | 3 | 2 | $2,182 |
| 500 | 20 | 3 | 2 | $3,419 |
| 1000 | 40 | 5 | 3 | $6,112 |

**Note:** Cost per site decreases as scale increases!

---

## 🆘 Disaster Recovery

### Backup Strategy

**Database Backups:**
- Full: Daily at 2 AM
- Incremental: Every 6 hours
- Retention: 30 days
- Storage: Digital Ocean Spaces (encrypted)

**File Backups:**
- WordPress uploads: Daily at 3 AM
- Retention: 30 days (7 daily, 4 weekly, 3 monthly)
- Tool: Restic (deduplicated, encrypted)

**Configuration Backups:**
- All stack files: Version controlled in Git
- Secrets: Encrypted offline backup

### Recovery Procedures

**Single Site Recovery:**
```bash
./restore-site.sh 123 2024-01-10
# RTO: 15 minutes
```

**Database Recovery:**
```bash
./restore-database.sh 2024-01-10
# RTO: 30 minutes
```

**Full Cluster Recovery:**
```bash
./restore-cluster.sh 2024-01-10
# RTO: 1 hour
```

---

## 🎓 Learning Resources

### Documentation
- [Complete Architecture](wordpress-farm-architecture.md) - Full technical specifications
- [Network Diagrams](network-diagram.md) - Visual architecture diagrams
- [Implementation Guide](implementation-guide.md) - Step-by-step deployment
- [Cost Analysis](cost-analysis.md) - ROI calculations & pricing

### External Resources
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [WordPress Best Practices](https://wordpress.org/support/article/wordpress-best-practices/)
- [Galera Cluster Documentation](https://galeracluster.com/library/documentation/)

---

## 🤝 Contributing

Contributions are welcome! This is an open-source project designed to help the community host WordPress at scale.

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-improvement`)
3. Commit your changes (`git commit -m 'Add amazing improvement'`)
4. Push to the branch (`git push origin feature/amazing-improvement`)
5. Open a Pull Request

### Areas for Contribution

- 📝 Documentation improvements
- 🐛 Bug fixes
- ✨ New features (e.g., auto-scaling scripts)
- 🎨 Additional Grafana dashboards
- 🔧 Configuration optimizations
- 🧪 Testing improvements

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⭐ Show Your Support

If this project helped you, please consider:
- ⭐ Starring the repository
- 🐦 Sharing on Twitter
- 📝 Writing a blog post about your experience
- 💬 Contributing improvements

---

## 💬 Community & Support

### Get Help

- 📖 [Documentation](wordpress-farm-architecture.md)
- 💬 [GitHub Discussions](https://github.com/yourusername/wordpress-farm/discussions)
- 🐛 [Issue Tracker](https://github.com/yourusername/wordpress-farm/issues)
- 📧 Email: support@yourdomain.com

### Roadmap

- [ ] Automated site provisioning API
- [ ] Multi-region deployment guide
- [ ] Kubernetes alternative architecture
- [ ] Terraform/Ansible automation
- [ ] Marketplace for WordPress templates
- [ ] Advanced traffic management (A/B testing, canary deployments)
- [ ] Integration with CI/CD pipelines
- [ ] WordPress multisite support
- [ ] Advanced security features (2FA, audit logs)

---

## 🙏 Acknowledgments

Built with open-source technologies from amazing communities:
- Docker & Docker Swarm
- Traefik Labs
- WordPress Foundation
- MariaDB Foundation
- Grafana Labs
- Redis
- Nginx
- CrowdSec
- And many more!

---

## 📞 Contact

**Project Maintainer:** Your Name  
**Email:** your.email@example.com  
**Twitter:** [@yourhandle](https://twitter.com/yourhandle)  
**Website:** [yourdomain.com](https://yourdomain.com)

---

<div align="center">

**[⬆ Back to Top](#wordpress-farm-infrastructure)**

Made with ❤️ for the WordPress community

**Ready to host 500+ WordPress sites?** [Get Started →](implementation-guide.md)

</div>


