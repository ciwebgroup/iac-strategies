<?php
/**
 * Plugin Name: WP Farm Performance Optimizations
 * Description: Performance optimizations for WordPress Farm
 * Version: 1.0.0
 * Author: WordPress Farm
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Disable emojis
 */
function wpfarm_disable_emojis() {
    remove_action('wp_head', 'print_emoji_detection_script', 7);
    remove_action('admin_print_scripts', 'print_emoji_detection_script');
    remove_action('wp_print_styles', 'print_emoji_styles');
    remove_action('admin_print_styles', 'print_emoji_styles');
    remove_filter('the_content_feed', 'wp_staticize_emoji');
    remove_filter('comment_text_rss', 'wp_staticize_emoji');
    remove_filter('wp_mail', 'wp_staticize_emoji_for_email');
    
    add_filter('tiny_mce_plugins', function($plugins) {
        return is_array($plugins) ? array_diff($plugins, ['wpemoji']) : [];
    });
    
    add_filter('wp_resource_hints', function($urls, $relation_type) {
        if ('dns-prefetch' === $relation_type) {
            $urls = array_filter($urls, function($url) {
                return strpos($url, 'https://s.w.org/images/core/emoji/') === false;
            });
        }
        return $urls;
    }, 10, 2);
}
add_action('init', 'wpfarm_disable_emojis');

/**
 * Remove jQuery Migrate
 */
function wpfarm_remove_jquery_migrate($scripts) {
    if (!is_admin() && isset($scripts->registered['jquery'])) {
        $script = $scripts->registered['jquery'];
        if ($script->deps) {
            $script->deps = array_diff($script->deps, ['jquery-migrate']);
        }
    }
}
add_action('wp_default_scripts', 'wpfarm_remove_jquery_migrate');

/**
 * Disable self-pingbacks
 */
function wpfarm_disable_self_pingback(&$links) {
    $home = get_option('home');
    foreach ($links as $l => $link) {
        if (strpos($link, $home) === 0) {
            unset($links[$l]);
        }
    }
}
add_action('pre_ping', 'wpfarm_disable_self_pingback');

/**
 * Limit post revisions
 */
if (!defined('WP_POST_REVISIONS')) {
    define('WP_POST_REVISIONS', 5);
}

/**
 * Increase autosave interval
 */
if (!defined('AUTOSAVE_INTERVAL')) {
    define('AUTOSAVE_INTERVAL', 120); // 2 minutes
}

/**
 * Remove shortlink from head
 */
remove_action('wp_head', 'wp_shortlink_wp_head');

/**
 * Remove RSD link from head
 */
remove_action('wp_head', 'rsd_link');

/**
 * Remove Windows Live Writer manifest link
 */
remove_action('wp_head', 'wlwmanifest_link');

/**
 * Remove feed links
 */
remove_action('wp_head', 'feed_links', 2);
remove_action('wp_head', 'feed_links_extra', 3);

/**
 * Remove REST API link from head
 */
remove_action('wp_head', 'rest_output_link_wp_head');
remove_action('wp_head', 'wp_oembed_add_discovery_links');
remove_action('template_redirect', 'rest_output_link_header', 11);

/**
 * Disable oEmbed
 */
function wpfarm_disable_oembed() {
    // Remove oEmbed discovery links
    remove_action('wp_head', 'wp_oembed_add_discovery_links');
    remove_action('wp_head', 'wp_oembed_add_host_js');
    
    // Remove oEmbed-specific JavaScript from the front-end and back-end
    remove_action('wp_head', 'wp_oembed_add_host_js');
}
add_action('init', 'wpfarm_disable_oembed');

/**
 * Heartbeat API optimization
 */
function wpfarm_heartbeat_settings($settings) {
    $settings['interval'] = 60; // 60 seconds instead of 15
    return $settings;
}
add_filter('heartbeat_settings', 'wpfarm_heartbeat_settings');

/**
 * Disable Heartbeat on front-end (optional)
 */
function wpfarm_disable_frontend_heartbeat() {
    if (!is_admin()) {
        wp_deregister_script('heartbeat');
    }
}
add_action('init', 'wpfarm_disable_frontend_heartbeat', 1);

/**
 * Optimize WP Query for large sites
 */
