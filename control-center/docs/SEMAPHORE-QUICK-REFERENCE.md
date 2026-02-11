# Semaphore UI - Quick Reference

## Installation & Setup

```bash
# Quick setup (interactive)
cd /var/opt/manage/control-center/scripts
./setup-semaphore.sh

# Generate encryption keys only
openssl rand -base64 32

# Check deployment status
docker service ls | grep semaphore
docker service ps semaphore_semaphore

# View logs
docker service logs -f semaphore_semaphore
```

## Management Commands

```bash
# Deploy/Redeploy
docker stack deploy -c docker-compose-examples/semaphore-stack.yml semaphore

# Stop
docker stack rm semaphore

# Scale
docker service scale semaphore_semaphore=0  # Stop
docker service scale semaphore_semaphore=1  # Start

# Update image
docker service update --image semaphoreui/semaphore:latest semaphore_semaphore

# Force restart
docker service update --force semaphore_semaphore
```

## Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose-examples/semaphore-stack.yml` | Main compose file |
| `.env` | Environment variables |
| `scripts/setup-semaphore.sh` | Setup script |
| `docs/SEMAPHORE-UI-GUIDE.md` | Full documentation |

## Environment Variables

### Required
```bash
SEMAPHORE_ADMIN                   # Admin username
SEMAPHORE_ADMIN_PASSWORD          # Admin password
SEMAPHORE_ACCESS_KEY_ENCRYPTION   # Encryption key
SEMAPHORE_COOKIE_HASH             # Cookie hash key
SEMAPHORE_COOKIE_ENCRYPTION       # Cookie encryption key
```

### Optional
```bash
SEMAPHORE_ADMIN_NAME              # Admin display name
SEMAPHORE_ADMIN_EMAIL             # Admin email
SEMAPHORE_EMAIL_HOST              # SMTP host
SEMAPHORE_EMAIL_PORT              # SMTP port (587)
SEMAPHORE_SLACK_URL               # Slack webhook
SEMAPHORE_TELEGRAM_TOKEN          # Telegram bot token
```

## Common Tasks

### First-Time Setup Workflow

1. **Create Key Store**
   - SSH keys for remote access
   - Login passwords for sudo
   - Vault passwords for Ansible Vault

2. **Create Environment**
   - Define Ansible variables
   - Set connection parameters

3. **Create Repository**
   - Local: `/ansible`
   - Git: Clone from remote

4. **Create Inventory**
   - Static inventory content
   - Or file reference

5. **Create Task Template**
   - Link all components
   - Define playbook path
   - Add survey for variables

6. **Run Task**
   - Manual execution
   - Or schedule with cron

### Using Existing Ansible Playbooks

```yaml
# Repository setup
Type: Local
Path: /ansible

# Playbook paths
/ansible/deploy.yml
/ansible/backup.yml
/ansible/dns.yml
/ansible/provision.yml
/ansible/health.yml

# Inventory path
/ansible/inventory/static.yml

# Roles path
/ansible/roles/
```

## Troubleshooting

### Service Not Starting
```bash
# Check service status
docker service ps semaphore_semaphore --no-trunc

# Check logs for errors
docker service logs --tail 100 semaphore_semaphore

# Verify networks exist
docker network ls | grep -E 'management|traefik-public'

# Create networks if missing
docker network create --driver=overlay --attachable management
docker network create --driver=overlay --attachable traefik-public
```

### Cannot Access Web UI
```bash
# Check if service is running
docker service ls | grep semaphore

# Check Traefik routing
docker service logs traefik_traefik | grep semaphore

# Verify DNS resolution
nslookup semaphore.yourdomain.com

# Check SSL certificate
curl -I https://semaphore.yourdomain.com
```

### Database Issues
```bash
# Check volume
docker volume ls | grep semaphore

# Inspect volume
docker volume inspect semaphore_semaphore-data

# Backup database
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/semaphore-backup.tar.gz -C /data .
```

### Ansible Playbook Errors
```bash
# Verify mount
docker exec -it $(docker ps -q -f name=semaphore) ls -la /ansible/

# Check Ansible version
docker exec -it $(docker ps -q -f name=semaphore) ansible --version

# Test playbook syntax
docker exec -it $(docker ps -q -f name=semaphore) \
  ansible-playbook --syntax-check /ansible/deploy.yml
```

## API Examples

