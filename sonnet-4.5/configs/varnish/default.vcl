vcl 4.1;

# =============================================================================
# VARNISH CONFIGURATION - WordPress Optimized
# =============================================================================
# Version: 7.4
# Optimized for: Multi-site WordPress farm
# Backend: WordPress containers via Docker Swarm service discovery
# =============================================================================

import std;
import directors;

# =============================================================================
# BACKEND CONFIGURATION
# =============================================================================

backend wordpress {
    .host = "wordpress";  # Docker Swarm service name
    .port = "80";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 10s;
    .max_connections = 300;
    
    .probe = {
        .url = "/health";
        .timeout = 5s;
        .interval = 10s;
        .window = 5;
        .threshold = 3;
    }
}

# =============================================================================
# ACCESS CONTROL
# =============================================================================

acl purge {
    "localhost";
    "127.0.0.1";
    "172.20.0.0"/16;  # traefik-public network
    "172.24.0.0"/16;  # cache-net network
}

# =============================================================================
# VCL_RECV - Request Processing
# =============================================================================

sub vcl_recv {
    # Set backend
    set req.backend_hint = wordpress;
    
    # Add Varnish header for debugging
    set req.http.X-Varnish-Cache = "true";
    
    # Normalize host header
    set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");
    
    # Handle PURGE requests
    if (req.method == "PURGE") {
        if (client.ip ~ purge) {
            return (purge);
        }
        return (synth(405, "Not allowed"));
    }
    
    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
    
    # Don't cache WordPress admin
    if (req.url ~ "wp-(admin|login|cron)" || req.url ~ "xmlrpc.php") {
        return (pass);
    }
    
    # Don't cache if logged in
    if (req.http.Cookie ~ "wordpress_logged_in|comment_author|wp-postpass") {
        return (pass);
    }
    
    # Don't cache WooCommerce pages
    if (req.http.Cookie ~ "woocommerce_items_in_cart|woocommerce_cart_hash") {
        return (pass);
    }
    
    # Don't cache if nocache parameter present
    if (req.url ~ "(\?|&)(nocache|no-cache)=") {
        return (pass);
    }
    
    # Remove unnecessary cookies for cacheable requests
    if (req.url !~ "wp-(admin|login|cron)" && req.url !~ "xmlrpc.php") {
        unset req.http.Cookie;
    }
    
    # Normalize Accept-Encoding
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|jpeg|png|gif|ico|webp|svg|css|js|woff|woff2|ttf|eot)(\?.*)?$") {
            # Don't compress already compressed files
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }
    
    # Lookup in cache
    return (hash);
}

# =============================================================================
# VCL_HASH - Cache Key Generation
# =============================================================================

sub vcl_hash {
    hash_data(req.url);
    
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    
    # Include device type in cache key (mobile vs desktop)
    if (req.http.X-UA-Device) {
        hash_data(req.http.X-UA-Device);
    }
    
    # Include HTTPS status in cache key
    if (req.http.X-Forwarded-Proto) {
        hash_data(req.http.X-Forwarded-Proto);
    }
    
    return (lookup);
}

# =============================================================================
# VCL_BACKEND_RESPONSE - Backend Response Processing
# =============================================================================

sub vcl_backend_response {
    # Set cache TTL based on status code
    if (beresp.status == 200 || beresp.status == 301 || beresp.status == 302) {
        # Cache successful responses
        set beresp.ttl = 1h;
        set beresp.grace = 6h;
    } elsif (beresp.status == 404) {
        # Cache 404s for shorter time
        set beresp.ttl = 5m;
    } elsif (beresp.status >= 500) {
        # Don't cache errors
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Don't cache if Set-Cookie present
    if (beresp.http.Set-Cookie) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Don't cache if Cache-Control says no-cache
    if (beresp.http.Cache-Control ~ "(private|no-cache|no-store)") {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
        return (deliver);
    }
    
    # Cache static files longer
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|ico|webp|svg|css|js|woff|woff2|ttf|eot|pdf)(\?.*)?$") {
        set beresp.ttl = 7d;
        unset beresp.http.Set-Cookie;
    }
    
    # Remove unnecessary headers
    unset beresp.http.X-Powered-By;
    unset beresp.http.X-Pingback;
    unset beresp.http.Link;
    
    # Enable ESI (Edge Side Includes) for WordPress
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.do_esi = true;
    }
    
    # Gzip compression
    if (beresp.http.content-type ~ "text|application/json|application/javascript|application/xml") {
        set beresp.do_gzip = true;
    }
    
    return (deliver);
}