function wpfarm_optimize_queries($query) {
    if (!is_admin() && $query->is_main_query()) {
        // Don't count total rows for performance
        $query->set('no_found_rows', true);
        
        // Limit posts per page
        if ($query->get('posts_per_page') > 50) {
            $query->set('posts_per_page', 50);
        }
    }
}
add_action('pre_get_posts', 'wpfarm_optimize_queries');

/**
 * Cache menu items
 */
function wpfarm_cache_nav_menu($nav_menu, $args) {
    if (is_admin()) {
        return $nav_menu;
    }
    
    $cache_key = 'wpfarm_menu_' . md5(serialize($args));
    $cached_menu = wp_cache_get($cache_key, 'nav_menus');
    
    if ($cached_menu !== false) {
        return $cached_menu;
    }
    
    wp_cache_set($cache_key, $nav_menu, 'nav_menus', HOUR_IN_SECONDS);
    
    return $nav_menu;
}
add_filter('wp_nav_menu', 'wpfarm_cache_nav_menu', 10, 2);

/**
 * Clear menu cache on menu update
 */
function wpfarm_clear_menu_cache($menu_id) {
    wp_cache_flush_group('nav_menus');
}
add_action('wp_update_nav_menu', 'wpfarm_clear_menu_cache');

/**
 * Preload critical resources
 */
function wpfarm_preload_resources() {
    // Preload critical fonts
    echo '<link rel="preload" href="' . get_template_directory_uri() . '/fonts/main.woff2" as="font" type="font/woff2" crossorigin>' . "\n";
}
// Uncomment and customize for your theme:
// add_action('wp_head', 'wpfarm_preload_resources', 1);

/**
 * Add async/defer to scripts
 */
function wpfarm_script_loader_tag($tag, $handle, $src) {
    // Scripts to defer
    $defer_scripts = ['jquery', 'wp-embed'];
    
    // Scripts to async
    $async_scripts = [];
    
    if (in_array($handle, $defer_scripts)) {
        return str_replace(' src', ' defer src', $tag);
    }
    
    if (in_array($handle, $async_scripts)) {
        return str_replace(' src', ' async src', $tag);
    }
    
    return $tag;
}
// Uncomment if needed (may break some functionality):
// add_filter('script_loader_tag', 'wpfarm_script_loader_tag', 10, 3);

/**
 * Database cleanup (runs weekly via cron)
 */
function wpfarm_cleanup_database() {
    global $wpdb;
    
    // Delete old revisions (keep last 5)
    $wpdb->query("
        DELETE FROM $wpdb->posts 
        WHERE post_type = 'revision' 
        AND ID NOT IN (
            SELECT * FROM (
                SELECT ID FROM $wpdb->posts 
                WHERE post_type = 'revision' 
                ORDER BY post_date DESC 
                LIMIT 5
            ) AS t
        )
    ");
    
    // Delete orphaned postmeta
    $wpdb->query("
        DELETE FROM $wpdb->postmeta 
        WHERE post_id NOT IN (
            SELECT ID FROM $wpdb->posts
        )
    ");
    
    // Delete expired transients
    $wpdb->query("
        DELETE FROM $wpdb->options 
        WHERE option_name LIKE '_transient_timeout_%' 
        AND option_value < UNIX_TIMESTAMP()
    ");
    
    $wpdb->query("
        DELETE FROM $wpdb->options 
        WHERE option_name LIKE '_transient_%' 
        AND option_name NOT LIKE '_transient_timeout_%'
        AND REPLACE(option_name, '_transient_', '_transient_timeout_') NOT IN (
            SELECT option_name FROM (
                SELECT option_name FROM $wpdb->options 
                WHERE option_name LIKE '_transient_timeout_%'
            ) AS t
        )
    ");
    
    // Optimize tables
    $wpdb->query("OPTIMIZE TABLE $wpdb->posts, $wpdb->postmeta, $wpdb->options, $wpdb->comments, $wpdb->commentmeta");
}

// Schedule weekly cleanup
if (!wp_next_scheduled('wpfarm_weekly_cleanup')) {
    wp_schedule_event(time(), 'weekly', 'wpfarm_weekly_cleanup');
}
add_action('wpfarm_weekly_cleanup', 'wpfarm_cleanup_database');


