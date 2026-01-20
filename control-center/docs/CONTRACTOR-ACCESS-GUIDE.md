# Contractor Access Guide - Secure WordPress Management

## 🎯 Overview

Secure, web-based access system for 3rd party contractors to manage WordPress sites without SSH access or technical knowledge.

**Features:**
- ✅ **Web-based file management** (FileBrowser with SFTP)
- ✅ **Web-based database management** (Adminer)
- ✅ **SSO via Authentik** (centralized authentication)
- ✅ **Site selector portal** (dropdown to choose sites)
- ✅ **Per-site access control** (contractors only see assigned sites)
- ✅ **Audit logging** (track all actions)
- ✅ **No SSH required** (web + SFTP only)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   CONTRACTOR                            │
│            (Web Browser or SFTP Client)                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  CLOUDFLARE                             │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│               TRAEFIK (with Authentik)                  │
│     Forward Auth → Authentik SSO Verification           │
└────────────┬────────────────┬────────────────┬──────────┘
             │                │                │
    ┌────────▼────┐   ┌───────▼──────┐  ┌────▼──────┐
    │ Contractor  │   │ FileBrowser  │  │  Adminer  │
    │   Portal    │   │(File Manager)│  │(DB Manager)│
    └─────────────┘   └──────┬───────┘  └────┬──────┘
         │                   │                │
         │                   │                │
         └───────────────────┼────────────────┘
                             │
                     ┌───────┴────────┐
                     │                │
                ┌────▼─────┐    ┌─────▼────┐
                │GlusterFS │    │ProxySQL/ │
                │(Files)   │    │Galera    │
                └──────────┘    └──────────┘
```

---

## 🚀 Deployment

### Prerequisites

1. **Authentik Instance** (your existing SSO)
   - URL: `https://authentik.yourdomain.com`
   - API Token generated
   - Forward auth provider configured

2. **Network Configuration**
   ```bash
   # Create contractor network
   docker network create --driver overlay --attachable contractor-net
   ```

3. **Directory Setup**
   ```bash
   mkdir -p /var/opt/wordpress-farm/{web/contractor-portal,configs/filebrowser,scripts/contractor}
   chmod 755 /var/opt/wordpress-farm/web/contractor-portal
   ```

### Deploy Contractor Access Stack

```bash
# 1. Configure environment variables in .env
AUTHENTIK_URL=https://authentik.yourdomain.com
AUTHENTIK_API_TOKEN=your_token_here
AUTHENTIK_COOKIE_SECRET=$(openssl rand -base64 32)
CODE_SERVER_PASSWORD=$(openssl rand -base64 16)
API_SESSION_SECRET=$(openssl rand -base64 32)

# 2. Deploy stack
docker stack deploy -c docker-compose-examples/contractor-access-stack.yml contractor

# 3. Verify services
docker service ls | grep contractor

# Expected services:
# contractor_site-selector-api (2 replicas)
# contractor_filebrowser (2 replicas)
# contractor_adminer (2 replicas)
# contractor_contractor-portal (2 replicas)
# contractor_authentik-proxy (2 replicas)
# contractor_sftp-server (2 replicas)
# contractor_audit-logger (1 replica)
```

---

## 🔐 Authentik SSO Configuration

### 1. Create Forward Auth Provider in Authentik

```
Navigate to: Admin → Applications → Providers → Create

Provider Type: Proxy Provider
Name: WordPress Farm Contractor Access
Authorization Flow: default-authentication-flow
Forward Auth (single application): Yes
External Host: https://portal.yourdomain.com

Save and note the Token
```

### 2. Create Application

```
Navigate to: Admin → Applications → Create

Name: WordPress Farm Contractor Portal
Slug: wordpress-farm-contractors
Provider: (select provider from step 1)
Launch URL: https://portal.yourdomain.com

Save
```

### 3. Create Groups

```
Navigate to: Admin → Directory → Groups → Create

Groups to create:
1. contractors (base group - access to portal)
2. admins (full access to all sites)
3. contractor-site-001 (access to specific site)
4. contractor-site-002
... (one group per site for granular access)
```

### 4. Create Users

```
Navigate to: Admin → Directory → Users → Create

Example:
Username: john.contractor
Email: john@contractorcompany.com
Groups: contractors, contractor-site-042, contractor-site-089

Result: John can only access sites 042 and 089
```

### 5. Configure Traefik Middleware

