#!/usr/bin/env bash
#
# WordPress Farm Infrastructure - Environment Setup Script
#
# This script interactively generates the .env configuration file with:
# - User-provided values (tokens, domains, etc.)
# - Auto-generated secure passwords
# - Validation of required settings
#
# Usage:
#   ./setup-env.sh                    # Interactive mode
#   ./setup-env.sh --from-example     # Copy from .env.example and fill in
#   ./setup-env.sh --validate         # Just validate existing .env
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
CF_ZONES_CONFIG="${SCRIPT_DIR}/cloudflare-zones.yml"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

die() {
    log_error "$*"
    exit 1
}

# Prompt for input with optional default
prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="${3:-}"
    local secret="${4:-false}"
    
    local current_value="${!var_name:-}"
    
    # Use current value if already set
    if [[ -n "$current_value" ]]; then
        default_value="$current_value"
    fi
    
    if [[ -n "$default_value" ]]; then
        if [[ "$secret" == "true" ]]; then
            read -r -p "$(echo -e "${CYAN}${prompt_text}${NC} [${YELLOW}***hidden***${NC}]: ")" value
        else
            read -r -p "$(echo -e "${CYAN}${prompt_text}${NC} [${YELLOW}${default_value}${NC}]: ")" value
        fi
        value="${value:-$default_value}"
    else
        if [[ "$secret" == "true" ]]; then
            read -r -p "$(echo -e "${CYAN}${prompt_text}${NC}: ")" value
        else
            read -r -p "$(echo -e "${CYAN}${prompt_text}${NC}: ")" value
        fi
    fi
    
    eval "$var_name=\"$value\""
}

confirm() {
    local prompt="$1"
    read -r -p "$(echo -e "${YELLOW}${prompt}${NC} [y/N]: ")" response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Generate secure random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Generate hex secret
generate_hex_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length" | tr -d '\n'
}

# Generate htpasswd hash
generate_htpasswd() {
    local username="$1"
    local password="$2"
    htpasswd -nb "$username" "$password" | tr -d '\n'
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    
    # Check for openssl
    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found (required for password generation)"
        ((missing++))
    fi
    
    # Check for htpasswd
    if ! command -v htpasswd &>/dev/null; then
        log_warn "htpasswd not found (needed for Traefik dashboard auth)"
        log_info "Install with: sudo apt install apache2-utils"
        ((missing++))
    fi
    
    # Check for yq (optional, for Cloudflare zones)
    if ! command -v yq &>/dev/null; then
        log_warn "yq not found (optional, for Cloudflare multi-zone config)"
        log_info "Install from: https://github.com/mikefarah/yq"
    fi
    
    if [[ $missing -gt 0 ]]; then
        die "Missing $missing required tool(s). Please install and try again."
    fi
    
    log_success "All prerequisites satisfied"
}

# =============================================================================
# CONFIGURATION COLLECTION
# =============================================================================

collect_digitalocean_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  DigitalOcean Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    prompt DO_API_TOKEN "DigitalOcean API Token (from https://cloud.digitalocean.com/account/api/tokens)" "" "true"
    prompt DO_REGION "DigitalOcean Region" "nyc3"
    prompt DO_SSH_KEY_NAME "SSH Key Name (must exist in DO)" "wp-farm-deploy-key"
    
    echo ""
    log_info "DigitalOcean Spaces (S3-compatible storage for backups)"
    prompt DO_SPACES_ACCESS_KEY "Spaces Access Key" "" "true"
    prompt DO_SPACES_SECRET_KEY "Spaces Secret Key" "" "true"
    prompt DO_SPACES_REGION "Spaces Region" "${DO_REGION}"
    prompt DO_SPACES_BUCKET "Spaces Bucket Name" "wp-farm-backups"
}

collect_cloudflare_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cloudflare Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    prompt CF_API_TOKEN "Cloudflare API Token (needs Zone:Edit, DNS:Edit)" "" "true"
    prompt CF_API_EMAIL "Cloudflare Account Email" ""
    prompt CF_ACCOUNT_ID "Cloudflare Account ID (optional)" ""
    
    # Offer to create cloudflare-zones.yml for multi-zone support
    if confirm "Do you have multiple Cloudflare zones to manage?"; then
        log_info "You'll need to create ${CF_ZONES_CONFIG} manually"
        log_info "See .env.example for the YAML structure"
    fi
}

