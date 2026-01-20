#!/usr/bin/env bash
#
# =============================================================================
# BACKUP MONITOR SCRIPT - Verify Backup Health
# =============================================================================
# Monitors backup freshness and integrity
# Alerts if backups are missing, too old, or too small
# Exports metrics to Prometheus Pushgateway
# =============================================================================

set -euo pipefail

# Configuration
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"
BACKUP_MIN_SIZE_MB="${BACKUP_MIN_SIZE_MB:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://alertmanager:9093}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://prometheus-pushgateway:9091}"
NOTIFICATION_URL="${NOTIFICATION_URL:-}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

send_alert() {
    local alertname="$1"
    local summary="$2"
    local severity="${3:-warning}"
    
    # Send to Alertmanager
    local alert_json=$(cat <<EOF
[{
  "labels": {
    "alertname": "$alertname",
    "severity": "$severity",
    "service": "backup-monitor",
    "tier": "backup"
  },
  "annotations": {
    "summary": "$summary",
    "description": "Backup monitoring detected an issue"
  }
}]
EOF
)
    
    curl -X POST "$ALERTMANAGER_URL/api/v1/alerts" \
        -H "Content-Type: application/json" \
        -d "$alert_json" \
        2>/dev/null || true
    
    # Also send to Slack
    if [[ -n "$NOTIFICATION_URL" ]]; then
        local emoji="⚠️"
        [[ "$severity" == "critical" ]] && emoji="🚨"
        
        curl -X POST "$NOTIFICATION_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"$emoji $alertname: $summary\"}" \
            2>/dev/null || true
    fi
}

push_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local labels="$3"
    
    cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/backup-monitor" 2>/dev/null || true
# TYPE $metric_name gauge
$metric_name{$labels} $metric_value
EOF
}

check_database_backups() {
    log "Checking database backups..."
    
    # Get latest database backup
    local latest_db_backup
    latest_db_backup=$(aws s3 ls "s3://${S3_BUCKET}/database-backups/" \
        --recursive \
        --endpoint-url="$S3_ENDPOINT" \
        | sort | tail -n 1)
    
    if [[ -z "$latest_db_backup" ]]; then
        send_alert "DatabaseBackupMissing" "No database backups found in S3" "critical"
        push_metric "backup_database_status" "0" "type=\"database\""
        return 1
    fi
    
    # Check backup age
    local backup_date=$(echo "$latest_db_backup" | awk '{print $1" "$2}')
    local backup_timestamp=$(date -d "$backup_date" +%s)
    local current_timestamp=$(date +%s)
    local age_seconds=$((current_timestamp - backup_timestamp))
    local age_hours=$((age_seconds / 3600))
    
    # Check size
    local backup_size=$(echo "$latest_db_backup" | awk '{print $3}')
    local backup_size_mb=$((backup_size / 1024 / 1024))
    
    # Export metrics
    push_metric "backup_database_age_hours" "$age_hours" "type=\"database\""
    push_metric "backup_database_size_mb" "$backup_size_mb" "type=\"database\""
    
    # Check if backup is too old
    if [[ $age_hours -gt $BACKUP_MAX_AGE_HOURS ]]; then
        send_alert "DatabaseBackupTooOld" "Latest database backup is $age_hours hours old (max: $BACKUP_MAX_AGE_HOURS)" "critical"
        push_metric "backup_database_status" "0" "type=\"database\""
        return 1
    fi
    
    # Check if backup is too small
    if [[ $backup_size_mb -lt $BACKUP_MIN_SIZE_MB ]]; then
        send_alert "DatabaseBackupTooSmall" "Database backup is only ${backup_size_mb}MB (min: $BACKUP_MIN_SIZE_MB)" "warning"
        push_metric "backup_database_status" "0" "type=\"database\""
        return 1
    fi
    
    log "✓ Database backup OK: $age_hours hours old, ${backup_size_mb}MB"
    push_metric "backup_database_status" "1" "type=\"database\""
    return 0
}

