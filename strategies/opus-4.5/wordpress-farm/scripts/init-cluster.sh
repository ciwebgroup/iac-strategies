#!/bin/bash
# =============================================================================
# WORDPRESS FARM - Cluster Initialization Script
# =============================================================================
# Run this script on the first manager node to initialize the Swarm cluster
# and create all necessary networks and volumes.
# =============================================================================

set -euo pipefail

# =============================================================================
# COLORS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# FUNCTIONS
# =============================================================================

check_docker() {
    log_step "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_info "Docker is installed and running"
}

init_swarm() {
    log_step "Initializing Docker Swarm..."
    
    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        log_warn "Swarm is already initialized"
        return 0
    fi
    
    # Get the advertise address (private IP)
    local advertise_addr=$(ip -4 addr show eth1 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [[ -z "$advertise_addr" ]]; then
        advertise_addr=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    
    docker swarm init --advertise-addr "$advertise_addr"
    
    log_info "Swarm initialized with advertise address: $advertise_addr"
    
    # Display join tokens
    echo ""
    log_info "Manager join token:"
    docker swarm join-token manager
    
    echo ""
    log_info "Worker join token:"
    docker swarm join-token worker
}

create_networks() {
    log_step "Creating Docker overlay networks..."
    
    local networks=(
        "traefik-public"
        "crowdsec-net"
        "cache-net"
        "wordpress-net"
        "database-net"
        "storage-net"
        "observability-net"
    )
    
    for network in "${networks[@]}"; do
        if docker network ls | grep -q "$network"; then
            log_warn "Network already exists: $network"
        else
            docker network create \
                --driver overlay \
                --attachable \
                --opt encrypted=true \
                "$network"
            log_info "Created network: $network"
        fi
    done
}

create_directories() {
    log_step "Creating directory structure..."
    
    local directories=(
        "/var/opt/wordpress-farm/docker/configs/traefik/acme"
        "/var/opt/wordpress-farm/docker/configs/traefik/dynamic"
        "/var/opt/wordpress-farm/docker/configs/crowdsec"
        "/var/opt/wordpress-farm/docker/configs/varnish"
        "/var/opt/wordpress-farm/docker/configs/redis"
        "/var/opt/wordpress-farm/docker/configs/mariadb"
        "/var/opt/wordpress-farm/docker/configs/proxysql"
        "/var/opt/wordpress-farm/docker/configs/grafana/provisioning/datasources"
        "/var/opt/wordpress-farm/docker/configs/grafana/provisioning/dashboards"
        "/var/opt/wordpress-farm/docker/configs/grafana/dashboards"
        "/var/opt/wordpress-farm/docker/configs/mimir"
        "/var/opt/wordpress-farm/docker/configs/loki"
        "/var/opt/wordpress-farm/docker/configs/tempo"
        "/var/opt/wordpress-farm/docker/configs/alloy"
        "/var/opt/wordpress-farm/docker/configs/alertmanager"
        "/var/opt/wordpress-farm/sites"
        "/var/opt/wordpress-farm/backups/daily"
        "/var/opt/wordpress-farm/backups/weekly"
        "/var/opt/wordpress-farm/backups/monthly"
        "/var/opt/wordpress-farm/data/mariadb-1"
        "/var/opt/wordpress-farm/data/mariadb-2"
        "/var/opt/wordpress-farm/data/mariadb-3"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_info "Created: $dir"
    done
    
    # Set permissions for acme.json
    touch /var/opt/wordpress-farm/docker/configs/traefik/acme/acme.json
    chmod 600 /var/opt/wordpress-farm/docker/configs/traefik/acme/acme.json
}

label_nodes() {
    log_step "Labeling nodes..."
    
    # Get current node ID
    local node_id=$(docker info --format '{{.Swarm.NodeID}}')
    
    # Label this node as manager and ops (for initial setup)
    docker node update --label-add manager=true "$node_id"
    docker node update --label-add ops=true "$node_id"
    docker node update --label-add crowdsec=true "$node_id"
    
    log_info "Labeled node $node_id as manager, ops, crowdsec"
    
    echo ""
    log_warn "Remember to label other nodes as they join:"
    echo "  # App workers:"
    echo "  docker node update --label-add app=true <node-id>"
    echo ""
    echo "  # Cache nodes:"
    echo "  docker node update --label-add cache=true <node-id>"
    echo ""
    echo "  # Database nodes:"
    echo "  docker node update --label-add db=true <node-id>"
    echo "  docker node update --label-add db-node=1 <node-id>  # For node 1"
    echo "  docker node update --label-add db-node=2 <node-id>  # For node 2"
    echo "  docker node update --label-add db-node=3 <node-id>  # For node 3"
    echo ""
    echo "  # Storage nodes:"
    echo "  docker node update --label-add storage=true <node-id>"
}

copy_configs() {
    log_step "Copying configuration files..."
    
    # Copy configs from repo to system location
    if [[ -d "${PROJECT_ROOT}/docker/configs" ]]; then
        cp -r "${PROJECT_ROOT}/docker/configs/"* /var/opt/wordpress-farm/docker/configs/
        log_info "Configuration files copied"
    else
        log_warn "Config directory not found at ${PROJECT_ROOT}/docker/configs"
    fi
}

print_next_steps() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Cluster Initialization Complete!${NC}"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Join other manager nodes:"
    docker swarm join-token manager 2>/dev/null | tail -3
    echo ""
    echo "2. Join worker nodes:"
    docker swarm join-token worker 2>/dev/null | tail -3
    echo ""
    echo "3. Label nodes based on their role (see above)"
    echo ""
    echo "4. Copy environment file:"
    echo "   cp ${PROJECT_ROOT}/config/env.example /var/opt/wordpress-farm/.env"
    echo "   # Edit and fill in your values"
    echo ""
    echo "5. Deploy stacks in order:"
    echo "   cd /var/opt/wordpress-farm"
    echo "   docker stack deploy -c docker/compose/crowdsec.yml crowdsec"
    echo "   docker stack deploy -c docker/compose/traefik.yml traefik"
    echo "   docker stack deploy -c docker/compose/database.yml database"
    echo "   docker stack deploy -c docker/compose/cache.yml cache"
    echo "   docker stack deploy -c docker/compose/observability.yml observability"
    echo "   docker stack deploy -c docker/compose/management.yml management"
    echo ""
    echo "6. Create your first site:"
    echo "   ./scripts/site-create.sh example.com"
    echo ""
    echo "=============================================="
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo "=============================================="
    echo "WordPress Farm - Cluster Initialization"
    echo "=============================================="
    echo ""
    
    check_docker
    init_swarm
    create_networks
    create_directories
    label_nodes
    copy_configs
    print_next_steps
}

# Run main function
main "$@"