collect_domain_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Domain & Email Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    prompt DOMAIN "Primary Domain" "example.com"
    prompt LETSENCRYPT_EMAIL "Let's Encrypt Email" "admin@${DOMAIN}"
}

collect_node_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cluster Node Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_info "Manager nodes (minimum 1, recommended 3 for HA)"
    prompt MANAGER_NODE_COUNT "Manager Node Count" "3"
    prompt MANAGER_NODE_SIZE "Manager Node Size" "s-2vcpu-4gb"
    
    log_info "Worker nodes (application servers)"
    prompt WORKER_NODE_COUNT "Worker Node Count" "3"
    prompt WORKER_NODE_SIZE "Worker Node Size" "s-2vcpu-4gb"
    
    log_info "Cache nodes (Redis + Varnish)"
    prompt CACHE_NODE_COUNT "Cache Node Count" "2"
    prompt CACHE_NODE_SIZE "Cache Node Size" "s-2vcpu-4gb"
    
    log_info "Database nodes (MySQL/MariaDB)"
    prompt DB_NODE_COUNT "Database Node Count" "2"
    prompt DB_NODE_SIZE "Database Node Size" "s-4vcpu-8gb"
    
    log_info "Storage nodes (NFS for uploads)"
    prompt STORAGE_NODE_COUNT "Storage Node Count" "2"
    prompt STORAGE_NODE_SIZE "Storage Node Size" "s-2vcpu-4gb"
    prompt STORAGE_VOLUME_SIZE "Block Storage Volume Size (GB)" "100"
    
    log_info "Monitoring nodes (Prometheus, Grafana, Loki)"
    prompt MONITOR_NODE_COUNT "Monitor Node Count" "1"
    prompt MONITOR_NODE_SIZE "Monitor Node Size" "s-4vcpu-8gb"
}

collect_alerting_config() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Alerting Configuration (Optional)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if confirm "Configure Slack alerts?"; then
        prompt SLACK_WEBHOOK_URL "Slack Webhook URL" "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    else
        SLACK_WEBHOOK_URL=""
    fi
    
    if confirm "Configure email alerts (via SendGrid)?"; then
        prompt SENDGRID_API_KEY "SendGrid API Key" "" "true"
        prompt SENDGRID_FROM_EMAIL "Alert From Email" "alerts@${DOMAIN}"
        prompt SENDGRID_TO_EMAIL "Alert To Email" "ops-team@${DOMAIN}"
    else
        SENDGRID_API_KEY=""
        SENDGRID_FROM_EMAIL=""
        SENDGRID_TO_EMAIL=""
    fi
}

# =============================================================================
# PASSWORD GENERATION
# =============================================================================

generate_all_passwords() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Generating Secure Passwords${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log_info "Generating database passwords..."
    MYSQL_ROOT_PASSWORD=$(generate_password 32)
    PROXYSQL_ADMIN_PASSWORD=$(generate_password 32)
    GALERA_SST_PASSWORD=$(generate_password 32)
    DB_BACKUP_PASSWORD=$(generate_password 32)
    
    log_info "Generating cache passwords..."
    REDIS_PASSWORD=$(generate_password 32)
    VARNISH_SECRET=$(generate_hex_secret 32)
    
    log_info "Generating monitoring passwords..."
    GRAFANA_ADMIN_PASSWORD=$(generate_password 32)
    
    log_info "Generating management passwords..."
    PORTAINER_ADMIN_PASSWORD=$(generate_password 32)
    
    log_info "Generating backup encryption keys..."
    BACKUP_ENCRYPTION_PASSWORD=$(generate_password 32)
    RESTIC_PASSWORD=$(generate_password 32)
    
    log_info "Generating Traefik dashboard auth..."
    TRAEFIK_PASSWORD=$(generate_password 16)
    TRAEFIK_DASHBOARD_PASSWORD_HASH=$(generate_htpasswd "admin" "$TRAEFIK_PASSWORD")
    
    log_success "All passwords generated"
    
    # Show critical passwords
    echo ""
    log_warn "IMPORTANT: Save these credentials securely!"
    echo ""
    echo -e "${YELLOW}Grafana Admin:${NC} admin / ${GRAFANA_ADMIN_PASSWORD}"
    echo -e "${YELLOW}Portainer Admin:${NC} admin / ${PORTAINER_ADMIN_PASSWORD}"
    echo -e "${YELLOW}Traefik Dashboard:${NC} admin / ${TRAEFIK_PASSWORD}"
    echo -e "${YELLOW}MySQL Root:${NC} root / ${MYSQL_ROOT_PASSWORD}"
    echo ""
}

