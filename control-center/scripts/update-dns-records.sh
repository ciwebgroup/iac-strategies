#!/bin/bash
set -euo pipefail

# =============================================================================
# Cloudflare DNS Record Update Script
# =============================================================================
# Updates/creates DNS records for all management services
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_CENTER_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$CONTROL_CENTER_DIR/.env"

# Load environment
source "$ENV_FILE"

# Configuration
ZONE_ID="dc2ed38d40f64f8d949c94a8ea5ebce5"
SERVER_IP="45.55.171.53"
DOMAIN="ciwebgroup.com"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# List of subdomains to create/update
SUBDOMAINS=(
    "antman"
    "traefik"
    "prometheus"
    "loki"
    "tempo"
    "grafana"
    "alertmanager"
    "portainer"
    "registry"
    "registry-ui"
    "logs"
    "apprise"
    "swarmpit"
)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Cloudflare DNS Record Update${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "Zone: ${DOMAIN}"
echo -e "Target IP: ${SERVER_IP}"
echo -e "Records to process: ${#SUBDOMAINS[@]}"
echo

# Function to check if record exists
check_record() {
    local subdomain=$1
    local full_domain="${subdomain}.${DOMAIN}"
    
    local record_id=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${full_domain}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
    
    echo "$record_id"
}

# Function to create DNS record
create_record() {
    local subdomain=$1
    local full_domain="${subdomain}.${DOMAIN}"
    
    local response=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"A\",
            \"name\": \"${subdomain}\",
            \"content\": \"${SERVER_IP}\",
            \"ttl\": 1,
            \"proxied\": false,
            \"comment\": \"Management service: ${subdomain}\"
        }")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        echo -e "${GREEN}✓${NC} Created: ${full_domain} -> ${SERVER_IP}"
        return 0
    else
        local error=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}✗${NC} Failed to create ${full_domain}: ${error}"
        return 1
    fi
}

# Function to update DNS record
update_record() {
    local subdomain=$1
    local record_id=$2
    local full_domain="${subdomain}.${DOMAIN}"
    
    local response=$(curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"A\",
            \"name\": \"${subdomain}\",
            \"content\": \"${SERVER_IP}\",
            \"ttl\": 1,
            \"proxied\": false,
            \"comment\": \"Management service: ${subdomain}\"
        }")
    
    local success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        echo -e "${GREEN}✓${NC} Updated: ${full_domain} -> ${SERVER_IP}"
        return 0
    else
        local error=$(echo "$response" | jq -r '.errors[0].message')
        echo -e "${RED}✗${NC} Failed to update ${full_domain}: ${error}"
        return 1
    fi
}

# Process all subdomains
for subdomain in "${SUBDOMAINS[@]}"; do
    echo -n "Processing ${subdomain}.${DOMAIN}... "
    
    record_id=$(check_record "$subdomain")
    
    if [ -z "$record_id" ]; then
        echo "not found, creating..."
        create_record "$subdomain"
    else
        echo "found (ID: ${record_id:0:8}...), updating..."
        update_record "$subdomain" "$record_id"
    fi
done

echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}DNS Update Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "Verification:"
echo "  nslookup <subdomain>.ciwebgroup.com 1.1.1.1"
echo
echo "DNS propagation may take 1-5 minutes."
