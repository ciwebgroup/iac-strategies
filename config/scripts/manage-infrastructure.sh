#!/usr/bin/env bash
#
# =============================================================================
# WORDPRESS FARM INFRASTRUCTURE MANAGEMENT SCRIPT
# =============================================================================
# Comprehensive automation for deploying and managing WordPress farm infrastructure
#
# Usage: ./manage-infrastructure.sh [COMMAND] [OPTIONS]
# Example: ./manage-infrastructure.sh deploy --component all
#
# Requirements:
# - doctl (DigitalOcean CLI)
# - docker
# - jq
# - curl
# - ssh
# - Source the .env file with configuration
#
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERBOSE=false
DRY_RUN=false
FORCE=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

die() {
    log_error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Loading environment from $ENV_FILE"
        # shellcheck disable=SC1090
        set -a
        source "$ENV_FILE"
        set +a
    else
        die "Environment file not found: $ENV_FILE. Copy env.example to .env and configure it."
    fi
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    require_command "doctl"
    require_command "docker"
    require_command "jq"
    require_command "curl"
    require_command "ssh"
    require_command "ssh-keygen"
    
    # Check DO CLI auth
    if ! doctl auth list >/dev/null 2>&1; then
        die "DigitalOcean CLI not authenticated. Run: doctl auth init"
    fi
    
    log_success "All prerequisites met"
}

confirm() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    local prompt="$1"
    read -r -p "${prompt} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# DIGITALOCEAN OPERATIONS
# =============================================================================

do_create_vpc() {
    log "Creating DigitalOcean VPC..."
    
    local vpc_name="${DEPLOYMENT_PROJECT}-vpc"
    local vpc_id
    
    # Check if VPC already exists
    vpc_id=$(doctl vpcs list --format ID,Name --no-header | grep "$vpc_name" | awk '{print $1}')
    
    if [[ -n "$vpc_id" ]]; then
        log_info "VPC already exists: $vpc_id"
        echo "$vpc_id"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create VPC: $vpc_name"
        return 0
    fi
    
    vpc_id=$(doctl vpcs create \
        --name "$vpc_name" \
        --region "${DO_REGION}" \
        --ip-range "${VPC_CIDR}" \
        --format ID \
        --no-header)
    
    log_success "VPC created: $vpc_id"
    echo "$vpc_id"
}

do_create_ssh_key() {
    log "Setting up SSH key in DigitalOcean..."
    
    local key_path="$HOME/.ssh/${DO_SSH_KEY_NAME}"
    
    # Generate SSH key if it doesn't exist
    if [[ ! -f "$key_path" ]]; then
        log_info "Generating new SSH key: $key_path"
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "${DO_SSH_KEY_NAME}@wordpress-farm"
    fi
    
    # Check if key exists in DO
    if doctl compute ssh-key list --format Name --no-header | grep -q "^${DO_SSH_KEY_NAME}$"; then
        log_info "SSH key already exists in DigitalOcean"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would upload SSH key: ${DO_SSH_KEY_NAME}"
        return 0
    fi
    
    # Upload key to DO
    doctl compute ssh-key import "$DO_SSH_KEY_NAME" \
        --public-key-file "${key_path}.pub"
    
    log_success "SSH key uploaded: ${DO_SSH_KEY_NAME}"
}

do_create_droplet() {
    local name="$1"
    local size="$2"
    local tags="$3"
    local vpc_id="$4"
    
    log "Creating droplet: $name ($size)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create droplet: $name"
        return 0
    fi
    
    local droplet_id
    droplet_id=$(doctl compute droplet create "$name" \
        --region "${DO_REGION}" \
        --size "$size" \
        --image "ubuntu-22-04-x64" \
        --ssh-keys "${DO_SSH_KEY_NAME}" \
        --tag-names "$tags" \
        --vpc-uuid "$vpc_id" \
        --enable-private-networking \
        --enable-monitoring \
        --format ID \
        --no-header \
        --wait)
    
    log_success "Droplet created: $name ($droplet_id)"
    echo "$droplet_id"
}

