# WordPress Farm Infrastructure Architecture

## Executive Summary

This architecture supports 500+ WordPress websites with high availability, load balancing, automatic backups, and full redundancy using Docker Swarm orchestration on Digital Ocean infrastructure.

## Architecture Overview

### Core Design Principles
1. **High Availability**: Multi-node cluster with automatic failover
2. **Horizontal Scalability**: Easy addition of worker nodes
3. **Security-First**: Multi-layer security approach
4. **Observability**: Full-stack monitoring and tracing
5. **Performance**: Multi-tier caching strategy
6. **Disaster Recovery**: Automated backup and restore procedures

---

## Infrastructure Layers

### 1. Container Orchestration Layer
**Technology**: Docker Swarm (chosen over K8s for operational simplicity)

**Why Docker Swarm over Kubernetes:**
- Native Docker integration (matches existing infrastructure)
- Lower operational overhead
- Sufficient for 500+ sites
- Built-in load balancing and service discovery
- Simpler secrets management
- Easier to maintain for smaller teams

**Cluster Configuration:**

#### Manager Nodes (3 nodes - HA quorum)
- **Purpose**: Cluster orchestration, scheduling, and management
- **Specs**: 16GB RAM / 8 vCPU each
- **Role**: Control plane only (no workload)
- **HA**: 3-node quorum (survives 1 node failure)

#### Worker Nodes (6+ nodes - scalable)
- **Purpose**: WordPress application workload
- **Specs**: 16GB RAM / 8 vCPU each
- **Capacity**: ~80-100 sites per node (conservative estimate)
- **Scaling**: Add nodes as you approach 500 sites

#### Database Cluster Nodes (3 nodes - dedicated)
- **Purpose**: MySQL/MariaDB Galera cluster
- **Specs**: 16GB RAM / 8 vCPU each
- **Config**: Multi-master replication with read/write splitting

#### Storage/NFS Nodes (2 nodes - redundant)
- **Purpose**: Shared persistent storage for WordPress uploads/plugins
- **Specs**: 16GB RAM / 8 vCPU + Block Storage
- **Tech**: GlusterFS or NFS with DRBD for replication

**Total Base Cluster**: 14 nodes

---

### 2. Network & Routing Layer (Traefik)

**Traefik v3.x Configuration:**

```yaml
# Core Features Enabled:
- HTTP/HTTPS routing with automatic HTTPS (Let's Encrypt)
- TCP routing (for MySQL connections if needed)
- Dynamic service discovery
- Automatic SSL certificate management
- Rate limiting
- Circuit breakers
- Sticky sessions for WordPress
- HTTP/2 and HTTP/3 support
```

**Network Architecture:**

1. **External Network** (`traefik-public`)
   - Ingress traffic from internet
   - Traefik edge routers
   - CrowdSec integration

2. **Application Networks** (per-site isolation)
   - `wp-site-{id}` - Isolated network per WordPress site
   - PHP-FPM, Nginx, Redis per site

3. **Shared Services Network** (`shared-services`)
   - Database cluster
   - Central Redis/Memcached
   - Monitoring services

4. **Management Network** (`management`)
   - Portainer
   - Backup services
   - Internal tools

**Traefik Deployment:**
- 3+ replicas across multiple nodes
- Deployed on manager nodes with `--constraint node.role==manager`
- Bound to host ports 80, 443
- Priority: Keep-alive routing with health checks

---

### 3. Security Layer

#### 3.1 Network Security

**CrowdSec** (Recommended over Fail2ban)
- **Why**: Distributed, collaborative threat intelligence
- **Deployment**: 
  - CrowdSec agent on each Traefik node
  - Traefik bouncer integration
  - Central Security API on manager nodes
- **Features**:
  - Real-time IP reputation
  - Automatic ban/unban
  - Community blocklists
  - Machine learning anomaly detection

**Firewall Strategy:**
```
External Firewall (Digital Ocean):
- Allow: 80, 443 (HTTP/HTTPS) → Traefik nodes only
- Allow: 22 (SSH) → Management IPs only (Cloudflare Zero Trust)
- Block: All other inbound

Internal Firewall (iptables/nftables):
- Docker network isolation
- Swarm overlay encryption enabled
- Manager nodes: 2377/tcp (cluster management)
- All nodes: 7946/tcp+udp, 4789/udp (overlay network)
```

#### 3.2 Application Security

