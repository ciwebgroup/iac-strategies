#!/usr/bin/env bash
#
# =============================================================================
# STACK VERIFICATION SCRIPT
# =============================================================================
# Verifies that a Docker stack is correctly deployed and healthy
# Run on a manager node to validate stack deployment
#
# Usage: ./verify-stack.sh <stack-name> [--json] [--push-metrics]
# =============================================================================

set -euo pipefail

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
OUTPUT_FORMAT="text"
PUSH_METRICS=false
STACK_NAME=""

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
        -*) shift ;;
        *) STACK_NAME="$1"; shift ;;
    esac
done

if [[ -z "$STACK_NAME" ]]; then
    echo "Usage: $0 <stack-name> [--json] [--push-metrics]"
    echo ""
    echo "Available stacks:"
    docker stack ls --format '  - {{.Name}}' 2>/dev/null || echo "  (none)"
    exit 1
fi

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

check_stack_exists() {
    if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -q "^${STACK_NAME}$"; then
        local service_count
        service_count=$(docker stack services "$STACK_NAME" --format '{{.ID}}' 2>/dev/null | wc -l)
        log_check "StackExists" "PASS" "Stack '$STACK_NAME' exists with $service_count services"
        return 0
    else
        log_check "StackExists" "FAIL" "Stack '$STACK_NAME' does not exist"
        return 1
    fi
}

check_service_replicas() {
    local services
    services=$(docker stack services "$STACK_NAME" --format '{{.Name}} {{.Replicas}}' 2>/dev/null)
    
    local all_healthy=true
    
    while IFS= read -r line; do
        local service_name replicas
        service_name=$(echo "$line" | awk '{print $1}')
        replicas=$(echo "$line" | awk '{print $2}')
        
        local current desired
        current=$(echo "$replicas" | cut -d'/' -f1)
        desired=$(echo "$replicas" | cut -d'/' -f2)
        
        if [[ "$current" -eq "$desired" ]] && [[ "$desired" -gt 0 ]]; then
            log_check "Service:$service_name" "PASS" "$replicas replicas"
        elif [[ "$current" -gt 0 ]]; then
            log_check "Service:$service_name" "WARN" "$replicas replicas (degraded)"
            all_healthy=false
        else
            log_check "Service:$service_name" "FAIL" "$replicas replicas (down)"
            all_healthy=false
        fi
    done <<< "$services"
    
    $all_healthy && return 0 || return 1
}

check_service_health() {
    local services
    services=$(docker stack services "$STACK_NAME" --format '{{.Name}}' 2>/dev/null)
    
    while IFS= read -r service_name; do
        # Get tasks for this service
        local tasks
        tasks=$(docker service ps "$service_name" --filter "desired-state=running" --format '{{.CurrentState}}' 2>/dev/null)
        
        local running_count=0
        local total_count=0
        
        while IFS= read -r state; do
            ((total_count++))
            if [[ "$state" == Running* ]]; then
                ((running_count++))
            fi
        done <<< "$tasks"
        
        if [[ "$OUTPUT_FORMAT" == "text" ]] && [[ "$total_count" -gt 0 ]]; then
            echo "    $service_name: $running_count/$total_count tasks running"
        fi
    done <<< "$services"
}

check_recent_errors() {
    local services
    services=$(docker stack services "$STACK_NAME" --format '{{.Name}}' 2>/dev/null)
    
    local error_count=0
    
    while IFS= read -r service_name; do
        # Check for failed tasks in last hour
        local failed
        failed=$(docker service ps "$service_name" --filter "desired-state=shutdown" --format '{{.Error}}' 2>/dev/null | grep -v "^$" | wc -l)
        
        if [[ "$failed" -gt 0 ]]; then
            ((error_count += failed))
            if [[ "$OUTPUT_FORMAT" == "text" ]]; then
                echo -e "  ${YELLOW}$service_name: $failed recent failures${NC}"
            fi
        fi
    done <<< "$services"
    
    if [[ "$error_count" -eq 0 ]]; then
        log_check "RecentErrors" "PASS" "No recent task failures"
    else
        log_check "RecentErrors" "WARN" "$error_count recent task failures"
    fi
}

check_stack_networks() {
    local services
    services=$(docker stack services "$STACK_NAME" --format '{{.Name}}' 2>/dev/null)
    
    local networks=""
    
    while IFS= read -r service_name; do
        local svc_networks
        svc_networks=$(docker service inspect "$service_name" --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}' 2>/dev/null)
        networks="$networks $svc_networks"
    done <<< "$services"
    
    # Deduplicate
    networks=$(echo "$networks" | tr ' ' '\n' | sort -u | grep -v "^$")
    
    if [[ -n "$networks" ]]; then
        local net_count
        net_count=$(echo "$networks" | wc -l)
        log_check "StackNetworks" "PASS" "$net_count networks attached"
        
        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            echo "$networks" | while read -r net; do
                # Resolve network ID to name
                local net_name
                net_name=$(docker network inspect "$net" --format '{{.Name}}' 2>/dev/null || echo "$net")
                echo "    - $net_name"
            done
        fi
    else
        log_check "StackNetworks" "WARN" "No networks detected"
    fi
}

show_service_logs_hint() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}Troubleshooting commands:${NC}"
        echo "  docker stack services $STACK_NAME"
        echo "  docker stack ps $STACK_NAME"
        docker stack services "$STACK_NAME" --format '{{.Name}}' 2>/dev/null | head -3 | while read -r svc; do
            echo "  docker service logs --tail 50 $svc"
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
        echo "Stack Verification: $STACK_NAME"
        echo "========================================"
        echo ""
    fi
    
    # Check stack exists first
    if ! check_stack_exists; then
        echo -e "${RED}Stack '$STACK_NAME' not found${NC}"
        exit 1
    fi
    
    echo ""
    echo "Checking service replicas..."
    check_service_replicas
    
    echo ""
    echo "Checking task health..."
    check_service_health
    
    echo ""
    check_recent_errors
    
    echo ""
    check_stack_networks
    
    show_service_logs_hint
    
    # Output results
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "========================================"
        echo -e "Summary: ${GREEN}$PASS_COUNT passed${NC}, ${YELLOW}$WARN_COUNT warnings${NC}, ${RED}$FAIL_COUNT failed${NC}"
        echo "========================================"
    else
        # JSON output
        echo "{"
        echo "  \"stack\": \"$STACK_NAME\","
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
        local total_services healthy_services
        total_services=$(docker stack services "$STACK_NAME" --format '{{.ID}}' 2>/dev/null | wc -l)
        healthy_services=$PASS_COUNT
        
        cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/stack-verify/stack/$STACK_NAME" 2>/dev/null || true
# TYPE stack_services_total gauge
stack_services_total{stack="$STACK_NAME"} $total_services
# TYPE stack_services_healthy gauge
stack_services_healthy{stack="$STACK_NAME"} $healthy_services
# TYPE stack_verify_passed gauge
stack_verify_passed{stack="$STACK_NAME"} $PASS_COUNT
# TYPE stack_verify_warnings gauge
stack_verify_warnings{stack="$STACK_NAME"} $WARN_COUNT
# TYPE stack_verify_failed gauge
stack_verify_failed{stack="$STACK_NAME"} $FAIL_COUNT
# TYPE stack_verify_timestamp gauge
stack_verify_timestamp{stack="$STACK_NAME"} $(date +%s)
EOF
    fi
    
    # Exit code based on failures
    [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
