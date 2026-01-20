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
#VERBOSE=false
DRY_RUN=false
FORCE=false
INTERACTIVE=true

# Verification scripts directory
VERIFY_SCRIPTS_DIR="${SCRIPT_DIR}/verify"

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
        

        # shellcheck disable=SC1090,SC1091

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
    require_command "yq"
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
# VERIFICATION & INTERACTIVE PAUSE FUNCTIONS
# =============================================================================

# Interactive pause with verification instructions
# Usage: interactive_pause "stage_name" "instructions"
interactive_pause() {
    local stage="$1"
    local instructions="$2"
    
    if [[ "$INTERACTIVE" != "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  VERIFICATION CHECKPOINT: ${stage}${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Please verify the deployment before continuing:${NC}"
    echo ""
    echo -e "$instructions"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    
    while true; do
        echo ""
        read -r -p "$(echo -e "${GREEN}[R]${NC}etry / ${GREEN}[C]${NC}ontinue / ${RED}[A]${NC}bort? ")" response
        case "$response" in
            [rR])
                echo "Retrying..."
                return 1
                ;;
            [cC])
                echo "Continuing..."
                return 0
                ;;
            [aA])
                echo "Aborting deployment."
                exit 1
                ;;
            *)
                echo "Please enter R, C, or A"
                ;;
        esac
    done
}

# Wait for SSH connectivity to a node
# Usage: wait_for_ssh <ip> [max_attempts] [delay_seconds]
wait_for_ssh() {
    local host="$1"
    local max_attempts="${2:-30}"
    local delay="${3:-5}"
    local attempt=1
    
    log_info "Waiting for SSH on $host..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$host" "exit 0" 2>/dev/null; then
            log_success "SSH available on $host"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts - SSH not ready..."
        sleep "$delay"
        ((attempt++))
    done
    
    log_error "SSH not available on $host after $max_attempts attempts"
    return 1
}

# Wait for Docker to be ready on a node
# Usage: wait_for_docker <ip> [max_attempts]
wait_for_docker() {
    local host="$1"
    local max_attempts="${2:-30}"
    local attempt=1
    
    log_info "Waiting for Docker on $host..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no "root@$host" "docker info" &>/dev/null; then
            log_success "Docker ready on $host"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts - Docker not ready..."
        sleep 5
        ((attempt++))
    done
    
    log_error "Docker not ready on $host after $max_attempts attempts"
    return 1
}

# Deploy verification scripts to a node
# Usage: deploy_verify_scripts <ip>
deploy_verify_scripts() {
    local host="$1"
    
    log_info "Deploying verification scripts to $host..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would deploy verify scripts to $host"
        return 0
    fi
    
    # Create directory and copy scripts
    ssh -o StrictHostKeyChecking=no "root@$host" "mkdir -p /opt/verify"
    scp -o StrictHostKeyChecking=no "${VERIFY_SCRIPTS_DIR}/"*.sh "root@$host:/opt/verify/"
    ssh -o StrictHostKeyChecking=no "root@$host" "chmod +x /opt/verify/*.sh"
    
    log_success "Verification scripts deployed to $host:/opt/verify/"
}

# Wait for a Docker stack to be fully deployed
# Usage: wait_for_stack <stack_name> <manager_ip> [timeout_seconds]
wait_for_stack() {
    local stack_name="$1"
    local manager_ip="$2"
    local timeout="${3:-300}"
    local start_time
    start_time=$(date +%s)
    
    log_info "Waiting for stack $stack_name to be ready..."
    
    while true; do
        local elapsed=$(( $(date +%s) - start_time ))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Stack $stack_name timed out after ${timeout}s"
            ssh "root@$manager_ip" "docker stack services $stack_name" || true
            return 1
        fi
        
        # Check if all services have desired replicas
        local not_ready
        not_ready=$(ssh "root@$manager_ip" "docker stack services $stack_name --format '{{.Replicas}}' 2>/dev/null | grep -v -E '^([0-9]+)/\1$' | wc -l" 2>/dev/null || echo "999")
        
        if [[ "$not_ready" -eq 0 ]]; then
            log_success "Stack $stack_name is ready (${elapsed}s)"
            return 0
        fi
        
        log_info "Stack $stack_name: waiting... (${elapsed}s elapsed, $not_ready services pending)"
        sleep 10
    done
}

