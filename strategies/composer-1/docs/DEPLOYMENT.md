# Deployment Guide

## Prerequisites

- Docker Swarm cluster initialized (minimum 3 nodes)
- Digital Ocean VPS nodes (16GB RAM / 8 Core) configured
- Cloudflare DNS configured
- SSH access to all nodes

## Initial Setup

### 1. Initialize Docker Swarm

On the first node (manager):
```bash
docker swarm init --advertise-addr <MANAGER_IP>
```

On other nodes (workers):
```bash
docker swarm join --token <JOIN_TOKEN> <MANAGER_IP>:2377
```

### 2. Create Networks

```bash
docker network create --driver overlay --attachable web
docker network create --driver overlay --attachable wordpress
docker network create --driver overlay --attachable database
docker network create --driver overlay --attachable caching
docker network create --driver overlay --attachable monitoring
docker network create --driver overlay --attachable management
```

### 3. Create Secrets

```bash
# Database passwords
echo "changeme" | docker secret create db_root_password -
echo "changeme" | docker secret create db_password -
echo "changeme" | docker secret create db_repl_password -

# Redis password
echo "changeme" | docker secret create redis_password -

# Crowdsec bouncer key
echo "changeme" | docker secret create crowdsec_bouncer_key -

# Grafana admin password
echo "changeme" | docker secret create grafana_admin_password -
```

### 4. Deploy Core Stack

```bash
docker stack deploy -c docker-compose/swarm-stack.yml wordpress-farm
```

### 5. Deploy Observability Stack

```bash
docker stack deploy -c docker-compose/observability.yml observability
```

### 6. Deploy Security Stack

```bash
docker stack deploy -c docker-compose/security.yml security
```

## WordPress Site Deployment

### Single Site Deployment

1. Create site directory:
```bash
mkdir -p /var/opt/wordpress/sites/example.com
cd /var/opt/wordpress/sites/example.com
```

2. Copy WordPress files:
```bash
cp -r wordpress/* .
```

3. Customize configuration:
```bash
cp wp-config.php.example wp-config.php
# Edit wp-config.php with site-specific settings
```

4. Set environment variables:
```bash
export SITE_NAME=example-com
export SITE_DOMAIN=example.com
export DB_PASSWORD=changeme
export REDIS_PASSWORD=changeme
```

5. Deploy:
```bash
docker stack deploy -c docker-compose.yml ${SITE_NAME}
```

### Multi-Site Deployment

For managing 500+ sites, use a deployment script:

```bash
#!/bin/bash
# deploy-site.sh

SITE_NAME=$1
SITE_DOMAIN=$2
DB_NAME=$3

# Create site directory
mkdir -p /var/opt/wordpress/sites/${SITE_DOMAIN}

# Copy template files
cp -r wordpress/* /var/opt/wordpress/sites/${SITE_DOMAIN}/

# Generate wp-config.php
envsubst < wp-config.php.example > /var/opt/wordpress/sites/${SITE_DOMAIN}/wp-config.php

# Set environment variables
export SITE_NAME=${SITE_NAME}
export SITE_DOMAIN=${SITE_DOMAIN}
export WP_DB_NAME=${DB_NAME}

# Deploy stack
cd /var/opt/wordpress/sites/${SITE_DOMAIN}
docker stack deploy -c docker-compose.yml ${SITE_NAME}
```

## Custom WordPress Image

### Build Custom Image

```bash
cd wordpress
docker build -t wordpress-custom:latest .
```

### Push to Registry

```bash
docker tag wordpress-custom:latest registry.yourdomain.com/wordpress-custom:latest
docker push registry.yourdomain.com/wordpress-custom:latest
```

### Update Stack to Use Custom Image

Edit `docker-compose.yml`:
```yaml
services:
  wordpress:
    image: registry.yourdomain.com/wordpress-custom:latest
```

## Scaling

### Scale WordPress Containers

```bash
docker service scale wordpress-farm_wordpress=10
```

### Scale Database Read Replicas

```bash
docker service scale wordpress-farm_mariadb-replica-1=3
```

### Add New Nodes

1. Add node to Swarm:
```bash
docker swarm join --token <JOIN_TOKEN> <MANAGER_IP>:2377
```

2. Services will automatically distribute across nodes

## Monitoring

### Access Grafana

- URL: `https://grafana.yourdomain.com`
- Default credentials: admin / changeme (change immediately!)

### Access Portainer

- URL: `https://portainer.yourdomain.com`
- Create admin user on first access

### Access Traefik Dashboard

- URL: `https://traefik.yourdomain.com`
- Protected by admin-chain middleware

## Backup Strategy

### Automated Backups

See `docs/BACKUP_STRATEGY.md` for detailed backup procedures.

### Manual Database Backup

```bash
docker exec $(docker ps -q -f name=mariadb-master-1) \
  mysqldump -u root -p${DB_ROOT_PASSWORD} --all-databases > backup.sql
```

### Manual Files Backup

```bash
tar -czf wordpress-files-$(date +%Y%m%d).tar.gz /var/nfs/wordpress/
```

## Troubleshooting

### Check Service Status

```bash
docker service ls
docker service ps <service-name>
```

### View Logs

```bash
docker service logs <service-name>
docker service logs <service-name> --follow
```

### Restart Service

```bash
docker service update --force <service-name>
```

### Remove Service

```bash
docker service rm <service-name>
```

## Security Checklist

- [ ] Change all default passwords
- [ ] Configure Cloudflare WAF rules
- [ ] Set up IP whitelist for admin access
- [ ] Enable Crowdsec collections
- [ ] Configure Fail2ban filters
- [ ] Set up SSL certificates (automatic via Let's Encrypt)
- [ ] Review Traefik middleware configuration
- [ ] Enable firewall rules on nodes
- [ ] Set up VPN for management access
- [ ] Configure backup encryption

## Performance Tuning

### Database Optimization

1. Review slow query log
2. Add indexes as needed
3. Optimize queries
4. Consider query caching

### Caching Optimization

1. Monitor cache hit rates
2. Adjust Varnish TTLs
3. Optimize Redis memory limits
4. Review Memcached configuration

### PHP-FPM Tuning

Adjust `pm.max_children` based on:
- Available memory
- Average request memory usage
- Expected concurrent requests

Formula: `pm.max_children = (Total RAM - System RAM) / Average Memory per Request`

## Maintenance

### Update WordPress Core

```bash
docker exec -it <wordpress-container> wp core update
```

### Update Plugins

```bash
docker exec -it <wordpress-container> wp plugin update --all
```

### Update Themes

```bash
docker exec -it <wordpress-container> wp theme update --all
```

### Database Maintenance

```bash
docker exec -it <mariadb-container> mysqlcheck -u root -p --all-databases --optimize
```


