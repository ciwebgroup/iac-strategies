# Initial Setup Guide - WordPress Farm Infrastructure

This guide walks you through the **manual prerequisites** required before using the automated infrastructure deployment tools.

**Estimated Time:** 2-3 hours  
**Skill Level:** Intermediate (Linux, Cloud, Networking basics)

---

## 📋 Table of Contents

1. [Prerequisites Overview](#prerequisites-overview)
2. [Local Machine Setup](#local-machine-setup)
3. [DigitalOcean Account Setup](#digitalocean-account-setup)
4. [Cloudflare Account Setup](#cloudflare-account-setup)
5. [Third-Party Services](#third-party-services-optional)
6. [SSH Key Generation](#ssh-key-generation)
7. [Environment Configuration](#environment-configuration)
8. [First Deployment](#first-deployment)
9. [Post-Deployment Configuration](#post-deployment-configuration)
10. [Troubleshooting](#troubleshooting)

---

## ✅ Prerequisites Overview

### Required Accounts

- [ ] DigitalOcean account with billing enabled
- [ ] Cloudflare account (free tier OK)
- [ ] Domain name (registered and active)

### Optional Accounts

- [ ] SendGrid account (for email alerts)
- [ ] Twilio account (for SMS alerts)
- [ ] GitHub/GitLab account (for code storage)
- [ ] PagerDuty account (for incident management)

### Local Machine Requirements

- [ ] Linux or macOS (Windows WSL2 also works)
- [ ] Bash shell (version 4.0+)
- [ ] Internet connection (stable, high-speed preferred)
- [ ] 5GB free disk space (for tools and temp files)

### Knowledge Requirements

- Basic Linux command line
- Understanding of Docker concepts
- Basic networking knowledge (IP, DNS, ports)
- Comfort with editing configuration files

---

## 💻 Local Machine Setup

### 1. Install Required Tools

#### On Ubuntu/Debian:

```bash
# Update package list
sudo apt update

# Install core tools
sudo apt install -y \
    curl \
    wget \
    git \
    jq \
    python3 \
    python3-pip \
    ssh \
    openssh-client \
    apache2-utils

# Install DigitalOcean CLI (doctl)
cd ~
wget https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
tar xf ~/doctl-1.104.0-linux-amd64.tar.gz
sudo mv ~/doctl /usr/local/bin
rm ~/doctl-1.104.0-linux-amd64.tar.gz

# Verify installation
doctl version

# Install Docker (if testing locally)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

#### On macOS:

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install \
    doctl \
    jq \
    wget \
    git

# Install Docker Desktop
brew install --cask docker
```

#### Verify All Tools:

```bash
# Check each tool
doctl version      # Should show version 1.104.0 or higher
docker --version   # Should show version 20.10.0 or higher
jq --version       # Should show version 1.6 or higher
ssh -V            # Should show OpenSSH version
git --version     # Should show Git version
```

---

## 🌊 DigitalOcean Account Setup

### 1. Create DigitalOcean Account

1. **Sign up:** https://cloud.digitalocean.com/registrations/new
2. **Verify email** address
3. **Add billing information:**
   - Credit card OR
   - PayPal
4. **Initial credit:**
   - Use promo code if available (e.g., $200 credit for 60 days)

### 2. Generate API Token

1. **Navigate to:** https://cloud.digitalocean.com/account/api/tokens
2. **Click:** "Generate New Token"
3. **Token Name:** `wordpress-farm-deploy`
4. **Scopes:** Select "Read" and "Write"
5. **Expiration:** Never (or 90 days if security policy requires)
6. **Copy token immediately** (shown only once!)
7. **Save token securely** (password manager recommended)

Example token format:

```
dop_v1_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVW
```

### 3. Authenticate CLI

```bash
# Initialize doctl authentication
doctl auth init

# When prompted, paste your API token
# Token: dop_v1_...

# Verify authentication
doctl account get

# Expected output:
# Email: your-email@example.com
# Droplet Limit: 25
# Status: active
```

### 4. Create Spaces Access Keys

Spaces is DigitalOcean's S3-compatible object storage for backups.

1. **Navigate to:** https://cloud.digitalocean.com/account/api/spaces
2. **Click:** "Generate New Key"
3. **Key Name:** `wordpress-farm-backups`
4. **Copy both:**
   - Access Key: `DO00XXXXXXXXXXXXX`
   - Secret Key: `xxxxxxxxxxxxxxxxxxxxxx`
5. **Save securely**

### 5. Create VPC (Optional - can be automated)

1. **Navigate to:** https://cloud.digitalocean.com/networking/vpc
2. **Click:** "Create VPC Network"
3. **Name:** `wordpress-farm-vpc`
4. **Region:** `NYC3` (or your preferred region)
5. **IP Range:** `10.0.0.0/16`
6. **Note the VPC UUID** for later

---

## ☁️ Cloudflare Account Setup

### 1. Create Cloudflare Account

1. **Sign up:** https://dash.cloudflare.com/sign-up
2. **Verify email** address
3. **Free plan is sufficient** for most use cases

### 2. Add Your Domain to Cloudflare

1. **Click:** "Add a Site"
2. **Enter your domain:** `yourdomain.com`
3. **Select plan:** Free
4. **Cloudflare scans** existing DNS records
5. **Review and import** DNS records
6. **Update nameservers** at your domain registrar to:
   ```
   alice.ns.cloudflare.com
   bob.ns.cloudflare.com
   ```
7. **Wait for activation** (usually 5-60 minutes)

### 3. Generate API Token

1. **Navigate to:** https://dash.cloudflare.com/profile/api-tokens
2. **Click:** "Create Token"
3. **Use template:** "Edit zone DNS"
4. **Permissions:**
   - Zone - DNS - Edit
   - Zone - Zone - Read
5. **Zone Resources:**
   - Include - Specific zone - yourdomain.com
6. **Click:** "Continue to summary"
7. **Click:** "Create Token"
8. **Copy token** (shown only once!)

Example token format:

```
abcdefghijklmnopqrstuvwxyz1234567890ABCD
```

### 4. Get Zone ID

1. **Navigate to:** https://dash.cloudflare.com/
2. **Select your domain**
3. **Scroll down in Overview tab**
4. **Find "Zone ID"** in the API section
5. **Copy Zone ID**

Example Zone ID:

```
1234567890abcdef1234567890abcdef
```

### 5. Configure Cloudflare Settings (Optional but Recommended)

```
SSL/TLS:
- Mode: Full (strict)
- Edge Certificates: Automatic HTTPS Rewrites ON
- Always Use HTTPS: ON

Speed:
- Auto Minify: CSS, JavaScript, HTML
- Brotli: ON

Caching:
- Caching Level: Standard
- Browser Cache TTL: Respect Existing Headers

Security:
- Security Level: Medium
- Challenge Passage: 30 minutes
- Browser Integrity Check: ON

Network:
- HTTP/2: ON
- HTTP/3 (with QUIC): ON
- 0-RTT Connection Resumption: ON
```

---

## 📧 Third-Party Services (Optional)

### SendGrid (Email Alerts)

1. **Sign up:** https://signup.sendgrid.com/
2. **Verify email and account**
3. **Create API Key:**
   - Settings → API Keys → Create API Key
   - Name: `wordpress-farm-alerts`
   - Permissions: Full Access (or Restricted: Mail Send)
   - Copy key: `SG.xxxxxxxxxxx...`
4. **Verify sender identity:**
   - Settings → Sender Authentication
   - Verify single sender OR domain
   - Use: `alerts@yourdomain.com`

**Free tier:** 100 emails/day (sufficient for alerts)

### Twilio (SMS Alerts)

1. **Sign up:** https://www.twilio.com/try-twilio
2. **Complete verification** (phone number required)
3. **Get credentials from dashboard:**
   - Account SID: `ACxxxxxxxxxxxxxxxx`
   - Auth Token: `xxxxxxxxxxxxxxxx`
4. **Get phone number:**
   - Buy a number ($1-2/month) OR
   - Use trial number (limited)
5. **Note your Twilio phone number:** `+15551234567`

**Free trial:** $15 credit, then pay-as-you-go (~$0.0075/SMS)

### PagerDuty (Optional - Enterprise)

1. **Sign up:** https://www.pagerduty.com/sign-up/
2. **Create service:**
   - Services → Service Directory → New Service
   - Name: WordPress Farm
   - Integration: Prometheus
3. **Copy Integration Key**
4. **Set up escalation policies**
5. **Configure on-call schedules**

---

## 🔑 SSH Key Generation

### 1. Generate SSH Key Pair

```bash
# Create SSH directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate ED25519 key (modern, secure)
ssh-keygen -t ed25519 \
  -f ~/.ssh/wp-farm-deploy-key \
  -C "wp-farm-deploy@$(hostname)" \
  -N ""

# Or RSA if ED25519 not supported (older systems)
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/wp-farm-deploy-key -N ""

# Verify keys were created
ls -la ~/.ssh/wp-farm-deploy-key*

# Expected output:
# -rw------- wp-farm-deploy-key       (private key)
# -rw-r--r-- wp-farm-deploy-key.pub   (public key)

# Display public key
cat ~/.ssh/wp-farm-deploy-key.pub
```

### 2. Add SSH Key to DigitalOcean

**Option A: Via Web UI**

1. **Navigate to:** https://cloud.digitalocean.com/account/security
2. **Click:** "Add SSH Key"
3. **Paste** contents of `~/.ssh/wp-farm-deploy-key.pub`
4. **Name:** `wp-farm-deploy-key`
5. **Click:** "Add SSH Key"

**Option B: Via CLI**

```bash
# Upload SSH key to DO
doctl compute ssh-key import wp-farm-deploy-key \
  --public-key-file ~/.ssh/wp-farm-deploy-key.pub

# List SSH keys to verify
doctl compute ssh-key list

# Note the Key ID and Fingerprint
```

### 3. Configure SSH Client

```bash
# Add to SSH config for easier access
cat >> ~/.ssh/config <<EOF

# WordPress Farm Infrastructure
Host wp-farm-*
    User root
    IdentityFile ~/.ssh/wp-farm-deploy-key
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host *.yourdomain.com
    User root
    IdentityFile ~/.ssh/wp-farm-deploy-key
EOF

chmod 600 ~/.ssh/config
```

---

## ⚙️ Environment Configuration

### 1. Clone Repository

```bash
# Clone the infrastructure repository
cd ~/projects  # or your preferred directory
git clone <repository-url> wordpress-farm-infrastructure
cd wordpress-farm-infrastructure/control-center/scripts

# Or if you're setting up from scratch
mkdir -p ~/projects/wordpress-farm
cd ~/projects/wordpress-farm
```

### 2. Configure Environment (Automated)

We provide an **automated setup script** that handles all environment configuration:

**Option A: Interactive Mode (Recommended)**

```bash
# Run interactive setup wizard
./setup-env.sh

# The script will:
# ✓ Prompt for all required values (API tokens, domains, etc.)
# ✓ Auto-generate ALL passwords securely
# ✓ Validate your configuration
# ✓ Create .env file with everything configured
```

The interactive wizard will guide you through:

1. **DigitalOcean Configuration** - API token, region, SSH key, Spaces credentials
2. **Cloudflare Configuration** - API token, email, account ID
3. **Domain & SSL** - Primary domain, Let's Encrypt email
4. **Node Configuration** - Cluster sizing (managers, workers, cache, DB, etc.)
5. **Alerting** (Optional) - Slack webhooks, SendGrid for email alerts
6. **Password Generation** - All security credentials auto-generated
7. **Validation** - Checks all required variables and password strength

**Option B: Quick Generation (For Advanced Users)**

```bash
# Generate .env with auto-generated passwords
./setup-env.sh --print-env-only > .env

# Then edit to add your API tokens and domain:
vim .env  # or nano, code, etc.

# Update these values:
# - DO_API_TOKEN
# - DO_SPACES_ACCESS_KEY
# - DO_SPACES_SECRET_KEY
# - CF_API_TOKEN
# - CF_API_EMAIL
# - DOMAIN
# - LETSENCRYPT_EMAIL

# All passwords are already generated!
```

**Option C: Manual Configuration**

```bash
# Generate example template
./setup-env.sh --print-env-example-only > .env

# Secure the file
chmod 600 .env

# Edit and replace all CHANGE_ME values
vim .env
```

### 3. What Gets Auto-Generated

The `setup-env.sh` script automatically generates:

✅ **Database Credentials:**

- MySQL root password (32 chars)
- ProxySQL admin password
- Galera SST password
- Database backup password

✅ **Cache Credentials:**

- Redis password (32 chars)
- Varnish secret (64 hex chars)

✅ **Monitoring:**

- Grafana admin password
- Prometheus settings

✅ **Management:**

- Portainer admin password
- Traefik dashboard auth (htpasswd hash)

✅ **Backup Encryption:**

- Restic password
- Backup encryption key

### 4. Validate Configuration

```bash
# Validate your .env file
./setup-env.sh --validate

# Expected output:
# ✓ DO_API_TOKEN is configured
# ✓ CF_API_TOKEN is configured
# ✓ DOMAIN is configured
# ✓ MYSQL_ROOT_PASSWORD is strong
# ✓ Manager count: 3
# ✓ Database HA enabled (2 nodes)
# ✅ All validation checks passed!
```

### 5. Save Credentials Securely

**IMPORTANT:** Your `.env` file contains sensitive credentials!

```bash
# Ensure .env is in .gitignore
echo '.env' >> .gitignore

# Set restrictive permissions
chmod 600 .env

# Backup to secure location (password manager, encrypted vault)
cp .env ~/.env.wp-farm.backup

# Or save critical credentials to password manager:
grep -E '(GRAFANA|PORTAINER|TRAEFIK|MYSQL_ROOT)_PASSWORD' .env
```

---

## 🚀 First Deployment

### 1. Test Connectivity

```bash
# Test DO API
doctl account get

# Test Cloudflare API
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type:application/json"

# Expected: {"result":{"status":"active"},"success":true}
```

### 2. Run Dry-Run (Optional)

```bash
# Test what would be created (no actual changes)
./manage-infrastructure.sh provision --all --dry-run

# Review output carefully
```

### 3. Deployment Mode

Choose your deployment approach:

**Interactive Mode (Recommended for First Time):**

```bash
# Deploy with verification pauses at each step
./manage-infrastructure.sh --interactive provision --all

# At each checkpoint, you'll see:
# - What was just deployed
# - Verification commands to run
# - Option to [R]etry, [C]ontinue, or [A]bort
```

**Automated Mode (For Experienced Users):**

```bash
# Deploy without pauses (for automation/CI)
./manage-infrastructure.sh --no-interactive provision --all
```

**Default:** Interactive mode is enabled by default

### 4. Provision Infrastructure (15-25 minutes)

```bash
# This provisions all nodes with interactive verification
./manage-infrastructure.sh provision --all

# The script will:
# 1. Create manager nodes (3x)
# 2. Wait for SSH & Docker
# 3. Deploy verification scripts to each node
# 4. Pause for manual verification
# 5. Repeat for workers, cache, DB, storage, monitoring

# At each pause, run suggested commands:
ssh root@<node_ip> '/opt/verify/verify-node.sh'
```

**Verification scripts deployed to each node:**

- `/opt/verify/verify-node.sh` - Node health (SSH, Docker, network, disk)
- `/opt/verify/verify-swarm.sh` - Cluster health (quorum, managers, workers)
- `/opt/verify/verify-labels.sh` - Node labels validation
- `/opt/verify/verify-networks.sh` - Overlay network checks
- `/opt/verify/verify-stack.sh` - Per-stack service health

### 5. Initialize Docker Swarm (2-3 minutes)

```bash
# Initialize Swarm on first manager
./manage-infrastructure.sh init-swarm

# Verification checkpoint:
# Run: ssh root@<manager_ip> 'docker node ls'
# Expected: 1 manager node in 'Ready' state

# Note: Join tokens are automatically saved to .env
```

### 6. Join Nodes (5-10 minutes)

```bash
# Join remaining managers and all workers
./manage-infrastructure.sh join-nodes

# Verification checkpoint:
# Run: ssh root@<manager_ip> '/opt/verify/verify-swarm.sh'
# Expected:
# - All managers + workers listed
# - All nodes in 'Ready' status
# - One manager marked as 'Leader'
# - Raft quorum healthy
```

### 7. Label Nodes (1-2 minutes)

```bash
# Apply node labels for service placement
./manage-infrastructure.sh label-nodes

# Verification checkpoint:
# Run: ssh root@<manager_ip> '/opt/verify/verify-labels.sh'
# Expected:
# - cache=true on cache nodes (with cache-node=N)
# - db=true on database nodes (with db-node=N)
# - storage=true on storage nodes
# - app=true on worker nodes
# - ops=true on monitoring nodes
```

### 8. Create Networks (1 minute)

```bash
# Create Docker overlay networks
./manage-infrastructure.sh create-networks

# Verification checkpoint:
# Run: ssh root@<manager_ip> '/opt/verify/verify-networks.sh'
# Expected: All 9 networks created:
# - traefik-public, wordpress-net, database-net, storage-net
# - cache-net, observability-net, crowdsec-net
# - management-net, contractor-net
```

### 9. Deploy Stacks (10-20 minutes)

```bash
# Deploy all infrastructure stacks with smart waiting
./manage-infrastructure.sh deploy --all

# The script will deploy in dependency order:
# 1. Traefik (reverse proxy) → wait for ready
# 2. Cache (Redis + Varnish) → wait for ready
# 3. Database (MySQL Galera) → wait for ready
# 4. Monitoring (Prometheus + Grafana) → wait for ready
# 5. Management (Portainer) → wait for ready
# 6. Backup services → wait for ready
# 7. Contractor access → wait for ready

# At each checkpoint, you can verify:
ssh root@<manager_ip> '/opt/verify/verify-stack.sh <stack_name>'
```

**Note:** The script now uses `wait_for_stack()` instead of fixed `sleep` delays, so deployment is faster and more reliable!

### 10. Final Verification

```bash
# Run comprehensive health check
./manage-infrastructure.sh health

# Or manually verify:
ssh root@<manager_ip> 'docker node ls'          # All nodes Ready
ssh root@<manager_ip> 'docker service ls'       # All services running
ssh root@<manager_ip> 'docker stack ls'         # All stacks active
ssh root@<manager_ip> '/opt/verify/verify-swarm.sh'  # Full cluster check

# Check for any failing services:
ssh root@<manager_ip> 'docker service ls --filter "desired-state=running" | grep "0/"'
# Expected: No output (all services have replicas)
```

---

## 🔧 Post-Deployment Configuration

### 1. Access Grafana

```bash
# Get manager IP
MANAGER_IP=$(doctl compute droplet list --tag-name swarm-manager --format PublicIPv4 --no-header | head -n1)

echo "Grafana URL: https://grafana.${DOMAIN}"
echo "Username: admin"
echo "Password: ${GRAFANA_ADMIN_PASSWORD}"
```

Navigate to Grafana and:

1. Change admin password (if needed)
2. Import dashboards from `/configs/grafana/dashboards/`
3. Configure data sources (auto-provisioned)
4. Set up alert notifications

### 2. Access Portainer

```bash
echo "Portainer URL: https://portainer.${DOMAIN}"
echo "Username: admin"
echo "Password: ${PORTAINER_ADMIN_PASSWORD}"
```

Configure:

1. Accept EULA
2. Connect to Swarm cluster
3. Add registries if using private images
4. Configure RBAC if needed

### 3. Configure Alertmanager

1. Navigate to `https://alerts.${DOMAIN}`
2. Verify Slack integration works
3. Send test alert
4. Configure alert routing rules
5. Set quiet hours if needed

### 4. Create First WordPress Site

```bash
# Create a test site
./scripts/manage-infrastructure.sh site --create test.${DOMAIN}

# Wait 2-3 minutes for deployment

# Navigate to: https://test.${DOMAIN}
# Should see WordPress installation page
```

### 5. Configure Backups

```bash
# Test database backup
./scripts/manage-infrastructure.sh backup

# Verify backup in DO Spaces
# Navigate to: https://cloud.digitalocean.com/spaces/${DO_SPACES_BUCKET}
```

### 6. Configure DNS

For each site:

```bash
# Get load balancer IP
LB_IP=$(doctl compute load-balancer list --format IP --no-header)

# Add DNS record (automated or manual)
./scripts/manage-infrastructure.sh dns --add yourdomain.com --ip $LB_IP
```

---

## 🔍 Verification Checklist

After deployment, verify everything works:

- [ ] All nodes show as "Ready" in Swarm
- [ ] All services have desired replica count
- [ ] Grafana accessible and showing metrics
- [ ] Portainer accessible and connected
- [ ] Traefik dashboard shows routes
- [ ] Cache hit ratio > 0% (after some traffic)
- [ ] Database cluster shows 3 nodes online
- [ ] Storage mounts working on workers
- [ ] Alerts can be sent to Slack
- [ ] Email alerts work (if configured)
- [ ] Test WordPress site loads
- [ ] HTTPS certificates auto-issued
- [ ] Backup job completes successfully

---

## 🐛 Troubleshooting

### SSH Connection Issues

```bash
# Test SSH to manager
MANAGER_IP=$(doctl compute droplet list --tag-name swarm-manager --format PublicIPv4 --no-header | head -n1)
ssh -i ~/.ssh/wp-farm-deploy-key root@$MANAGER_IP

# If connection refused, wait 60 seconds for droplet to boot
# If permission denied, verify SSH key was added to DO
```

### Swarm Init Fails

```bash
# Check if Swarm already initialized
ssh root@$MANAGER_IP "docker info | grep Swarm"

# If already init, leave and re-init
ssh root@$MANAGER_IP "docker swarm leave --force"
./scripts/manage-infrastructure.sh init-swarm
```

### Service Won't Start

```bash
# Check service logs
ssh root@$MANAGER_IP "docker service logs <service-name> --tail 50"

# Check service constraints
ssh root@$MANAGER_IP "docker service inspect <service-name> | jq '.[] | .Spec.TaskTemplate.Placement'"

# Verify nodes have required labels
ssh root@$MANAGER_IP "docker node ls -q | xargs docker node inspect | jq '.[] | {Name: .Description.Hostname, Labels: .Spec.Labels}'"
```

### DNS Not Resolving

```bash
# Check Cloudflare DNS
dig @1.1.1.1 yourdomain.com

# Check if proxied (orange cloud)
# Should resolve to Cloudflare IP, not your server IP

# Verify origin server accessible
curl -H "Host: yourdomain.com" http://$LB_IP
```

### Alerts Not Working

```bash
# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert from WordPress Farm"}' \
  $SLACK_WEBHOOK_URL

# Check Alertmanager logs
ssh root@$MANAGER_IP "docker service logs alerting_alertmanager"
```

---

## 📚 Next Steps

After successful initial setup:

1. **Read:** [Implementation Guide](implementation-guide.md)
2. **Review:** [Network Topology](diagrams/NETWORK-TOPOLOGY.md)
3. **Study:** [Cost Analysis](cost-analysis.md)
4. **Setup:** Additional monitoring dashboards
5. **Configure:** Automated scaling policies
6. **Document:** Your specific customizations
7. **Train:** Your team on operations

---

## 🆘 Getting Help

If you encounter issues:

1. **Check logs:** Use `docker service logs <service>`
2. **Review docs:** All documentation in this repository
3. **Search issues:** GitHub issues for similar problems
4. **Ask community:** Docker/Swarm forums
5. **Contact support:** DigitalOcean or Cloudflare support if platform-specific

---

## ✅ You're Ready!

If you've completed all steps above, you have:

- ✅ Fully automated infrastructure deployment
- ✅ Production-ready WordPress farm
- ✅ Comprehensive monitoring and alerting
- ✅ Automated backups
- ✅ High availability setup
- ✅ Dedicated cache tier (Opus 4.5 style)

**Estimated total time:** 3-4 hours  
**Infrastructure cost:** ~$3,707/month for 500 sites  
**Next:** Start migrating WordPress sites or creating new ones!

---

**Last Updated:** $(date)  
**Version:** 1.0.0  
**Status:** Production Ready