### Get API Token
UI → User Menu → API Tokens → Create Token

### List Projects
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://semaphore.yourdomain.com/api/projects
```

### Run Task
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"template_id": 1, "debug": false}' \
  https://semaphore.yourdomain.com/api/project/1/tasks
```

### Get Task Status
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://semaphore.yourdomain.com/api/project/1/tasks/123
```

## Backup & Restore

### Backup BoltDB
```bash
# Create backup directory
mkdir -p /backup/semaphore

# Backup database volume
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v /backup/semaphore:/backup \
  alpine tar czf /backup/semaphore-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Backup configuration
cp /var/opt/manage/control-center/.env /backup/semaphore/env-$(date +%Y%m%d-%H%M%S).backup
cp /var/opt/manage/control-center/docker-compose-examples/semaphore-stack.yml \
   /backup/semaphore/compose-$(date +%Y%m%d-%H%M%S).yml
```

### Restore BoltDB
```bash
# Stop service
docker service scale semaphore_semaphore=0

# Restore from backup
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v /backup/semaphore:/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/semaphore-TIMESTAMP.tar.gz -C /data"

# Start service
docker service scale semaphore_semaphore=1
```

## Monitoring

### Health Checks
```bash
# Service health
docker service ps semaphore_semaphore

# HTTP health check
curl -I https://semaphore.yourdomain.com/api/ping

# Container stats
docker stats $(docker ps -q -f name=semaphore)
```

### Logs
```bash
# Follow logs
docker service logs -f semaphore_semaphore

# Last 100 lines
docker service logs --tail 100 semaphore_semaphore

# Logs since timestamp
docker service logs --since 2024-01-01T00:00:00 semaphore_semaphore

# Filter logs
docker service logs semaphore_semaphore 2>&1 | grep ERROR
```

## Performance Tuning

### Resource Limits
```yaml
# In compose file
resources:
  limits:
    cpus: '2'
    memory: 2G
  reservations:
    cpus: '0.5'
    memory: 512M
```

### Concurrency
```bash
# In .env file
SEMAPHORE_MAX_PARALLEL_TASKS=5  # Adjust based on load
```

### Database
```bash
# For high-load scenarios, switch to PostgreSQL
# Uncomment postgres service in compose file
# Update SEMAPHORE_DB_DIALECT=postgres
```

## Security Checklist

- [ ] Changed default admin password
- [ ] Using strong encryption keys (32+ chars)
- [ ] HTTPS enabled with valid certificate
- [ ] Traefik auth middleware enabled (optional)
- [ ] SSH keys stored in Key Store, not in code
- [ ] Ansible Vault passwords configured
- [ ] Regular backups scheduled
- [ ] Audit logs reviewed periodically
- [ ] API tokens rotated regularly
- [ ] Non-admin users created with limited roles

## Network Diagram

```
Internet
   ↓
Traefik (443/80)
   ↓
Semaphore UI (3000)
   ↓
Ansible Execution
   ↓
Target Hosts (SSH)
```

## Useful Links

- **Web UI**: https://semaphore.yourdomain.com
- **API Docs**: https://docs.ansible-semaphore.com/api-reference
- **GitHub**: https://github.com/ansible-semaphore/semaphore
- **Docker Hub**: https://hub.docker.com/r/semaphoreui/semaphore

## Quick Tips

💡 **Tip 1**: Use the "Survey" feature in task templates to prompt for runtime variables

💡 **Tip 2**: Enable task scheduling to automate regular maintenance

💡 **Tip 3**: Set up Slack/Telegram notifications for task failures

💡 **Tip 4**: Use the API to integrate Semaphore with CI/CD pipelines

💡 **Tip 5**: Create separate projects for dev/staging/prod environments

💡 **Tip 6**: Use Git repositories for version control of playbooks

💡 **Tip 7**: Test playbooks manually before scheduling them

💡 **Tip 8**: Review task logs regularly for optimization opportunities

## Getting Help

```bash
# Check Semaphore version
docker exec $(docker ps -q -f name=semaphore) semaphore version

# Check Ansible version
docker exec $(docker ps -q -f name=semaphore) ansible --version

# Access container shell
docker exec -it $(docker ps -q -f name=semaphore) sh

# View container environment
docker exec $(docker ps -q -f name=semaphore) env | grep SEMAPHORE
```

---

**Remember**: Always test in a non-production environment first!
