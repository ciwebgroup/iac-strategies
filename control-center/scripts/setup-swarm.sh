#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup-swarm.sh — Proxmox-less Ansible orchestration for Swarm stack
# =============================================================================
# This script:
#   1. Validates prerequisites (ansible, env file)
#   2. Optionally enables DigitalOcean dynamic inventory
#   3. Runs Ansible playbooks to provision and deploy the stack
#
# Usage:
#   ./setup-swarm.sh                         # Full workflow
#   ./setup-swarm.sh --interactive           # Prompt for options
#   ./setup-swarm.sh --skip-provision        # Deploy only
#   ./setup-swarm.sh --skip-dns              # Skip DNS playbook
#
# Flags:
#   --interactive                      Prompt for options with defaults
#   --inventory <path|static|do>       Use a specific inventory (default: prompt)
#   --skip-provision                   Skip provision.yml
#   --skip-deploy                      Skip deploy.yml
#   --skip-health                      Skip health.yml
#   --skip-dns                         Skip dns.yml
#   --install-collections              Install Ansible collections before run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../ansible" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_SETUP="$SCRIPT_DIR/setup-env.sh"
REQUIREMENTS_FILE="$ANSIBLE_DIR/requirements.yml"

PROVISION_PLAYBOOK="$ANSIBLE_DIR/provision.yml"
DEPLOY_PLAYBOOK="$ANSIBLE_DIR/deploy.yml"
HEALTH_PLAYBOOK="$ANSIBLE_DIR/health.yml"
DNS_PLAYBOOK="$ANSIBLE_DIR/dns.yml"

DIGITALOCEAN_INVENTORY_DISABLED="$ANSIBLE_DIR/inventory/digitalocean.yml.disabled"
DIGITALOCEAN_INVENTORY="$ANSIBLE_DIR/inventory/digitalocean.yml"
STATIC_INVENTORY="$ANSIBLE_DIR/inventory/static.yml"

INTERACTIVE=false
SKIP_PROVISION=false
SKIP_DEPLOY=false
SKIP_HEALTH=false
SKIP_DNS=false
INSTALL_COLLECTIONS=false
INVENTORY_CHOICE=""

print_usage() {
    sed -n '1,80p' "$0" | sed 's/^#//'
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    read -r -p "$prompt [$default]: " value
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

confirm() {
    local prompt="$1"
    read -r -p "$prompt [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --interactive) INTERACTIVE=true; shift ;;
        --skip-provision) SKIP_PROVISION=true; shift ;;
        --skip-deploy) SKIP_DEPLOY=true; shift ;;
        --skip-health) SKIP_HEALTH=true; shift ;;
        --skip-dns) SKIP_DNS=true; shift ;;
        --install-collections) INSTALL_COLLECTIONS=true; shift ;;
        --inventory) INVENTORY_CHOICE="$2"; shift 2 ;;
        --help|-h) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

if [ "$INTERACTIVE" = true ]; then
    echo ""
    echo "🧭 Interactive setup"
    echo "---------------------"
    SKIP_PROVISION_INPUT=$(prompt_default "Skip provision.yml? (true/false)" "$SKIP_PROVISION")
    SKIP_DEPLOY_INPUT=$(prompt_default "Skip deploy.yml? (true/false)" "$SKIP_DEPLOY")
    SKIP_HEALTH_INPUT=$(prompt_default "Skip health.yml? (true/false)" "$SKIP_HEALTH")
    SKIP_DNS_INPUT=$(prompt_default "Skip dns.yml? (true/false)" "$SKIP_DNS")
    INSTALL_COLLECTIONS_INPUT=$(prompt_default "Install Ansible collections? (true/false)" "$INSTALL_COLLECTIONS")
    INVENTORY_CHOICE=$(prompt_default "Inventory (static|do|path)" "")

    if [ "$SKIP_PROVISION_INPUT" = "true" ]; then SKIP_PROVISION=true; else SKIP_PROVISION=false; fi
    if [ "$SKIP_DEPLOY_INPUT" = "true" ]; then SKIP_DEPLOY=true; else SKIP_DEPLOY=false; fi
    if [ "$SKIP_HEALTH_INPUT" = "true" ]; then SKIP_HEALTH=true; else SKIP_HEALTH=false; fi
    if [ "$SKIP_DNS_INPUT" = "true" ]; then SKIP_DNS=true; else SKIP_DNS=false; fi
    if [ "$INSTALL_COLLECTIONS_INPUT" = "true" ]; then INSTALL_COLLECTIONS=true; else INSTALL_COLLECTIONS=false; fi
fi

# --- PREREQUISITE CHECKS ---
echo "🔍 [0/6] Checking prerequisites..."

if ! command -v ansible-playbook &> /dev/null; then
    echo "   ❌ ansible-playbook is not installed."
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "   ⚠️  Env file not found at $ENV_FILE"
    if [ "$INTERACTIVE" = true ] && [ -x "$ENV_SETUP" ]; then
        if confirm "Run setup-env.sh to create it?"; then
            "$ENV_SETUP"
        else
            echo "   ❌ .env is required to proceed."
            exit 1
        fi
    else
        echo "   ❌ .env is required to proceed."
        exit 1
    fi
fi