# =============================================================================
# ENV FILE GENERATION
# =============================================================================

print_env_example_template() {
    cat <<'EOF'
# WordPress Farm Infrastructure Configuration
# This is an example file - copy to .env and fill in your values
# DO NOT COMMIT .env TO VERSION CONTROL

# =============================================================================
# DIGITALOCEAN CONFIGURATION
# =============================================================================

DO_API_TOKEN=dop_v1_your_actual_token_here
DO_REGION=nyc3
DO_SSH_KEY_NAME=wp-farm-deploy-key

# DigitalOcean Spaces (S3-compatible storage)
DO_SPACES_ACCESS_KEY=DO00XXXXXXXXXXXX
DO_SPACES_SECRET_KEY=your_secret_key_here
DO_SPACES_REGION=nyc3
DO_SPACES_BUCKET=wp-farm-backups
DO_SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com

# S3 compatibility (aliases for DO Spaces)
S3_ACCESS_KEY=${DO_SPACES_ACCESS_KEY}
S3_SECRET_KEY=${DO_SPACES_SECRET_KEY}
S3_REGION=${DO_SPACES_REGION}
S3_BUCKET=${DO_SPACES_BUCKET}
S3_ENDPOINT=https://${DO_SPACES_REGION}.digitaloceanspaces.com

# =============================================================================
# NODE CONFIGURATION
# =============================================================================

# Manager nodes (Swarm control plane)
MANAGER_NODE_COUNT=3
MANAGER_NODE_SIZE=s-2vcpu-4gb

# Worker nodes (application servers)
WORKER_NODE_COUNT=3
WORKER_NODE_SIZE=s-2vcpu-4gb

# Cache nodes (Redis + Varnish)
CACHE_NODE_COUNT=2
CACHE_NODE_SIZE=s-2vcpu-4gb

# Database nodes (MySQL/MariaDB Galera Cluster)
DB_NODE_COUNT=2
DB_NODE_SIZE=s-4vcpu-8gb

# Storage nodes (NFS for WordPress uploads)
STORAGE_NODE_COUNT=2
STORAGE_NODE_SIZE=s-2vcpu-4gb
STORAGE_VOLUME_SIZE=100

# Monitoring nodes (Prometheus, Grafana, Loki)
MONITOR_NODE_COUNT=1
MONITOR_NODE_SIZE=s-4vcpu-8gb

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# Generate with: openssl rand -base64 32
MYSQL_ROOT_PASSWORD=CHANGE_ME
PROXYSQL_ADMIN_PASSWORD=CHANGE_ME
GALERA_SST_PASSWORD=CHANGE_ME
DB_BACKUP_PASSWORD=CHANGE_ME

# Database cluster settings
MYSQL_MAX_CONNECTIONS=500
GALERA_CLUSTER_NAME=wp-farm-cluster

# =============================================================================
# CACHE CONFIGURATION
# =============================================================================

REDIS_PASSWORD=CHANGE_ME
REDIS_MAXMEMORY=2gb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Generate with: openssl rand -hex 32
VARNISH_SECRET=CHANGE_ME
VARNISH_MEMORY=256M

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Backup encryption
BACKUP_ENCRYPTION_PASSWORD=CHANGE_ME
RESTIC_PASSWORD=CHANGE_ME

# Backup retention (days)
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=3

# Backup schedule (cron format)
BACKUP_SCHEDULE_DB=0 2 * * *
BACKUP_SCHEDULE_FILES=0 3 * * *

# =============================================================================
# MONITORING & ALERTING
# =============================================================================

GRAFANA_ADMIN_PASSWORD=CHANGE_ME
PROMETHEUS_RETENTION=30d

# Alerting (optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
SENDGRID_API_KEY=SG.your_sendgrid_key_here
SENDGRID_FROM_EMAIL=alerts@yourdomain.com
SENDGRID_TO_EMAIL=ops-team@yourdomain.com

# =============================================================================
# MANAGEMENT & ACCESS
# =============================================================================

PORTAINER_ADMIN_PASSWORD=CHANGE_ME
# Generate with: htpasswd -nb admin "$(openssl rand -base64 16)"
TRAEFIK_DASHBOARD_PASSWORD_HASH='admin:$apr1$CHANGE_ME'

# Contractor access settings
CONTRACTOR_SESSION_TIMEOUT=3600
CONTRACTOR_ALLOWED_IPS=0.0.0.0/0

# =============================================================================
# CLOUDFLARE & DNS
# =============================================================================

CF_API_TOKEN=your_cloudflare_token_here
CF_API_EMAIL=your-email@example.com
CF_ACCOUNT_ID=your_account_id_here

# Multi-zone config (see cloudflare-zones.yml for details)
CF_ZONES_CONFIG=${SCRIPT_DIR}/cloudflare-zones.yml

# =============================================================================
# DOMAIN & SSL
# =============================================================================

DOMAIN=yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com

# =============================================================================
# DOCKER SWARM
# =============================================================================

# Join tokens (will be populated by init-swarm)
SWARM_MANAGER_TOKEN=
SWARM_WORKER_TOKEN=

EOF
}

