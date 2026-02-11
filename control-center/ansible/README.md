# WordPress Farm Infrastructure - Ansible Edition

**Complete Ansible automation for deploying and managing a production-scale WordPress farm on DigitalOcean.**

---

## 🎯 Overview

This is a **full Ansible conversion** of the WordPress farm infrastructure management system. It provisions 33 nodes across 6 tiers, configures Docker Swarm, and deploys all necessary services for hosting 500 WordPress sites at scale.

### Key Features

✅ **Fully Idempotent** - Safe to re-run without breaking things  
✅ **Production-Ready** - Used for $3,613/month infrastructure  
✅ **Well-Organized** - Roles, playbooks, and dynamic inventory  
✅ **Comprehensive** - Provisioning, deployment, health checks, backups  
✅ **Tag-Based Execution** - Run specific parts independently  
✅ **Industry Standard** - Uses Ansible best practices  

---

## 📊 Infrastructure Scale

| Component | Count | Size | Purpose |
|-----------|-------|------|---------|
| Managers | 3 | 2vCPU, 4GB | Docker Swarm control plane |
| Workers | 20 | 4vCPU, 8GB | WordPress application nodes |
| Cache | 3 | 2vCPU, 4GB | Varnish + Redis |
| Database | 3 | 4vCPU, 8GB | MariaDB Galera cluster |
| Storage | 2 | 2vCPU, 4GB | GlusterFS/NFS |
| Monitors | 2 | 2vCPU, 4GB | Prometheus + Grafana |
| **Total** | **33 nodes** | | **$3,613/month** |

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install Ansible
sudo apt update
sudo apt install ansible

# Install required collections
ansible-galaxy collection install -r requirements.yml

# Install doctl (DigitalOcean CLI)
wget https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
tar xf doctl-1.104.0-linux-amd64.tar.gz
sudo mv doctl /usr/local/bin

# Authenticate doctl
doctl auth init
```

### Environment Setup

```bash
# Copy and configure environment
cp ../scripts/.env.example ../.env
nano ../.env

# Required variables:
# - DO_API_TOKEN
# - CF_API_TOKEN
# - MYSQL_ROOT_PASSWORD
# - S3_ACCESS_KEY
# - S3_SECRET_KEY

# Export environment variables
set -a
source ../.env
set +a
```

### Full Deployment (45 minutes)

```bash
# 1. Provision infrastructure (15-20 min)
ansible-playbook provision.yml

# 2. Wait 2-3 minutes for droplets to boot

# 3. Deploy and configure everything (20-25 min)
ansible-playbook deploy.yml

# 4. Verify health
ansible-playbook health.yml

# 5. Create your first WordPress site
ansible-playbook site.yml -e domain=example.com

# 6. Configure DNS
ansible-playbook dns.yml -e domain=example.com
```

---

## 📁 Project Structure

```
ansible/
├── ansible.cfg                 # Ansible configuration
├── requirements.yml            # Galaxy collections and roles
├── README.md                   # This file
│
├── inventory/
│   ├── digitalocean.yml        # Dynamic DO inventory
│   └── static.yml              # Static inventory (fallback)
│
├── group_vars/
│   ├── all.yml                 # Global variables
│   ├── swarm_managers.yml      # Manager-specific vars
│   ├── cache_nodes.yml         # Cache tier vars
│   ├── database_nodes.yml      # Database tier vars
│   ├── storage_nodes.yml       # Storage tier vars
│   ├── worker_nodes.yml        # Worker tier vars
│   └── monitor_nodes.yml       # Monitoring tier vars
│
├── roles/
│   ├── common/                 # Base system configuration
│   │   └── tasks/main.yml
│   └── docker/                 # Docker installation
│       ├── tasks/main.yml
│       └── handlers/main.yml
│
├── playbooks/                  # Main playbooks
│   ├── provision.yml           # Provision infrastructure
│   ├── deploy.yml              # Deploy all services
│   ├── site.yml                # Manage WordPress sites
│   ├── health.yml              # Health checks
│   ├── backup.yml              # Backup operations
│   └── dns.yml                 # Cloudflare DNS
│
└── docs/
    ├── USAGE.md                # Detailed usage guide
    ├── MIGRATION.md            # Migration from bash script
    └── TROUBLESHOOTING.md      # Common issues
```

---

## 📖 Playbooks

### provision.yml - Infrastructure Provisioning

Creates all infrastructure on DigitalOcean.

```bash
# Provision everything
ansible-playbook provision.yml

# Provision specific components
ansible-playbook provision.yml --tags managers
ansible-playbook provision.yml --tags workers,cache
ansible-playbook provision.yml --tags database,storage

# Dry run
ansible-playbook provision.yml --check
```

**What it does:**
- Creates VPC network
- Uploads SSH keys
- Creates droplets (managers, workers, cache, database, storage, monitors)
- Attaches block storage to storage nodes
- Tags droplets for inventory grouping

**Duration:** 15-20 minutes

---

### deploy.yml - Full Stack Deployment

Configures all nodes and deploys services.

```bash
# Full deployment
ansible-playbook deploy.yml

