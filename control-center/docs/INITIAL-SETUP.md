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
cd wordpress-farm-infrastructure/sonnet-4.5

# Or if you're setting up from scratch
mkdir -p ~/projects/wordpress-farm
cd ~/projects/wordpress-farm
```

### 2. Create Environment File

```bash
# Copy template to .env
cp env.example .env

# Secure the file
chmod 600 .env

# Open for editing
nano .env  # or vim, code, etc.
```

### 3. Configure Required Variables

**Minimum required configuration:**

```bash
# DigitalOcean
DO_API_TOKEN=dop_v1_your_actual_token_here
DO_SPACES_ACCESS_KEY=DO00XXXXXXXXXXXX
DO_SPACES_SECRET_KEY=your_secret_key_here
DO_SPACES_REGION=nyc3
DO_SPACES_BUCKET=wp-farm-backups
DO_REGION=nyc3
DO_SSH_KEY_NAME=wp-farm-deploy-key

# Cloudflare
CF_API_TOKEN=your_cloudflare_token_here
CF_API_EMAIL=your-email@example.com
CF_ZONE_ID=your_zone_id_here
CF_ACCOUNT_ID=your_account_id_here

# Domain
DOMAIN=yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com

# Security (Generate with: openssl rand -base64 32)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
PROXYSQL_ADMIN_PASSWORD=$(openssl rand -base64 32)
VARNISH_SECRET=$(openssl rand -hex 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
PORTAINER_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Alerting (Optional - can configure later)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
SENDGRID_API_KEY=SG.your_sendgrid_key_here
SENDGRID_FROM_EMAIL=alerts@yourdomain.com
SENDGRID_TO_EMAIL=ops-team@yourdomain.com
```

**Generate strong passwords:**
```bash
# Run this to generate all passwords
cat <<EOF >> .env

# Generated Passwords ($(date))
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
PROXYSQL_ADMIN_PASSWORD=$(openssl rand -base64 32)
GALERA_SST_PASSWORD=$(openssl rand -base64 32)
DB_BACKUP_PASSWORD=$(openssl rand -base64 32)
VARNISH_SECRET=$(openssl rand -hex 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
PORTAINER_ADMIN_PASSWORD=$(openssl rand -base64 32)
BACKUP_ENCRYPTION_PASSWORD=$(openssl rand -base64 32)
RESTIC_PASSWORD=$(openssl rand -base64 32)
EOF
```

**Generate htpasswd for Traefik:**
```bash
# Install htpasswd if not available
sudo apt install apache2-utils

# Generate password hash
TRAEFIK_PASSWORD=$(htpasswd -nb admin "$(openssl rand -base64 16)")

# Add to .env
echo "TRAEFIK_DASHBOARD_PASSWORD_HASH='$TRAEFIK_PASSWORD'" >> .env
```

### 4. Validate Configuration

```bash
# Source the .env file
set -a
source .env
set +a

# Check required variables
required_vars=(
    "DO_API_TOKEN"
    "CF_API_TOKEN"
    "DOMAIN"
    "MYSQL_ROOT_PASSWORD"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is not set"
    else
        echo "OK: $var is configured"
    fi
done
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

### 2. Run Dry-Run

```bash
# Test what would be created (no actual changes)
./scripts/manage-infrastructure.sh provision --all --dry-run

# Review output carefully
```

### 3. Provision Infrastructure

```bash
# This will take 15-30 minutes
./scripts/manage-infrastructure.sh provision --all

# Monitor progress
# Creates: Managers, Workers, Cache, Database, Storage, Monitoring nodes
```

### 4. Initialize Docker Swarm

```bash
# Initialize Swarm on first manager
./scripts/manage-infrastructure.sh init-swarm

# Note the tokens displayed - they're also saved to .env

# Join remaining nodes
./scripts/manage-infrastructure.sh join-nodes

# This takes 5-10 minutes
```

### 5. Label Nodes

```bash
# Apply node labels for service placement
./scripts/manage-infrastructure.sh label-nodes

# Labels nodes as: cache, database, storage, app, ops
```

### 6. Create Networks

```bash
# Create Docker overlay networks
./scripts/manage-infrastructure.sh create-networks

# Creates: traefik-public, wordpress-net, database-net, etc.
```

### 7. Deploy Stacks

```bash
# Deploy all infrastructure stacks
./scripts/manage-infrastructure.sh deploy --all

# This deploys:
# - Traefik (edge router)
# - Cache layer (Varnish + Redis)
# - Database (MariaDB Galera + ProxySQL)
# - Monitoring (Grafana, Prometheus, Loki, Tempo)
# - Alerting (Alertmanager)
# - Management (Portainer)

# Takes 10-15 minutes
```

### 8. Verify Deployment

```bash
# Run health checks
./scripts/manage-infrastructure.sh health

# Expected output:
# - All nodes: Ready
# - All services: Running (replicas match desired)
# - All stacks: Active
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