print_env_template() {
    # Generate all passwords
    local MYSQL_ROOT_PASSWORD
    local PROXYSQL_ADMIN_PASSWORD
    local GALERA_SST_PASSWORD
    local DB_BACKUP_PASSWORD
    local REDIS_PASSWORD
    local VARNISH_SECRET
    local GRAFANA_ADMIN_PASSWORD
    local PORTAINER_ADMIN_PASSWORD
    local BACKUP_ENCRYPTION_PASSWORD
    local RESTIC_PASSWORD
    local TRAEFIK_PASSWORD
    local TRAEFIK_DASHBOARD_PASSWORD_HASH

	TRAEFIK_PASSWORD=$(htpasswd -nb admin "$(openssl rand -base64 16)")
	TRAEFIK_DASHBOARD_PASSWORD_HASH=$(generate_htpasswd "admin" "$TRAEFIK_PASSWORD")
	MYSQL_ROOT_PASSWORD=$(generate_password 32)
	PROXYSQL_ADMIN_PASSWORD=$(generate_password 32)
	TRAEFIK_PASSWORD=$(generate_password 16)
	RESTIC_PASSWORD=$(generate_password 32)
	BACKUP_ENCRYPTION_PASSWORD=$(generate_password 32)
	PORTAINER_ADMIN_PASSWORD=$(generate_password 32)
	GRAFANA_ADMIN_PASSWORD=$(generate_password 32)
	VARNISH_SECRET=$(generate_hex_secret 32)
	REDIS_PASSWORD=$(generate_password 32)
	DB_BACKUP_PASSWORD=$(generate_password 32)
	GALERA_SST_PASSWORD=$(generate_password 32)
    
    cat <<EOF
# WordPress Farm Infrastructure Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

# =============================================================================
# DIGITALOCEAN CONFIGURATION
# =============================================================================

DO_API_TOKEN=dop_v1_your_actual_token_here
DO_REGION=nyc3
DO_SSH_KEY_NAME=wp-farm-deploy-key

# DigitalOcean Spaces (S3-compatible storage)
DO_SPACES_ACCESS_KEY=DO00XXXXXXXXXXXX
DO_SPACES_SECRET_KEY=your_secret_key_here
DO_SPACES_REGION=nyc3
DO_SPACES_BUCKET=wp-farm-backups
DO_SPACES_ENDPOINT=https://nyc3.digitaloceanspaces.com

# S3 compatibility (aliases for DO Spaces)
S3_ACCESS_KEY=\${DO_SPACES_ACCESS_KEY}
S3_SECRET_KEY=\${DO_SPACES_SECRET_KEY}
S3_REGION=\${DO_SPACES_REGION}
S3_BUCKET=\${DO_SPACES_BUCKET}
S3_ENDPOINT=https://\${DO_SPACES_REGION}.digitaloceanspaces.com

# =============================================================================
# NODE CONFIGURATION
# =============================================================================

# Manager nodes (Swarm control plane)
MANAGER_NODE_COUNT=3
MANAGER_NODE_SIZE=s-2vcpu-4gb

# Worker nodes (application servers)
WORKER_NODE_COUNT=3
WORKER_NODE_SIZE=s-2vcpu-4gb

# Cache nodes (Redis + Varnish)
CACHE_NODE_COUNT=2
CACHE_NODE_SIZE=s-2vcpu-4gb

# Database nodes (MySQL/MariaDB Galera Cluster)
DB_NODE_COUNT=2
DB_NODE_SIZE=s-4vcpu-8gb

# Storage nodes (NFS for WordPress uploads)
STORAGE_NODE_COUNT=2
STORAGE_NODE_SIZE=s-2vcpu-4gb
STORAGE_VOLUME_SIZE=100

# Monitoring nodes (Prometheus, Grafana, Loki)
MONITOR_NODE_COUNT=1
MONITOR_NODE_SIZE=s-4vcpu-8gb

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
PROXYSQL_ADMIN_PASSWORD=${PROXYSQL_ADMIN_PASSWORD}
GALERA_SST_PASSWORD=${GALERA_SST_PASSWORD}
DB_BACKUP_PASSWORD=${DB_BACKUP_PASSWORD}

# Database cluster settings
MYSQL_MAX_CONNECTIONS=500
GALERA_CLUSTER_NAME=wp-farm-cluster

# =============================================================================
# CACHE CONFIGURATION
# =============================================================================

REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_MAXMEMORY=2gb
REDIS_MAXMEMORY_POLICY=allkeys-lru

VARNISH_SECRET=${VARNISH_SECRET}
VARNISH_MEMORY=256M

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Backup encryption
BACKUP_ENCRYPTION_PASSWORD=${BACKUP_ENCRYPTION_PASSWORD}
RESTIC_PASSWORD=${RESTIC_PASSWORD}

# Backup retention (days)
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=3

# Backup schedule (cron format)
BACKUP_SCHEDULE_DB=0 2 * * *
BACKUP_SCHEDULE_FILES=0 3 * * *

# =============================================================================
# MONITORING & ALERTING
# =============================================================================

GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
PROMETHEUS_RETENTION=30d

# Alerting (optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
SENDGRID_API_KEY=SG.your_sendgrid_key_here
SENDGRID_FROM_EMAIL=alerts@yourdomain.com
SENDGRID_TO_EMAIL=ops-team@yourdomain.com

# =============================================================================
# MANAGEMENT & ACCESS
# =============================================================================

PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD}
TRAEFIK_DASHBOARD_PASSWORD_HASH='${TRAEFIK_DASHBOARD_PASSWORD_HASH}'