do_create_spaces_bucket() {
    log "Creating DO Spaces bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create Spaces bucket: ${DO_SPACES_BUCKET}"
        return 0
    fi
    
    # Note: Spaces bucket creation typically done via AWS CLI (s3cmd) or web UI
    # This is a placeholder for the actual implementation
    log_warn "Spaces bucket creation should be done via DO console or s3cmd"
    log_info "Bucket name: ${DO_SPACES_BUCKET}"
    log_info "Region: ${DO_SPACES_REGION}"
}

# =============================================================================
# NODE PROVISIONING
# =============================================================================

provision_manager_nodes() {
    log "Provisioning manager nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${MANAGER_NODE_COUNT}"); do
        local node_name="wp-manager-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${MANAGER_NODE_SIZE}" "manager,swarm-manager" "$vpc_id"
    done
    
    log_success "Manager nodes provisioned"
}

provision_worker_nodes() {
    log "Provisioning worker nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${WORKER_NODE_COUNT}"); do
        local node_name="wp-worker-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${WORKER_NODE_SIZE}" "worker,swarm-worker" "$vpc_id"
    done
    
    log_success "Worker nodes provisioned"
}

provision_cache_nodes() {
    log "Provisioning dedicated cache nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${CACHE_NODE_COUNT}"); then
        local node_name="wp-cache-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${CACHE_NODE_SIZE}" "cache,swarm-worker" "$vpc_id"
    done
    
    log_success "Cache nodes provisioned"
}

provision_database_nodes() {
    log "Provisioning database nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${DB_NODE_COUNT}"); do
        local node_name="wp-db-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${DB_NODE_SIZE}" "database,swarm-worker" "$vpc_id"
    done
    
    log_success "Database nodes provisioned"
}

provision_storage_nodes() {
    log "Provisioning storage nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${STORAGE_NODE_COUNT}"); do
        local node_name="wp-storage-$(printf "%02d" "$i")"
        local droplet_id
        droplet_id=$(do_create_droplet "$node_name" "${STORAGE_NODE_SIZE}" "storage,swarm-worker" "$vpc_id")
        
        # Attach block storage
        if [[ -n "$droplet_id" ]]; then
            log_info "Attaching ${STORAGE_VOLUME_SIZE}GB volume to $node_name..."
            doctl compute volume create "${node_name}-vol" \
                --region "${DO_REGION}" \
                --size "${STORAGE_VOLUME_SIZE}gb" \
                --fs-type ext4
            
            doctl compute volume-action attach "${node_name}-vol" "$droplet_id"
        fi
    done
    
    log_success "Storage nodes provisioned"
}

provision_monitor_nodes() {
    log "Provisioning monitoring nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    for i in $(seq 1 "${MONITOR_NODE_COUNT}"); do
        local node_name="wp-monitor-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${MONITOR_NODE_SIZE}" "monitor,swarm-worker,ops" "$vpc_id"
    done
    
    log_success "Monitoring nodes provisioned"
}

# =============================================================================
# DOCKER SWARM OPERATIONS
# =============================================================================

init_swarm() {
    log "Initializing Docker Swarm..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    if [[ -z "$manager_ip" ]]; then
        die "No manager nodes found. Provision manager nodes first."
    fi
    
    log_info "Initializing Swarm on $manager_ip..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would initialize Swarm on $manager_ip"
        return 0
    fi
    
    # Initialize swarm on first manager
    ssh -o StrictHostKeyChecking=no "root@$manager_ip" "docker swarm init --advertise-addr ${manager_ip}"
    
    # Get join tokens
    local manager_token
    local worker_token
    manager_token=$(ssh "root@$manager_ip" "docker swarm join-token manager -q")
    worker_token=$(ssh "root@$manager_ip" "docker swarm join-token worker -q")
    
    log_success "Swarm initialized"
    log_info "Manager token: $manager_token"
    log_info "Worker token: $worker_token"
    
    # Save tokens to .env
    sed -i "s|^SWARM_MANAGER_TOKEN=.*|SWARM_MANAGER_TOKEN=$manager_token|" "$ENV_FILE"
    sed -i "s|^SWARM_WORKER_TOKEN=.*|SWARM_WORKER_TOKEN=$worker_token|" "$ENV_FILE"
}

