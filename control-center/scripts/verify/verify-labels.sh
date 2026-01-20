#!/usr/bin/env bash
#
# =============================================================================
# NODE LABELS VERIFICATION SCRIPT
# =============================================================================
# Verifies that Docker Swarm node labels are correctly configured
# Run on a manager node to validate label assignments
#
# Usage: ./verify-labels.sh [--json] [--push-metrics]
# =============================================================================

set -euo pipefail

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
OUTPUT_FORMAT="text"
PUSH_METRICS=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json) OUTPUT_FORMAT="json"; shift ;;
        --push-metrics) PUSH_METRICS=true; shift ;;
        *) shift ;;
    esac
done

# Results tracking
declare -A RESULTS
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_check() {
    local name="$1"
    local status="$2"
    local message="$3"
    
    RESULTS["$name"]="$status:$message"
    
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        case "$status" in
            PASS) echo -e "${GREEN}✓${NC} $name: $message"; ((PASS_COUNT++)) ;;
            FAIL) echo -e "${RED}✗${NC} $name: $message"; ((FAIL_COUNT++)) ;;
            WARN) echo -e "${YELLOW}!${NC} $name: $message"; ((WARN_COUNT++)) ;;
        esac
    fi
}

# =============================================================================
# CHECKS
# =============================================================================

check_label_exists() {
    local label="$1"
    local min_count="${2:-1}"
    local friendly_name="${3:-$label}"
    
    local count
    count=$(docker node ls --filter "node.label.$label=true" --format '{{.Hostname}}' 2>/dev/null | wc -l)
    
    if [[ "$count" -ge "$min_count" ]]; then
        log_check "$friendly_name" "PASS" "$count nodes with label $label=true"
        return 0
    elif [[ "$count" -gt 0 ]]; then
        log_check "$friendly_name" "WARN" "$count nodes (expected: $min_count+)"
        return 0
    else
        log_check "$friendly_name" "WARN" "No nodes with label $label=true"
        return 0
    fi
}

list_nodes_with_label() {
    local label="$1"
    
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        local nodes
        nodes=$(docker node ls --filter "node.label.$label=true" --format '{{.Hostname}}' 2>/dev/null)
        if [[ -n "$nodes" ]]; then
            echo "$nodes" | while read -r node; do
                echo "    - $node"
            done
        fi
    fi
}

check_cache_nodes() {
    check_label_exists "cache" 1 "CacheNodes"
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes_with_label "cache"
}

check_database_nodes() {
    check_label_exists "db" 1 "DatabaseNodes"
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes_with_label "db"
}

check_storage_nodes() {
    check_label_exists "storage" 1 "StorageNodes"
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes_with_label "storage"
}

check_app_nodes() {
    check_label_exists "app" 1 "AppNodes"
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes_with_label "app"
}

check_ops_nodes() {
    check_label_exists "ops" 1 "OpsNodes"
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes_with_label "ops"
}

check_numbered_labels() {
    # Check for cache-node and db-node numbered labels
    local cache_numbered
    cache_numbered=$(docker node ls --format '{{.Hostname}}' 2>/dev/null | while read -r node; do
        docker node inspect "$node" --format '{{index .Spec.Labels "cache-node"}}' 2>/dev/null | grep -v "^$" && echo "$node"
    done | wc -l)
    
    if [[ "$cache_numbered" -gt 0 ]]; then
        log_check "CacheNumbering" "PASS" "Cache nodes have numbered labels"
    else
        log_check "CacheNumbering" "WARN" "No cache-node numbered labels (may not be needed)"
    fi
    
    local db_numbered
    db_numbered=$(docker node ls --format '{{.Hostname}}' 2>/dev/null | while read -r node; do
        docker node inspect "$node" --format '{{index .Spec.Labels "db-node"}}' 2>/dev/null | grep -v "^$" && echo "$node"
    done | wc -l)
    
    if [[ "$db_numbered" -gt 0 ]]; then
        log_check "DBNumbering" "PASS" "Database nodes have numbered labels"
    else
        log_check "DBNumbering" "WARN" "No db-node numbered labels (may not be needed)"
    fi
}

show_all_labels() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}All Node Labels:${NC}"
        docker node ls --format '{{.Hostname}}' 2>/dev/null | while read -r node; do
            echo "  $node:"
            local labels
            labels=$(docker node inspect "$node" --format '{{range $k, $v := .Spec.Labels}}    {{$k}}={{$v}}{{"\n"}}{{end}}' 2>/dev/null)
            if [[ -n "$labels" ]]; then
                echo "$labels"
            else
                echo "    (no labels)"
            fi
        done
        echo ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "========================================"
        echo "Node Labels Verification"
        echo "========================================"
        echo ""
    fi
    
    # Check for required labels
    check_cache_nodes
    check_database_nodes
    check_storage_nodes
    check_app_nodes
    check_ops_nodes
    check_numbered_labels
    
    # Show all labels
    show_all_labels
    
    # Output results
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "========================================"
        echo -e "Summary: ${GREEN}$PASS_COUNT passed${NC}, ${YELLOW}$WARN_COUNT warnings${NC}, ${RED}$FAIL_COUNT failed${NC}"
        echo "========================================"
    else
        # JSON output
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"summary\": {"
        echo "    \"passed\": $PASS_COUNT,"
        echo "    \"warnings\": $WARN_COUNT,"
        echo "    \"failed\": $FAIL_COUNT"
        echo "  },"
        echo "  \"checks\": {"
        local first=true
        for key in "${!RESULTS[@]}"; do
            local status="${RESULTS[$key]%%:*}"
            local message="${RESULTS[$key]#*:}"
            [[ "$first" == "true" ]] || echo ","
            echo -n "    \"$key\": {\"status\": \"$status\", \"message\": \"$message\"}"
            first=false
        done
        echo ""
        echo "  }"
        echo "}"
    fi
    
    # Push metrics if enabled
    if [[ "$PUSH_METRICS" == "true" && -n "$PUSHGATEWAY_URL" ]]; then
        local cache_count db_count storage_count app_count ops_count
        cache_count=$(docker node ls --filter "node.label.cache=true" --format '{{.ID}}' 2>/dev/null | wc -l)
        db_count=$(docker node ls --filter "node.label.db=true" --format '{{.ID}}' 2>/dev/null | wc -l)
        storage_count=$(docker node ls --filter "node.label.storage=true" --format '{{.ID}}' 2>/dev/null | wc -l)
        app_count=$(docker node ls --filter "node.label.app=true" --format '{{.ID}}' 2>/dev/null | wc -l)
        ops_count=$(docker node ls --filter "node.label.ops=true" --format '{{.ID}}' 2>/dev/null | wc -l)
        
        cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/labels-verify" 2>/dev/null || true
# TYPE swarm_labeled_nodes gauge
swarm_labeled_nodes{label="cache"} $cache_count
swarm_labeled_nodes{label="db"} $db_count
swarm_labeled_nodes{label="storage"} $storage_count
swarm_labeled_nodes{label="app"} $app_count
swarm_labeled_nodes{label="ops"} $ops_count
EOF
    fi
    
    # Exit code based on failures
    [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