# Verify swarm health
# Usage: verify_swarm_health <manager_ip>
verify_swarm_health() {
    local manager_ip="$1"
    
    log_info "Verifying Swarm cluster health..."
    
    # Check all nodes are ready
    local not_ready
    not_ready=$(ssh "root@$manager_ip" "docker node ls --format '{{.Status}}' | grep -v 'Ready' | wc -l" 2>/dev/null || echo "999")
    
    if [[ "$not_ready" -gt 0 ]]; then
        log_error "$not_ready nodes not ready"
        ssh "root@$manager_ip" "docker node ls"
        return 1
    fi
    
    log_success "Swarm cluster healthy"
    return 0
}

# Verify networks exist
# Usage: verify_networks <manager_ip>
verify_networks_exist() {
    local manager_ip="$1"
    local required_networks=(
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
    local missing=0
    
    log_info "Verifying Docker networks..."
    
    for network in "${required_networks[@]}"; do
        if ssh "root@$manager_ip" "docker network inspect $network" &>/dev/null; then
            log_info "  ✓ $network"
        else
            log_error "  ✗ $network (missing)"
            ((missing++))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "$missing networks missing"
        return 1
    fi
    
    log_success "All networks verified"
    return 0
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
    
    local node_ips=()
    
    for i in $(seq 1 "${MANAGER_NODE_COUNT}"); do
        local node_name 
        node_name="wp-manager-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${MANAGER_NODE_SIZE}" "manager,swarm-manager" "$vpc_id"
        
        # Get IP and wait for SSH
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Manager nodes provisioned"
    
    interactive_pause "Manager Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. SSH to each manager node and verify:
     ${CYAN}ssh root@<manager_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check all nodes are reachable:
$(for ip in "${node_ips[@]}"; do echo "     ${CYAN}ssh root@$ip 'hostname && docker --version'${NC}"; done)

  3. Verify Docker is running:
     ${CYAN}ssh root@<manager_ip> 'docker info | head -20'${NC}

${YELLOW}Expected result:${NC}
  - All ${MANAGER_NODE_COUNT} manager droplet(s) created
  - SSH accessible on all nodes
  - Docker installed and running
"
}

provision_worker_nodes() {
    log "Provisioning worker nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    local node_ips=()
    
    for i in $(seq 1 "${WORKER_NODE_COUNT}"); do
        local node_name
        node_name="wp-worker-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${WORKER_NODE_SIZE}" "worker,swarm-worker" "$vpc_id"
        
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Worker nodes provisioned"
    
    interactive_pause "Worker Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. Verify each worker node:
     ${CYAN}ssh root@<worker_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check private network connectivity:
     ${CYAN}ssh root@<worker_ip> 'ping -c 3 <manager_private_ip>'${NC}

${YELLOW}Expected result:${NC}
  - All ${WORKER_NODE_COUNT} worker droplet(s) created
  - Private network connectivity working
  - Docker ready on all nodes
"
}

provision_cache_nodes() {
    log "Provisioning dedicated cache nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    local node_ips=()
    
    for i in $(seq 1 "${CACHE_NODE_COUNT}"); do
        local node_name
        node_name="wp-cache-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${CACHE_NODE_SIZE}" "cache,swarm-worker" "$vpc_id"
        
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Cache nodes provisioned"
    
    interactive_pause "Cache Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. Verify cache nodes are ready:
     ${CYAN}ssh root@<cache_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check memory availability (Redis/Varnish need RAM):
     ${CYAN}ssh root@<cache_ip> 'free -h'${NC}

${YELLOW}Expected result:${NC}
  - All ${CACHE_NODE_COUNT} cache droplet(s) created
  - Sufficient memory for caching services
"
}

provision_database_nodes() {
    log "Provisioning database nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    local node_ips=()
    
    for i in $(seq 1 "${DB_NODE_COUNT}"); do
        local node_name;
        node_name="wp-db-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${DB_NODE_SIZE}" "database,swarm-worker" "$vpc_id"
        
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Database nodes provisioned"
    
    interactive_pause "Database Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. Verify database nodes are ready:
     ${CYAN}ssh root@<db_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check disk I/O performance (important for databases):
     ${CYAN}ssh root@<db_ip> 'dd if=/dev/zero of=/tmp/test bs=1M count=100 oflag=direct 2>&1 | tail -1'${NC}

${YELLOW}Expected result:${NC}
  - All ${DB_NODE_COUNT} database droplet(s) created  
  - Adequate disk performance for MySQL/MariaDB
"
}

provision_storage_nodes() {
    log "Provisioning storage nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    local node_ips=()
    
    for i in $(seq 1 "${STORAGE_NODE_COUNT}"); do
        local node_name
        node_name="wp-storage-$(printf "%02d" "$i")"
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
        
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Storage nodes provisioned"
    
    interactive_pause "Storage Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. Verify storage nodes and attached volumes:
     ${CYAN}ssh root@<storage_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check block storage is attached and mounted:
     ${CYAN}ssh root@<storage_ip> 'lsblk && df -h'${NC}

  3. Verify NFS-ready filesystem:
     ${CYAN}ssh root@<storage_ip> 'ls -la /mnt/volume_*'${NC}

${YELLOW}Expected result:${NC}
  - All ${STORAGE_NODE_COUNT} storage droplet(s) created
  - ${STORAGE_VOLUME_SIZE}GB volumes attached to each
  - Block storage visible in lsblk output
"
}

provision_monitor_nodes() {
    log "Provisioning monitoring nodes..."
    
    local vpc_id
    vpc_id=$(do_create_vpc)
    
    local node_ips=()
    
    for i in $(seq 1 "${MONITOR_NODE_COUNT}"); do
        local node_name;
        node_name="wp-monitor-$(printf "%02d" "$i")"
        do_create_droplet "$node_name" "${MONITOR_NODE_SIZE}" "monitor,swarm-worker,ops" "$vpc_id"
        
        local node_ip
        node_ip=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep "^${node_name}" | awk '{print $2}')
        node_ips+=("$node_ip")
        
        if [[ "$DRY_RUN" != "true" && -n "$node_ip" ]]; then
            wait_for_ssh "$node_ip"
            wait_for_docker "$node_ip"
            deploy_verify_scripts "$node_ip"
        fi
    done
    
    log_success "Monitoring nodes provisioned"
    
    interactive_pause "Monitor Node Provisioning" "
${GREEN}Verification Steps:${NC}
  1. Verify monitoring nodes are ready:
     ${CYAN}ssh root@<monitor_ip> '/opt/verify/verify-node.sh'${NC}

  2. Check disk space for metrics/logs storage:
     ${CYAN}ssh root@<monitor_ip> 'df -h /'${NC}

${YELLOW}Expected result:${NC}
  - All ${MONITOR_NODE_COUNT} monitor droplet(s) created
  - Sufficient disk space for Prometheus/Loki data
  - Tagged with 'ops' label for service placement
"
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
    
    interactive_pause "Swarm Initialization" "
${GREEN}Verification Steps:${NC}
  1. Check Swarm status on the leader:
     ${CYAN}ssh root@$manager_ip 'docker info | grep -A5 Swarm'${NC}

  2. Run the verify-swarm script:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-swarm.sh'${NC}

  3. Verify node is listed as leader:
     ${CYAN}ssh root@$manager_ip 'docker node ls'${NC}

${YELLOW}Expected result:${NC}
  - Swarm: active
  - Is Manager: true
  - 1 manager node in 'Ready' state
  - Join tokens saved to .env file
"
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
        
        ssh -n -o StrictHostKeyChecking=no "root@$ip" \
            "docker swarm join --token ${SWARM_MANAGER_TOKEN} ${lead_manager}:2377"
    done
    
    log_success "Manager nodes joined"
    
    interactive_pause "Manager Nodes Joined" "
${GREEN}Verification Steps:${NC}
  1. Verify all managers are in the cluster:
     ${CYAN}ssh root@$lead_manager 'docker node ls | grep -i manager'${NC}

  2. Check Raft consensus:
     ${CYAN}ssh root@$lead_manager '/opt/verify/verify-swarm.sh'${NC}

${YELLOW}Expected result:${NC}
  - ${MANAGER_NODE_COUNT} manager nodes listed
  - All managers show 'Ready' status
  - One node marked as Leader
  - Raft quorum healthy (need majority of managers)
"
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
        
        ssh -n -o StrictHostKeyChecking=no "root@$ip" \
            "docker swarm join --token ${SWARM_WORKER_TOKEN} ${lead_manager}:2377"
    done
    
    log_success "Worker nodes joined"
    
    interactive_pause "Worker Nodes Joined" "
${GREEN}Verification Steps:${NC}
  1. Verify all nodes are in the cluster:
     ${CYAN}ssh root@$lead_manager 'docker node ls'${NC}

  2. Run full cluster verification:
     ${CYAN}ssh root@$lead_manager '/opt/verify/verify-swarm.sh'${NC}

  3. Check node connectivity:
     ${CYAN}ssh root@$lead_manager 'docker node ls --format \"{{.Hostname}}: {{.Status}}\"'${NC}

${YELLOW}Expected result:${NC}
  - All manager + worker nodes listed
  - All nodes show 'Ready' status
  - No nodes in 'Down' or 'Unknown' state
"
}