Already configured in contractor-access-stack.yml:
```yaml
traefik.http.middlewares.authentik.forwardauth.address=http://authentik-proxy:9000/outpost.goauthentik.io/auth/traefik
```

---

## 🌐 Access URLs

### For Contractors

| Service | URL | Purpose |
|---------|-----|---------|
| **Contractor Portal** | https://portal.yourdomain.com | Main landing page, site selector |
| **File Manager** | https://files.yourdomain.com | Web-based file management |
| **Database Manager** | https://db.yourdomain.com | Web-based SQL management |
| **SFTP Access** | sftp://yourdomain.com:2222 | Direct SFTP (FileZilla, etc.) |
| **Code Editor** | https://code.yourdomain.com | VSCode in browser (optional) |

### For Admins

| Service | URL | Purpose |
|---------|-----|---------|
| **User Management** | https://users.yourdomain.com | Manage contractor accounts |
| **Authentik Admin** | https://authentik.yourdomain.com | Full SSO management |
| **Audit Logs** | https://grafana.yourdomain.com | Contractor action logs |

---

## 👥 Contractor Workflow

### 1. Login via SSO

```
Contractor navigates to: https://portal.yourdomain.com
                          ↓
Redirected to: https://authentik.yourdomain.com/login
                          ↓
Enters credentials (or SSO provider like Google/GitHub)
                          ↓
Authenticated → Redirected back to portal
                          ↓
Sees only assigned sites
```

### 2. Select Site

```
Contractor Portal shows:
├── Site 042: example.com
│   ├── 1,234 posts
│   ├── 450MB files
│   ├── 89MB database
│   └── Actions:
│       ├── [Manage Files] → Opens FileBrowser
│       ├── [Manage Database] → Opens Adminer
│       └── [SFTP Info] → Shows connection details
└── Site 089: another-site.com
    └── (same actions)
```

### 3. Manage Files (FileBrowser)

```
Click "Manage Files"
                          ↓
Opens: https://files.yourdomain.com/?path=/wp-site-042
                          ↓
Web interface showing:
├── /uploads (media files)
│   ├── 2026/01/image.jpg
│   └── 2025/12/photo.png
├── /plugins (installed plugins)
└── /themes (installed themes)

Actions available:
├── Upload files (drag & drop)
├── Download files
├── Delete files
├── Rename/move files
├── Edit text files (CSS, JS, PHP)
└── Create folders
```

### 4. Manage Database (Adminer)

```
Click "Manage Database"
                          ↓
Opens: https://db.yourdomain.com/?server=proxysql&db=wp_site_042
                          ↓
Auto-connected to database:
├── Tables: wp_posts, wp_users, wp_options, etc.
├── Can run SELECT queries
├── Can UPDATE/INSERT (if permissions allow)
├── Can export database
└── Can import SQL files

Features:
├── Visual query builder
├── Table editor
├── SQL command interface
├── Export to CSV/SQL
└── Dark mode UI
```

### 5. SFTP Access (Alternative)

```
For command-line users or tools like FileZilla:

Host: yourdomain.com
Port: 2222
Protocol: SFTP
Username: contractor
Password: (their Authentik password)
Path: /sites/wp-site-042

Tools supported:
├── FileZilla (Windows/Mac/Linux)
├── Cyberduck (Mac)
├── WinSCP (Windows)
└── Command line: sftp -P 2222 contractor@yourdomain.com
```

---

## 🔒 Security & Access Control

### Per-Site Access Control

**Authentik Groups:**
```
contractors (base group)
└── Grants: Access to portal

admins (admin group)
└── Grants: Access to ALL sites

contractor-site-{ID} (per-site group)
└── Grants: Access to specific site only

Example:
User: john@contractor.com
Groups: contractors, contractor-site-042, contractor-site-089
Result: Can only access sites 042 and 089
```

### File Permissions

**FileBrowser enforces:**
- ✅ Contractors can only see/edit their assigned sites
- ✅ Cannot access other sites' directories
- ✅ Cannot access system files
- ✅ Cannot escalate to root
- ❌ No SSH access
- ❌ No Docker access
- ❌ No infrastructure access

**File system isolation:**
```
/mnt/glusterfs/
├── wp-site-001/ (only contractor-site-001 group)
├── wp-site-042/ (only contractor-site-042 group)
└── wp-site-089/ (only contractor-site-089 group)
```

### Database Permissions

**Adminer restrictions:**
- ✅ Can only connect to assigned databases
- ✅ Read/write on WordPress tables
- ❌ Cannot CREATE/DROP databases
- ❌ Cannot access other site databases
- ❌ Cannot access mysql system tables
- ❌ No GRANT privileges

