# Semaphore UI Deployment - Summary

## What Has Been Configured

### 1. Docker Compose Stack
**Location**: `/var/opt/manage/control-center/docker-compose-examples/semaphore-stack.yml`

The stack includes:
- ✅ Semaphore UI service with proper Traefik integration
- ✅ BoltDB embedded database (with PostgreSQL option available)
- ✅ Volume persistence for database and temporary files
- ✅ Access to your existing Ansible playbooks (read-only mount)
- ✅ Health checks and resource limits
- ✅ Auto-update capability via Shepherd/Watchtower
- ✅ SSL/TLS via Traefik Let's Encrypt
- ✅ Connection to `management` and `traefik-public` networks

### 2. Environment Configuration
**Location**: `/var/opt/manage/control-center/.env`

Added variables:
- `SEMAPHORE_ADMIN` - Admin username
- `SEMAPHORE_ADMIN_PASSWORD` - Admin password (needs to be changed)
- `SEMAPHORE_ADMIN_NAME` - Admin display name
- `SEMAPHORE_ADMIN_EMAIL` - Admin email address
- `SEMAPHORE_ACCESS_KEY_ENCRYPTION` - Encryption key (needs to be generated)
- `SEMAPHORE_COOKIE_HASH` - Cookie hash key (needs to be generated)
- `SEMAPHORE_COOKIE_ENCRYPTION` - Cookie encryption key (needs to be generated)
- Optional notification settings (email, Slack, Telegram)

### 3. Setup Script
**Location**: `/var/opt/manage/control-center/scripts/setup-semaphore.sh`

Features:
- ✅ Interactive menu-driven setup
- ✅ Automatic encryption key generation
- ✅ Admin credential configuration
- ✅ Domain configuration
- ✅ Network verification and creation
- ✅ One-command deployment
- ✅ Easy removal/cleanup

### 4. Documentation
**Locations**:
- `/var/opt/manage/control-center/docs/SEMAPHORE-UI-GUIDE.md` - Complete guide
- `/var/opt/manage/control-center/docs/SEMAPHORE-QUICK-REFERENCE.md` - Quick reference

Coverage:
- ✅ Architecture overview
- ✅ Installation instructions
- ✅ Configuration options
- ✅ Usage guide with examples
- ✅ Security best practices
- ✅ API access documentation
- ✅ Troubleshooting guide
- ✅ Backup and restore procedures
- ✅ Quick reference commands

## Architecture Integration

```
┌─────────────────────────────────────────────────────────┐
│                    Your Infrastructure                   │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Traefik Proxy (traefik-public network)                 │
│    ↓                                                     │
│  Semaphore UI (management network)                      │
│    ↓                                                     │
│  Your Ansible Playbooks (/var/opt/manage/.../ansible)  │
│    ↓                                                     │
│  Target Infrastructure (via SSH)                        │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

## Next Steps

### Option 1: Quick Setup (Recommended)

Run the interactive setup script:

```bash
cd /var/opt/manage/control-center/scripts
./setup-semaphore.sh
```

Select option **6** for full automated setup.

### Option 2: Manual Setup

#### Step 1: Generate Encryption Keys

```bash
# Generate three keys and note them down
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
```

#### Step 2: Update Environment File

Edit `/var/opt/manage/control-center/.env`:

```bash
# Replace these with actual values
SEMAPHORE_ADMIN_PASSWORD=your_strong_password_here
SEMAPHORE_ACCESS_KEY_ENCRYPTION=first_generated_key
SEMAPHORE_COOKIE_HASH=second_generated_key
SEMAPHORE_COOKIE_ENCRYPTION=third_generated_key
```

#### Step 3: Configure Domain

Edit `/var/opt/manage/control-center/docker-compose-examples/semaphore-stack.yml`:

Replace `semaphore.yourdomain.com` with your actual domain (e.g., `semaphore.example.com`)

#### Step 4: Verify Networks

```bash
# Check if networks exist
docker network ls | grep -E 'management|traefik-public'

# Create if missing
docker network create --driver=overlay --attachable management
docker network create --driver=overlay --attachable traefik-public
```

#### Step 5: Deploy

```bash
cd /var/opt/manage/control-center
docker stack deploy -c docker-compose-examples/semaphore-stack.yml semaphore
```

#### Step 6: Verify Deployment

```bash
# Check service status
docker service ls | grep semaphore

# View logs
docker service logs -f semaphore_semaphore

# Check if healthy
docker service ps semaphore_semaphore
```

## Post-Deployment Configuration

### 1. Access Web Interface

Navigate to: `https://semaphore.yourdomain.com`

Login with:
- Username: Value of `SEMAPHORE_ADMIN` (default: `admin`)
- Password: Value of `SEMAPHORE_ADMIN_PASSWORD`

### 2. Create Your First Project

Follow the guide in `/var/opt/manage/control-center/docs/SEMAPHORE-UI-GUIDE.md`:

1. Create SSH Key Store entries
2. Create Environment with your variables
3. Create Repository pointing to `/ansible`
4. Create Inventory (use your existing `/ansible/inventory/static.yml`)
5. Create Task Templates for your playbooks:
   - `deploy.yml`
   - `backup.yml`
   - `dns.yml`
   - `health.yml`
   - `provision.yml`

### 3. Test Task Execution

Run a simple playbook first to verify everything works:
- Try running `health.yml` to check infrastructure health
- Review logs in the web interface
- Verify SSH connectivity

### 4. Set Up Notifications (Optional)

Configure Slack/Telegram/Email notifications in:
- `.env` file for global settings
- Web UI → Project Settings → Integrations