# Contractor access settings
CONTRACTOR_SESSION_TIMEOUT=3600
CONTRACTOR_ALLOWED_IPS=0.0.0.0/0

# =============================================================================
# CLOUDFLARE & DNS
# =============================================================================

CF_API_TOKEN=your_cloudflare_token_here
CF_API_EMAIL=your-email@example.com
CF_ACCOUNT_ID=your_account_id_here

# Multi-zone config (see cloudflare-zones.yml for details)
CF_ZONES_CONFIG=\${SCRIPT_DIR}/cloudflare-zones.yml

# =============================================================================
# DOMAIN & SSL
# =============================================================================

DOMAIN=yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com

# =============================================================================
# DOCKER SWARM
# =============================================================================

# Join tokens (will be populated by init-swarm)
SWARM_MANAGER_TOKEN=
SWARM_WORKER_TOKEN=

# =============================================================================
# GENERATED CREDENTIALS REFERENCE
# =============================================================================
# Save these credentials securely!
#
# Grafana:  admin / ${GRAFANA_ADMIN_PASSWORD}
# Portainer: admin / ${PORTAINER_ADMIN_PASSWORD}
# Traefik:  admin / ${TRAEFIK_PASSWORD}
# MySQL:    root / ${MYSQL_ROOT_PASSWORD}
#
EOF
}

