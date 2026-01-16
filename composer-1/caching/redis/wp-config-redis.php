<?php
/**
 * WordPress Redis Object Cache Configuration
 * Add this to wp-config.php or include it
 */

// Redis Object Cache Configuration
define('WP_REDIS_HOST', getenv('REDIS_HOST') ?: 'redis');
define('WP_REDIS_PORT', getenv('REDIS_PORT') ?: 6379);
define('WP_REDIS_PASSWORD', getenv('REDIS_PASSWORD') ?: 'changeme');
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DISABLED', false);

// Use Redis for sessions
define('WP_REDIS_GLOBAL_GROUPS', array('users', 'userlogins', 'usermeta', 'user_meta', 'site-transient', 'site-options', 'site-lookup', 'blog-lookup', 'blog-details', 'rss', 'global-posts', 'blog-id-cache', 'networks', 'sites'));
define('WP_REDIS_IGNORED_GROUPS', array('counts', 'plugins'));

// Cache prefix
define('WP_CACHE_KEY_SALT', getenv('WP_CACHE_KEY_SALT') ?: 'wp_');

// Enable compression
define('WP_REDIS_COMPRESSION', true);

// Enable igbinary serializer if available
if (extension_loaded('igbinary')) {
    define('WP_REDIS_IGBINARY', true);
}


