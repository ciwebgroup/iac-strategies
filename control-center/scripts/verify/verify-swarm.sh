#!/usr/bin/env bash
#
# =============================================================================
# SWARM VERIFICATION SCRIPT
# =============================================================================
# Verifies Docker Swarm cluster health and configuration
# Run on a manager node to validate the cluster
#
# Usage: ./verify-swarm.sh [--json] [--push-metrics]
# =============================================================================

set -euo pipefail

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
OUTPUT_FORMAT="text"
PUSH_METRICS=false

# Expected counts (can be overridden by environment)
EXPECTED_MANAGERS="${EXPECTED_MANAGERS:-3}"
EXPECTED_WORKERS="${EXPECTED_WORKERS:-0}"

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
        --expected-managers) EXPECTED_MANAGERS="$2"; shift 2 ;;
        --expected-workers) EXPECTED_WORKERS="$2"; shift 2 ;;
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

push_metric() {
    local metric_name="$1"
    local metric_value="$2"
    
    if [[ "$PUSH_METRICS" == "true" && -n "$PUSHGATEWAY_URL" ]]; then
        cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/swarm-verify" 2>/dev/null || true
# TYPE $metric_name gauge
$metric_name $metric_value
EOF
    fi
}

# =============================================================================
# CHECKS
# =============================================================================

check_swarm_active() {
    local state
    state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "unknown")
    
    if [[ "$state" == "active" ]]; then
        log_check "SwarmActive" "PASS" "Swarm is active"
        return 0
    else
        log_check "SwarmActive" "FAIL" "Swarm state: $state"
        return 1
    fi
}

check_is_manager() {
    local is_manager
    is_manager=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo "false")
    
    if [[ "$is_manager" == "true" ]]; then
        log_check "IsManager" "PASS" "This node is a Swarm manager"
        return 0
    else
        log_check "IsManager" "FAIL" "This node is not a manager (run on manager node)"
        return 1
    fi
}

check_manager_count() {
    local manager_count
    manager_count=$(docker node ls --filter role=manager --format '{{.ID}}' 2>/dev/null | wc -l)
    
    if [[ "$manager_count" -ge "$EXPECTED_MANAGERS" ]]; then
        log_check "ManagerCount" "PASS" "$manager_count managers (expected: $EXPECTED_MANAGERS)"
        return 0
    else
        log_check "ManagerCount" "WARN" "$manager_count managers (expected: $EXPECTED_MANAGERS)"
        return 0
    fi
}

check_worker_count() {
    local worker_count
    worker_count=$(docker node ls --filter role=worker --format '{{.ID}}' 2>/dev/null | wc -l)
    
    if [[ "$EXPECTED_WORKERS" -eq 0 ]] || [[ "$worker_count" -ge "$EXPECTED_WORKERS" ]]; then
        log_check "WorkerCount" "PASS" "$worker_count workers"
        return 0
    else
        log_check "WorkerCount" "WARN" "$worker_count workers (expected: $EXPECTED_WORKERS)"
        return 0
    fi
}

check_nodes_ready() {
    local not_ready
    not_ready=$(docker node ls --format '{{.Status}}' 2>/dev/null | grep -cv "Ready" || echo "0")
    
    if [[ "$not_ready" -eq 0 ]]; then
        local total
        total=$(docker node ls --format '{{.ID}}' 2>/dev/null | wc -l)
        log_check "NodesReady" "PASS" "All $total nodes are Ready"
        return 0
    else
        log_check "NodesReady" "FAIL" "$not_ready nodes not Ready"
        return 1
    fi
}

check_manager_reachability() {
    local unreachable
    unreachable=$(docker node ls --filter role=manager --format '{{.ManagerStatus}}' 2>/dev/null | grep -cv "Reachable\|Leader" || echo "0")
    
    if [[ "$unreachable" -eq 0 ]]; then
        log_check "ManagerReachability" "PASS" "All managers reachable"
        return 0
    else
        log_check "ManagerReachability" "FAIL" "$unreachable managers unreachable"
        return 1
    fi
}

