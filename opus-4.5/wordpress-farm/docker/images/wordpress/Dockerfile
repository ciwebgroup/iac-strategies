# =============================================================================
# CUSTOM WORDPRESS IMAGE - Optimized for Production Farm
# =============================================================================
# Build: docker build -t wpfarm/wordpress:latest .
# =============================================================================

FROM wordpress:6.7-php8.3-fpm-alpine

LABEL maintainer="WordPress Farm <admin@example.com>"
LABEL description="Production-optimized WordPress with nginx, PHP-FPM, and performance plugins"

# =============================================================================
# SYSTEM PACKAGES
# =============================================================================
RUN apk add --no-cache \
    # Web server
    nginx \
    # Image optimization
    jpegoptim \
    optipng \
    pngquant \
    gifsicle \
    # CLI tools
    curl \
    wget \
    git \
    unzip \
    # Health checks
    fcgi \
    # Supervisor for process management
    supervisor \
    # MariaDB client for WP-CLI
    mariadb-client \
    # Text processing
    sed \
    gawk \
    # Timezone data
    tzdata

# =============================================================================
# PHP EXTENSIONS
# =============================================================================
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        imagemagick-dev \
        icu-dev \
        libmemcached-dev \
        zlib-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        gd \
        exif \
        intl \
        zip \
        opcache \
        pdo_mysql \
        mysqli \
        bcmath \
    && pecl install \
        redis-6.0.2 \
        imagick \
        apcu \
    && docker-php-ext-enable \
        redis \
        imagick \
        apcu \
    && apk del .build-deps \
    && rm -rf /tmp/pear

# =============================================================================
# PHP CONFIGURATION
# =============================================================================
COPY php/php.ini /usr/local/etc/php/php.ini
COPY php/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# =============================================================================
# NGINX CONFIGURATION
# =============================================================================
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/wordpress.conf /etc/nginx/http.d/default.conf
COPY nginx/security.conf /etc/nginx/snippets/security.conf
COPY nginx/cache.conf /etc/nginx/snippets/cache.conf

# =============================================================================
# WP-CLI
# =============================================================================
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# =============================================================================
# MUST-USE PLUGINS (Pre-installed)
# =============================================================================
RUN mkdir -p /var/www/html/wp-content/mu-plugins

# Redis Object Cache Drop-in
RUN curl -L https://github.com/rhubarbgroup/redis-cache/releases/latest/download/redis-cache.zip -o /tmp/redis-cache.zip \
    && unzip /tmp/redis-cache.zip -d /tmp \
    && mv /tmp/redis-cache /var/www/html/wp-content/plugins/redis-cache \
    && rm /tmp/redis-cache.zip

# Security Hardening MU-Plugin
COPY mu-plugins/security-hardening.php /var/www/html/wp-content/mu-plugins/

# Performance MU-Plugin
COPY mu-plugins/performance.php /var/www/html/wp-content/mu-plugins/

# =============================================================================
# SUPERVISOR (Multi-process container)
# =============================================================================
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# =============================================================================
# ENTRYPOINT & SCRIPTS
# =============================================================================
COPY scripts/entrypoint.sh /usr/local/bin/docker-entrypoint-custom.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh \
    && chmod +x /usr/local/bin/healthcheck.sh

# =============================================================================
# DIRECTORIES & PERMISSIONS
# =============================================================================
RUN mkdir -p /var/log/nginx \
    && mkdir -p /var/log/php-fpm \
    && mkdir -p /var/cache/nginx \
    && mkdir -p /run/nginx \
    && chown -R www-data:www-data /var/www/html \
    && chown -R www-data:www-data /var/log/nginx \
    && chown -R www-data:www-data /var/log/php-fpm \
    && chown -R www-data:www-data /var/cache/nginx

# =============================================================================
# EXPOSE & HEALTHCHECK
# =============================================================================
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD /usr/local/bin/healthcheck.sh

# =============================================================================
# ENTRYPOINT
# =============================================================================
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-custom.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]