**WordPress Hardening:**
- Custom WordPress Docker images with:
  - Security headers (via Traefik middleware)
  - Disabled XML-RPC (unless needed)
  - Limit login attempts (CrowdSec integration)
  - File permission hardening
  - No wp-admin access to internet (VPN/Cloudflare Access only)

**SSL/TLS:**
- Traefik automatic HTTPS with Let's Encrypt
- TLS 1.2+ only
- HSTS enabled
- OCSP stapling

**Secrets Management:**
- Docker Swarm secrets for all credentials
- Rotation policy: 90 days
- No secrets in environment variables
- Vault integration (optional, for advanced secret management)

---

### 4. Caching Layer (Multi-Tier)

#### Tier 1: CDN (Cloudflare)
- **What**: Static assets, images, CSS, JS
- **Cache**: Edge locations worldwide
- **Configuration**:
  - Full page caching for logged-out users
  - Bypass cache for /wp-admin, /wp-login
  - Polish (image optimization)
  - Mirage (lazy loading)
  - Argo Smart Routing (optional, paid)

#### Tier 2: Varnish (HTTP Cache)
- **Deployment**: Sidecar container with each Traefik replica
- **Purpose**: Full page caching for anonymous users
- **Cache Rules**:
  - Cache: Homepage, posts, pages (logged-out)
  - Bypass: /wp-admin, /wp-login, ?add-to-cart
  - TTL: 1 hour (adjustable per site)
  - Purge: Automatic on post updates (WP plugin integration)

#### Tier 3: Redis (Object Cache)
- **Deployment**: 
  - Shared Redis cluster (3 masters, 3 replicas) on dedicated nodes
  - OR per-site Redis containers (better isolation, more resources)
- **Purpose**: 
  - WordPress object cache (database queries)
  - Session storage
  - Transient API cache
- **Configuration**:
  - Redis Sentinel for HA
  - LRU eviction policy
  - 4GB per instance (adjust per load)

#### Tier 4: OPcache (PHP)
- **Deployment**: Built into PHP-FPM containers
- **Purpose**: PHP bytecode caching
- **Configuration**:
  - `opcache.memory_consumption=256M`
  - `opcache.max_accelerated_files=20000`
  - `opcache.revalidate_freq=60`

#### Optional: Memcached
- Use if some WordPress plugins require it
- Otherwise, Redis covers all use cases

**Recommended Caching Plugin**: WP Redis or W3 Total Cache (configured for Redis)

---

### 5. Observability Layer (LGTM Stack)

#### 5.1 Metrics (Mimir/Prometheus)

**Prometheus + Mimir (long-term storage)**

**Monitoring Targets:**
- **Infrastructure Metrics** (node-exporter):
  - CPU, Memory, Disk, Network per node
  - Swarm service health
  
- **Container Metrics** (cAdvisor):
  - Per-container resource usage
  - Container restart counts
  - Image pull durations

- **Application Metrics** (custom exporters):
  - PHP-FPM status
  - Nginx metrics
  - MySQL/MariaDB metrics
  - Redis metrics
  - Traefik metrics (built-in)

- **WordPress Metrics** (custom exporter):
  - Response times per site
  - Plugin/theme versions
  - User counts
  - Post counts
  - Update availability

**Alerting Rules:**
- Node down > 5 minutes
- Disk usage > 85%
- Memory usage > 90%
- Service replica count < expected
- MySQL replication lag > 10s
- High error rates (5xx) > 5%
- Certificate expiry < 7 days

#### 5.2 Logs (Loki)

**Loki Configuration:**
- Centralized log aggregation
- 30-day retention (adjustable)
- Compression enabled

**Log Sources:**
- All container stdout/stderr
- Traefik access logs
- CrowdSec logs
- MySQL slow query logs
- PHP error logs
- System logs (syslog)

**Log Processing:**
- Structured JSON logging
- Automatic label extraction
- LogQL queries in Grafana

#### 5.3 Traces (Tempo)

**OpenTelemetry Integration:**
- PHP auto-instrumentation (via OTel PHP extension)
- Trace full request lifecycle:
  - Traefik → Nginx → PHP-FPM → MySQL
- Identify slow database queries
- Detect N+1 query problems
- Trace cross-service calls

#### 5.4 Visualization (Grafana)

**Dashboards:**
1. **Cluster Overview**: Node health, resource usage
2. **WordPress Farm**: Per-site metrics, response times
3. **Database Health**: Query times, replication status
4. **Cache Performance**: Hit rates, memory usage
5. **Security Dashboard**: CrowdSec bans, blocked IPs
6. **Traffic Overview**: Requests/sec, bandwidth
7. **Application Performance**: Apdex scores, error rates

