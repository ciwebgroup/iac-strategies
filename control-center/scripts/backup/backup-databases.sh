#!/usr/bin/env bash
#
# =============================================================================
# DATABASE BACKUP SCRIPT - Per-Database SQL Dumps
# =============================================================================
# Creates individual SQL dumps for each WordPress database
# Uploads to DigitalOcean Spaces with date-based naming
# Runs daily at 02:00 (configured via cron or environment)
# =============================================================================

set -euo pipefail

# Configuration from environment
MYSQL_HOST="${MYSQL_HOST:-proxysql}"
MYSQL_PORT="${MYSQL_PORT:-6033}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
BACKUP_DIR="/backups/$(date +%Y-%m-%d)"
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
S3_PREFIX="${S3_PREFIX:-database-backups}"
COMPRESSION="${COMPRESSION:-gzip}"
ENCRYPTION_ENABLED="${ENCRYPTION_ENABLED:-true}"
NOTIFICATION_URL="${NOTIFICATION_URL:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

send_notification() {
    local message="$1"
    local status="${2:-info}"
    
    if [[ -n "$NOTIFICATION_URL" ]]; then
        local color="good"
        [[ "$status" == "error" ]] && color="danger"
        [[ "$status" == "warning" ]] && color="warning"
        
        curl -X POST "$NOTIFICATION_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"📦 Database Backup: $message\",\"color\":\"$color\"}" \
            2>/dev/null || true
    fi
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Get list of all WordPress databases
log "Fetching list of WordPress databases..."
DATABASES=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -uroot -p"$MYSQL_ROOT_PASSWORD" \
    -e "SHOW DATABASES LIKE 'wp_%';" -sN)

if [[ -z "$DATABASES" ]]; then
    log_error "No WordPress databases found!"
    send_notification "No databases found to backup" "error"
    exit 1
fi

# Count databases
DB_COUNT=$(echo "$DATABASES" | wc -l)
log "Found $DB_COUNT WordPress databases to backup"

# Backup statistics
SUCCESSFUL=0
FAILED=0
TOTAL_SIZE=0
START_TIME=$(date +%s)

# Backup each database
for DB in $DATABASES; do
    log "Backing up database: $DB..."
    
    BACKUP_FILE="${BACKUP_DIR}/${DB}_$(date +%Y%m%d_%H%M%S).sql"
    
    # Create SQL dump
    if mysqldump \
        -h "$MYSQL_HOST" \
        -P "$MYSQL_PORT" \
        -uroot \
        -p"$MYSQL_ROOT_PASSWORD" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --default-character-set=utf8mb4 \
        "$DB" > "$BACKUP_FILE" 2>/dev/null; then
        
        log "✓ SQL dump created: $BACKUP_FILE"
        
        # Compress
        if [[ "$COMPRESSION" == "gzip" ]]; then
            gzip "$BACKUP_FILE"
            BACKUP_FILE="${BACKUP_FILE}.gz"
            log "✓ Compressed: $BACKUP_FILE"
        fi
        
        # Encrypt (if enabled)
        if [[ "$ENCRYPTION_ENABLED" == "true" && -n "${GPG_RECIPIENT:-}" ]]; then
            gpg --encrypt --recipient "$GPG_RECIPIENT" "$BACKUP_FILE"
            rm "$BACKUP_FILE"
            BACKUP_FILE="${BACKUP_FILE}.gpg"
            log "✓ Encrypted: $BACKUP_FILE"
        fi
        
        # Get file size
        FILE_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE")
        TOTAL_SIZE=$((TOTAL_SIZE + FILE_SIZE))
        SIZE_MB=$((FILE_SIZE / 1024 / 1024))
        
        # Upload to S3
        DATE_PATH=$(date +%Y/%m/%d)
        WEEKDAY=$(date +%A | tr '[:upper:]' '[:lower:]')
        DAY_OF_MONTH=$(date +%d)
        
        # Tag the backup for retention
        TAGS="date=$(date +%Y-%m-%d),weekday=$WEEKDAY,day_of_month=$DAY_OF_MONTH,database=$DB"
        
        S3_KEY="${S3_PREFIX}/${DATE_PATH}/${DB}_$(date +%Y%m%d_%H%M%S).sql$([ -f "${BACKUP_FILE}.gz" ] && echo .gz)$([ -f "${BACKUP_FILE}.gpg" ] && echo .gpg)"
        
        if aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/${S3_KEY}" \
            --endpoint-url="$S3_ENDPOINT" \
            --metadata "tags=$TAGS" 2>/dev/null; then
            
            log "✓ Uploaded to S3: s3://${S3_BUCKET}/${S3_KEY} ($SIZE_MB MB)"
            SUCCESSFUL=$((SUCCESSFUL + 1))
            
            # Clean up local file
            rm "$BACKUP_FILE"
        else
            log_error "✗ Failed to upload: $BACKUP_FILE"
            FAILED=$((FAILED + 1))
        fi
        
    else
        log_error "✗ Failed to dump database: $DB"
        FAILED=$((FAILED + 1))
    fi
done

# Calculate statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL_SIZE_MB=$((TOTAL_SIZE / 1024 / 1024))
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_MB / 1024" | bc)

# Summary
log "================================"
log "Backup Summary"
log "================================"
log "Total databases: $DB_COUNT"
log "Successful: $SUCCESSFUL"
log "Failed: $FAILED"
log "Total size: ${TOTAL_SIZE_GB}GB"
log "Duration: ${DURATION}s"
log "================================"

# Send notification
if [[ $FAILED -eq 0 ]]; then
    send_notification "✅ Database backup completed: $SUCCESSFUL/$DB_COUNT databases (${TOTAL_SIZE_GB}GB) in ${DURATION}s" "good"
    touch /tmp/backup-healthy
else
    send_notification "⚠️ Database backup completed with errors: $SUCCESSFUL successful, $FAILED failed" "warning"
fi

# Clean up old local backups (keep only today's)
find /backups -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

# Exit with error if any backups failed
[[ $FAILED -eq 0 ]] && exit 0 || exit 1