**ProxySQL enforces:**
```
Per-database users (future enhancement):
CREATE USER 'contractor_site_042'@'%' IDENTIFIED BY 'secure_pass';
GRANT SELECT, INSERT, UPDATE, DELETE ON wp_site_042.* TO 'contractor_site_042'@'%';

Contractors use limited-privilege accounts, not root
```

### Network Isolation

```
contractor-net (separate network)
├── Isolated from production wordpress-net
├── Cannot access Swarm management
├── Cannot access other infrastructure
├── Firewall rules restrict access
└── Rate limiting enabled (20 req/sec per IP)
```

---

## 📊 Audit Logging

### What Gets Logged

**All contractor actions tracked:**
- ✅ Login/logout events
- ✅ Site access (which site, when)
- ✅ File operations (upload, download, delete, edit)
- ✅ Database queries (SELECT, UPDATE, etc.)
- ✅ SFTP connections and transfers
- ✅ IP addresses
- ✅ Timestamps

**Log format:**
```json
{
  "timestamp": "2026-01-15T14:32:15Z",
  "user": "john.contractor",
  "email": "john@contractorcompany.com",
  "action": "open_files",
  "site_id": "042",
  "site_name": "example.com",
  "ip": "203.0.113.45",
  "details": {
    "file": "/uploads/2026/01/image.jpg",
    "operation": "download"
  }
}
```

### Viewing Audit Logs

**Grafana Dashboard:**
```
Navigate to: Grafana → Explore → Loki

Query:
{job="audit-logger"} |= "contractor"

Shows:
- All contractor actions
- Filterable by user, site, action
- Time-series view
```

**Slack Notifications:**
```
Channel: #contractor-audit

Receives:
- High-risk actions (database structure changes)
- Bulk operations (>100 files)
- Off-hours access (if enabled)
```

---

## 👥 User Management

### Adding a New Contractor

```bash
# 1. Create user in Authentik
Navigate to: Authentik → Directory → Users → Create
Username: jane.contractor
Email: jane@agencyname.com
Groups: contractors, contractor-site-100, contractor-site-101

# 2. Contractor receives invitation email

# 3. Sets password on first login

# 4. Can immediately access assigned sites via portal
```

### Assigning Sites to Contractor

```bash
# Option A: Via Authentik UI
Navigate to: Users → john.contractor → Edit
Add Groups: contractor-site-150

# Option B: Via Authentik API
curl -X POST https://authentik.yourdomain.com/api/v3/core/users/{user_id}/add_group/ \
  -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  -d '{"group": "contractor-site-150"}'

# Contractor can now access site 150 immediately
```

### Revoking Access

```bash
# Remove from group
Navigate to: Users → john.contractor → Edit
Remove Groups: contractor-site-042

# Or disable user entirely
Navigate to: Users → john.contractor → Edit
Set: is_active = false

# Access revoked immediately (next authentication check)
```

---

## 🛠️ Contractor Tools

### Tool 1: FileBrowser (File Management)

**Features:**
- 📁 Browse WordPress directories
- ⬆️ Upload files (drag & drop)
- ⬇️ Download files/folders
- ✏️ Edit files inline (syntax highlighting)
- 🗑️ Delete files/folders
- 📋 Copy/move files
- 🔍 Search files
- 📦 Bulk operations
- 🔐 SFTP built-in

**Access:** https://files.yourdomain.com

**File structure:**
```
/wp-site-042/
├── uploads/
│   ├── 2026/
│   │   └── 01/
│   │       └── image.jpg
│   └── 2025/
├── plugins/
│   ├── akismet/
│   └── contact-form-7/
└── themes/
    ├── twentytwentyfour/
    └── custom-theme/
```

### Tool 2: Adminer (Database Management)

**Features:**
- 🗄️ Browse database tables
- 📊 View table data
- ✏️ Edit records
- ➕ Insert records
- 🗑️ Delete records
- 🔍 Search/filter
- 📤 Export database (SQL/CSV)
- 📥 Import SQL files
- 🔧 Run custom SQL queries
- 📈 View table structure

**Access:** https://db.yourdomain.com