# Source env
set -a
source "$ENV_FILE"
set +a

if [ -z "${DO_API_TOKEN:-}" ] || [ "$DO_API_TOKEN" = "dop_v1_your_actual_token_here" ]; then
    echo "   ❌ DO_API_TOKEN is not set to a real value in $ENV_FILE"
    echo "      Update DO_API_TOKEN in $ENV_FILE and re-run."
    exit 1
fi

if [ "$INSTALL_COLLECTIONS" = true ]; then
    if [ -f "$REQUIREMENTS_FILE" ]; then
        echo "   📦 Installing Ansible collections..."
        ansible-galaxy collection install -r "$REQUIREMENTS_FILE"
    else
        echo "   ❌ requirements.yml not found at $REQUIREMENTS_FILE"
        exit 1
    fi
fi

echo "   ✅ Prerequisites satisfied."

# --- INVENTORY SELECTION ---
INVENTORY_PATH=""

if [ -n "$INVENTORY_CHOICE" ]; then
    case "$INVENTORY_CHOICE" in
        static)
            INVENTORY_PATH="$STATIC_INVENTORY"
            ;;
        do|digitalocean)
            if [ ! -f "$DIGITALOCEAN_INVENTORY" ] && [ -f "$DIGITALOCEAN_INVENTORY_DISABLED" ]; then
                if [ "$INTERACTIVE" = true ]; then
                    if confirm "Enable DigitalOcean dynamic inventory?"; then
                        mv "$DIGITALOCEAN_INVENTORY_DISABLED" "$DIGITALOCEAN_INVENTORY"
                    else
                        echo "   ❌ DigitalOcean inventory not enabled."
                        exit 1
                    fi
                else
                    echo "   ❌ DigitalOcean inventory disabled. Re-run with --interactive or enable it manually."
                    exit 1
                fi
            fi
            INVENTORY_PATH="$DIGITALOCEAN_INVENTORY"
            ;;
        *)
            INVENTORY_PATH="$INVENTORY_CHOICE"
            ;;
    esac
else
    if [ -f "$DIGITALOCEAN_INVENTORY" ]; then
        INVENTORY_PATH="$DIGITALOCEAN_INVENTORY"
    elif [ -f "$DIGITALOCEAN_INVENTORY_DISABLED" ] && [ "$INTERACTIVE" = true ]; then
        if confirm "Enable DigitalOcean dynamic inventory?"; then
            mv "$DIGITALOCEAN_INVENTORY_DISABLED" "$DIGITALOCEAN_INVENTORY"
            INVENTORY_PATH="$DIGITALOCEAN_INVENTORY"
        else
            INVENTORY_PATH="$STATIC_INVENTORY"
        fi
    else
        INVENTORY_PATH="$STATIC_INVENTORY"
    fi
fi

if [ ! -f "$INVENTORY_PATH" ]; then
    echo "   ❌ Inventory not found: $INVENTORY_PATH"
    exit 1
fi

echo "📄 Using inventory: $INVENTORY_PATH"

# --- ANSIBLE EXECUTION ---
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

STEP=1
if [ "$SKIP_PROVISION" = false ]; then
    echo ""
    echo "🚀 [$STEP/6] Provisioning infrastructure..."
    ansible-playbook -i "$INVENTORY_PATH" "$PROVISION_PLAYBOOK"
fi
STEP=$((STEP+1))

if [ "$SKIP_DEPLOY" = false ]; then
    echo ""
    echo "📦 [$STEP/6] Deploying services..."
    ansible-playbook -i "$INVENTORY_PATH" "$DEPLOY_PLAYBOOK"
fi
STEP=$((STEP+1))

if [ "$SKIP_HEALTH" = false ]; then
    echo ""
    echo "🩺 [$STEP/6] Running health checks..."
    ansible-playbook -i "$INVENTORY_PATH" "$HEALTH_PLAYBOOK"
fi
STEP=$((STEP+1))

if [ "$SKIP_DNS" = false ]; then
    if [ "$INTERACTIVE" = true ]; then
        if confirm "Run DNS updates via dns.yml?"; then
            echo ""
            echo "🌐 [$STEP/6] Updating DNS..."
            ansible-playbook -i "$INVENTORY_PATH" "$DNS_PLAYBOOK"
        else
            echo "⏭️  DNS updates skipped by user."
        fi
    else
        echo ""
        echo "🌐 [$STEP/6] Updating DNS..."
        ansible-playbook -i "$INVENTORY_PATH" "$DNS_PLAYBOOK"
    fi
fi

# --- DONE ---
echo ""
echo "🎉 Deployment Complete!"
echo "═══════════════════════════════════════════════════════════"
echo "  Inventory:       $INVENTORY_PATH"
echo "  Env file:        $ENV_FILE"
echo "  Provisioned:     $([ "$SKIP_PROVISION" = false ] && echo yes || echo no)"
echo "  Deployed:        $([ "$SKIP_DEPLOY" = false ] && echo yes || echo no)"
echo "  Health checks:   $([ "$SKIP_HEALTH" = false ] && echo yes || echo no)"
echo "  DNS updates:     $([ "$SKIP_DNS" = false ] && echo yes || echo no)"
echo "═══════════════════════════════════════════════════════════"