# =============================================================================
# VCL_DELIVER - Client Response
# =============================================================================

sub vcl_deliver {
    # Add cache status headers (useful for debugging)
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
    
    # Add Varnish server identifier
    set resp.http.X-Served-By = server.hostname;
    
    # Remove backend server headers (security)
    unset resp.http.Server;
    unset resp.http.X-Powered-By;
    unset resp.http.X-Varnish;
    
    # Add cache age
    if (obj.age > 0s) {
        set resp.http.X-Cache-Age = obj.age;
    }
    
    return (deliver);
}

# =============================================================================
# VCL_SYNTH - Synthetic Responses
# =============================================================================

sub vcl_synth {
    # Health check endpoint
    if (req.url ~ "^/health$") {
        set resp.status = 200;
        set resp.http.Content-Type = "text/plain";
        synthetic("OK");
        return (deliver);
    }
    
    # Custom error pages
    if (resp.status == 503) {
        set resp.http.Content-Type = "text/html; charset=utf-8";
        set resp.http.Retry-After = "5";
        synthetic({"
            <!DOCTYPE html>
            <html>
            <head>
                <title>Service Temporarily Unavailable</title>
                <style>
                    body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
                    h1 { color: #d32f2f; }
                </style>
            </head>
            <body>
                <h1>Service Temporarily Unavailable</h1>
                <p>We're experiencing technical difficulties. Please try again in a few moments.</p>
                <p><small>Error "} + resp.status + {" - Varnish Cache</small></p>
            </body>
            </html>
        "});
        return (deliver);
    }
}

# =============================================================================
# VCL_HIT - Cache Hit
# =============================================================================

sub vcl_hit {
    # Serve stale content if backend is down (grace mode)
    if (obj.ttl >= 0s) {
        return (deliver);
    }
    
    # Serve stale content during grace period
    if (obj.ttl + obj.grace > 0s) {
        return (deliver);
    }
    
    return (restart);
}

# =============================================================================
# VCL_MISS - Cache Miss
# =============================================================================

sub vcl_miss {
    return (fetch);
}

# =============================================================================
# VCL_BACKEND_ERROR - Backend Failure
# =============================================================================

sub vcl_backend_error {
    # Serve stale content if available
    if (beresp.ttl + beresp.grace > 0s) {
        return (deliver);
    }
    
    # Otherwise show error page
    set beresp.http.Content-Type = "text/html; charset=utf-8";
    synthetic({"
        <!DOCTYPE html>
        <html>
        <head>
            <title>Backend Error</title>
            <style>
                body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
                h1 { color: #d32f2f; }
            </style>
        </head>
        <body>
            <h1>Backend Error</h1>
            <p>The application server is temporarily unavailable.</p>
            <p>Our team has been notified and is working on the issue.</p>
        </body>
        </html>
    "});
    
    return (deliver);
}

# =============================================================================
# CONFIGURATION NOTES
# =============================================================================
#
# Cache Behavior:
# - HTML pages: 1 hour TTL, 6 hour grace
# - Static assets: 7 days TTL
# - 404 errors: 5 minutes TTL
# - 5xx errors: Not cached
#
# Bypass Cache:
# - POST, PUT, DELETE requests
# - Logged-in users (WordPress cookies)
# - Admin panel (wp-admin, wp-login)
# - WooCommerce cart pages
# - URLs with nocache parameter
#
# Cache Key Includes:
# - URL (req.url)
# - Host header (req.http.host)
# - Device type (mobile vs desktop)
# - Protocol (HTTP vs HTTPS)
#
# Health Check:
# curl -H "Host: any.domain" http://varnish:6081/health
# Response: 200 OK
#
# Purge Cache:
# curl -X PURGE -H "Host: example.com" http://varnish:6081/path/to/page
#
# =============================================================================

