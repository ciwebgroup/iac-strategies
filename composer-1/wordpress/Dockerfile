# Custom WordPress Image
# Extends official WordPress image with optimizations

FROM wordpress:php8.2-fpm

# Install additional PHP extensions
RUN apt-get update && apt-get install -y \
    libzip-dev \
    libicu-dev \
    libonig-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libxpm-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm \
    && docker-php-ext-install -j$(nproc) \
    zip \
    intl \
    mbstring \
    opcache \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Redis extension
RUN pecl install redis igbinary \
    && docker-php-ext-enable redis igbinary

# Install Memcached extension
RUN apt-get update && apt-get install -y \
    libmemcached-dev \
    zlib1g-dev \
    && pecl install memcached \
    && docker-php-ext-enable memcached \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure PHP
COPY php.ini /usr/local/etc/php/conf.d/custom.ini
COPY php-fpm.conf /usr/local/etc/php-fpm.d/zzz-custom.conf

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Install healthcheck script
COPY php-fpm-healthcheck /usr/local/bin/
RUN chmod +x /usr/local/bin/php-fpm-healthcheck

# Set working directory
WORKDIR /var/www/html

# Create uploads directory with proper permissions
RUN mkdir -p /var/www/html/wp-content/uploads \
    && chown -R www-data:www-data /var/www/html/wp-content/uploads

# Expose PHP-FPM port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD php-fpm-healthcheck || exit 1

# Use PHP-FPM
CMD ["php-fpm"]