join_managers() {
    log "Joining additional manager nodes to Swarm..."
    
    local lead_manager
    lead_manager=$(doctl compute droplet list --tag-name "swarm-manager" --format Name,PublicIPv4 --no-header | head -n1 | awk '{print $2}')
    
    doctl compute droplet list --tag-name "swarm-manager" --format Name,PublicIPv4 --no-header | tail -n +2 | while read -r name ip; do
        log_info "Joining $name to Swarm as manager..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[DRY RUN] Would join $name to Swarm"
            continue
        fi
        
        ssh -o StrictHostKeyChecking=no "root@$ip" \
            "docker swarm join --token ${SWARM_MANAGER_TOKEN} ${lead_manager}:2377"
    done
    
    log_success "Manager nodes joined"
}

join_workers() {
    log "Joining worker nodes to Swarm..."
    
    local lead_manager
    lead_manager=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    doctl compute droplet list --tag-name "swarm-worker" --format Name,PublicIPv4 --no-header | while read -r name ip; do
        log_info "Joining $name to Swarm as worker..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[DRY RUN] Would join $name to Swarm"
            continue
        fi
        
        ssh -o StrictHostKeyChecking=no "root@$ip" \
            "docker swarm join --token ${SWARM_WORKER_TOKEN} ${lead_manager}:2377"
    done
    
    log_success "Worker nodes joined"
}

label_nodes() {
    log "Labeling nodes..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    # Label cache nodes
    doctl compute droplet list --tag-name "cache" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as cache node..."
        ssh "root@$manager_ip" "docker node update --label-add cache=true $name"
        
        # Add node number for master selection
        local node_num
        node_num=$(echo "$name" | grep -oP '\d+$')
        ssh "root@$manager_ip" "docker node update --label-add cache-node=$node_num $name"
    done
    
    # Label database nodes
    doctl compute droplet list --tag-name "database" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as database node..."
        ssh "root@$manager_ip" "docker node update --label-add db=true $name"
        
        local node_num
        node_num=$(echo "$name" | grep -oP '\d+$')
        ssh "root@$manager_ip" "docker node update --label-add db-node=$node_num $name"
    done
    
    # Label storage nodes
    doctl compute droplet list --tag-name "storage" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as storage node..."
        ssh "root@$manager_ip" "docker node update --label-add storage=true $name"
    done
    
    # Label worker nodes
    doctl compute droplet list --tag-name "worker" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as app node..."
        ssh "root@$manager_ip" "docker node update --label-add app=true $name"
    done
    
    # Label monitoring nodes
    doctl compute droplet list --tag-name "ops" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as ops node..."
        ssh "root@$manager_ip" "docker node update --label-add ops=true $name"
    done
    
    log_success "Nodes labeled"
}

create_networks() {
    log "Creating Docker overlay networks..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    local networks=(
        "traefik-public"
        "wordpress-net"
        "database-net"
        "storage-net"
        "cache-net"
        "observability-net"
        "crowdsec-net"
        "management-net"
        "contractor-net"
    )
    
    for network in "${networks[@]}"; do
        log_info "Creating network: $network..."
        ssh "root@$manager_ip" "docker network create --driver overlay --attachable $network" || true
    done
    
    log_success "Networks created"
}

# =============================================================================
# DEPLOYMENT OPERATIONS
# =============================================================================

deploy_stack() {
    local stack_name="$1"
    local compose_file="$2"
    
    log "Deploying stack: $stack_name..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would deploy stack $stack_name from $compose_file"
        return 0
    fi
    
    # Copy compose file to manager
    scp "$compose_file" "root@$manager_ip:/tmp/${stack_name}.yml"
    
    # Copy configs
    ssh "root@$manager_ip" "mkdir -p /var/opt/wordpress-farm/configs"
    scp -r "${PROJECT_ROOT}/configs/"* "root@$manager_ip:/var/opt/wordpress-farm/configs/"
    
    # Deploy stack
    ssh "root@$manager_ip" "docker stack deploy -c /tmp/${stack_name}.yml --with-registry-auth $stack_name"
    
    log_success "Stack deployed: $stack_name"
}