**Alerting Channels:**
- Email
- Slack/Discord webhooks
- PagerDuty (for critical alerts)
- Telegram (optional)

---

### 6. Management Layer

#### 6.1 Portainer (Container Management)

**Deployment:**
- Portainer Business Edition (for multi-cluster support)
- Deployed on manager nodes
- Accessible via Traefik (with Cloudflare Access for security)

**Features:**
- Visual stack management
- Service scaling
- Log viewing
- Container stats
- Registry management
- Role-based access control (RBAC)

#### 6.2 Backup Strategy

**Database Backups:**
- **Tool**: Percona XtraBackup or mysqldump
- **Frequency**: 
  - Full backup: Daily at 2 AM
  - Incremental: Every 6 hours
- **Retention**: 30 days
- **Storage**: 
  - Digital Ocean Spaces (S3-compatible)
  - Encrypted with GPG
  - Cross-region replication

**WordPress File Backups:**
- **Tool**: Restic or Duplicati
- **Frequency**: Daily at 3 AM
- **What**: `/var/www/html/wp-content/uploads` per site
- **Retention**: 30 days (7 daily, 4 weekly, 3 monthly)
- **Storage**: Digital Ocean Spaces

**Configuration Backups:**
- **Tool**: Git + automation
- **Frequency**: On every change (automated)
- **What**: All docker-compose files, Traefik configs
- **Storage**: Private Git repository

**Disaster Recovery Plan:**
- RTO (Recovery Time Objective): 1 hour
- RPO (Recovery Point Objective): 6 hours
- Automated restore testing: Weekly
- Full DR drill: Quarterly

#### 6.3 Deployment & Orchestration

**CI/CD Pipeline (GitLab CI or GitHub Actions):**
1. Build custom WordPress images
2. Run security scans (Trivy)
3. Push to private registry
4. Deploy to staging
5. Automated tests
6. Deploy to production (blue-green)

**WordPress Site Provisioning:**
- Automated via API or CLI tool
- Template stack: Nginx + PHP-FPM + Redis
- Automatic DNS creation (Cloudflare API)
- Automatic SSL certificate
- Database user creation
- Backup configuration

#### 6.4 Monitoring & Maintenance

**Automated Updates:**
- Docker image updates: Weekly (staged rollout)
- WordPress core/plugins: Manual (via Portainer or WP-CLI)
- Security patches: Immediate (automated)

**Health Checks:**
- Traefik health checks: Every 10s
- Service restart on failure: Automatic (max 3 retries)
- Node health: Monitored by Prometheus

---

## Site Isolation Strategy

### Per-Site Architecture

Each WordPress site runs in an isolated stack:

```yaml
services:
  nginx-{site-id}:
    image: custom/nginx-wordpress:latest
    networks:
      - wp-site-{site-id}
      - traefik-public
    volumes:
      - site-{site-id}-uploads:/var/www/html/wp-content/uploads:ro
      - site-{site-id}-cache:/var/www/html/wp-content/cache
    deploy:
      replicas: 2
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.site-{site-id}.rule=Host(`domain.com`)"
        # ... more Traefik labels

  php-fpm-{site-id}:
    image: custom/wordpress-fpm:8.2
    networks:
      - wp-site-{site-id}
      - shared-services
    volumes:
      - site-{site-id}-uploads:/var/www/html/wp-content/uploads
      - site-{site-id}-plugins:/var/www/html/wp-content/plugins
      - site-{site-id}-themes:/var/www/html/wp-content/themes
    secrets:
      - db_password_{site-id}
      - wp_keys_{site-id}
    deploy:
      replicas: 2

  redis-{site-id}:
    image: redis:7-alpine
    networks:
      - wp-site-{site-id}
    deploy:
      replicas: 1
```

**Benefits:**
- Security: Complete isolation between sites
- Scalability: Scale individual sites independently
- Reliability: Failure isolated to single site
- Performance: Dedicated resources per site

**Trade-offs:**
- Resource overhead (manageable with 16GB nodes)
- Complexity (automated via templates)

---

## Network Topology

### Swarm Overlay Networks

1. **traefik-public** (attachable)
   - All ingress traffic
   - Traefik routers
   - Site Nginx containers

2. **wp-site-{1..500}** (isolated)
   - Nginx ↔ PHP-FPM ↔ Redis per site