check_leader() {
    local leader
    leader=$(docker node ls --filter role=manager --format '{{.Hostname}} {{.ManagerStatus}}' 2>/dev/null | grep Leader | awk '{print $1}')
    
    if [[ -n "$leader" ]]; then
        log_check "Leader" "PASS" "Leader: $leader"
        return 0
    else
        log_check "Leader" "FAIL" "No leader elected"
        return 1
    fi
}

check_quorum() {
    local manager_count
    manager_count=$(docker node ls --filter role=manager --format '{{.ID}}' 2>/dev/null | wc -l)
    
    local reachable_count
    reachable_count=$(docker node ls --filter role=manager --format '{{.ManagerStatus}}' 2>/dev/null | grep -c "Reachable\|Leader" || echo "0")
    
    local quorum_needed=$(( (manager_count / 2) + 1 ))
    
    if [[ "$reachable_count" -ge "$quorum_needed" ]]; then
        log_check "Quorum" "PASS" "$reachable_count/$manager_count managers reachable (quorum: $quorum_needed)"
        return 0
    else
        log_check "Quorum" "FAIL" "Quorum lost: $reachable_count/$manager_count (need: $quorum_needed)"
        return 1
    fi
}

check_node_availability() {
    local drained
    drained=$(docker node ls --format '{{.Availability}}' 2>/dev/null | grep -c "Drain" || echo "0")
    local paused
    paused=$(docker node ls --format '{{.Availability}}' 2>/dev/null | grep -c "Pause" || echo "0")
    
    if [[ "$drained" -eq 0 ]] && [[ "$paused" -eq 0 ]]; then
        log_check "NodeAvailability" "PASS" "All nodes Active"
        return 0
    else
        log_check "NodeAvailability" "WARN" "$drained drained, $paused paused"
        return 0
    fi
}

check_service_count() {
    local service_count
    service_count=$(docker service ls --format '{{.ID}}' 2>/dev/null | wc -l)
    
    log_check "ServiceCount" "PASS" "$service_count services deployed"
    return 0
}

check_failing_services() {
    local failing
    failing=$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | grep -E "0/[1-9]" | wc -l || echo "0")
    
    if [[ "$failing" -eq 0 ]]; then
        log_check "FailingServices" "PASS" "No failing services"
        return 0
    else
        log_check "FailingServices" "FAIL" "$failing services with 0 running replicas"
        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            echo -e "  ${RED}Failing services:${NC}"
            docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null | grep -E "0/[1-9]" | while read -r line; do
                echo "    - $line"
            done
        fi
        return 1
    fi
}

list_nodes() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}Node List:${NC}"
        docker node ls 2>/dev/null || echo "  Unable to list nodes"
        echo ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "========================================"
        echo "Swarm Cluster Verification"
        echo "========================================"
        echo ""
    fi
    
    # Pre-flight: must be on a swarm manager
    if ! check_swarm_active; then
        echo -e "${RED}ERROR: This node is not part of an active Swarm${NC}"
        exit 1
    fi
    
    if ! check_is_manager; then
        echo -e "${RED}ERROR: This script must run on a Swarm manager node${NC}"
        exit 1
    fi
    
    # Run cluster checks
    check_manager_count
    check_worker_count
    check_nodes_ready
    check_manager_reachability
    check_leader
    check_quorum
    check_node_availability
    check_service_count
    check_failing_services
    
    # Show node list in text mode
    [[ "$OUTPUT_FORMAT" == "text" ]] && list_nodes
    
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
        push_metric "swarm_verify_passed" "$PASS_COUNT"
        push_metric "swarm_verify_warnings" "$WARN_COUNT"
        push_metric "swarm_verify_failed" "$FAIL_COUNT"
        push_metric "swarm_verify_timestamp" "$(date +%s)"
        push_metric "swarm_manager_count" "$(docker node ls --filter role=manager --format '{{.ID}}' | wc -l)"
        push_metric "swarm_worker_count" "$(docker node ls --filter role=worker --format '{{.ID}}' | wc -l)"
    fi
    
    # Exit code based on failures
    [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
