#!/usr/bin/env bash
#
# =============================================================================
# BACKUP CLEANUP SCRIPT - Smart Retention Policy
# =============================================================================
# Retention Policy:
# - Days 1-14:    Keep ALL backups (daily)
# - Days 15-180:  Keep SUNDAY backups only (weekly)
# - Days 181-365: Keep 1st of MONTH backups only (monthly)
# - Days 365+:    DELETE
#
# This gives you:
# - 14 daily backups (last 2 weeks)
# - ~26 weekly backups (6 months of Sundays)  
# - ~12 monthly backups (12 months of 1st day)
# Total: ~52 backups per site/database
# =============================================================================

set -euo pipefail

# Configuration
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
NOTIFICATION_URL="${NOTIFICATION_URL:-}"
DRY_RUN="${DRY_RUN:-false}"

# Retention configuration
KEEP_ALL_DAYS=14
KEEP_WEEKLY_START_DAY=15
KEEP_WEEKLY_END_DAY=180
KEEP_MONTHLY_START_DAY=181
KEEP_MONTHLY_END_DAY=365
MAX_AGE_DAYS=365

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

send_notification() {
    local message="$1"
    
    if [[ -n "$NOTIFICATION_URL" ]]; then
        curl -X POST "$NOTIFICATION_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"🗑️  Backup Cleanup: $message\"}" \
            2>/dev/null || true
    fi
}

calculate_age_days() {
    local backup_date="$1"
    local current_date=$(date +%s)
    local backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo 0)
    local age_seconds=$((current_date - backup_timestamp))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
}

is_sunday_backup() {
    local backup_date="$1"
    local weekday=$(date -d "$backup_date" +%A)
    [[ "$weekday" == "Sunday" ]] && return 0 || return 1
}

is_first_of_month() {
    local backup_date="$1"
    local day=$(date -d "$backup_date" +%d)
    [[ "$day" == "01" ]] && return 0 || return 1
}

should_delete_backup() {
    local backup_date="$1"
    local age_days=$(calculate_age_days "$backup_date")
    
    # Keep all backups younger than KEEP_ALL_DAYS
    if [[ $age_days -le $KEEP_ALL_DAYS ]]; then
        echo "keep:daily:${age_days}d"
        return 1
    fi
    
    # For backups 15-180 days old: Keep only Sunday backups
    if [[ $age_days -ge $KEEP_WEEKLY_START_DAY && $age_days -le $KEEP_WEEKLY_END_DAY ]]; then
        if is_sunday_backup "$backup_date"; then
            echo "keep:weekly:${age_days}d:sunday"
            return 1
        else
            echo "delete:not-sunday:${age_days}d"
            return 0
        fi
    fi
    
    # For backups 181-365 days old: Keep only 1st of month backups
    if [[ $age_days -ge $KEEP_MONTHLY_START_DAY && $age_days -le $KEEP_MONTHLY_END_DAY ]]; then
        if is_first_of_month "$backup_date"; then
            echo "keep:monthly:${age_days}d:1st"
            return 1
        else
            echo "delete:not-1st:${age_days}d"
            return 0
        fi
    fi
    
    # Delete backups older than MAX_AGE_DAYS
    if [[ $age_days -gt $MAX_AGE_DAYS ]]; then
        echo "delete:too-old:${age_days}d"
        return 0
    fi
    
    # Default: keep
    echo "keep:default:${age_days}d"
    return 1
}

