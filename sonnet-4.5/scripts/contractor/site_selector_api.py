#!/usr/bin/env python3
"""
Site Selector API - Lists WordPress sites and provides access URLs
Integrates with Authentik SSO for authentication and authorization
"""

from flask import Flask, jsonify, request, session
from flask_cors import CORS
import pymysql
import os
import json
import logging
from functools import wraps
import jwt
import requests

app = Flask(__name__)
app.secret_key = os.getenv('SESSION_SECRET', 'change-me-in-production')
CORS(app)

# Configuration
MYSQL_HOST = os.getenv('MYSQL_HOST', 'proxysql')
MYSQL_PORT = int(os.getenv('MYSQL_PORT', 6033))
MYSQL_USER = 'root'
MYSQL_PASSWORD = os.getenv('MYSQL_ROOT_PASSWORD')
FILEBROWSER_URL = os.getenv('FILEBROWSER_URL', 'https://files.yourdomain.com')
ADMINER_URL = os.getenv('ADMINER_URL', 'https://db.yourdomain.com')
AUTHENTIK_URL = os.getenv('AUTHENTIK_URL', 'https://authentik.yourdomain.com')
WORDPRESS_DATA_PATH = '/wordpress-data'

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# DATABASE CONNECTION
# =============================================================================

def get_db_connection():
    """Get MySQL connection"""
    try:
        conn = pymysql.connect(
            host=MYSQL_HOST,
            port=MYSQL_PORT,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return None

# =============================================================================
# AUTHENTICATION
# =============================================================================

def verify_authentik_token(token):
    """Verify Authentik JWT token"""
    try:
        # Verify token with Authentik
        headers = {'Authorization': f'Bearer {token}'}
        response = requests.get(f'{AUTHENTIK_URL}/api/v3/core/user/me/', headers=headers)
        
        if response.status_code == 200:
            user_data = response.json()
            return {
                'username': user_data.get('username'),
                'email': user_data.get('email'),
                'groups': user_data.get('groups', []),
                'is_admin': 'admins' in [g.get('name') for g in user_data.get('groups', [])]
            }
    except Exception as e:
        logger.error(f"Token verification failed: {e}")
    
    return None

def require_auth(f):
    """Decorator to require authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Check for Authentik headers (set by Traefik forward auth)
        auth_username = request.headers.get('X-Authentik-Username')
        auth_email = request.headers.get('X-Authentik-Email')
        auth_groups = request.headers.get('X-Authentik-Groups', '').split(',')
        
        if not auth_username:
            return jsonify({'error': 'Unauthorized'}), 401
        
        # Store user info in request context
        request.user = {
            'username': auth_username,
            'email': auth_email,
            'groups': auth_groups,
            'is_admin': 'admins' in auth_groups
        }
        
        return f(*args, **kwargs)
    
    return decorated_function

# =============================================================================
# API ENDPOINTS
# =============================================================================

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'site-selector-api'}), 200

@app.route('/api/sites', methods=['GET'])
@require_auth
def list_sites():
    """List all WordPress sites user has access to"""
    try:
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database connection failed'}), 500
        
        # Get all WordPress databases
        with conn.cursor() as cursor:
            cursor.execute("SHOW DATABASES LIKE 'wp_%'")
            databases = [row['Database (wp_%)'] for row in cursor.fetchall()]
        
        # Get site info for each database
        sites = []
        for db_name in databases:
            try:
                with conn.cursor() as cursor:
                    cursor.execute(f"USE {db_name}")
                    cursor.execute("SELECT option_value FROM wp_options WHERE option_name IN ('siteurl', 'blogname') LIMIT 2")
                    options = cursor.fetchall()
                    
                    site_url = next((o['option_value'] for o in options if 'http' in o.get('option_value', '')), '')
                    site_name = next((o['option_value'] for o in options if 'http' not in o.get('option_value', '')), db_name)
                    
                    # Extract site ID from database name
                    site_id = db_name.replace('wp_site_', '')
                    
                    # Check user access (admins see all, contractors see assigned only)
                    if request.user['is_admin'] or f'contractor-site-{site_id}' in request.user['groups'] or 'contractors' in request.user['groups']:
                        sites.append({
                            'id': site_id,
                            'database': db_name,
                            'name': site_name,
                            'url': site_url,
                            'file_path': f'/wordpress-data/wp-site-{site_id}',
                            'access': {
                                'files': f"{FILEBROWSER_URL}/?path=/wp-site-{site_id}",
                                'database': f"{ADMINER_URL}/?server={MYSQL_HOST}&db={db_name}",
                                'sftp': f"sftp://contractor@{request.host}:2222/sites/wp-site-{site_id}"
                            }
                        })
            except Exception as e:
                logger.error(f"Error getting info for {db_name}: {e}")
                continue
        
        conn.close()
        
        return jsonify({
            'sites': sites,
            'count': len(sites),
            'user': request.user['username'],
            'is_admin': request.user['is_admin']
        }), 200
        
    except Exception as e:
        logger.error(f"Error listing sites: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/sites/<site_id>', methods=['GET'])
@require_auth
def get_site(site_id):
    """Get detailed information for a specific site"""
    try:
        db_name = f'wp_site_{site_id}'
        
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database connection failed'}), 500
        
        with conn.cursor() as cursor:
            # Verify database exists
            cursor.execute(f"SHOW DATABASES LIKE '{db_name}'")
            if not cursor.fetchone():
                return jsonify({'error': 'Site not found'}), 404
            
            # Check access
            if not request.user['is_admin'] and f'contractor-site-{site_id}' not in request.user['groups']:
                return jsonify({'error': 'Access denied'}), 403
            
            # Get site details
            cursor.execute(f"USE {db_name}")
            cursor.execute("""
                SELECT option_name, option_value 
                FROM wp_options 
                WHERE option_name IN ('siteurl', 'home', 'blogname', 'admin_email')
            """)
            options = {row['option_name']: row['option_value'] for row in cursor.fetchall()}
            
            # Get user count
            cursor.execute("SELECT COUNT(*) as count FROM wp_users")
            user_count = cursor.fetchone()['count']
            
            # Get post count
            cursor.execute("SELECT COUNT(*) as count FROM wp_posts WHERE post_status='publish' AND post_type='post'")
            post_count = cursor.fetchone()['count']
            
            # Get page count
            cursor.execute("SELECT COUNT(*) as count FROM wp_posts WHERE post_status='publish' AND post_type='page'")
            page_count = cursor.fetchone()['count']
            
            # Get database size
            cursor.execute(f"SELECT SUM(data_length + index_length) / 1024 / 1024 AS size_mb FROM information_schema.TABLES WHERE table_schema = '{db_name}'")
            db_size = cursor.fetchone()['size_mb'] or 0
        
        conn.close()
        
        # Get file size (if path exists)
        import subprocess
        file_size_mb = 0
        file_path = f'/wordpress-data/wp-site-{site_id}'
        try:
            result = subprocess.run(['du', '-sm', file_path], capture_output=True, text=True)
            if result.returncode == 0:
                file_size_mb = int(result.stdout.split()[0])
        except:
            pass
        
        return jsonify({
            'site': {
                'id': site_id,
                'database': db_name,
                'name': options.get('blogname', 'Unknown'),
                'url': options.get('siteurl', ''),
                'admin_email': options.get('admin_email', ''),
                'stats': {
                    'users': user_count,
                    'posts': post_count,
                    'pages': page_count,
                    'db_size_mb': round(db_size, 2),
                    'file_size_mb': file_size_mb
                },
                'access': {
                    'files': f"{FILEBROWSER_URL}/?path=/wp-site-{site_id}",
                    'database': f"{ADMINER_URL}/?server={MYSQL_HOST}&db={db_name}",
                    'sftp': f"sftp://contractor@{request.host}:2222/sites/wp-site-{site_id}",
                    'site_url': options.get('siteurl', '')
                }
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Error getting site {site_id}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/user/profile', methods=['GET'])
@require_auth
def user_profile():
    """Get current user profile and permissions"""
    return jsonify({
        'user': request.user,
        'permissions': {
            'can_edit_files': True,
            'can_edit_database': True,
            'can_manage_users': request.user['is_admin'],
            'can_view_all_sites': request.user['is_admin']
        }
    }), 200

@app.route('/api/audit/log', methods=['POST'])
@require_auth
def log_audit():
    """Log contractor action for audit trail"""
    try:
        data = request.json
        action = data.get('action')
        site_id = data.get('site_id')
        details = data.get('details', {})
        
        audit_entry = {
            'timestamp': __import__('datetime').datetime.now().isoformat(),
            'user': request.user['username'],
            'email': request.user['email'],
            'action': action,
            'site_id': site_id,
            'details': details,
            'ip': request.remote_addr
        }
        
        # Log to file
        with open('/var/log/audit/contractor-actions.log', 'a') as f:
            f.write(json.dumps(audit_entry) + '\n')
        
        # Log to application log
        logger.info(f"AUDIT: {request.user['username']} performed {action} on site {site_id}")
        
        return jsonify({'status': 'logged'}), 200
        
    except Exception as e:
        logger.error(f"Error logging audit: {e}")
        return jsonify({'error': str(e)}), 500

# =============================================================================
# RUN APPLICATION
# =============================================================================

if __name__ == '__main__':
    logger.info("Starting Site Selector API...")
    logger.info(f"Authentik URL: {AUTHENTIK_URL}")
    logger.info(f"FileBrowser URL: {FILEBROWSER_URL}")
    logger.info(f"Adminer URL: {ADMINER_URL}")
    
    app.run(host='0.0.0.0', port=8000, debug=False)