**Common tasks:**
```sql
-- View all posts
SELECT * FROM wp_posts WHERE post_status='publish' LIMIT 100;

-- Update site URL (after domain change)
UPDATE wp_options SET option_value='https://newdomain.com' 
WHERE option_name IN ('siteurl', 'home');

-- Find user by email
SELECT * FROM wp_users WHERE user_email='user@example.com';

-- Export specific posts
SELECT * FROM wp_posts WHERE post_author=5 INTO OUTFILE '/tmp/export.csv';
```

### Tool 3: Contractor Portal (Site Selector)

**Features:**
- 🌐 Lists all assigned sites
- 🔍 Search/filter sites
- 📊 Site statistics (posts, pages, size)
- 🔗 Direct links to file/database managers
- 📋 SFTP connection info
- 📈 Site health indicators

**Access:** https://portal.yourdomain.com

**Interface shows:**
```
┌────────────────────────────────────────┐
│ WordPress Farm - Contractor Portal     │
│ User: john.contractor (Contractor)     │
├────────────────────────────────────────┤
│ Search: [____________________] 🔍      │
├────────────────────────────────────────┤
│                                        │
│ ┌─────────────────────────────────┐   │
│ │ Site 042: example.com           │   │
│ │ 1,234 posts │ 450MB files       │   │
│ │ [Manage Files] [Manage DB] [SFTP]│   │
│ └─────────────────────────────────┘   │
│                                        │
│ ┌─────────────────────────────────┐   │
│ │ Site 089: another-site.com      │   │
│ │ 567 posts │ 230MB files         │   │
│ │ [Manage Files] [Manage DB] [SFTP]│   │
│ └─────────────────────────────────┘   │
└────────────────────────────────────────┘
```

### Tool 4: SFTP Access (For Power Users)

**Connection details:**
```
Host: yourdomain.com
Port: 2222
Protocol: SFTP
Username: contractor
Password: (Authentik password)
```

**Using FileZilla:**
```
1. Open FileZilla
2. File → Site Manager → New Site
3. Protocol: SFTP
4. Host: yourdomain.com
5. Port: 2222
6. Logon Type: Normal
7. User: contractor
8. Password: (your Authentik password)
9. Connect
```

**Using command line:**
```bash
# Connect
sftp -P 2222 contractor@yourdomain.com

# Navigate to site
cd /sites/wp-site-042

# List files
ls -la

# Upload file
put local-image.jpg uploads/2026/01/

# Download file
get uploads/2026/01/image.jpg

# Exit
exit
```

---

## 📋 Contractor Instructions (Share with Contractors)

### Getting Started

1. **Receive invitation email** from admin
2. **Click link** to set password in Authentik
3. **Navigate to** https://portal.yourdomain.com
4. **Login** with credentials
5. **See assigned sites** in portal
6. **Click site** to manage

### Managing Files (Web)

**Upload Image:**
1. Click "Manage Files" for your site
2. Navigate to: `uploads/2026/01/`
3. Drag image file into browser
4. Done! Image uploaded

**Edit CSS:**
1. Click "Manage Files"
2. Navigate to: `themes/your-theme/style.css`
3. Click file → Edit
4. Make changes
5. Save
6. Refresh website to see changes

**Download Backup:**
1. Click "Manage Files"
2. Select folder (uploads, plugins, themes)
3. Click "Download" button
4. Saves as ZIP file

### Managing Database (Web)

**View Posts:**
1. Click "Manage Database"
2. Click table: `wp_posts`
3. Browse records
4. Click row to edit

**Search Users:**
1. Click "Manage Database"
2. Click table: `wp_users`
3. Use search box
4. Filter by email or username

**Run Custom Query:**
1. Click "Manage Database"
2. Click "SQL command" tab
3. Enter query:
   ```sql
   SELECT * FROM wp_posts 
   WHERE post_status='publish' 
   ORDER BY post_date DESC 
   LIMIT 20;
   ```
4. Click "Execute"

**Export Database:**
1. Click "Manage Database"
2. Click "Export" tab
3. Select "SQL" format
4. Click "Export"
5. Download SQL file

### Using SFTP (FileZilla)

**First Time Setup:**
1. Download FileZilla: https://filezilla-project.org/
2. Install and open
3. File → Site Manager → New Site
4. Enter connection details (provided by admin)
5. Save site
6. Connect

**Upload Files:**
1. Connect to SFTP
2. Navigate to: `/sites/wp-site-042/uploads/`
3. Drag files from left panel (local) to right panel (remote)
4. Done!

**Download Backup:**
1. Connect to SFTP
2. Right-click folder → Download
3. Wait for transfer
4. Files saved to local computer

---

