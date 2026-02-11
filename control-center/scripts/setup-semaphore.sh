#!/bin/bash
set -euo pipefail

# =============================================================================
# Semaphore UI Setup Script
# =============================================================================
# This script helps set up Semaphore UI with proper encryption keys
# and deploys it to Docker Swarm
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_CENTER_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$CONTROL_CENTER_DIR/.env"
COMPOSE_FILE="$CONTROL_CENTER_DIR/docker-compose-examples/semaphore-stack.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

generate_key() {
    openssl rand -base64 32
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Generate encryption keys
generate_keys() {
    print_header "Generating Encryption Keys"
    
    # Check if keys already exist
    if grep -q "SEMAPHORE_ACCESS_KEY_ENCRYPTION=.\+" "$ENV_FILE" 2>/dev/null; then
        print_warning "Encryption keys already exist in .env file"
        read -p "Do you want to regenerate them? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Keeping existing keys"
            return 0
        fi
    fi
    
    print_info "Generating SEMAPHORE_ACCESS_KEY_ENCRYPTION..."
    local access_key=$(generate_key)
    
    print_info "Generating SEMAPHORE_COOKIE_HASH..."
    local cookie_hash=$(generate_key)
    
    print_info "Generating SEMAPHORE_COOKIE_ENCRYPTION..."
    local cookie_encryption=$(generate_key)
    
    # Update .env file
    sed -i "s|^SEMAPHORE_ACCESS_KEY_ENCRYPTION=.*|SEMAPHORE_ACCESS_KEY_ENCRYPTION=$access_key|" "$ENV_FILE"
    sed -i "s|^SEMAPHORE_COOKIE_HASH=.*|SEMAPHORE_COOKIE_HASH=$cookie_hash|" "$ENV_FILE"
    sed -i "s|^SEMAPHORE_COOKIE_ENCRYPTION=.*|SEMAPHORE_COOKIE_ENCRYPTION=$cookie_encryption|" "$ENV_FILE"
    
    print_success "Encryption keys generated and saved to .env file"
}

# Configure admin credentials
configure_admin() {
    print_header "Configure Admin User"
    
    print_info "Current admin configuration in .env:"
    grep "^SEMAPHORE_ADMIN" "$ENV_FILE" || true
    echo
    
    read -p "Do you want to update admin credentials? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Admin username [admin]: " admin_user
        admin_user=${admin_user:-admin}
        
        read -s -p "Admin password: " admin_password
        echo
        read -s -p "Confirm password: " admin_password_confirm
        echo
        
        if [ "$admin_password" != "$admin_password_confirm" ]; then
            print_error "Passwords do not match"
            exit 1
        fi
        
        read -p "Admin name [Administrator]: " admin_name
        admin_name=${admin_name:-Administrator}
        
        read -p "Admin email [admin@yourdomain.com]: " admin_email
        admin_email=${admin_email:-admin@yourdomain.com}
        
        # Update .env file
        sed -i "s|^SEMAPHORE_ADMIN=.*|SEMAPHORE_ADMIN=$admin_user|" "$ENV_FILE"
        sed -i "s|^SEMAPHORE_ADMIN_PASSWORD=.*|SEMAPHORE_ADMIN_PASSWORD=$admin_password|" "$ENV_FILE"
        sed -i "s|^SEMAPHORE_ADMIN_NAME=.*|SEMAPHORE_ADMIN_NAME=$admin_name|" "$ENV_FILE"
        sed -i "s|^SEMAPHORE_ADMIN_EMAIL=.*|SEMAPHORE_ADMIN_EMAIL=$admin_email|" "$ENV_FILE"
        
        print_success "Admin credentials updated"
    fi
}

# Configure domain
configure_domain() {
    print_header "Configure Domain"
    
    read -p "Enter your domain for Semaphore (e.g., semaphore.example.com): " semaphore_domain
    
    if [ -z "$semaphore_domain" ]; then
        print_error "Domain cannot be empty"
        exit 1
    fi
    
    # Update compose file
    sed -i "s|semaphore.yourdomain.com|$semaphore_domain|g" "$COMPOSE_FILE"
    
    print_success "Domain configured: $semaphore_domain"
}

# Check/create networks
check_networks() {
    print_header "Checking Docker Networks"
    
    local networks=("management" "traefik-public")
    
    for network in "${networks[@]}"; do
        if docker network ls | grep -q "$network"; then
            print_success "Network '$network' exists"
        else
            print_warning "Network '$network' does not exist"
            read -p "Create network '$network'? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker network create --driver=overlay --attachable "$network"
                print_success "Network '$network' created"
            else
                print_error "Required network '$network' missing. Cannot proceed."
                exit 1
            fi
        fi
    done
}

# Deploy stack
deploy_stack() {
    print_header "Deploying Semaphore UI Stack"
    
    print_info "Loading environment variables..."
    source "$ENV_FILE"
    
    print_info "Deploying stack to Docker Swarm..."
    docker stack deploy -c "$COMPOSE_FILE" semaphore
    
    print_success "Semaphore UI stack deployed"
    
    echo
    print_info "Waiting for service to start..."
    sleep 5
    
    docker service ls | grep semaphore || true
    echo
    
    print_info "View logs with:"
    echo "  docker service logs -f semaphore_semaphore"
    echo
    print_info "Check status with:"
    echo "  docker service ps semaphore_semaphore"
}

# Main menu
main_menu() {
    print_header "Semaphore UI Setup"
    
    echo "1) Generate encryption keys"
    echo "2) Configure admin credentials"
    echo "3) Configure domain"
    echo "4) Check/create networks"
    echo "5) Deploy Semaphore UI"
    echo "6) Full setup (all steps)"
    echo "7) Remove deployment"
    echo "8) Exit"
    echo
    read -p "Select an option [1-8]: " choice
    
    case $choice in
        1)
            generate_keys
            ;;
        2)
            configure_admin
            ;;
        3)
            configure_domain
            ;;
        4)
            check_networks
            ;;
        5)
            deploy_stack
            ;;
        6)
            generate_keys
            configure_admin
            configure_domain
            check_networks
            deploy_stack
            print_success "Setup complete!"
            echo
            print_info "Access Semaphore UI at: https://$(grep 'semaphore\.' $COMPOSE_FILE | grep -oP 'semaphore\.\K[^`]+' | head -1)"
            ;;
        7)
            print_warning "Removing Semaphore UI stack..."
            docker stack rm semaphore
            print_success "Stack removed"
            ;;
        8)
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

# Main execution
check_prerequisites
main_menu