deploy_all_stacks() {
    log "Deploying all infrastructure stacks..."
    
    local stacks_dir="${PROJECT_ROOT}/docker-compose-examples"
    
    # Deploy in dependency order
    deploy_stack "traefik" "${stacks_dir}/traefik-stack.yml"
    sleep 30
    
    deploy_stack "cache" "${stacks_dir}/cache-stack.yml"
    sleep 30
    
    deploy_stack "database" "${stacks_dir}/database-stack.yml"
    sleep 60
    
    deploy_stack "monitoring" "${stacks_dir}/monitoring-stack.yml"
    sleep 30
    
    # Note: Alerting is included in monitoring stack (Alertmanager)
    # No separate alerting stack needed
    
    deploy_stack "management" "${stacks_dir}/management-stack.yml"
    sleep 30
    
    deploy_stack "backup" "${stacks_dir}/backup-stack.yml"
    sleep 30
    
    deploy_stack "contractor" "${stacks_dir}/contractor-access-stack.yml"
    
    log_success "All stacks deployed"
}

backup_now() {
    local backup_type="${1:-all}"
    
    log "Running backups: $backup_type..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    case "$backup_type" in
        database|db)
            log_info "Triggering database backup..."
            ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_database-backup') /scripts/backup-databases.sh"
            ;;
        files|wordpress)
            log_info "Triggering WordPress file backup..."
            ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_wordpress-file-backup') /scripts/backup-wordpress-files.sh"
            ;;
        all|*)
            log_info "Triggering all backups..."
            ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_database-backup') /scripts/backup-databases.sh"
            ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_wordpress-file-backup') /scripts/backup-wordpress-files.sh"
            ;;
    esac
    
    log_success "Backups completed"
}

backup_cleanup() {
    log "Running backup cleanup..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Running cleanup in dry-run mode..."
        ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_backup-cleanup') sh -c 'DRY_RUN=true /scripts/backup-cleanup.sh'"
    else
        ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_backup-cleanup') /scripts/backup-cleanup.sh"
    fi
    
    log_success "Cleanup completed"
}

# =============================================================================
# WORDPRESS SITE OPERATIONS
# =============================================================================

create_wordpress_site() {
    local domain="$1"
    local site_id="${2:-$(date +%s)}"
    
    log "Creating WordPress site: $domain (ID: $site_id)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would create WordPress site: $domain"
        return 0
    fi
    
    # Generate database credentials
    local db_name="wp_site_${site_id}"
    local db_user="wp_user_${site_id}"
    local db_pass
    db_pass=$(openssl rand -base64 32)
    
    # Create WordPress site stack
    local site_stack="${domain//./_}"
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    # Generate site-specific compose file from template
    sed -e "s/{SITE_ID}/$site_id/g" \
        -e "s/{DOMAIN}/$domain/g" \
        -e "s/{DB_NAME}/$db_name/g" \
        -e "s/{DB_USER}/$db_user/g" \
        -e "s/{DB_PASS}/$db_pass/g" \
        "${PROJECT_ROOT}/docker-compose-examples/wordpress-site-template.yml" > "/tmp/${site_stack}.yml"
    
    # Deploy
    deploy_stack "$site_stack" "/tmp/${site_stack}.yml"
    
    # Store credentials
    mkdir -p "${PROJECT_ROOT}/sites/${domain}"
    cat > "${PROJECT_ROOT}/sites/${domain}/credentials.txt" <<EOF
Domain: $domain
Site ID: $site_id
Database: $db_name
DB User: $db_user
DB Password: $db_pass
Created: $(date)
EOF
    
    log_success "WordPress site created: $domain"
    log_info "Credentials saved to: ${PROJECT_ROOT}/sites/${domain}/credentials.txt"
}

# =============================================================================
# HEALTH CHECK OPERATIONS
# =============================================================================

health_check() {
    log "Running health checks..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    # Check Swarm status
    log_info "Checking Swarm status..."
    ssh "root@$manager_ip" "docker node ls"
    
    # Check services
    log_info "Checking service status..."
    ssh "root@$manager_ip" "docker service ls"
    
    # Check stacks
    log_info "Checking stacks..."
    ssh "root@$manager_ip" "docker stack ls"
    
    log_success "Health check complete"
}

# =============================================================================
# BACKUP & RESTORE OPERATIONS
# =============================================================================

backup_database() {
    log "Backing up databases..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would backup databases"
        return 0
    fi
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=database_backup') /backup.sh"
    
    log_success "Database backup complete"
}

