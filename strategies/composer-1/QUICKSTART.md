# Quick Start Guide

## Prerequisites Checklist

- [ ] 3+ Digital Ocean VPS nodes (16GB RAM / 8 Core)
- [ ] Cloudflare account with DNS access
- [ ] SSH access to all nodes
- [ ] Domain names configured in Cloudflare

## 5-Minute Setup

### Step 1: Initialize Swarm (2 minutes)

On **Node 1** (Manager):
```bash
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
```

On **Node 2 & 3** (Workers):
```bash
# Copy the join command from Node 1 output
docker swarm join --token <TOKEN> <MANAGER_IP>:2377
```

### Step 2: Create Networks (1 minute)

On **Node 1**:
```bash
docker network create --driver overlay --attachable web
docker network create --driver overlay --attachable wordpress
docker network create --driver overlay --attachable database
docker network create --driver overlay --attachable caching
docker network create --driver overlay --attachable monitoring
docker network create --driver overlay --attachable management
```

### Step 3: Configure Environment (1 minute)

Create `.env` file:
```bash
cat > .env << EOF
DB_ROOT_PASSWORD=$(openssl rand -base64 32)
DB_PASSWORD=$(openssl rand -base64 32)
DB_REPL_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
CROWDSEC_BOUNCER_KEY=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32)
EOF
```

### Step 4: Deploy Core Stack (1 minute)

```bash
# Deploy core services
docker stack deploy -c docker-compose/swarm-stack.yml wordpress-farm

# Deploy observability
docker stack deploy -c docker-compose/observability.yml observability

# Deploy security
docker stack deploy -c docker-compose/security.yml security
```

### Step 5: Verify (1 minute)

```bash
# Check services
docker service ls

# Check Traefik
curl -I http://localhost

# Check Portainer (after DNS configured)
# https://portainer.yourdomain.com
```

## Next Steps

1. **Configure DNS**: Point your domains to Traefik nodes in Cloudflare
2. **Update Traefik Config**: Edit `traefik/traefik.yml` with your email
3. **Deploy WordPress Site**: Follow `docs/DEPLOYMENT.md`
4. **Set Up Monitoring**: Access Grafana at `https://grafana.yourdomain.com`
5. **Configure Backups**: See `docs/BACKUP_STRATEGY.md`

## Common Commands

```bash
# View all services
docker service ls

# View service details
docker service ps <service-name>

# View logs
docker service logs -f <service-name>

# Scale service
docker service scale <service-name>=5

# Update service
docker service update --image <new-image> <service-name>

# Remove service
docker service rm <service-name>
```

## Troubleshooting

### Services Not Starting

```bash
# Check service status
docker service ps <service-name> --no-trunc

# Check node resources
docker node inspect <node-id> | grep -A 10 Resources

# Check logs
docker service logs <service-name>
```

### Network Issues

```bash
# List networks
docker network ls

# Inspect network
docker network inspect <network-name>

# Test connectivity
docker exec <container> ping <target>
```

### Storage Issues

```bash
# Check volumes
docker volume ls

# Inspect volume
docker volume inspect <volume-name>

# Check disk space
df -h
```

## Getting Help

- Architecture: See `ARCHITECTURE.md`
- Deployment: See `docs/DEPLOYMENT.md`
- Node Setup: See `docs/NODE_SETUP.md`
- Backups: See `docs/BACKUP_STRATEGY.md`

## Security Reminders

⚠️ **IMPORTANT**: Before going to production:

1. Change all default passwords in `.env`
2. Configure IP whitelist in Traefik middleware
3. Set up VPN for management access
4. Enable Cloudflare WAF rules
5. Review and test backup procedures
6. Set up monitoring alerts
7. Configure SSL certificates properly
8. Review firewall rules

## Performance Tips

- Start with 3 nodes, scale as needed
- Monitor resource usage in Grafana
- Adjust PHP-FPM pool sizes based on load
- Tune cache TTLs based on traffic patterns
- Use Cloudflare CDN for static assets