cleanup_prefix() {
    local prefix="$1"
    local prefix_name="$2"
    
    log "Cleaning up $prefix_name backups in s3://${S3_BUCKET}/${prefix}..."
    
    # List all backups in this prefix
    local backups
    backups=$(aws s3 ls "s3://${S3_BUCKET}/${prefix}" \
        --recursive \
        --endpoint-url="$S3_ENDPOINT" \
        2>/dev/null || true)
    
    if [[ -z "$backups" ]]; then
        log_warn "No backups found in $prefix"
        return 0
    fi
    
    local total_count=0
    local delete_count=0
    local keep_count=0
    local deleted_size=0
    
    # Process each backup
    while IFS= read -r line; do
        # Parse S3 ls output: date time size key
        local backup_date=$(echo "$line" | awk '{print $1}')
        local backup_size=$(echo "$line" | awk '{print $3}')
        local backup_key=$(echo "$line" | awk '{print $4}')
        
        total_count=$((total_count + 1))
        
        # Determine if should delete
        local decision
        decision=$(should_delete_backup "$backup_date")
        local action=$(echo "$decision" | cut -d: -f1)
        local reason=$(echo "$decision" | cut -d: -f2-)
        
        if [[ "$action" == "delete" ]]; then
            delete_count=$((delete_count + 1))
            deleted_size=$((deleted_size + backup_size))
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_warn "[DRY RUN] Would delete: $backup_key ($reason)"
            else
                log "Deleting: $backup_key ($reason)"
                aws s3 rm "s3://${S3_BUCKET}/${backup_key}" \
                    --endpoint-url="$S3_ENDPOINT" \
                    2>/dev/null || log_error "Failed to delete: $backup_key"
            fi
        else
            keep_count=$((keep_count + 1))
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                log "Keeping: $backup_key ($reason)"
            fi
        fi
    done <<< "$backups"
    
    # Convert deleted size to human readable
    local deleted_size_mb=$((deleted_size / 1024 / 1024))
    local deleted_size_gb=$(echo "scale=2; $deleted_size_mb / 1024" | bc)
    
    log "$prefix_name summary: Total=$total_count, Keeping=$keep_count, Deleting=$delete_count (${deleted_size_gb}GB)"
    
    echo "$prefix_name:$total_count:$keep_count:$delete_count:$deleted_size_gb" >> /tmp/cleanup-stats.txt
}

# Main execution
log "Starting backup cleanup process..."
log "Retention policy:"
log "  - Days 1-14: Keep ALL backups"
log "  - Days 15-180: Keep SUNDAY backups only"
log "  - Days 181-365: Keep 1st of MONTH backups only"
log "  - Days 365+: DELETE"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No files will be deleted"
fi

# Initialize stats
> /tmp/cleanup-stats.txt

START_TIME=$(date +%s)

# Cleanup database backups
cleanup_prefix "database-backups" "Database"

# Cleanup WordPress file backups
cleanup_prefix "wordpress-files" "WordPress Files"

# Calculate totals
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ -f /tmp/cleanup-stats.txt ]]; then
    TOTAL_FILES=$(awk -F: '{sum += $2} END {print sum}' /tmp/cleanup-stats.txt)
    TOTAL_KEPT=$(awk -F: '{sum += $3} END {print sum}' /tmp/cleanup-stats.txt)
    TOTAL_DELETED=$(awk -F: '{sum += $4} END {print sum}' /tmp/cleanup-stats.txt)
    TOTAL_FREED_GB=$(awk -F: '{sum += $5} END {printf "%.2f", sum}' /tmp/cleanup-stats.txt)
    
    # Summary
    log "================================"
    log "Cleanup Summary"
    log "================================"
    log "Total backups: $TOTAL_FILES"
    log "Kept: $TOTAL_KEPT"
    log "Deleted: $TOTAL_DELETED"
    log "Space freed: ${TOTAL_FREED_GB}GB"
    log "Duration: ${DURATION}s"
    log "================================"
    
    # Send notification
    if [[ "$DRY_RUN" == "true" ]]; then
        send_notification "[DRY RUN] Would delete $TOTAL_DELETED/$TOTAL_FILES backups (${TOTAL_FREED_GB}GB)"
    else
        send_notification "✅ Cleanup completed: Deleted $TOTAL_DELETED/$TOTAL_FILES backups, freed ${TOTAL_FREED_GB}GB"
        touch /tmp/cleanup-healthy
    fi
fi

log "Backup cleanup completed"

