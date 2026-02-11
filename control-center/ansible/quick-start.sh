#!/usr/bin/env bash
#
# =============================================================================
# WORDPRESS FARM - ANSIBLE QUICK START
# =============================================================================
# One-command setup for Ansible-based infrastructure management
#
# Usage: ./quick-start.sh [check|setup|provision|deploy|all]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { log_error "$*"; exit 1; }

# =============================================================================
# CHECKS
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing=0
    
    # Check Ansible
    if ! command -v ansible >/dev/null 2>&1; then
        log_error "Ansible not installed"
        echo "  Install: sudo apt install ansible"
        ((missing++))
    else
        log_info "✓ Ansible $(ansible --version | head -n1 | awk '{print $2}')"
    fi
    
    # Check doctl
    if ! command -v doctl >/dev/null 2>&1; then
        log_error "doctl not installed"
        echo "  Install: https://docs.digitalocean.com/reference/doctl/how-to/install/"
        ((missing++))
    else
        log_info "✓ doctl $(doctl version | awk '{print $3}')"
    fi
    
    # Check Python libraries
    if ! python3 -c "import docker" 2>/dev/null; then
        log_warn "Python docker library not installed"
        echo "  Install: pip3 install docker"
    fi
    
    # Check environment
    if [[ ! -f "../.env" ]]; then
        log_error ".env file not found"
        echo "  Copy: cp ../scripts/.env.example ../.env"
        ((missing++))
    else
        log_info "✓ .env file exists"
    fi
    
    # Check DO token
    if [[ -f "../.env" ]]; then
        set -a
        source "../.env"
        set +a
        
        if [[ -z "${DO_API_TOKEN:-}" ]]; then
            log_error "DO_API_TOKEN not set in .env"
            ((missing++))
        else
            log_info "✓ DO_API_TOKEN configured"
        fi
        
        if [[ -z "${CF_API_TOKEN:-}" ]]; then
            log_warn "CF_API_TOKEN not set (optional)"
        else
            log_info "✓ CF_API_TOKEN configured"
        fi
    fi
    
    if [[ $missing -gt 0 ]]; then
        die "Missing $missing required prerequisites"
    fi
    
    log "✓ All prerequisites met"
}

check_collections() {
    log "Checking Ansible collections..."
    
    if [[ ! -f "requirements.yml" ]]; then
        die "requirements.yml not found"
    fi
    
    # Check if collections are installed
    if ansible-galaxy collection list community.digitalocean >/dev/null 2>&1; then
        log_info "✓ Ansible collections installed"
    else
        log_warn "Ansible collections not installed"
        log_info "Run: ansible-galaxy collection install -r requirements.yml"
    fi
}

# =============================================================================
# SETUP
# =============================================================================

setup_environment() {
    log "Setting up Ansible environment..."
    
    # Install collections
    log_info "Installing Ansible collections..."
    ansible-galaxy collection install -r requirements.yml
    
    # Load environment
    if [[ -f "../.env" ]]; then
        set -a
        source "../.env"
        set +a
        log_info "✓ Environment variables loaded"
    fi
    
    # Test doctl authentication
    log_info "Testing DigitalOcean authentication..."
    if doctl account get >/dev/null 2>&1; then
        log_info "✓ DigitalOcean authenticated"
    else
        log_warn "DigitalOcean not authenticated"
        echo "  Run: doctl auth init"
    fi
    
    # Test inventory
    log_info "Testing dynamic inventory..."
    if ansible-inventory --list >/dev/null 2>&1; then
        log_info "✓ Inventory working"
    else
        log_warn "Inventory check failed (expected if no droplets exist)"
    fi
    
    log "✓ Setup complete"
}

# =============================================================================
# DEPLOYMENT
# =============================================================================

provision_infrastructure() {
    log "Provisioning infrastructure..."
    log_warn "This will create ~33 droplets on DigitalOcean!"
    log_warn "Estimated cost: $3,613/month"
    
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        die "Provisioning cancelled"
    fi
    
    ansible-playbook provision.yml
    
    log "✓ Infrastructure provisioned"
    log_info "Waiting 2 minutes for droplets to boot..."
    sleep 120
}

deploy_services() {
    log "Deploying services..."
    
    ansible-playbook deploy.yml
    
    log "✓ Services deployed"
}

verify_deployment() {
    log "Verifying deployment..."
    
    ansible-playbook health.yml
    
    log "✓ Deployment verified"
}

# =============================================================================
# MAIN
# =============================================================================

usage() {
    cat <<EOF
WordPress Farm - Ansible Quick Start

Usage: $0 [COMMAND]

Commands:
  check       Check prerequisites only
  setup       Install collections and setup environment
  provision   Provision infrastructure on DigitalOcean
  deploy      Deploy all services
  verify      Run health checks
  all         Run everything (check → setup → provision → deploy → verify)

Examples:
  $0 check          # Check if ready to deploy
  $0 setup          # Install Ansible collections
  $0 all            # Full deployment (45 minutes)

EOF
}

main() {
    local command="${1:-help}"
    
    cd "$(dirname "${BASH_SOURCE[0]}")"
    
    case "$command" in
        check)
            check_prerequisites
            check_collections
            ;;
        setup)
            check_prerequisites
            setup_environment
            ;;
        provision)
            check_prerequisites
            provision_infrastructure
            ;;
        deploy)
            check_prerequisites
            deploy_services
            ;;
        verify)
            check_prerequisites
            verify_deployment
            ;;
        all)
            check_prerequisites
            setup_environment
            provision_infrastructure
            deploy_services
            verify_deployment
            
            log ""
            log "========================================"
            log "  DEPLOYMENT COMPLETE! 🎉"
            log "========================================"
            log ""
            log "Next steps:"
            log "  1. Create a WordPress site:"
            log "     ansible-playbook site.yml -e domain=example.com"
            log ""
            log "  2. Configure DNS:"
            log "     ansible-playbook dns.yml -e domain=example.com"
            log ""
            log "  3. Access services:"
            log "     - Grafana: https://grafana.yourdomain.com"
            log "     - Portainer: https://portainer.yourdomain.com"
            log ""
            log "========================================"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
