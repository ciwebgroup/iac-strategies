<?php
/**
 * Plugin Name: WP Farm Security Hardening
 * Description: Security hardening for WordPress Farm
 * Version: 1.0.0
 * Author: WordPress Farm
 */

if (!defined('ABSPATH')) {
    exit;
}

/**
 * Disable XML-RPC
 */
add_filter('xmlrpc_enabled', '__return_false');
add_filter('xmlrpc_methods', function() {
    return [];
});

/**
 * Remove WordPress version from head
 */
remove_action('wp_head', 'wp_generator');
add_filter('the_generator', '__return_empty_string');

/**
 * Remove version from scripts and styles
 */
function wpfarm_remove_version_strings($src) {
    if (strpos($src, 'ver=')) {
        $src = remove_query_arg('ver', $src);
    }
    return $src;
}
add_filter('style_loader_src', 'wpfarm_remove_version_strings', 9999);
add_filter('script_loader_src', 'wpfarm_remove_version_strings', 9999);

/**
 * Disable file editing in admin
 */
if (!defined('DISALLOW_FILE_EDIT')) {
    define('DISALLOW_FILE_EDIT', true);
}

/**
 * Disable plugin/theme installation via admin (use deployment instead)
 */
if (!defined('DISALLOW_FILE_MODS')) {
    define('DISALLOW_FILE_MODS', true);
}

/**
 * Security headers (additional to Traefik/nginx)
 */
function wpfarm_security_headers() {
    if (!is_admin()) {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: SAMEORIGIN');
        header('X-XSS-Protection: 1; mode=block');
        header('Referrer-Policy: strict-origin-when-cross-origin');
    }
}
add_action('send_headers', 'wpfarm_security_headers');

/**
 * Disable REST API for non-authenticated users (optional, may break some plugins)
 */
function wpfarm_restrict_rest_api($result) {
    // Allow certain endpoints for non-authenticated users
    $allowed_routes = [
        '/wp/v2/posts',
        '/wp/v2/pages',
        '/wp/v2/categories',
        '/wp/v2/tags',
        '/oembed/',
        '/contact-form-7/', // If using Contact Form 7
    ];
    
    $current_route = $GLOBALS['wp']->query_vars['rest_route'] ?? '';
    
    foreach ($allowed_routes as $route) {
        if (strpos($current_route, $route) !== false) {
            return $result;
        }
    }
    
    if (!is_user_logged_in()) {
        return new WP_Error(
            'rest_forbidden',
            'REST API restricted',
            ['status' => 403]
        );
    }
    
    return $result;
}
// Uncomment to enable REST API restriction:
// add_filter('rest_authentication_errors', 'wpfarm_restrict_rest_api');

/**
 * Disable author archives (prevents user enumeration)
 */
function wpfarm_disable_author_archives() {
    if (is_author()) {
        wp_redirect(home_url(), 301);
        exit;
    }
}
add_action('template_redirect', 'wpfarm_disable_author_archives');

/**
 * Remove login error messages (prevents username enumeration)
 */
function wpfarm_login_errors() {
    return 'Invalid credentials.';
}
add_filter('login_errors', 'wpfarm_login_errors');

/**
 * Limit login attempts (basic implementation, use with CrowdSec)
 */
function wpfarm_limit_login_attempts($user, $username, $password) {
    if (empty($username) || empty($password)) {
        return $user;
    }
    
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    $transient_key = 'wpfarm_login_attempts_' . md5($ip);
    $attempts = get_transient($transient_key) ?: 0;
    
    if ($attempts >= 5) {
        return new WP_Error(
            'too_many_attempts',
            'Too many failed login attempts. Please try again later.'
        );
    }
    
    return $user;
}
add_filter('authenticate', 'wpfarm_limit_login_attempts', 30, 3);

function wpfarm_login_failed($username) {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    $transient_key = 'wpfarm_login_attempts_' . md5($ip);
    $attempts = get_transient($transient_key) ?: 0;
    set_transient($transient_key, $attempts + 1, 15 * MINUTE_IN_SECONDS);
}
add_action('wp_login_failed', 'wpfarm_login_failed');

function wpfarm_login_success($user_login, $user) {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    $transient_key = 'wpfarm_login_attempts_' . md5($ip);
    delete_transient($transient_key);
}
add_action('wp_login', 'wpfarm_login_success', 10, 2);

/**
 * Disable pingbacks
 */
function wpfarm_disable_pingbacks(&$links) {
    foreach ($links as $l => $link) {
        if (0 === strpos($link, get_option('home'))) {
            unset($links[$l]);
        }
    }
}
add_action('pre_ping', 'wpfarm_disable_pingbacks');

/**
 * Remove unnecessary dashboard widgets
 */
function wpfarm_remove_dashboard_widgets() {
    remove_meta_box('dashboard_incoming_links', 'dashboard', 'normal');
    remove_meta_box('dashboard_plugins', 'dashboard', 'normal');
    remove_meta_box('dashboard_primary', 'dashboard', 'side');
    remove_meta_box('dashboard_secondary', 'dashboard', 'normal');
    remove_meta_box('dashboard_quick_press', 'dashboard', 'side');
    remove_meta_box('dashboard_recent_drafts', 'dashboard', 'side');
    remove_meta_box('dashboard_browser_nag', 'dashboard', 'normal');
    remove_action('welcome_panel', 'wp_welcome_panel');
}
add_action('wp_dashboard_setup', 'wpfarm_remove_dashboard_widgets');

/**
 * Hide WordPress update nag for non-admins
 */
function wpfarm_hide_update_nag() {
    if (!current_user_can('manage_options')) {
        remove_action('admin_notices', 'update_nag', 3);
    }
}
add_action('admin_head', 'wpfarm_hide_update_nag', 1);