3. **shared-services** (attachable)
   - PHP-FPM containers → Database cluster
   - PHP-FPM containers → Central caching (if used)

4. **database** (internal)
   - Database cluster replication
   - Not accessible from application directly

5. **monitoring** (internal)
   - Prometheus, Loki, Tempo
   - Exporters on all nodes
   - Grafana

6. **management** (internal)
   - Portainer
   - Backup services
   - CI/CD runners

### External Connectivity

**Cloudflare DNS:**
- All site domains pointed to Cloudflare
- Cloudflare → Load Balancer IP (Digital Ocean Floating IP)
- Floating IP points to Traefik node pool

**Load Balancing:**
- Digital Ocean Load Balancer (Layer 4) OR
- Multiple A records to Traefik nodes (DNS round-robin) OR
- Cloudflare Load Balancing (recommended, with health checks)

---

## Resource Planning

### Per-Site Resource Estimate

| Component | CPU (m) | Memory (MB) | Notes |
|-----------|---------|-------------|-------|
| Nginx | 50-100 | 32-64 | Static file serving |
| PHP-FPM | 200-500 | 256-512 | Depends on traffic |
| Redis | 50 | 64-128 | Object cache |
| **Total** | **300-650** | **352-704** | Per site |

### Node Capacity

**16GB / 8 vCPU node:**
- Available: ~14GB (after OS overhead)
- Per site: ~500MB average
- **Capacity**: ~28 sites per node (conservative)
- **Actual**: Run 20-25 sites per node (headroom for traffic spikes)

### Cluster Size for 500 Sites

**Application Nodes:**
- 500 sites ÷ 25 sites/node = **20 worker nodes**

**Total Cluster:**
- 3 Manager nodes
- 20 Worker nodes
- 3 Database nodes
- 2 Storage nodes
- 2 Monitoring/management nodes
- **Total: 30 nodes**

**Monthly Cost (Digital Ocean):**
- 30 nodes × $96/month (16GB/8vCPU) = **$2,880/month**
- Block storage (5TB) = ~$500/month
- Load Balancer = $12/month
- Spaces (backups) = ~$100/month
- **Total: ~$3,500/month** ($7/site/month)

---

## High Availability Features

### Service Level

1. **Automatic Failover**
   - Swarm health checks every 10s
   - Automatic container restart
   - Rescheduling on healthy nodes

2. **Rolling Updates**
   - Zero-downtime deployments
   - Update parallelism: 1
   - Update delay: 10s
   - Rollback on failure: automatic

3. **Database HA**
   - Galera multi-master cluster
   - Automatic failover
   - Read/write splitting via ProxySQL or MaxScale

4. **Storage HA**
   - GlusterFS replica 2
   - Automatic replication
   - Self-healing volumes

### Infrastructure Level

1. **Multi-AZ Deployment**
   - Nodes spread across Digital Ocean regions
   - Manager quorum in different regions
   - Database cluster in different regions

2. **Floating IPs**
   - Quick failover between Traefik nodes
   - Managed via keepalived or similar

3. **Automated Backups**
   - Offsite to Digital Ocean Spaces
   - Cross-region replication
   - Automated restore testing

---

## Security Hardening Checklist

### Network Security
- [x] CrowdSec with Traefik bouncer
- [x] Encrypted overlay networks
- [x] Firewall rules (minimal exposure)
- [x] SSH key-only authentication
- [x] Cloudflare proxy (hide origin IPs)
- [x] Rate limiting (Traefik middleware)
- [x] DDoS protection (Cloudflare)

### Application Security
- [x] Regular security updates
- [x] Vulnerability scanning (Trivy)
- [x] Secrets management (Docker secrets)
- [x] Security headers (Traefik middleware)
- [x] Content Security Policy (CSP)
- [x] HTTPS-only
- [x] WordPress hardening (custom image)

### Access Control
- [x] RBAC in Portainer
- [x] Cloudflare Access for admin panels
- [x] VPN for SSH access (optional)
- [x] Audit logging (all admin actions)

### Compliance
- [x] Encrypted backups
- [x] Data retention policies
- [x] GDPR-compliant logging
- [x] Regular security audits

---

## Custom Docker Images

### 1. WordPress PHP-FPM Image

**Base**: `php:8.2-fpm-alpine`

**Additions:**
- PHP extensions: mysqli, gd, imagick, redis, opcache, zip
- OPcache configuration
- OpenTelemetry PHP extension
- Security hardening (non-root user)
- Health check endpoint
- WP-CLI pre-installed

