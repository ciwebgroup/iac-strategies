#!/usr/bin/env bash
#
# =============================================================================
# NETWORKS VERIFICATION SCRIPT
# =============================================================================
# Verifies that Docker overlay networks are correctly configured
# Run on a manager node to validate network setup
#
# Usage: ./verify-networks.sh [--json] [--push-metrics]
# =============================================================================

set -euo pipefail

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
OUTPUT_FORMAT="text"
PUSH_METRICS=false

# Required networks for WordPress farm
REQUIRED_NETWORKS=(
    "traefik-public"
    "wordpress-net"
    "database-net"
    "storage-net"
    "cache-net"
    "observability-net"
    "crowdsec-net"
    "management-net"
    "contractor-net"
)

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

check_network() {
    local network_name="$1"
    
    if docker network inspect "$network_name" &>/dev/null; then
        local driver scope attachable
        driver=$(docker network inspect "$network_name" --format '{{.Driver}}' 2>/dev/null)
        scope=$(docker network inspect "$network_name" --format '{{.Scope}}' 2>/dev/null)
        attachable=$(docker network inspect "$network_name" --format '{{.Attachable}}' 2>/dev/null)
        
        if [[ "$driver" == "overlay" ]] && [[ "$scope" == "swarm" ]]; then
            if [[ "$attachable" == "true" ]]; then
                log_check "$network_name" "PASS" "overlay, swarm-scoped, attachable"
            else
                log_check "$network_name" "WARN" "overlay, swarm-scoped, not attachable"
            fi
            return 0
        else
            log_check "$network_name" "WARN" "driver=$driver, scope=$scope (expected overlay/swarm)"
            return 0
        fi
    else
        log_check "$network_name" "FAIL" "Network does not exist"
        return 1
    fi
}

check_all_required_networks() {
    local missing=0
    
    for network in "${REQUIRED_NETWORKS[@]}"; do
        check_network "$network" || ((missing++))
    done
    
    return "$missing"
}

check_ingress_network() {
    if docker network inspect ingress &>/dev/null; then
        log_check "ingress" "PASS" "Ingress network exists (Swarm default)"
    else
        log_check "ingress" "WARN" "Ingress network missing (unusual)"
    fi
}

check_docker_gwbridge() {
    if docker network inspect docker_gwbridge &>/dev/null; then
        log_check "docker_gwbridge" "PASS" "Gateway bridge exists"
    else
        log_check "docker_gwbridge" "WARN" "Gateway bridge missing"
    fi
}

show_network_details() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}Network Details:${NC}"
        docker network ls --filter driver=overlay --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null
        echo ""
    fi
}

show_network_endpoints() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${BLUE}Network Endpoints (containers):${NC}"
        for network in "${REQUIRED_NETWORKS[@]}"; do
            if docker network inspect "$network" &>/dev/null; then
                local endpoint_count
                endpoint_count=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
                echo "  $network: $endpoint_count containers"
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
        echo "Docker Networks Verification"
        echo "========================================"
        echo ""
        echo "Checking required networks..."
        echo ""
    fi
    
    # Check all required networks
    check_all_required_networks
    
    # Check system networks
    echo ""
    echo "Checking system networks..."
    echo ""
    check_ingress_network
    check_docker_gwbridge
    
    # Show details
    show_network_details
    show_network_endpoints
    
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
        echo "  \"required_networks\": ["
        local first=true
        for network in "${REQUIRED_NETWORKS[@]}"; do
            [[ "$first" == "true" ]] || echo ","
            echo -n "    \"$network\""
            first=false
        done
        echo ""
        echo "  ],"
        echo "  \"checks\": {"
        first=true
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
        local total_networks missing_networks
        total_networks=${#REQUIRED_NETWORKS[@]}
        missing_networks=$FAIL_COUNT
        
        cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/networks-verify" 2>/dev/null || true
# TYPE swarm_networks_required gauge
swarm_networks_required $total_networks
# TYPE swarm_networks_missing gauge
swarm_networks_missing $missing_networks
# TYPE swarm_networks_verify_timestamp gauge
swarm_networks_verify_timestamp $(date +%s)
EOF
    fi
    
    # Exit code based on failures
    [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