write_env_file() {
    log_info "Writing .env file..."
    
    # Backup existing .env if present
    if [[ -f "$ENV_FILE" ]]; then
        local backup="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$backup"
        log_warn "Existing .env backed up to: $backup"
    fi
    
    cat > "$ENV_FILE" <<EOF
# WordPress Farm Infrastructure Configuration
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

# =============================================================================
# DIGITALOCEAN CONFIGURATION
# =============================================================================

DO_API_TOKEN=${DO_API_TOKEN}
DO_REGION=${DO_REGION}
DO_SSH_KEY_NAME=${DO_SSH_KEY_NAME}

# DigitalOcean Spaces (S3-compatible storage)
DO_SPACES_ACCESS_KEY=${DO_SPACES_ACCESS_KEY}
DO_SPACES_SECRET_KEY=${DO_SPACES_SECRET_KEY}
DO_SPACES_REGION=${DO_SPACES_REGION}
DO_SPACES_BUCKET=${DO_SPACES_BUCKET}
DO_SPACES_ENDPOINT=https://${DO_SPACES_REGION}.digitaloceanspaces.com

# S3 compatibility (aliases for DO Spaces)
S3_ACCESS_KEY=${DO_SPACES_ACCESS_KEY}
S3_SECRET_KEY=${DO_SPACES_SECRET_KEY}
S3_REGION=${DO_SPACES_REGION}
S3_BUCKET=${DO_SPACES_BUCKET}
S3_ENDPOINT=https://${DO_SPACES_REGION}.digitaloceanspaces.com

# =============================================================================
# NODE CONFIGURATION
# =============================================================================

# Manager nodes (Swarm control plane)
MANAGER_NODE_COUNT=${MANAGER_NODE_COUNT}
MANAGER_NODE_SIZE=${MANAGER_NODE_SIZE}

# Worker nodes (application servers)
WORKER_NODE_COUNT=${WORKER_NODE_COUNT}
WORKER_NODE_SIZE=${WORKER_NODE_SIZE}

# Cache nodes (Redis + Varnish)
CACHE_NODE_COUNT=${CACHE_NODE_COUNT}
CACHE_NODE_SIZE=${CACHE_NODE_SIZE}

# Database nodes (MySQL/MariaDB Galera Cluster)
DB_NODE_COUNT=${DB_NODE_COUNT}
DB_NODE_SIZE=${DB_NODE_SIZE}

# Storage nodes (NFS for WordPress uploads)
STORAGE_NODE_COUNT=${STORAGE_NODE_COUNT}
STORAGE_NODE_SIZE=${STORAGE_NODE_SIZE}
STORAGE_VOLUME_SIZE=${STORAGE_VOLUME_SIZE}

# Monitoring nodes (Prometheus, Grafana, Loki)
MONITOR_NODE_COUNT=${MONITOR_NODE_COUNT}
MONITOR_NODE_SIZE=${MONITOR_NODE_SIZE}

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
PROXYSQL_ADMIN_PASSWORD=${PROXYSQL_ADMIN_PASSWORD}
GALERA_SST_PASSWORD=${GALERA_SST_PASSWORD}
DB_BACKUP_PASSWORD=${DB_BACKUP_PASSWORD}

# Database cluster settings
MYSQL_MAX_CONNECTIONS=500
GALERA_CLUSTER_NAME=wp-farm-cluster

# =============================================================================
# CACHE CONFIGURATION
# =============================================================================

REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_MAXMEMORY=2gb
REDIS_MAXMEMORY_POLICY=allkeys-lru

VARNISH_SECRET=${VARNISH_SECRET}
VARNISH_MEMORY=256M

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

# Backup encryption
BACKUP_ENCRYPTION_PASSWORD=${BACKUP_ENCRYPTION_PASSWORD}
RESTIC_PASSWORD=${RESTIC_PASSWORD}

# Backup retention (days)
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=3

# Backup schedule (cron format)
BACKUP_SCHEDULE_DB=0 2 * * *
BACKUP_SCHEDULE_FILES=0 3 * * *

# =============================================================================
# MONITORING & ALERTING
# =============================================================================

GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
PROMETHEUS_RETENTION=30d

# Alerting (optional)
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}
SENDGRID_API_KEY=${SENDGRID_API_KEY}
SENDGRID_FROM_EMAIL=${SENDGRID_FROM_EMAIL}
SENDGRID_TO_EMAIL=${SENDGRID_TO_EMAIL}