# Specific stages
ansible-playbook deploy.yml --tags base,docker
ansible-playbook deploy.yml --tags swarm
ansible-playbook deploy.yml --tags networks
ansible-playbook deploy.yml --tags stacks

# Deploy specific stacks
ansible-playbook deploy.yml --tags traefik
ansible-playbook deploy.yml --tags cache,database
ansible-playbook deploy.yml --tags monitoring
```

**What it does:**
- Base system configuration (common role)
- Docker installation
- Swarm initialization
- Node joining and labeling
- Network creation
- Stack deployment (Traefik, Cache, Database, Monitoring, etc.)

**Duration:** 20-25 minutes

---

### site.yml - WordPress Site Management

Create or delete WordPress sites.

```bash
# Create new site
ansible-playbook site.yml -e domain=example.com

# Create with specific ID
ansible-playbook site.yml -e domain=example.com -e site_id=12345

# Delete site (with confirmation)
ansible-playbook site.yml -e domain=example.com -e state=absent

# Delete site (no confirmation)
ansible-playbook site.yml -e domain=example.com -e state=absent -e confirm_delete=true
```

**Features:**
- Generates unique database credentials
- Deploys WordPress Docker stack
- Saves credentials securely
- Waits for service readiness

---

### health.yml - Health Checks

Comprehensive infrastructure health checks.

```bash
# Full health check
ansible-playbook health.yml

# Specific checks
ansible-playbook health.yml --tags nodes
ansible-playbook health.yml --tags swarm
ansible-playbook health.yml --tags services
ansible-playbook health.yml --tags cache
ansible-playbook health.yml --tags database
```

**Checks:**
- Node connectivity
- Docker service status
- Swarm cluster health
- Network existence
- Service replica status
- Cache layer (Redis, Varnish)
- Database connectivity

---

### backup.yml - Backup Operations

Trigger and manage backups.

```bash
# All backups
ansible-playbook backup.yml

# Database only
ansible-playbook backup.yml --tags database

# WordPress files only
ansible-playbook backup.yml --tags wordpress

# Cleanup old backups
ansible-playbook backup.yml --tags cleanup

# Verify backup health
ansible-playbook backup.yml --tags verify
```

---

### dns.yml - Cloudflare DNS

Configure DNS records on Cloudflare.

```bash
# Create/update A record (uses manager IP)
ansible-playbook dns.yml -e domain=example.com

# Specific IP
ansible-playbook dns.yml -e domain=example.com -e ip=1.2.3.4

# Without proxy (orange cloud off)
ansible-playbook dns.yml -e domain=example.com -e proxied=false

# Delete record
ansible-playbook dns.yml -e domain=example.com -e state=absent
```

---

## 🏷️ Tags Reference

### Provision Playbook Tags
- `prerequisites` - Check requirements
- `vpc`, `network` - VPC creation
- `ssh`, `keys` - SSH key setup
- `managers` - Manager nodes
- `workers` - Worker nodes
- `cache` - Cache nodes
- `database`, `db` - Database nodes
- `storage` - Storage nodes
- `monitors`, `monitoring` - Monitor nodes
- `nodes` - All node types

### Deploy Playbook Tags
- `base`, `system` - Base configuration
- `docker` - Docker installation
- `swarm`, `init` - Swarm initialization
- `join`, `managers`, `workers` - Node joining
- `labels` - Node labeling
- `networks` - Network creation
- `verify`, `scripts` - Verification scripts
- `config`, `dirs` - Configuration directories
- `stacks` - All stack deployments
- `traefik` - Traefik stack
- `cache` - Cache stack
- `database` - Database stack
- `monitoring` - Monitoring stack
- `management` - Management stack
- `backup` - Backup stack
- `contractor` - Contractor stack

### Health Playbook Tags
- `nodes` - Node health
- `swarm` - Swarm health
- `networks` - Network health
- `services` - Service health
- `stacks` - Stack status
- `cache` - Cache layer health
- `database` - Database health

### Backup Playbook Tags
- `database`, `db` - Database backup
- `wordpress`, `files` - File backup
- `cleanup` - Retention cleanup
- `verify`, `health` - Backup health

---

## 🔧 Advanced Usage

### Limit Execution to Specific Hosts

```bash
# Only managers
ansible-playbook deploy.yml --limit swarm_managers

# Only cache nodes
ansible-playbook health.yml --limit cache_nodes

# Specific node
ansible-playbook deploy.yml --limit wp-worker-01
```

### Check Mode (Dry Run)

```bash
# See what would change
ansible-playbook deploy.yml --check

# Diff mode
ansible-playbook deploy.yml --check --diff
```

### Verbose Output

```bash
# Verbose
ansible-playbook provision.yml -v

# Very verbose
ansible-playbook deploy.yml -vv

