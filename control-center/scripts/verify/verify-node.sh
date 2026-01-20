#!/usr/bin/env bash
#
# =============================================================================
# NODE VERIFICATION SCRIPT
# =============================================================================
# Verifies that a droplet is correctly configured for the WordPress farm
# Deploy this to each node and run to validate configuration
#
# Usage: ./verify-node.sh [--json] [--push-metrics]
# =============================================================================

set -euo pipefail

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
OUTPUT_FORMAT="text"
PUSH_METRICS=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
#BLUE='\033[0;34m'
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

push_metric() {
    local metric_name="$1"
    local metric_value="$2"
    
    if [[ "$PUSH_METRICS" == "true" && -n "$PUSHGATEWAY_URL" ]]; then
        cat <<EOF | curl --data-binary @- "$PUSHGATEWAY_URL/metrics/job/node-verify/instance/$NODE_NAME" 2>/dev/null || true
# TYPE $metric_name gauge
$metric_name{node="$NODE_NAME"} $metric_value
EOF
    fi
}

# =============================================================================
# CHECKS
# =============================================================================

check_ssh() {
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log_check "SSH" "PASS" "SSH daemon is running"
        return 0
    else
        log_check "SSH" "FAIL" "SSH daemon is not running"
        return 1
    fi
}

check_docker() {
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            local version
            version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
            log_check "Docker" "PASS" "Docker $version is running"
            return 0
        else
            log_check "Docker" "FAIL" "Docker installed but daemon not running"
            return 1
        fi
    else
        log_check "Docker" "FAIL" "Docker is not installed"
        return 1
    fi
}

check_docker_swarm() {
    local swarm_state
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "unknown")
    
    case "$swarm_state" in
        active)
            local role
            role=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)
            if [[ "$role" == "true" ]]; then
                log_check "Swarm" "PASS" "Node is active Swarm manager"
            else
                log_check "Swarm" "PASS" "Node is active Swarm worker"
            fi
            return 0
            ;;
        pending)
            log_check "Swarm" "WARN" "Swarm join pending"
            return 0
            ;;
        inactive)
            log_check "Swarm" "WARN" "Node not part of Swarm (may be expected)"
            return 0
            ;;
        *)
            log_check "Swarm" "FAIL" "Unknown Swarm state: $swarm_state"
            return 1
            ;;
    esac
}

check_private_network() {
    # Check for private network interface (eth1 or ens4 typically on DO)
    if ip addr show eth1 &>/dev/null || ip addr show ens4 &>/dev/null; then
        local private_ip
        private_ip=$(ip addr show eth1 2>/dev/null | grep -oP 'inet \K[\d.]+' || \
                     ip addr show ens4 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")
        
        if [[ -n "$private_ip" ]]; then
            # Check if it's a private IP (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
            if [[ "$private_ip" =~ ^10\. ]] || [[ "$private_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$private_ip" =~ ^192\.168\. ]]; then
                log_check "PrivateNetwork" "PASS" "Private IP: $private_ip"
                return 0
            fi
        fi
    fi
    
    log_check "PrivateNetwork" "WARN" "No private network interface detected"
    return 0
}

check_disk_space() {
    local root_usage
    root_usage=$(df / --output=pcent | tail -1 | tr -d ' %')
    
    if [[ "$root_usage" -lt 80 ]]; then
        log_check "DiskSpace" "PASS" "Root filesystem ${root_usage}% used"
        return 0
    elif [[ "$root_usage" -lt 90 ]]; then
        log_check "DiskSpace" "WARN" "Root filesystem ${root_usage}% used (>80%)"
        return 0
    else
        log_check "DiskSpace" "FAIL" "Root filesystem ${root_usage}% used (>90%)"
        return 1
    fi
}

check_memory() {
    local total_mem available_mem usage_pct
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    usage_pct=$(( (total_mem - available_mem) * 100 / total_mem ))
    
    local total_gb
    total_gb=$(echo "scale=1; $total_mem / 1024 / 1024" | bc)
    
    if [[ "$usage_pct" -lt 80 ]]; then
        log_check "Memory" "PASS" "${total_gb}GB total, ${usage_pct}% used"
        return 0
    elif [[ "$usage_pct" -lt 90 ]]; then
        log_check "Memory" "WARN" "${total_gb}GB total, ${usage_pct}% used (>80%)"
        return 0
    else
        log_check "Memory" "FAIL" "${total_gb}GB total, ${usage_pct}% used (>90%)"
        return 1
    fi
}

check_time_sync() {
    if command -v timedatectl &>/dev/null; then
        local synced
        synced=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "no")
        
        if [[ "$synced" == "yes" ]]; then
            log_check "TimeSync" "PASS" "NTP synchronized"
            return 0
        else
            log_check "TimeSync" "WARN" "NTP not synchronized"
            return 0
        fi
    else
        log_check "TimeSync" "WARN" "timedatectl not available"
        return 0
    fi
}

check_firewall() {
    if command -v ufw &>/dev/null; then
        local status
        status=$(ufw status 2>/dev/null | head -1)
        log_check "Firewall" "PASS" "UFW: $status"
    elif command -v firewall-cmd &>/dev/null; then
        local status
        status=$(firewall-cmd --state 2>/dev/null || echo "unknown")
        log_check "Firewall" "PASS" "firewalld: $status"
    else
        log_check "Firewall" "WARN" "No firewall detected"
    fi
    return 0
}

check_dns() {
    if host google.com &>/dev/null || dig google.com +short &>/dev/null; then
        log_check "DNS" "PASS" "DNS resolution working"
        return 0
    else
        log_check "DNS" "FAIL" "DNS resolution failed"
        return 1
    fi
}

check_docker_networks() {
    if ! docker info &>/dev/null; then
        log_check "DockerNetworks" "WARN" "Docker not available, skipping network check"
        return 0
    fi
    
    local network_count
    network_count=$(docker network ls --filter driver=overlay --format '{{.Name}}' 2>/dev/null | wc -l)
    
    if [[ "$network_count" -gt 0 ]]; then
        log_check "DockerNetworks" "PASS" "$network_count overlay networks"
    else
        log_check "DockerNetworks" "WARN" "No overlay networks (may be expected before swarm setup)"
    fi
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "========================================"
        echo "Node Verification: $NODE_NAME"
        echo "========================================"
        echo ""
    fi
    
    # Run all checks
    check_ssh
    check_docker
    check_docker_swarm
    check_private_network
    check_disk_space
    check_memory
    check_time_sync
    check_firewall
    check_dns
    check_docker_networks
    
    # Output results
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo "========================================"
        echo -e "Summary: ${GREEN}$PASS_COUNT passed${NC}, ${YELLOW}$WARN_COUNT warnings${NC}, ${RED}$FAIL_COUNT failed${NC}"
        echo "========================================"
    else
        # JSON output
        echo "{"
        echo "  \"node\": \"$NODE_NAME\","
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
        push_metric "node_verify_passed" "$PASS_COUNT"
        push_metric "node_verify_warnings" "$WARN_COUNT"
        push_metric "node_verify_failed" "$FAIL_COUNT"
        push_metric "node_verify_timestamp" "$(date +%s)"
    fi
    
    # Exit code based on failures
    [[ "$FAIL_COUNT" -eq 0 ]] && exit 0 || exit 1
}

main "$@"
