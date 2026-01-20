#!/bin/bash
# =============================================================================
# WORDPRESS FARM - Site Creation Script
# =============================================================================
# Usage: ./site-create.sh example.com [--scale N]
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SITES_DIR="${PROJECT_ROOT}/sites"
COMPOSE_DIR="${PROJECT_ROOT}/docker/compose"
TEMPLATE_FILE="${COMPOSE_DIR}/wordpress-template.yml"

# Database settings
DB_HOST="proxysql:6033"
DB_ROOT_USER="root"

# Load environment
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    source "${PROJECT_ROOT}/.env"
fi

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
# FUNCTIONS
# =============================================================================

usage() {
    cat << EOF
WordPress Farm - Site Creation Script

Usage: $0 <domain> [options]

Arguments:
    domain          The domain name for the WordPress site (e.g., example.com)

Options:
    --scale N       Number of container replicas (default: 1)
    --admin-user    WordPress admin username (default: admin)
    --admin-email   WordPress admin email
    --title         Site title
    --dry-run       Show what would be done without executing
    --help          Show this help message

Examples:
    $0 example.com
    $0 example.com --scale 2 --admin-email admin@example.com
    $0 blog.example.com --title "My Blog" --admin-user webmaster

EOF
    exit 0
}

generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24
}

sanitize_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]'
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $domain"
        exit 1
    fi
}

check_domain_exists() {
    local domain="$1"
    local site_name=$(sanitize_name "$domain")
    
    if docker service ls --format '{{.Name}}' | grep -q "wp-${site_name}"; then
        log_error "Site already exists: $domain"
        exit 1
    fi
}

create_database() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    
    log_step "Creating database: $db_name"
    
    # Connect to ProxySQL/MariaDB and create database
    docker exec $(docker ps -q -f name=mariadb-1) mysql -u"${DB_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';
FLUSH PRIVILEGES;
EOF
    
    log_info "Database created successfully"
}

create_site_directory() {
    local domain="$1"
    local site_dir="${SITES_DIR}/${domain}"
    
    log_step "Creating site directory: $site_dir"
    
    mkdir -p "${site_dir}/wp-content/uploads"
    mkdir -p "${site_dir}/wp-content/plugins"
    mkdir -p "${site_dir}/wp-content/themes"
    mkdir -p "${site_dir}/wp-content/cache"
    
    # Create .env file for site
    cat > "${site_dir}/.env" << EOF
# WordPress Site Configuration
# Domain: ${domain}
# Created: $(date -Iseconds)

SITE_DOMAIN=${domain}
SITE_NAME=$(sanitize_name "$domain")
DB_NAME=wp_$(sanitize_name "$domain")
DB_USER=user_$(sanitize_name "$domain")
DB_PASSWORD=${DB_PASS}
EOF
    
    chmod 600 "${site_dir}/.env"
    log_info "Site directory created"
}

create_compose_file() {
    local domain="$1"
    local site_name="$2"
    local db_name="$3"
    local db_user="$4"
    local db_pass="$5"
    local replicas="${6:-1}"
    
    local compose_file="${COMPOSE_DIR}/sites/wp-${site_name}.yml"
    
    log_step "Creating Docker Compose file: $compose_file"
    
    mkdir -p "${COMPOSE_DIR}/sites"
    
    # Generate compose file from template
    sed -e "s/{{SITE_DOMAIN}}/${domain}/g" \
        -e "s/{{SITE_NAME}}/${site_name}/g" \
        -e "s/{{DB_NAME}}/${db_name}/g" \
        -e "s/{{DB_USER}}/${db_user}/g" \
        -e "s/{{DB_PASSWORD}}/${db_pass}/g" \
        "${TEMPLATE_FILE}" > "${compose_file}"
    
    # Update replicas if specified
    if [[ "$replicas" -gt 1 ]]; then
        sed -i "s/replicas: 1/replicas: ${replicas}/" "${compose_file}"
    fi
    
    log_info "Compose file created"
}

