# Backup Strategy

## Overview

This backup strategy ensures data protection and disaster recovery for 500+ WordPress sites with:
- **RTO (Recovery Time Objective)**: < 1 hour
- **RPO (Recovery Point Objective)**: < 15 minutes
- **Retention**: 30 days daily, 12 months monthly

## Backup Components

### 1. Database Backups

#### Automated Hourly Incremental Backups
- Captures database changes every hour
- Stored in MinIO object storage
- Encrypted at rest

#### Daily Full Backups
- Complete database dump
- Compressed and encrypted
- Retained for 30 days

#### Monthly Archives
- Long-term retention
- Archived to cold storage
- Retained for 12 months

### 2. File Backups

#### WordPress Uploads
- Daily snapshots of `/wp-content/uploads`
- Incremental backups for efficiency
- Stored in MinIO

#### WordPress Core & Plugins
- Version-controlled via Git
- Daily snapshots for safety
- Stored in MinIO

### 3. Configuration Backups

#### Infrastructure as Code
- Docker Compose files
- Traefik configurations
- All configs in Git repository

#### Database Configuration
- MySQL/MariaDB configs
- Replication settings
- Backup scripts

## Implementation

### Backup Service Container

```yaml
backup-service:
  image: minio/mc:latest
  environment:
    MINIO_ENDPOINT: minio:9000
    MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY}
    MINIO_SECRET_KEY: ${MINIO_SECRET_KEY}
  volumes:
    - backup-scripts:/scripts
    - /var/nfs/wordpress:/data/wordpress:ro
  networks:
    - database
    - management
  deploy:
    replicas: 1
    placement:
      constraints:
        - node.role == manager
```

### Backup Scripts

#### Database Backup Script

```bash
#!/bin/bash
# backup-database.sh

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/backups/database"
MINIO_BUCKET="wordpress-backups/database"

# Full backup
mysqldump -h mariadb-master-1 \
  -u root -p${DB_ROOT_PASSWORD} \
  --all-databases \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  | gzip > ${BACKUP_DIR}/full-${DATE}.sql.gz

# Upload to MinIO
mc cp ${BACKUP_DIR}/full-${DATE}.sql.gz \
  minio/${MINIO_BUCKET}/daily/

# Cleanup old backups (keep 30 days)
find ${BACKUP_DIR} -name "*.sql.gz" -mtime +30 -delete
```

#### Files Backup Script

```bash
#!/bin/bash
# backup-files.sh

DATE=$(date +%Y%m%d)
BACKUP_DIR="/backups/files"
MINIO_BUCKET="wordpress-backups/files"

# Backup WordPress uploads
tar -czf ${BACKUP_DIR}/uploads-${DATE}.tar.gz \
  /data/wordpress/*/wp-content/uploads

# Upload to MinIO
mc cp ${BACKUP_DIR}/uploads-${DATE}.tar.gz \
  minio/${MINIO_BUCKET}/daily/

# Cleanup old backups
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +30 -delete
```

### Cron Schedule

```yaml
# Backup schedule
backup-cron:
  image: alpine:latest
  command: |
    sh -c "
    echo '0 */1 * * * /scripts/backup-database-incremental.sh' > /etc/crontabs/root
    echo '0 2 * * * /scripts/backup-database-full.sh' >> /etc/crontabs/root
    echo '0 3 * * * /scripts/backup-files.sh' >> /etc/crontabs/root
    crond -f
    "
  volumes:
    - backup-scripts:/scripts
```

## MinIO Configuration

### Setup MinIO

```yaml
minio:
  image: minio/minio:latest
  command: server /data --console-address ":9001"
  environment:
    MINIO_ROOT_USER: ${MINIO_ROOT_USER:-admin}
    MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-changeme}
  volumes:
    - minio-data:/data
  networks:
    - management
  deploy:
    replicas: 1
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.minio.rule=Host(`minio.yourdomain.com`)"
      - "traefik.http.routers.minio.entrypoints=websecure"
      - "traefik.http.routers.minio.tls.certresolver=letsencrypt"
      - "traefik.http.routers.minio.middlewares=admin-chain"
      - "traefik.http.services.minio.loadbalancer.server.port=9000"
```