# =============================================================================
# CLOUDFLARE OPERATIONS
# =============================================================================

configure_cloudflare_dns() {
    local domain="$1"
    local ip="$2"
    
    log "Configuring Cloudflare DNS for $domain..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would configure DNS: $domain -> $ip"
        return 0
    fi
    
    curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$ip\",\"proxied\":true}"
    
    log_success "DNS configured: $domain -> $ip"
}

# =============================================================================
# MAIN COMMAND DISPATCHER
# =============================================================================

usage() {
    cat <<EOF
WordPress Farm Infrastructure Management

Usage: $0 COMMAND [OPTIONS]

Commands:
  provision           Provision all infrastructure nodes
    --managers        Provision manager nodes only
    --workers         Provision worker nodes only
    --cache           Provision cache nodes only
    --database        Provision database nodes only
    --storage         Provision storage nodes only
    --monitors        Provision monitoring nodes only
    --all             Provision all node types

  init-swarm          Initialize Docker Swarm cluster
  join-nodes          Join nodes to Swarm cluster
  label-nodes         Apply labels to Swarm nodes
  create-networks     Create Docker overlay networks
  
  deploy              Deploy stacks
    --stack NAME      Deploy specific stack
    --all             Deploy all stacks
  
  site                WordPress site operations
    --create DOMAIN   Create new WordPress site
    --delete DOMAIN   Delete WordPress site
    --list            List all sites
  
  health              Run health checks
  backup              Backup operations
    --now [type]      Trigger backup now (database, files, or all)
    --cleanup         Run retention cleanup
    --verify          Verify backup health
  
  destroy             Destroy infrastructure
    --confirm         Skip confirmation prompt

Options:
  --dry-run           Show what would be done without making changes
  --force             Skip all confirmation prompts
  --verbose           Enable verbose output
  --help              Show this help message

Examples:
  # Full deployment
  $0 provision --all
  $0 init-swarm
  $0 join-nodes
  $0 label-nodes
  $0 create-networks
  $0 deploy --all

  # Create WordPress site
  $0 site --create example.com

  # Health check
  $0 health

EOF
}

main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Require at least one command
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Load environment and check prerequisites
    load_env
    check_prerequisites
    
    # Execute command
    case "$command" in
        provision)
            case "${1:-all}" in
                --managers) provision_manager_nodes ;;
                --workers) provision_worker_nodes ;;
                --cache) provision_cache_nodes ;;
                --database) provision_database_nodes ;;
                --storage) provision_storage_nodes ;;
                --monitors) provision_monitor_nodes ;;
                --all|*)
                    provision_manager_nodes
                    provision_worker_nodes
                    provision_cache_nodes
                    provision_database_nodes
                    provision_storage_nodes
                    provision_monitor_nodes
                    ;;
            esac
            ;;
        
        init-swarm)
            init_swarm
            ;;
        
        join-nodes)
            join_managers
            join_workers
            ;;
        
        label-nodes)
            label_nodes
            ;;
        
        create-networks)
            create_networks
            ;;
        
        deploy)
            case "${1:-all}" in
                --stack)
                    shift
                    deploy_stack "$1" "${PROJECT_ROOT}/docker-compose-examples/${1}-stack.yml"
                    ;;
                --all|*)
                    deploy_all_stacks
                    ;;
            esac
            ;;
        
        site)
            case "$1" in
                --create)
                    shift
                    create_wordpress_site "$1" "${2:-}"
                    ;;
                *)
                    die "Unknown site command: $1"
                    ;;
            esac
            ;;
        
        health)
            health_check
            ;;
        
        backup)
            case "${1:-now}" in
                --now)
                    shift
                    backup_now "${1:-all}"
                    ;;
                --cleanup)
                    backup_cleanup
                    ;;
                --verify)
                    log "Checking backup health..."
                    local manager_ip
                    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
                    ssh "root@$manager_ip" "docker exec \$(docker ps -qf 'name=backup_backup-monitor') /scripts/backup-monitor.sh --check-once"
                    ;;
                *)
                    backup_now "all"
                    ;;
            esac
            ;;
        
        *)
            die "Unknown command: $command"
            ;;
    esac
}

# Run main function
main "$@"

