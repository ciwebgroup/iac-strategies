#!/bin/sh
# =============================================================================
# WORDPRESS CONTAINER ENTRYPOINT
# =============================================================================

set -e

# =============================================================================
# COLOR OUTPUT
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# WAIT FOR DEPENDENCIES
# =============================================================================
wait_for_service() {
    local host=$1
    local port=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    log_info "Waiting for $host:$port..."
    
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            log_error "Service $host:$port not available after $max_attempts attempts"
            return 1
        fi
        log_warn "Attempt $attempt/$max_attempts - $host:$port not ready, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_info "$host:$port is available"
    return 0
}

# =============================================================================
# DIRECTORY SETUP
# =============================================================================
setup_directories() {
    log_info "Setting up directories..."
    
    # Create required directories
    mkdir -p /var/log/nginx
    mkdir -p /var/log/php-fpm
    mkdir -p /var/log/supervisor
    mkdir -p /var/cache/nginx
    mkdir -p /run/nginx
    mkdir -p /var/www/html/wp-content/uploads
    mkdir -p /var/www/html/wp-content/cache
    
    # Set permissions
    chown -R www-data:www-data /var/www/html
    chown -R www-data:www-data /var/log/nginx
    chown -R www-data:www-data /var/log/php-fpm
    chown -R www-data:www-data /var/cache/nginx
    
    # Secure wp-config.php
    if [ -f /var/www/html/wp-config.php ]; then
        chmod 640 /var/www/html/wp-config.php
    fi
    
    log_info "Directory setup complete"
}

# =============================================================================
# WORDPRESS CONFIGURATION
# =============================================================================
configure_wordpress() {
    log_info "Configuring WordPress..."
    
    # Run the original WordPress entrypoint if needed
    if [ ! -f /var/www/html/wp-config.php ]; then
        log_info "Running WordPress installation..."
        docker-entrypoint.sh php-fpm &
        sleep 5
        kill $! 2>/dev/null || true
    fi
    
    # Add Redis Object Cache drop-in if plugin is installed
    if [ -d /var/www/html/wp-content/plugins/redis-cache ]; then
        if [ ! -f /var/www/html/wp-content/object-cache.php ]; then
            log_info "Installing Redis Object Cache drop-in..."
            cp /var/www/html/wp-content/plugins/redis-cache/includes/object-cache.php \
               /var/www/html/wp-content/object-cache.php
            chown www-data:www-data /var/www/html/wp-content/object-cache.php
        fi
    fi
    
    # Set up WP-CLI config
    if [ ! -f /var/www/html/wp-cli.yml ]; then
        cat > /var/www/html/wp-cli.yml << 'EOF'
path: /var/www/html
url: ${WORDPRESS_SITE_URL}
user: admin
color: true
debug: false
quiet: false
EOF
        chown www-data:www-data /var/www/html/wp-cli.yml
    fi
    
    log_info "WordPress configuration complete"
}

# =============================================================================
# CRON SETUP
# =============================================================================
setup_cron() {
    log_info "Setting up cron jobs..."
    
    # Create crontab for WordPress
    cat > /etc/crontabs/www-data << 'EOF'
# WordPress cron (every 5 minutes)
*/5 * * * * cd /var/www/html && /usr/local/bin/wp cron event run --due-now --quiet 2>&1

# Opcache reset (daily at 3am)
0 3 * * * /usr/local/bin/php -r "opcache_reset();" 2>&1

# Cleanup old transients (daily at 4am)
0 4 * * * cd /var/www/html && /usr/local/bin/wp transient delete --expired --quiet 2>&1
EOF
    
    chmod 0644 /etc/crontabs/www-data
    
    log_info "Cron setup complete"
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================
perform_health_checks() {
    log_info "Performing pre-flight health checks..."
    
    # Check PHP
    if ! php -v > /dev/null 2>&1; then
        log_error "PHP is not working"
        return 1
    fi
    
    # Check nginx config
    if ! nginx -t > /dev/null 2>&1; then
        log_error "Nginx configuration is invalid"
        nginx -t
        return 1
    fi
    
    log_info "Health checks passed"
    return 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    log_info "Starting WordPress Farm container..."
    log_info "PHP Version: $(php -v | head -n 1)"
    log_info "Nginx Version: $(nginx -v 2>&1)"
    
    # Wait for required services
    if [ -n "$WORDPRESS_DB_HOST" ]; then
        DB_HOST=$(echo "$WORDPRESS_DB_HOST" | cut -d: -f1)
        DB_PORT=$(echo "$WORDPRESS_DB_HOST" | cut -d: -f2)
        DB_PORT=${DB_PORT:-3306}
        wait_for_service "$DB_HOST" "$DB_PORT" 60 || exit 1
    fi
    
    if [ -n "$WP_REDIS_HOST" ]; then
        wait_for_service "$WP_REDIS_HOST" "${WP_REDIS_PORT:-6379}" 30 || log_warn "Redis not available, continuing without cache"
    fi
    
    # Setup
    setup_directories
    configure_wordpress
    setup_cron
    
    # Health checks
    perform_health_checks || exit 1
    
    log_info "Container initialization complete"
    log_info "Starting supervisord..."
    
    # Execute the main command
    exec "$@"
}

# Run main function
main "$@"