check_wordpress_backups() {
    log "Checking WordPress file backups..."
    
    # Get latest WordPress backup
    local latest_wp_backup
    latest_wp_backup=$(aws s3 ls "s3://${S3_BUCKET}/wordpress-files/" \
        --recursive \
        --endpoint-url="$S3_ENDPOINT" \
        | sort | tail -n 1)
    
    if [[ -z "$latest_wp_backup" ]]; then
        send_alert "WordPressBackupMissing" "No WordPress file backups found in S3" "critical"
        push_metric "backup_wordpress_status" "0" "type=\"wordpress\""
        return 1
    fi
    
    # Check backup age
    local backup_date=$(echo "$latest_wp_backup" | awk '{print $1" "$2}')
    local backup_timestamp=$(date -d "$backup_date" +%s)
    local current_timestamp=$(date +%s)
    local age_seconds=$((current_timestamp - backup_timestamp))
    local age_hours=$((age_seconds / 3600))
    
    # Check size
    local backup_size=$(echo "$latest_wp_backup" | awk '{print $3}')
    local backup_size_mb=$((backup_size / 1024 / 1024))
    
    # Export metrics
    push_metric "backup_wordpress_age_hours" "$age_hours" "type=\"wordpress\""
    push_metric "backup_wordpress_size_mb" "$backup_size_mb" "type=\"wordpress\""
    
    # Check if backup is too old
    if [[ $age_hours -gt $BACKUP_MAX_AGE_HOURS ]]; then
        send_alert "WordPressBackupTooOld" "Latest WordPress backup is $age_hours hours old (max: $BACKUP_MAX_AGE_HOURS)" "critical"
        push_metric "backup_wordpress_status" "0" "type=\"wordpress\""
        return 1
    fi
    
    log "✓ WordPress backup OK: $age_hours hours old, ${backup_size_mb}MB"
    push_metric "backup_wordpress_status" "1" "type=\"wordpress\""
    return 0
}

check_backup_space() {
    log "Checking S3 bucket space usage..."
    
    # Get bucket size
    local bucket_size
    bucket_size=$(aws s3 ls "s3://${S3_BUCKET}/" \
        --recursive \
        --summarize \
        --endpoint-url="$S3_ENDPOINT" \
        2>/dev/null | grep "Total Size:" | awk '{print $3}')
    
    if [[ -n "$bucket_size" ]]; then
        local bucket_size_gb=$(echo "scale=2; $bucket_size / 1024 / 1024 / 1024" | bc)
        log "Bucket size: ${bucket_size_gb}GB"
        push_metric "backup_bucket_size_gb" "$bucket_size_gb" "bucket=\"$S3_BUCKET\""
    fi
    
    # Count total backups
    local backup_count
    backup_count=$(aws s3 ls "s3://${S3_BUCKET}/" \
        --recursive \
        --endpoint-url="$S3_ENDPOINT" \
        2>/dev/null | wc -l)
    
    log "Total backups: $backup_count"
    push_metric "backup_total_count" "$backup_count" "bucket=\"$S3_BUCKET\""
}

# Main monitoring loop
log "Backup monitor starting..."
log "Check interval: ${CHECK_INTERVAL}s"
log "Max age: ${BACKUP_MAX_AGE_HOURS}h"
log "Min size: ${BACKUP_MIN_SIZE_MB}MB"

while true; do
    log "Running backup health checks..."
    
    DB_STATUS=0
    WP_STATUS=0
    
    # Check database backups
    if check_database_backups; then
        DB_STATUS=1
    fi
    
    # Check WordPress backups
    if check_wordpress_backups; then
        WP_STATUS=1
    fi
    
    # Check S3 space
    check_backup_space
    
    # Overall status
    if [[ $DB_STATUS -eq 1 && $WP_STATUS -eq 1 ]]; then
        log "✓ All backups healthy"
        touch /tmp/backup-healthy
        push_metric "backup_overall_status" "1" "cluster=\"wordpress-farm\""
    else
        log_error "✗ Backup issues detected"
        push_metric "backup_overall_status" "0" "cluster=\"wordpress-farm\""
    fi
    
    log "Next check in ${CHECK_INTERVAL}s..."
    sleep "$CHECK_INTERVAL"
done