label_nodes() {
    log "Labeling nodes..."
    
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    # Label cache nodes
    doctl compute droplet list --tag-name "cache" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as cache node..."
        ssh -n "root@$manager_ip" "docker node update --label-add cache=true $name"
        
        # Add node number for master selection
        local node_num
        node_num=$(echo "$name" | grep -oP '\d+$')
        ssh -n "root@$manager_ip" "docker node update --label-add cache-node=$node_num $name"
    done
    
    # Label database nodes
    doctl compute droplet list --tag-name "database" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as database node..."
        ssh -n "root@$manager_ip" "docker node update --label-add db=true $name"
        
        local node_num
        node_num=$(echo "$name" | grep -oP '\d+$')
        ssh -n "root@$manager_ip" "docker node update --label-add db-node=$node_num $name"
    done
    
    # Label storage nodes
    doctl compute droplet list --tag-name "storage" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as storage node..."
        ssh -n "root@$manager_ip" "docker node update --label-add storage=true $name"
    done
    
    # Label worker nodes
    doctl compute droplet list --tag-name "worker" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as app node..."
        ssh -n "root@$manager_ip" "docker node update --label-add app=true $name"
    done
    
    # Label monitoring nodes
    doctl compute droplet list --tag-name "ops" --format Name --no-header | while read -r name; do
        log_info "Labeling $name as ops node..."
        ssh -n "root@$manager_ip" "docker node update --label-add ops=true $name"
    done
    
    log_success "Nodes labeled"
    
    interactive_pause "Node Labeling Complete" "
${GREEN}Verification Steps:${NC}
  1. Verify all labels are applied:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-labels.sh'${NC}

  2. Check individual node labels:
     ${CYAN}ssh root@$manager_ip 'docker node ls -q | xargs -I{} docker node inspect {} --format \"{{.Description.Hostname}}: {{.Spec.Labels}}\"'${NC}

${YELLOW}Expected result:${NC}
  - Cache nodes: cache=true, cache-node=<n>
  - Database nodes: db=true, db-node=<n>
  - Storage nodes: storage=true
  - Worker nodes: app=true
  - Monitor nodes: ops=true
"
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
        ssh -n "root@$manager_ip" "docker network create --driver overlay --attachable $network" || true
    done
    
    log_success "Networks created"
    
    interactive_pause "Network Creation Complete" "
${GREEN}Verification Steps:${NC}
  1. Verify all overlay networks exist:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-networks.sh'${NC}

  2. List all networks:
     ${CYAN}ssh root@$manager_ip 'docker network ls --filter driver=overlay'${NC}

${YELLOW}Expected result:${NC}
  - All 9 networks created: traefik-public, wordpress-net, database-net,
    storage-net, cache-net, observability-net, crowdsec-net,
    management-net, contractor-net
  - All networks using 'overlay' driver
  - Networks are 'attachable' for debugging
"
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
    ssh -n "root@$manager_ip" "docker stack deploy -c /tmp/${stack_name}.yml --with-registry-auth $stack_name"
    
    log_success "Stack deployed: $stack_name"
}