### 2. Nginx Image

**Base**: `nginx:alpine`

**Additions:**
- Optimized nginx.conf for WordPress
- FastCGI cache configuration
- Security headers
- Gzip/Brotli compression
- HTTP/2 enabled
- Rate limiting configuration

### 3. CrowdSec Image

**Base**: `crowdsecurity/crowdsec:latest`

**Additions:**
- Pre-configured collections for WordPress
- Traefik log parsing
- Notification plugins (Slack, email)

### 4. Custom Exporters

**Custom WordPress Exporter:**
- Prometheus metrics for WordPress health
- Plugin/theme update status
- Site response times
- User activity

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
1. Provision initial nodes (3 managers, 6 workers, 3 DB)
2. Initialize Docker Swarm
3. Deploy Traefik with basic routing
4. Set up overlay networks
5. Deploy Portainer

### Phase 2: Core Services (Week 3-4)
6. Deploy database cluster (Galera)
7. Set up shared storage (GlusterFS)
8. Deploy Redis cluster
9. Configure CrowdSec
10. Set up basic monitoring (Prometheus + Grafana)

### Phase 3: WordPress Stack (Week 5-6)
11. Build custom Docker images
12. Create WordPress stack template
13. Deploy pilot sites (10-20 sites)
14. Configure caching layers
15. Test failover scenarios

### Phase 4: Observability (Week 7)
16. Deploy full LGTM stack
17. Configure dashboards
18. Set up alerting
19. Integrate OpenTelemetry

### Phase 5: Automation (Week 8)
20. Automate site provisioning
21. Set up CI/CD pipeline
22. Configure backup automation
23. Create runbooks for common operations

### Phase 6: Migration (Week 9-12)
24. Migrate sites in batches (50-100 per week)
25. Monitor performance
26. Tune resources
27. Scale cluster as needed

### Phase 7: Optimization (Ongoing)
28. Performance tuning
29. Cost optimization
30. Security hardening
31. Documentation

---

## Operational Procedures

### Adding a New WordPress Site

```bash
# 1. Generate site configuration
./provision-site.sh --domain example.com --stack-id 123

# 2. Deploy stack
docker stack deploy -c stacks/site-123.yml wp-site-123

# 3. Configure DNS
./cloudflare-dns.sh --add example.com --ip $FLOATING_IP

# 4. Wait for SSL certificate
sleep 30

# 5. Initialize WordPress
docker exec wp-site-123_php-fpm.1 wp core install \
  --url=https://example.com \
  --title="Site Title" \
  --admin_user=admin \
  --admin_email=admin@example.com

# 6. Configure backup
./backup-config.sh --add site-123

# Total time: ~5 minutes (automated)
```

### Scaling a Site

```bash
# Scale up replicas
docker service scale wp-site-123_nginx=4
docker service scale wp-site-123_php-fpm=4

# Or via Portainer UI
```

### Disaster Recovery

```bash
# 1. Restore database
./restore-db.sh --site-id 123 --date 2026-01-11

# 2. Restore files
./restore-files.sh --site-id 123 --date 2026-01-11

# 3. Verify site
curl -I https://example.com
```

---

## Performance Tuning

### Database Optimization
- Use ProxySQL for query routing
- Enable query caching
- Optimize MySQL/MariaDB configuration for 16GB nodes
- Regular ANALYZE TABLE and OPTIMIZE TABLE

### PHP-FPM Tuning
- pm.max_children based on memory limits
- pm.start_servers, pm.min_spare_servers, pm.max_spare_servers
- Slow log enabled (track >1s queries)

### Traefik Optimization
- Increase timeouts for slow WordPress sites
- Configure retry attempts
- Enable HTTP/3 for faster connections

### Cache Tuning
- Monitor cache hit rates
- Adjust TTLs based on content update frequency
- Use cache warming for popular pages

---

## Conclusion

This architecture provides a robust, scalable, and secure foundation for hosting 500+ WordPress sites. Key advantages:

1. **High Availability**: Multiple layers of redundancy
2. **Scalability**: Easy horizontal scaling
3. **Security**: Multi-layer defense approach
4. **Observability**: Full visibility into all systems
5. **Cost-Effective**: ~$7/site/month with room to optimize
6. **Automated**: Minimal manual intervention required
7. **Open Source**: No vendor lock-in, full control

The Docker Swarm approach provides the right balance of simplicity and power for this use case, avoiding the operational overhead of Kubernetes while still delivering enterprise-grade reliability.


