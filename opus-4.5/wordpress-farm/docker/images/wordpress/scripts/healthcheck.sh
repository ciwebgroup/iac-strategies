#!/bin/sh
# =============================================================================
# WORDPRESS CONTAINER HEALTHCHECK
# =============================================================================

set -e

# Check nginx is running
if ! pgrep -x nginx > /dev/null; then
    echo "nginx is not running"
    exit 1
fi

# Check PHP-FPM is running
if ! pgrep -x php-fpm > /dev/null; then
    echo "php-fpm is not running"
    exit 1
fi

# Check PHP-FPM responds to ping
PING_RESPONSE=$(curl -s --fail http://127.0.0.1/fpm-ping 2>/dev/null || echo "failed")
if [ "$PING_RESPONSE" != "pong" ]; then
    echo "PHP-FPM ping failed"
    exit 1
fi

# Check WordPress responds
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/wp-includes/images/blank.gif 2>/dev/null || echo "000")
if [ "$HTTP_CODE" -ne 200 ]; then
    echo "WordPress health endpoint returned $HTTP_CODE"
    exit 1
fi

echo "healthy"
exit 0