deploy_all_stacks() {
    log "Deploying all infrastructure stacks..."
    
    local stacks_dir="${PROJECT_ROOT}/docker-compose-examples"
    local manager_ip
    manager_ip=$(doctl compute droplet list --tag-name "swarm-manager" --format PublicIPv4 --no-header | head -n1)
    
    # Deploy in dependency order with verification
    
    # 1. Traefik (reverse proxy - required by all other services)
    deploy_stack "traefik" "${stacks_dir}/traefik-stack.yml"
    wait_for_stack "traefik" "$manager_ip" 120
    
    interactive_pause "Traefik Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check Traefik services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh traefik'${NC}

  2. Verify Traefik dashboard (if enabled):
     ${CYAN}curl -s http://$manager_ip:8080/api/overview${NC}

${YELLOW}Expected result:${NC}
  - traefik_traefik service running
  - Dashboard accessible (if configured)
  - All replicas healthy
"
    
    # 2. Cache (Redis/Varnish - required before WordPress)
    deploy_stack "cache" "${stacks_dir}/cache-stack.yml"
    wait_for_stack "cache" "$manager_ip" 120
    
    interactive_pause "Cache Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check cache services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh cache'${NC}

  2. Test Redis connectivity:
     ${CYAN}ssh root@$manager_ip 'docker exec \$(docker ps -qf name=cache_redis -n1) redis-cli ping'${NC}

${YELLOW}Expected result:${NC}
  - Redis master running on cache-node=1
  - Varnish services running
  - PONG response from Redis
"
    
    # 3. Database (MySQL/MariaDB - required before WordPress)
    deploy_stack "database" "${stacks_dir}/database-stack.yml"
    wait_for_stack "database" "$manager_ip" 180
    
    interactive_pause "Database Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check database services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh database'${NC}

  2. Test MySQL connectivity:
     ${CYAN}ssh root@$manager_ip 'docker exec \$(docker ps -qf name=database_mysql -n1) mysqladmin -u root -p\${MYSQL_ROOT_PASSWORD} status'${NC}

${YELLOW}Expected result:${NC}
  - MySQL master running on db-node=1
  - Replicas synced (if configured)
  - Uptime showing in mysqladmin status
"
    
    # 4. Monitoring (Prometheus, Grafana, Loki)
    deploy_stack "monitoring" "${stacks_dir}/monitoring-stack.yml"
    wait_for_stack "monitoring" "$manager_ip" 180
    
    interactive_pause "Monitoring Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check monitoring services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh monitoring'${NC}

  2. Verify Prometheus is scraping:
     ${CYAN}curl -s http://$manager_ip:9090/api/v1/targets | jq '.data.activeTargets | length'${NC}

${YELLOW}Expected result:${NC}
  - Prometheus, Grafana, Loki running
  - Alertmanager healthy
  - Targets being scraped
"
    
    # 5. Management (Portainer, Filebrowser)
    deploy_stack "management" "${stacks_dir}/management-stack.yml"
    wait_for_stack "management" "$manager_ip" 120
    
    interactive_pause "Management Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check management services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh management'${NC}

  2. Verify Portainer access:
     Check https://portainer.${DOMAIN}

${YELLOW}Expected result:${NC}
  - Portainer agent on all nodes
  - Portainer UI accessible
  - Filebrowser running (if configured)
"
    
    # 6. Backup services
    deploy_stack "backup" "${stacks_dir}/backup-stack.yml"
    wait_for_stack "backup" "$manager_ip" 120
    
    interactive_pause "Backup Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check backup services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh backup'${NC}

  2. Verify S3 connectivity:
     ${CYAN}ssh root@$manager_ip 'docker exec \$(docker ps -qf name=backup -n1) s3cmd ls s3://${S3_BUCKET}/'${NC}

${YELLOW}Expected result:${NC}
  - Database backup service running
  - File backup service running
  - S3 bucket accessible
"
    
    # 7. Contractor access
    deploy_stack "contractor" "${stacks_dir}/contractor-access-stack.yml"
    wait_for_stack "contractor" "$manager_ip" 60
    
    interactive_pause "Contractor Stack Deployed" "
${GREEN}Verification Steps:${NC}
  1. Check contractor services:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-stack.sh contractor'${NC}

  2. Verify contractor portal access:
     Check https://contractor.${DOMAIN}

${YELLOW}Expected result:${NC}
  - Contractor portal running
  - Site selector API accessible
  - SSH proxy ready
"
    
    log_success "All stacks deployed"
    
    # Final comprehensive verification
    interactive_pause "Full Deployment Complete" "
${GREEN}Final Verification Steps:${NC}
  1. Full cluster health check:
     ${CYAN}ssh root@$manager_ip '/opt/verify/verify-swarm.sh'${NC}

  2. All stacks healthy:
     ${CYAN}ssh root@$manager_ip 'docker stack ls'${NC}

  3. Check for any failing services:
     ${CYAN}ssh root@$manager_ip 'docker service ls --filter 'desired-state=running' --format \"{{.Name}}: {{.Replicas}}\" | grep -v -E \"[0-9]+/[0-9]+ *\$\"'${NC}

${YELLOW}Deployment Summary:${NC}
  ✓ Traefik (reverse proxy)
  ✓ Cache (Redis + Varnish)
  ✓ Database (MySQL)
  ✓ Monitoring (Prometheus + Grafana + Loki)
  ✓ Management (Portainer)
  ✓ Backup (S3 automated backups)
  ✓ Contractor (SSH access portal)

${GREEN}Ready to deploy WordPress sites!${NC}
  ${CYAN}$0 site --create example.com${NC}
"
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

get_cloudflare_zone_id() {
    local domain="$1"
    local zones_config="${CF_ZONES_CONFIG:-${SCRIPT_DIR}/cloudflare-zones.yml}"
    
    if [[ ! -f "$zones_config" ]]; then
        log_error "Cloudflare zones config not found: $zones_config"
        return 1
    fi
    
    # Extract the base domain (handle subdomains)
    local base_domain
    if [[ "$domain" =~ ^[^.]+\.([^.]+\.[^.]+)$ ]]; then
        base_domain="${BASH_REMATCH[1]}"
    else
        base_domain="$domain"
    fi
    
    # Try to find zone for this domain
    local zone_id
    zone_id=$(yq eval ".zones[] | select(.domain == \"$base_domain\" and .enabled == true) | .zone_id" "$zones_config")
    
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        # Try parent domain if this is a subdomain
        if [[ "$domain" =~ \.([^.]+\.[^.]+)$ ]]; then
            local parent_domain="${BASH_REMATCH[1]}"
            zone_id=$(yq eval ".zones[] | select(.domain == \"$parent_domain\" and .enabled == true) | .zone_id" "$zones_config")
        fi
    fi
    
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        # Fall back to default zone
        local default_zone
        default_zone=$(yq eval '.default_zone' "$zones_config")
        zone_id=$(yq eval ".zones[] | select(.domain == \"$default_zone\" and .enabled == true) | .zone_id" "$zones_config")
        
        if [[ -n "$zone_id" && "$zone_id" != "null" ]]; then
            log_warn "Using default zone ($default_zone) for domain: $domain"
        fi
    fi
    
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        log_error "No Cloudflare zone found for domain: $domain"
        return 1
    fi
    
    echo "$zone_id"
}

get_cloudflare_dns_defaults() {
    local key="$1"
    local zones_config="${CF_ZONES_CONFIG:-${SCRIPT_DIR}/cloudflare-zones.yml}"
    
    yq eval ".dns_defaults.$key" "$zones_config"
}

configure_cloudflare_dns() {
    local domain="$1"
    local ip="$2"
    local record_type="${3:-A}"
    
    log "Configuring Cloudflare DNS for $domain..."
    
    # Get zone ID for this domain
    local zone_id
    zone_id=$(get_cloudflare_zone_id "$domain")
    
    if [[ -z "$zone_id" ]]; then
        log_error "Failed to determine Cloudflare zone for: $domain"
        return 1
    fi
    
    log_info "Using zone ID: $zone_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would configure DNS: $domain -> $ip (zone: $zone_id)"
        return 0
    fi
    
    # Get DNS defaults
    local ttl proxied
    ttl=$(get_cloudflare_dns_defaults "ttl")
    proxied=$(get_cloudflare_dns_defaults "proxied")
    
    # Default to safe values if not set
    ttl="${ttl:-1}"
    proxied="${proxied:-true}"
    
    # Check if record already exists
    local existing_record
    existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=${record_type}&name=${domain}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
    
    if [[ -n "$existing_record" ]]; then
        # Update existing record
        log_info "Updating existing DNS record..."
        local response
        response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${existing_record}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${domain}\",\"content\":\"${ip}\",\"ttl\":${ttl},\"proxied\":${proxied}}")
    else
        # Create new record
        log_info "Creating new DNS record..."
        local response
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${record_type}\",\"name\":\"${domain}\",\"content\":\"${ip}\",\"ttl\":${ttl},\"proxied\":${proxied}}")
    fi
    
    # Check response
    local success
    success=$(echo "$response" | jq -r '.success // false')
    
    if [[ "$success" == "true" ]]; then
        log_success "DNS configured: $domain -> $ip (zone: $zone_id, proxied: $proxied)"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Failed to configure DNS: $error_msg"
        return 1
    fi
}

# =============================================================================
# MAIN COMMAND DISPATCHER
# =============================================================================

usage() {
    cat <<EOF
WordPress Farm Infrastructure Management

Usage: $0 [GLOBAL OPTIONS] COMMAND [COMMAND OPTIONS]

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

Global Options:
  --dry-run           Show what would be done without making changes
  --force             Skip all confirmation prompts
  --interactive       Enable interactive verification pauses (default)
  --no-interactive    Disable interactive pauses (for automation)
  --verbose           Enable verbose output
  --help              Show this help message

Examples:
  # Full deployment with interactive verification
  $0 provision --all
  $0 init-swarm
  $0 join-nodes
  $0 label-nodes
  $0 create-networks
  $0 deploy --all

  # Automated deployment (no pauses)
  $0 --no-interactive provision --all
  $0 --no-interactive init-swarm

  # Dry run to preview changes
  $0 --dry-run provision --all
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
            --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            --verbose)
                # VERBOSE=true
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