deploy_site() {
    local site_name="$1"
    local compose_file="${COMPOSE_DIR}/sites/wp-${site_name}.yml"
    
    log_step "Deploying WordPress site..."
    
    docker stack deploy -c "${compose_file}" "wp-${site_name}"
    
    log_info "Site deployed to Swarm"
}

wait_for_site() {
    local domain="$1"
    local max_attempts=60
    local attempt=1
    
    log_step "Waiting for site to become available..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "https://${domain}/wp-includes/images/blank.gif" 2>/dev/null | grep -q "200"; then
            log_info "Site is available!"
            return 0
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo ""
    log_warn "Site may not be fully available yet. Check manually."
    return 1
}

install_wordpress() {
    local domain="$1"
    local site_name="$2"
    local admin_user="${3:-admin}"
    local admin_email="${4:-admin@${domain}}"
    local title="${5:-${domain}}"
    local admin_pass=$(generate_password)
    
    log_step "Installing WordPress..."
    
    # Get the container ID
    local container_id=$(docker ps -q -f name="wp-${site_name}" | head -1)
    
    if [[ -z "$container_id" ]]; then
        log_error "Container not found. Please install WordPress manually."
        return 1
    fi
    
    # Run WP-CLI to install WordPress
    docker exec "$container_id" wp core install \
        --url="https://${domain}" \
        --title="${title}" \
        --admin_user="${admin_user}" \
        --admin_password="${admin_pass}" \
        --admin_email="${admin_email}" \
        --skip-email \
        --allow-root 2>/dev/null || true
    
    # Activate Redis Cache
    docker exec "$container_id" wp plugin activate redis-cache --allow-root 2>/dev/null || true
    docker exec "$container_id" wp redis enable --allow-root 2>/dev/null || true
    
    # Set permalink structure
    docker exec "$container_id" wp rewrite structure '/%postname%/' --allow-root 2>/dev/null || true
    
    log_info "WordPress installed successfully!"
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Site Created Successfully!${NC}"
    echo "=============================================="
    echo ""
    echo "  URL:            https://${domain}"
    echo "  Admin URL:      https://${domain}/wp-admin"
    echo "  Admin User:     ${admin_user}"
    echo "  Admin Password: ${admin_pass}"
    echo ""
    echo "  SAVE THIS PASSWORD - It will not be shown again!"
    echo ""
    echo "=============================================="
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    local domain=""
    local scale=1
    local admin_user="admin"
    local admin_email=""
    local title=""
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                usage
                ;;
            --scale)
                scale="$2"
                shift 2
                ;;
            --admin-user)
                admin_user="$2"
                shift 2
                ;;
            --admin-email)
                admin_email="$2"
                shift 2
                ;;
            --title)
                title="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                domain="$1"
                shift
                ;;
        esac
    done
    
    # Validate input
    if [[ -z "$domain" ]]; then
        log_error "Domain is required"
        usage
    fi
    
    validate_domain "$domain"
    check_domain_exists "$domain"
    
    # Prepare variables
    local site_name=$(sanitize_name "$domain")
    local db_name="wp_${site_name}"
    local db_user="user_${site_name}"
    local db_pass=$(generate_password)
    
    [[ -z "$admin_email" ]] && admin_email="admin@${domain}"
    [[ -z "$title" ]] && title="$domain"
    
    echo ""
    log_info "Creating WordPress site: $domain"
    echo "  Site Name:   $site_name"
    echo "  Database:    $db_name"
    echo "  DB User:     $db_user"
    echo "  Replicas:    $scale"
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        log_warn "Dry run - no changes made"
        exit 0
    fi
    
    # Execute creation steps
    create_database "$db_name" "$db_user" "$db_pass"
    create_site_directory "$domain"
    create_compose_file "$domain" "$site_name" "$db_name" "$db_user" "$db_pass" "$scale"
    deploy_site "$site_name"
    
    # Wait and install
    sleep 30  # Wait for container to start
    wait_for_site "$domain" || true
    install_wordpress "$domain" "$site_name" "$admin_user" "$admin_email" "$title"
    
    log_info "Site creation complete!"
}

# Run main function
main "$@"