### Create Buckets

```bash
mc alias set minio http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}
mc mb minio/wordpress-backups
mc mb minio/wordpress-backups/database
mc mb minio/wordpress-backups/files
mc mb minio/wordpress-backups/configs
```

## Recovery Procedures

### Database Recovery

#### Full Database Restore

```bash
# Download backup
mc cp minio/wordpress-backups/database/daily/full-20240101-020000.sql.gz \
  /tmp/restore.sql.gz

# Restore
gunzip < /tmp/restore.sql.gz | \
  mysql -h mariadb-master-1 -u root -p${DB_ROOT_PASSWORD}
```

#### Single Database Restore

```bash
# Extract specific database
gunzip < /tmp/restore.sql.gz | \
  sed -n '/^-- Current Database: `sitename`/,/^-- Current Database: `/p' | \
  mysql -h mariadb-master-1 -u root -p${DB_ROOT_PASSWORD} sitename
```

### Files Recovery

#### Full Site Restore

```bash
# Download backup
mc cp minio/wordpress-backups/files/daily/uploads-20240101.tar.gz \
  /tmp/uploads.tar.gz

# Extract
tar -xzf /tmp/uploads.tar.gz -C /var/nfs/wordpress/sitename/wp-content/
```

#### Single File Restore

```bash
# Extract specific file
tar -xzf /tmp/uploads.tar.gz \
  wordpress/sitename/wp-content/uploads/2024/01/image.jpg \
  -C /tmp/

# Copy to site
cp /tmp/wordpress/sitename/wp-content/uploads/2024/01/image.jpg \
  /var/nfs/wordpress/sitename/wp-content/uploads/2024/01/
```

## Backup Verification

### Automated Testing

```bash
#!/bin/bash
# verify-backup.sh

# Test database backup integrity
gunzip -t /backups/database/full-*.sql.gz

# Test file backup integrity
tar -tzf /backups/files/uploads-*.tar.gz > /dev/null

# Verify MinIO uploads
mc ls minio/wordpress-backups/database/daily/ | wc -l
```

### Weekly Restore Test

```bash
#!/bin/bash
# test-restore.sh

# Restore to test database
gunzip < /backups/database/full-$(date +%Y%m%d).sql.gz | \
  mysql -h mariadb-test -u root -p${DB_ROOT_PASSWORD} test_db

# Verify data integrity
mysql -h mariadb-test -u root -p${DB_ROOT_PASSWORD} test_db \
  -e "SELECT COUNT(*) FROM wp_posts;"
```

## Off-Site Backup

### Cloud Storage Sync

```bash
# Sync to external storage (e.g., AWS S3, Backblaze B2)
mc mirror minio/wordpress-backups \
  s3/external-backups/wordpress-farm \
  --remove
```

### Retention Policy

- **Daily backups**: 30 days
- **Weekly backups**: 12 weeks
- **Monthly backups**: 12 months
- **Yearly backups**: 7 years

## Monitoring

### Backup Status Alerts

Configure Prometheus alerts for:
- Backup failures
- Backup size anomalies
- Backup age warnings
- Storage capacity alerts

### Grafana Dashboard

Monitor:
- Backup success rate
- Backup sizes over time
- Storage usage
- Recovery test results

## Encryption

### At-Rest Encryption

- MinIO server-side encryption
- Encrypted volumes for sensitive data
- GPG encryption for long-term archives

### In-Transit Encryption

- TLS for all backup transfers
- Encrypted connections to MinIO
- Secure backup script execution

## Disaster Recovery Plan

### RTO/RPO Targets

- **RTO**: < 1 hour
- **RPO**: < 15 minutes

### Recovery Steps

1. **Assess Damage**: Identify affected systems
2. **Restore Database**: Latest backup + binlog replay
3. **Restore Files**: Latest file backup
4. **Verify Integrity**: Test site functionality
5. **Update DNS**: Point to restored site
6. **Monitor**: Watch for issues

### Communication Plan

- Notify stakeholders within 15 minutes
- Provide status updates every 30 minutes
- Document recovery process
- Post-mortem review within 48 hours