# Debug level
ansible-playbook provision.yml -vvv
```

### Parallel Execution

Ansible runs tasks in parallel by default (20 forks). Adjust in `ansible.cfg`:

```ini
[defaults]
forks = 50  # Increase for faster execution
```

---

## 📊 Dynamic Inventory

The dynamic inventory automatically discovers droplets with `wordpress-farm` tags.

```bash
# List inventory
ansible-inventory --list

# Graph inventory
ansible-inventory --graph

# Show host variables
ansible-inventory --host wp-manager-01

# Refresh inventory cache
rm -rf /tmp/ansible_digitalocean_cache
ansible-inventory --list
```

### Inventory Groups

- `swarm_managers` - All manager nodes
- `swarm_workers` - All worker nodes
- `cache_nodes` - Cache tier
- `database_nodes` - Database tier
- `storage_nodes` - Storage tier
- `worker_nodes` - Application tier
- `monitor_nodes` - Monitoring tier
- `all_nodes` - All infrastructure

---

## 🔐 Security Best Practices

### Secrets Management

```bash
# Use Ansible Vault for sensitive data
ansible-vault create secrets.yml
ansible-vault edit secrets.yml

# Run with vault
ansible-playbook deploy.yml --ask-vault-pass

# Use vault password file
ansible-playbook deploy.yml --vault-password-file ~/.vault_pass
```

### SSH Keys

```bash
# Generate deployment key
ssh-keygen -t ed25519 -f ~/.ssh/wp-farm-deploy-key

# Use specific key
ansible-playbook provision.yml \
  --private-key ~/.ssh/wp-farm-deploy-key
```

---

## 🆚 Comparison: Ansible vs Bash Script

| Feature | Bash Script | Ansible |
|---------|-------------|---------|
| **Idempotency** | ❌ Manual checks | ✅ Built-in |
| **Error Handling** | ⚠️ Custom | ✅ Automatic |
| **Rollback** | ❌ Not supported | ✅ Check mode |
| **Parallelization** | ⚠️ Limited (async) | ✅ Native (forks) |
| **Readability** | ⚠️ Procedural | ✅ Declarative |
| **Testing** | ❌ None | ✅ Check/Diff mode |
| **Documentation** | ⚠️ Comments | ✅ Self-documenting |
| **Reusability** | ❌ Monolithic | ✅ Roles |
| **State Management** | ❌ Manual | ✅ Automatic |
| **Learning Curve** | Low | Medium |

---

## 🐛 Troubleshooting

### Common Issues

**Dynamic inventory not working:**
```bash
# Check DO token
echo $DO_API_TOKEN

# Test doctl
doctl compute droplet list

# Clear cache
rm -rf /tmp/ansible_digitalocean_cache
```

**SSH connection issues:**
```bash
# Test SSH manually
ssh -i ~/.ssh/wp-farm-deploy-key root@<manager-ip>

# Check SSH agent
ssh-add ~/.ssh/wp-farm-deploy-key
```

**Swarm join failures:**
```bash
# Check tokens
ansible-playbook deploy.yml --tags swarm,init -vv

# Manual join
ssh root@<node-ip> \
  docker swarm join --token <token> <manager-ip>:2377
```

**Service deployment timeout:**
```bash
# Check service logs
ansible swarm_managers[0] -m shell \
  -a "docker service logs <service-name> --tail 50"

# Check constraints
ansible swarm_managers[0] -m shell \
  -a "docker service inspect <service-name> | jq '.[] | .Spec.TaskTemplate.Placement'"
```

---

## 📚 Additional Documentation

- [USAGE.md](docs/USAGE.md) - Detailed usage examples
- [MIGRATION.md](docs/MIGRATION.md) - Migrating from bash script
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [../docs/](../docs/) - Original documentation

---

## 🤝 Contributing

Improvements welcome! This is a production system, so:

1. Test changes in a staging environment
2. Use check mode first
3. Document new variables
4. Follow Ansible best practices

---

## 📞 Support

- **Documentation**: See `docs/` directory
- **Issues**: Check bash script documentation
- **Questions**: Review playbook comments

---

## 📜 License

Same as the original WordPress farm infrastructure project.

---

## ✅ Migration Checklist

Migrating from bash script to Ansible:

- [ ] Install Ansible and collections
- [ ] Configure `.env` file
- [ ] Test provision playbook with `--check`
- [ ] Provision infrastructure
- [ ] Deploy services
- [ ] Run health checks
- [ ] Create test WordPress site
- [ ] Configure DNS
- [ ] Verify backups
- [ ] Update runbooks/documentation
- [ ] Train team on Ansible commands
- [ ] Deprecate bash script

---

**Status**: ✅ Production Ready  
**Version**: 2.0.0 (Ansible Edition)  
**Last Updated**: 2026-02-07

---

**Ready to deploy? Run:**

```bash
ansible-playbook provision.yml && ansible-playbook deploy.yml
```

🚀 **Let's build something awesome!**