## 🚨 Security Best Practices

### For Admins

✅ **DO:**
- Use Authentik groups for access control
- Assign minimum necessary site access
- Review audit logs weekly
- Rotate contractor passwords quarterly
- Enable MFA in Authentik
- Monitor for suspicious activity
- Keep contractor list up-to-date
- Remove access immediately when contract ends

❌ **DON'T:**
- Give contractors SSH access
- Share root database passwords
- Grant access to all sites by default
- Allow access to infrastructure services
- Ignore audit log alerts
- Skip MFA for contractors

### For Contractors

✅ **DO:**
- Use provided web interfaces
- Request access if you need additional sites
- Report security issues immediately
- Use strong passwords
- Log out when finished

❌ **DON'T:**
- Share login credentials
- Access sites you're not assigned to
- Attempt to bypass security
- Install backdoors or malicious code
- Export sensitive data without permission

---

## 📊 Monitoring & Alerts

### Contractor Activity Metrics

**Tracked in Prometheus:**
```
contractor_logins_total{user="john"}
contractor_file_operations_total{user="john",operation="upload"}
contractor_db_queries_total{user="john",site="042"}
contractor_failed_auth_total{user="john"}
```

**Grafana Dashboard:**
```
Contractor Activity Dashboard:
├── Active contractors (last 24h)
├── Most accessed sites
├── File operations by user
├── Database queries by user
├── Failed login attempts
└── Off-hours activity
```

### Security Alerts

```yaml
# Alert on suspicious activity
- alert: ContractorBulkDelete
  expr: rate(contractor_file_operations_total{operation="delete"}[5m]) > 10
  labels:
    severity: warning
  annotations:
    summary: "Contractor {{ $labels.user }} deleting many files"

- alert: ContractorFailedAuth
  expr: contractor_failed_auth_total > 5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Multiple failed login attempts for {{ $labels.user }}"

- alert: ContractorDatabaseStructureChange
  expr: contractor_db_queries_total{query_type="ALTER|DROP|CREATE"} > 0
  labels:
    severity: critical
  annotations:
    summary: "Contractor {{ $labels.user }} modified database structure"
```

---

## 💰 Cost Impact

### Additional Services

| Service | Replicas | Resources | Monthly Cost |
|---------|----------|-----------|--------------|
| **Site Selector API** | 2 | 0.5 CPU, 512MB | $0 (on existing ops nodes) |
| **FileBrowser** | 2 | 1 CPU, 512MB | $0 (on existing storage nodes) |
| **Adminer** | 2 | 0.5 CPU, 256MB | $0 (on existing ops nodes) |
| **Contractor Portal** | 2 | 0.2 CPU, 128MB | $0 (on existing ops nodes) |
| **Authentik Proxy** | 2 | 0.3 CPU, 256MB | $0 (on existing ops nodes) |
| **SFTP Server** | 2 | 0.5 CPU, 256MB | $0 (on existing storage nodes) |
| **Audit Logger** | 1 | 0.2 CPU, 256MB | $0 (on existing ops nodes) |

**Total Additional Cost:** $0/month ✅

**Why no cost increase?**
- Services run on existing nodes (ops and storage)
- Low resource requirements (total: ~3 CPU, 2GB RAM)
- Ops and storage nodes have spare capacity
- No new infrastructure needed!

---

## 🎓 Training Materials

### Contractor Onboarding

**Week 1: Getting Started (30 minutes)**
1. Login to portal
2. Explore assigned sites
3. Upload test file
4. View database tables
5. Connect via SFTP (if needed)

**Week 2: Common Tasks (1 hour)**
6. Upload images via FileBrowser
7. Edit CSS/JS files
8. Run database queries
9. Export/import database
10. Bulk file operations

**Week 3: Advanced (1 hour)**
11. SFTP workflow
12. Database optimization queries
13. Finding and replacing content
14. Troubleshooting common issues

### Video Tutorials (Create These)

- [ ] How to login to contractor portal
- [ ] Uploading files via web interface
- [ ] Editing theme files
- [ ] Running database queries
- [ ] Using SFTP with FileZilla
- [ ] Exporting/importing databases

---

## 🔧 Troubleshooting

### Contractor Can't Login

**Check:**
1. User exists in Authentik
2. User in "contractors" group
3. User is_active = true
4. Authentik forward auth configured
5. Check Authentik logs

**Solution:**
```bash
# Verify user in Authentik
curl https://authentik.yourdomain.com/api/v3/core/users/ \
  -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  | jq '.results[] | select(.username=="john.contractor")'
```