# =============================================================================
# MANAGEMENT & ACCESS
# =============================================================================

PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD}
TRAEFIK_DASHBOARD_PASSWORD_HASH='${TRAEFIK_DASHBOARD_PASSWORD_HASH}'

# Contractor access settings
CONTRACTOR_SESSION_TIMEOUT=3600
CONTRACTOR_ALLOWED_IPS=0.0.0.0/0

# =============================================================================
# CLOUDFLARE & DNS
# =============================================================================

CF_API_TOKEN=${CF_API_TOKEN}
CF_API_EMAIL=${CF_API_EMAIL}
CF_ACCOUNT_ID=${CF_ACCOUNT_ID}

# Multi-zone config (see cloudflare-zones.yml for details)
CF_ZONES_CONFIG=${CF_ZONES_CONFIG}

# =============================================================================
# DOMAIN & SSL
# =============================================================================

DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}

# =============================================================================
# DOCKER SWARM
# =============================================================================

# Join tokens (will be populated by init-swarm)
SWARM_MANAGER_TOKEN=
SWARM_WORKER_TOKEN=

EOF

    log_success ".env file created: $ENV_FILE"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_env() {
    log_info "Validating configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        die ".env file not found: $ENV_FILE"
    fi
    
    # Source the env file
    set -a
    source "$ENV_FILE"
    set +a
    
    local errors=0
    
    # Check required variables
    local required_vars=(
        "DO_API_TOKEN"
        "DO_REGION"
        "DO_SSH_KEY_NAME"
        "CF_API_TOKEN"
        "DOMAIN"
        "LETSENCRYPT_EMAIL"
        "MYSQL_ROOT_PASSWORD"
        "REDIS_PASSWORD"
        "GRAFANA_ADMIN_PASSWORD"
        "PORTAINER_ADMIN_PASSWORD"
    )
    
    echo ""
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "❌ $var is not set"
            ((errors++))
        else
            log_success "✓ $var is configured"
        fi
    done
    
    # Check password strength (at least 16 chars)
    echo ""
    log_info "Checking password strength..."
    local password_vars=(
        "MYSQL_ROOT_PASSWORD"
        "REDIS_PASSWORD"
        "GRAFANA_ADMIN_PASSWORD"
        "PORTAINER_ADMIN_PASSWORD"
        "BACKUP_ENCRYPTION_PASSWORD"
    )
    
    for var in "${password_vars[@]}"; do
        local pw="${!var:-}"
        if [[ ${#pw} -lt 16 ]]; then
            log_warn "⚠ $var is weak (< 16 chars)"
        else
            log_success "✓ $var is strong"
        fi
    done
    
    # Check node counts make sense
    echo ""
    log_info "Checking node configuration..."
    
    if [[ "${MANAGER_NODE_COUNT}" -lt 1 ]]; then
        log_error "❌ MANAGER_NODE_COUNT must be >= 1"
        ((errors++))
    elif [[ "${MANAGER_NODE_COUNT}" -eq 2 || "${MANAGER_NODE_COUNT}" -eq 4 ]]; then
        log_warn "⚠ MANAGER_NODE_COUNT of ${MANAGER_NODE_COUNT} is not recommended (use 1, 3, or 5 for proper quorum)"
    else
        log_success "✓ Manager count: ${MANAGER_NODE_COUNT}"
    fi
    
    if [[ "${DB_NODE_COUNT}" -ge 2 ]]; then
        log_success "✓ Database HA enabled (${DB_NODE_COUNT} nodes)"
    else
        log_warn "⚠ Single database node (no HA)"
    fi
    
    if [[ "${CACHE_NODE_COUNT}" -ge 2 ]]; then
        log_success "✓ Cache HA enabled (${CACHE_NODE_COUNT} nodes)"
    else
        log_warn "⚠ Single cache node (no HA)"
    fi
    
    echo ""
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        return 1
    else
        log_success "✅ All validation checks passed!"
        return 0
    fi
}

# =============================================================================
# MAIN
# =============================================================================

usage() {
    cat <<EOF
WordPress Farm Infrastructure - Environment Setup

Usage: $0 [OPTIONS]

Options:
  --from-example           Start from .env.example (fill in blanks only)
  --validate               Validate existing .env file
  --print-env-only         Print .env with auto-generated passwords
  --print-env-example-only Print .env.example template with placeholders
  --help                   Show this help message

Interactive Mode (default):
  The script will guide you through configuration step-by-step,
  generating secure passwords and creating a complete .env file.

Examples:
  # Full interactive setup
  $0

  # Validate existing configuration
  $0 --validate

  # Start from example file
  $0 --from-example

  # Generate .env with auto-generated passwords
  $0 --print-env-only > .env

  # Generate .env.example with placeholders
  $0 --print-env-example-only > .env.example

EOF
}

main() {
    local mode="interactive"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --from-example)
                mode="from-example"
                shift
                ;;
            --validate)
                mode="validate"
                shift
                ;;
            --print-env-only)
                mode="print-env-only"
                shift
                ;;
            --print-env-example-only)
                mode="print-env-example-only"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Handle print-env-example-only mode early (skip all checks)
    if [[ "$mode" == "print-env-example-only" ]]; then
        print_env_example_template
        exit 0
    fi
    
    # Handle print-env-only mode early (skip banner and checks)
    if [[ "$mode" == "print-env-only" ]]; then
        # Only check for openssl (required for password generation)
        if ! command -v openssl &>/dev/null; then
            echo "ERROR: openssl not found (required for password generation)" >&2
            exit 1
        fi
        print_env_template
        exit 0
    fi
    
    # Clear screen and show banner
    clear
    echo -e "${BLUE}"
    cat <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     WordPress Farm Infrastructure - Environment Setup         ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Check prerequisites
    check_prerequisites
    
    case "$mode" in
        validate)
            validate_env
            ;;
        
        from-example)
            if [[ ! -f "$ENV_EXAMPLE" ]]; then
                die ".env.example not found: $ENV_EXAMPLE"
            fi
            
            # Copy example and source it
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            log_success "Copied .env.example to .env"
            
            # Source to get defaults
            set -a
            source "$ENV_FILE" 2>/dev/null || true
            set +a
            
            # Interactive fill-in
            collect_digitalocean_config
            collect_cloudflare_config
            collect_domain_config
            collect_node_config
            collect_alerting_config
            generate_all_passwords
            write_env_file
            
            # Validate
            echo ""
            validate_env
            ;;
        
        interactive|*)
            # Full interactive mode
            collect_digitalocean_config
            collect_cloudflare_config
            collect_domain_config
            collect_node_config
            collect_alerting_config
            generate_all_passwords
            write_env_file
            
            # Validate
            echo ""
            validate_env
            ;;
    esac
    
    # Final instructions
    if [[ "$mode" != "validate" ]]; then
        echo ""
        echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Next Steps${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "1. Review your configuration:"
        echo -e "   ${CYAN}cat ${ENV_FILE}${NC}"
        echo ""
        echo -e "2. Add .env to .gitignore (if not already):"
        echo -e "   ${CYAN}echo '.env' >> .gitignore${NC}"
        echo ""
        echo -e "3. If using multiple Cloudflare zones, create:"
        echo -e "   ${CYAN}${CF_ZONES_CONFIG}${NC}"
        echo ""
        echo -e "4. Start infrastructure provisioning:"
        echo -e "   ${CYAN}./manage-infrastructure.sh provision --all${NC}"
        echo ""
        log_success "Setup complete! 🚀"
    fi
}

main "$@"
