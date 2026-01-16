#!/usr/bin/env bash
#
# =============================================================================
# WORDPRESS FILE BACKUP SCRIPT - Per-Site File Backups
# =============================================================================
# Backs up each WordPress site's uploads, plugins, and themes
# Uploads to DigitalOcean Spaces with date-based naming
# Runs daily at 03:00 (configured via cron or environment)
# =============================================================================

set -euo pipefail

# Configuration from environment
WORDPRESS_DATA_PATH="${WORDPRESS_DATA_PATH:-/wordpress-data}"
BACKUP_DIR="/backups/$(date +%Y-%m-%d)"
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
S3_PREFIX="${S3_PREFIX:-wordpress-files}"
COMPRESSION="${COMPRESSION:-gzip}"
ENCRYPTION_ENABLED="${ENCRYPTION_ENABLED:-true}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
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
            -d "{\"text\":\"📁 WordPress Backup: $message\",\"color\":\"$color\"}" \
            2>/dev/null || true
    fi
}

backup_site() {
    local site_dir="$1"
    local site_name=$(basename "$site_dir")
    
    log "Backing up site: $site_name..."
    
    # Create backup archive
    local backup_file="${BACKUP_DIR}/${site_name}_$(date +%Y%m%d_%H%M%S).tar"
    
    # Backup uploads, plugins, themes (exclude cache)
    if tar -cf "$backup_file" \
        -C "$site_dir" \
        --exclude='*/cache/*' \
        --exclude='*/upgrade/*' \
        --exclude='*.log' \
        --exclude='*.tmp' \
        uploads/ plugins/ themes/ 2>/dev/null; then
        
        # Compress
        if [[ "$COMPRESSION" == "gzip" ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
        fi
        
        # Encrypt (if enabled)
        if [[ "$ENCRYPTION_ENABLED" == "true" && -n "${GPG_RECIPIENT:-}" ]]; then
            gpg --encrypt --recipient "$GPG_RECIPIENT" "$backup_file"
            rm "$backup_file"
            backup_file="${backup_file}.gpg"
        fi
        
        # Get file size
        FILE_SIZE=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file")
        SIZE_MB=$((FILE_SIZE / 1024 / 1024))
        
        # Upload to S3
        DATE_PATH=$(date +%Y/%m/%d)
        WEEKDAY=$(date +%A | tr '[:upper:]' '[:lower:]')
        DAY_OF_MONTH=$(date +%d)
        
        S3_KEY="${S3_PREFIX}/${DATE_PATH}/${site_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if aws s3 cp "$backup_file" "s3://${S3_BUCKET}/${S3_KEY}" \
            --endpoint-url="$S3_ENDPOINT" \
            --metadata "site=$site_name,date=$(date +%Y-%m-%d),weekday=$WEEKDAY,day_of_month=$DAY_OF_MONTH" \
            2>/dev/null; then
            
            log "✓ $site_name backed up and uploaded ($SIZE_MB MB)"
            rm "$backup_file"
            echo "$site_name:success:$SIZE_MB" >> /tmp/backup-results.txt
        else
            log_error "✗ Failed to upload backup for $site_name"
            echo "$site_name:failed:0" >> /tmp/backup-results.txt
        fi
    else
        log_error "✗ Failed to create backup for $site_name"
        echo "$site_name:failed:0" >> /tmp/backup-results.txt
    fi
}

# Export function for parallel execution
export -f backup_site
export -f log
export -f log_error
export BACKUP_DIR S3_ENDPOINT S3_BUCKET S3_PREFIX COMPRESSION ENCRYPTION_ENABLED GPG_RECIPIENT GREEN RED NC

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Initialize results file
> /tmp/backup-results.txt

# Find all WordPress site directories
log "Scanning for WordPress sites in $WORDPRESS_DATA_PATH..."
SITES=$(find "$WORDPRESS_DATA_PATH" -maxdepth 1 -type d -name "wp-*" 2>/dev/null || true)

if [[ -z "$SITES" ]]; then
    log_error "No WordPress sites found in $WORDPRESS_DATA_PATH"
    send_notification "No WordPress sites found to backup" "error"
    exit 1
fi

SITE_COUNT=$(echo "$SITES" | wc -l)
log "Found $SITE_COUNT WordPress sites to backup"

START_TIME=$(date +%s)

# Backup sites in parallel
echo "$SITES" | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'backup_site "{}"'

# Calculate statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

SUCCESSFUL=$(grep -c ":success:" /tmp/backup-results.txt || echo 0)
FAILED=$(grep -c ":failed:" /tmp/backup-results.txt || echo 0)
TOTAL_SIZE_MB=$(awk -F: '{sum += $3} END {print sum}' /tmp/backup-results.txt)
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_MB / 1024" | bc)

# Summary
log "================================"
log "WordPress Backup Summary"
log "================================"
log "Total sites: $SITE_COUNT"
log "Successful: $SUCCESSFUL"
log "Failed: $FAILED"
log "Total size: ${TOTAL_SIZE_GB}GB"
log "Duration: ${DURATION}s"
log "Parallel jobs: $PARALLEL_JOBS"
log "================================"

# Send notification
if [[ $FAILED -eq 0 ]]; then
    send_notification "✅ WordPress file backup completed: $SUCCESSFUL/$SITE_COUNT sites (${TOTAL_SIZE_GB}GB) in ${DURATION}s" "good"
    touch /tmp/backup-healthy
else
    send_notification "⚠️ WordPress file backup completed with errors: $SUCCESSFUL successful, $FAILED failed" "warning"
fi

# Clean up old local backups
find /backups -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true

# Exit code
[[ $FAILED -eq 0 ]] && exit 0 || exit 1

