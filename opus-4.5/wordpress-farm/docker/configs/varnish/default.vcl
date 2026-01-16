# =============================================================================
# VARNISH VCL CONFIGURATION - WordPress Farm
# =============================================================================
# Version: 4.1
# =============================================================================

vcl 4.1;

import std;
import directors;

# =============================================================================
# BACKEND DEFINITION
# =============================================================================
# WordPress backends are dynamically resolved via Docker Swarm DNS
backend default {
    .host = "wordpress";
    .port = "80";
    .first_byte_timeout = 300s;
    .connect_timeout = 10s;
    .between_bytes_timeout = 10s;
    
    .probe = {
        .url = "/wp-includes/images/blank.gif";
        .timeout = 5s;
        .interval = 30s;
        .window = 5;
        .threshold = 3;
    }
}

# =============================================================================
# ACL - Purge Access
# =============================================================================
acl purge {
    "localhost";
    "127.0.0.1";
    "10.0.0.0"/8;
    "172.16.0.0"/12;
    "192.168.0.0"/16;
}

# =============================================================================
# VCL_INIT - Backend Director
# =============================================================================
sub vcl_init {
    new wordpress_director = directors.round_robin();
    wordpress_director.add_backend(default);
}

# =============================================================================
# VCL_RECV - Request Processing
# =============================================================================
sub vcl_recv {
    # Set the backend
    set req.backend_hint = wordpress_director.backend();
    
    # Health check endpoint
    if (req.url == "/health" || req.url == "/varnish-health") {
        return (synth(200, "OK"));
    }
    
    # Normalize host header
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");
    
    # Handle PURGE requests
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not Allowed"));
        }
        return (purge);
    }
    
    # Handle BAN requests
    if (req.method == "BAN") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not Allowed"));
        }
        ban("req.http.host == " + req.http.host + " && req.url ~ " + req.url);
        return (synth(200, "Banned"));
    }
    
    # Only handle GET and HEAD
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
    
    # =======================================================================
    # WordPress-specific rules
    # =======================================================================
    
    # Never cache admin, login, or POST requests
    if (req.url ~ "^/wp-(admin|login|cron)" ||
        req.url ~ "preview=true" ||
        req.url ~ "xmlrpc.php" ||
        req.method == "POST") {
        return (pass);
    }
    
    # Never cache WooCommerce pages
    if (req.url ~ "^/(cart|checkout|my-account|wc-api|addons)" ||
        req.url ~ "\?add-to-cart=" ||
        req.url ~ "\?wc-ajax=") {
        return (pass);
    }
    
    # Don't cache logged-in users
    if (req.http.Cookie ~ "wordpress_logged_in_" ||
        req.http.Cookie ~ "comment_author_" ||
        req.http.Cookie ~ "wp-postpass_" ||
        req.http.Cookie ~ "wordpress_no_cache" ||
        req.http.Cookie ~ "woocommerce_cart_hash" ||
        req.http.Cookie ~ "woocommerce_items_in_cart" ||
        req.http.Cookie ~ "wp_woocommerce_session_") {
        return (pass);
    }
    
    # Remove tracking cookies and parameters
    set req.url = regsuball(req.url, "(utm_[a-z]+|gclid|fbclid|mc_[a-z]+|_ga)=[^&]+&?", "");
    set req.url = regsub(req.url, "[?&]$", "");
    
    # Remove Google Analytics cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_gid=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn=[^;]+(; )?", "");
    
    # Remove Facebook cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "_fbp=[^;]+(; )?", "");
    
    # Remove other tracking cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "intercom-[^=]+=[^;]+(; )?", "");
    
    # Remove empty cookies
    if (req.http.Cookie ~ "^\s*$") {
        unset req.http.Cookie;
    }
    
    # Static files - long cache
    if (req.url ~ "\.(jpg|jpeg|png|gif|ico|webp|svg|css|js|woff|woff2|ttf|eot|otf|mp4|webm|ogg|mp3|pdf|zip|gz)(\?.*)?$") {
        unset req.http.Cookie;
        return (hash);
    }
    
    return (hash);
}

# =============================================================================
# VCL_HASH - Cache Key
# =============================================================================
sub vcl_hash {
    hash_data(req.url);
    
    if (req.http.Host) {
        hash_data(req.http.Host);
    } else {
        hash_data(server.ip);
    }
    
    # Separate cache for HTTPS
    if (req.http.X-Forwarded-Proto) {
        hash_data(req.http.X-Forwarded-Proto);
    }
    
    # Mobile detection (optional - separate cache for mobile)
    # if (req.http.User-Agent ~ "(?i)mobile|android|iphone|ipad") {
    #     hash_data("mobile");
    # }
    
    return (lookup);
}

# =============================================================================
# VCL_BACKEND_RESPONSE - Backend Response Processing
# =============================================================================
sub vcl_backend_response {
    # Grace period - serve stale content while fetching new
    set beresp.grace = 6h;
    
    # Don't cache errors
    if (beresp.status >= 400) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Don't cache if backend says not to
    if (beresp.http.Cache-Control ~ "no-cache|no-store|private" ||
        beresp.http.Pragma ~ "no-cache") {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Don't cache responses with Set-Cookie
    if (beresp.http.Set-Cookie) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Static files - cache for 1 week
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|ico|webp|svg|css|js|woff|woff2|ttf|eot|otf)(\?.*)?$") {
        set beresp.ttl = 7d;
        unset beresp.http.Set-Cookie;
        return (deliver);
    }
    
    # HTML pages - cache for 10 minutes
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.ttl = 10m;
        return (deliver);
    }
    
    # Default TTL
    set beresp.ttl = 5m;
    
    return (deliver);
}

# =============================================================================
# VCL_DELIVER - Response Delivery
# =============================================================================
sub vcl_deliver {
    # Remove Varnish headers (security)
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    unset resp.http.Server;
    unset resp.http.X-Powered-By;
    
    # Add cache status header (useful for debugging)
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    return (deliver);
}

# =============================================================================
# VCL_SYNTH - Synthetic Responses
# =============================================================================
sub vcl_synth {
    if (resp.status == 200) {
        set resp.http.Content-Type = "text/plain; charset=utf-8";
        synthetic(resp.reason);
        return (deliver);
    }
    
    # Custom error pages
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";
    
    synthetic({"<!DOCTYPE html>
<html>
<head>
    <title>"} + resp.status + " " + resp.reason + {"</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; 
               display: flex; align-items: center; justify-content: center; 
               height: 100vh; margin: 0; background: #f5f5f5; }
        .error { text-align: center; }
        h1 { color: #333; font-size: 48px; margin: 0; }
        p { color: #666; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="error">
        <h1>"} + resp.status + {"</h1>
        <p>"} + resp.reason + {"</p>
    </div>
</body>
</html>"});
    
    return (deliver);
}

# =============================================================================
# VCL_PURGE - Purge Handler
# =============================================================================
sub vcl_purge {
    return (synth(200, "Purged"));
}