## What's Available Now

### Your Existing Ansible Playbooks

These are automatically available in Semaphore at `/ansible/`:

| Playbook | Purpose | Path in Semaphore |
|----------|---------|-------------------|
| deploy.yml | Deployment automation | `/ansible/deploy.yml` |
| backup.yml | Backup operations | `/ansible/backup.yml` |
| dns.yml | DNS configuration | `/ansible/dns.yml` |
| health.yml | Health checks | `/ansible/health.yml` |
| provision.yml | Infrastructure provisioning | `/ansible/provision.yml` |
| site.yml | Main site playbook | `/ansible/site.yml` |

### Your Existing Inventory

Available at: `/ansible/inventory/static.yml`

### Your Existing Roles

Available at: `/ansible/roles/`

## Benefits

### Before Semaphore
- Manual SSH to servers
- Running ansible-playbook from command line
- No audit trail
- No access control
- Manual scheduling with cron
- Limited collaboration

### After Semaphore
- ✅ Web-based interface accessible from anywhere
- ✅ Role-based access control for team members
- ✅ Complete audit trail of all executions
- ✅ Scheduled tasks with cron expressions
- ✅ Real-time log streaming
- ✅ Notification on task completion/failure
- ✅ API for automation and CI/CD integration
- ✅ Git integration for version control
- ✅ Survey variables for interactive execution
- ✅ Task queuing and concurrency control

## Security Considerations

### Current Configuration

✅ **Secure**:
- HTTPS enforced via Traefik
- Let's Encrypt SSL certificates
- Encrypted session cookies
- Ansible playbooks mounted read-only
- Health checks enabled

⚠️ **Needs Configuration**:
- Change default admin password
- Generate unique encryption keys
- Optional: Enable Traefik auth middleware for additional protection
- Configure notification channels

### Optional: Add BasicAuth

To add an additional authentication layer via Traefik:

1. Generate password hash:
```bash
htpasswd -nb admin yourpassword
```

2. Add to Traefik middleware in compose file:
```yaml
- "traefik.http.routers.semaphore.middlewares=auth,semaphore-security"
- "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
```

## Monitoring

### Check Service Status

```bash
# Service list
docker service ls | grep semaphore

# Service details
docker service ps semaphore_semaphore

# Logs
docker service logs -f semaphore_semaphore

# Health status
curl -I https://semaphore.yourdomain.com/api/ping
```

### Prometheus Metrics

Semaphore doesn't expose Prometheus metrics by default, but you can monitor:
- Traefik metrics (request count, response times)
- Container metrics (CPU, memory)
- Task execution history via API

## Backup Strategy

### What to Backup

1. **Database** (most important):
   - BoltDB: `/etc/semaphore/database.boltdb` (in volume)
   - Contains all projects, tasks, users, keys, etc.

2. **Configuration**:
   - `.env` file (environment variables)
   - `semaphore-stack.yml` (compose configuration)

3. **Encryption Keys**:
   - Store encryption keys securely (password manager)
   - Needed for restore

### Automated Backup

Add to your existing backup playbook:

```bash
# Backup Semaphore database
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v /backup/semaphore:/backup \
  alpine tar czf /backup/semaphore-$(date +%Y%m%d).tar.gz -C /data .

# Rotate backups (keep 30 days)
find /backup/semaphore -name "semaphore-*.tar.gz" -mtime +30 -delete
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Service not starting | Check logs: `docker service logs semaphore_semaphore` |
| Cannot access web UI | Verify domain DNS, check Traefik routing |
| 502 Bad Gateway | Service may still be starting, wait 30 seconds |
| SSH connection fails | Check SSH keys in Key Store, verify network |
| Ansible playbook not found | Verify `/ansible` mount in container |

### Quick Fixes

```bash
# Restart service
docker service update --force semaphore_semaphore

# Check if networks exist
docker network ls | grep -E 'management|traefik-public'

# Verify volume
docker volume inspect semaphore_semaphore-data

# Container shell access
docker exec -it $(docker ps -q -f name=semaphore) sh
```

## Additional Resources

### Documentation
- Full guide: `/var/opt/manage/control-center/docs/SEMAPHORE-UI-GUIDE.md`
- Quick reference: `/var/opt/manage/control-center/docs/SEMAPHORE-QUICK-REFERENCE.md`

### Official Resources
- [Semaphore Documentation](https://docs.ansible-semaphore.com/)
- [GitHub Repository](https://github.com/ansible-semaphore/semaphore)
- [Docker Hub](https://hub.docker.com/r/semaphoreui/semaphore)
- [API Reference](https://docs.ansible-semaphore.com/api-reference)

## Estimated Timeline

- **Setup**: 10-15 minutes
- **First project configuration**: 15-20 minutes
- **Testing**: 10-15 minutes
- **Total**: ~45 minutes to full operation

## Summary

You now have everything needed to deploy Semaphore UI:

✅ Production-ready Docker Compose configuration
✅ Traefik integration with SSL/TLS
✅ Automated setup script
✅ Comprehensive documentation
✅ Quick reference guide
✅ Integration with existing Ansible infrastructure

**Ready to deploy?** Run:
```bash
cd /var/opt/manage/control-center/scripts
./setup-semaphore.sh
```

Or review the documentation first:
```bash
cat /var/opt/manage/control-center/docs/SEMAPHORE-UI-GUIDE.md
```

---

**Questions or Issues?**
- Check the troubleshooting section in the guide
- Review service logs: `docker service logs -f semaphore_semaphore`
- Consult official documentation: https://docs.ansible-semaphore.com/
