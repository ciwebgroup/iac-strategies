# Varnish Configuration for WordPress
# HTTP Cache Layer

vcl 4.1;

# Backend definitions
backend default {
    .host = "wordpress";
    .port = "80";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;
    .between_bytes_timeout = 60s;
    .max_connections = 300;
}

# ACL for purge requests
acl purge {
    "localhost";
    "127.0.0.1";
    "10.0.0.0/8";
    "172.16.0.0/12";
    "192.168.0.0/16";
}

sub vcl_recv {
    # Allow purge from trusted IPs
    if (req.method == "PURGE") {
        if (!client.ip ~ purge) {
            return (synth(405, "Not allowed"));
        }
        return (purge);
    }

    # Pass POST, PUT, DELETE requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Pass WordPress admin and login
    if (req.url ~ "^/wp-admin" || req.url ~ "^/wp-login.php") {
        return (pass);
    }

    # Pass XML-RPC
    if (req.url ~ "^/xmlrpc.php") {
        return (pass);
    }

    # Pass WooCommerce cart and checkout
    if (req.url ~ "^/cart" || req.url ~ "^/checkout" || req.url ~ "^/my-account") {
        return (pass);
    }

    # Pass if cookies indicate logged-in user
    if (req.http.Cookie ~ "wordpress_logged_in|wp_|woocommerce_") {
        return (pass);
    }

    # Remove cookies for static assets
    if (req.url ~ "\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|webp)$") {
        unset req.http.Cookie;
    }

    # Normalize Accept-Encoding header
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|flv)$") {
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }

    return (hash);
}

sub vcl_backend_response {
    # Cache static assets for 1 year
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|webp)$") {
        set beresp.ttl = 31536000s;
        set beresp.http.Cache-Control = "public, max-age=31536000";
    }

    # Cache HTML pages for 1 hour
    if (beresp.http.Content-Type ~ "text/html") {
        set beresp.ttl = 3600s;
        set beresp.http.Cache-Control = "public, max-age=3600";
    }

    # Don't cache if backend sets no-cache
    if (beresp.http.Cache-Control ~ "no-cache|no-store|private") {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    }

    # Don't cache error responses
    if (beresp.status >= 400) {
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    }

    # Grace mode - serve stale content if backend is down
    set beresp.grace = 1h;
}

sub vcl_deliver {
    # Add cache status header
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Remove Varnish version header
    unset resp.http.Via;
    unset resp.http.X-Varnish;

    return (deliver);
}

sub vcl_purge {
    return (synth(200, "Purged"));
}

sub vcl_synth {
    if (resp.status == 405) {
        set resp.http.Allow = "GET, HEAD, POST, PUT, DELETE, PURGE";
    }
    return (deliver);
}