### Contractor Can't See Sites

**Check:**
1. User in correct site-specific groups
2. API can connect to database
3. Sites exist in database

**Solution:**
```bash
# Check user groups
curl https://authentik.yourdomain.com/api/v3/core/users/{id}/ \
  -H "Authorization: Bearer $AUTHENTIK_TOKEN" \
  | jq '.groups'

# Should show: ["contractors", "contractor-site-042", ...]
```

### File Upload Failing

**Check:**
1. GlusterFS mounted correctly
2. Permissions on directories
3. Disk space available
4. File size limits

**Solution:**
```bash
# Check GlusterFS mount
df -h | grep glusterfs

# Check permissions
ls -la /mnt/glusterfs/wp-site-042

# Fix permissions if needed
chown -R www-data:www-data /mnt/glusterfs/wp-site-042
chmod -R 755 /mnt/glusterfs/wp-site-042
```

### Database Connection Failing

**Check:**
1. ProxySQL service running
2. Galera cluster healthy
3. Database credentials correct

**Solution:**
```bash
# Test ProxySQL
docker exec proxysql mysql -h127.0.0.1 -P6032 -pradmin -e "SELECT * FROM mysql_servers;"

# Test database connection
docker exec adminer php -r "echo mysqli_connect('proxysql', 'root', getenv('MYSQL_ROOT_PASSWORD')) ? 'OK' : 'FAIL';"
```

---

## 📚 Integration with Existing Infrastructure

### How It Fits

```
Existing Infrastructure:
├── 3 Manager nodes (Traefik, Swarm)
├── 3 Cache nodes (Varnish, Redis)
├── 20 Worker nodes (WordPress)
├── 3 Database nodes (Galera, ProxySQL)
├── 2 Storage nodes (GlusterFS) ← FileBrowser, SFTP here
└── 2 Monitor nodes (LGTM, Portainer) ← API, Adminer, Portal here

NEW contractor-net network:
├── Isolated from wordpress-net (security)
├── Can access database-net (for Adminer)
├── Can access storage-net (for FileBrowser)
└── Cannot access swarm management
```

### No New Nodes Required! ✅

All contractor services run on **existing infrastructure** with spare capacity:
- FileBrowser → Storage nodes (already access GlusterFS)
- Adminer → Ops nodes (need database access)
- Portal → Ops nodes (lightweight)
- API → Ops nodes (lightweight)

**Resource usage:** ~3 CPU, 2GB RAM total (minimal impact)

---

## ✅ Summary

### What Contractors Get

✅ **Web Portal** - https://portal.yourdomain.com
- See all assigned sites
- One-click access to file/database managers
- Statistics and info

✅ **File Manager** - https://files.yourdomain.com
- Web-based file management
- Upload/download/edit files
- No FTP client needed

✅ **Database Manager** - https://db.yourdomain.com
- Web-based SQL management
- Visual table editor
- Query interface

✅ **SFTP Access** - sftp://yourdomain.com:2222
- For power users
- FileZilla, Cyberduck, etc.
- Alternative to web interface

### What Admins Get

✅ **SSO Integration** - Authentik
- Centralized authentication
- Group-based access control
- Per-site permissions

✅ **Audit Logging**
- All actions tracked
- Grafana dashboard
- Slack notifications

✅ **Security**
- No SSH access for contractors
- Network isolation
- Rate limiting
- Per-site access control

### Cost

**Additional monthly cost:** $0 ✅
- Runs on existing infrastructure
- No new nodes needed
- Minimal resource impact

**Total infrastructure cost:** $3,733/month (unchanged)

---

## 🎯 Next Steps

1. **Configure Authentik** (if not already)
2. **Deploy contractor access stack**
3. **Create contractor users** in Authentik
4. **Assign site-specific groups**
5. **Share portal URL** with contractors
6. **Provide training** (share this guide)

---

**Status:** ✅ Complete  
**Cost Impact:** $0 (uses existing infrastructure)  
**Security:** Enterprise-grade (SSO + audit + isolation)  
**Contractor Experience:** Excellent (web-based, no SSH)

**Files Created:**
1. `docker-compose-examples/contractor-access-stack.yml` - Services
2. `scripts/contractor/site_selector_api.py` - API backend
3. `web/contractor-portal/index.html` - Web frontend
4. `CONTRACTOR-ACCESS-GUIDE.md` - This documentation

