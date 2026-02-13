#!/bin/bash
set -e

# =============================================================================
# setup-proxmox.sh — Provision a Proxmox VE host on DigitalOcean
# =============================================================================
# This script:
#   1. Validates prerequisites (doctl, ansible, SSH key)
#   2. Creates a DigitalOcean Droplet
#   3. Runs the install_proxmox.yml Ansible playbook to convert Debian → PVE
#   4. Exports PROXMOX_HOST_IP so the LXC inventory can use it
#   5. Optionally kicks off LXC container provisioning (lxc_provision.yml)
#
# Usage:
#   export DO_PAT="your_token_here"
#   ./setup-proxmox.sh                         # full workflow
#   ./setup-proxmox.sh --skip-lxc              # stop after Proxmox install
#   ./setup-proxmox.sh --interactive           # prompt for options
#
# Flags:
#   --interactive                      Prompt for options with defaults
#   --droplet-name <name>              Droplet name
#   --region <region>                  DO region (e.g., nyc3)
#   --size <size>                      Droplet size (e.g., s-4vcpu-8gb)
#   --image <slug>                     Image slug (e.g., debian-12-x64)
#   --ssh-key-path <path>              Local public key path
#   --do-pat <token>                   DigitalOcean API token
#   --proxmox-host-ip <ip>             Use existing Proxmox host IP
#   --skip-lxc                         Skip LXC container provisioning
#   --only-lxc                         Only run LXC provisioning (requires PROXMOX_HOST_IP)
#   --no-ssh-key-upload                Do not upload SSH key to DigitalOcean
#   --no-reboot                        Skip reboot at end of Proxmox install
# =============================================================================

# --- CONFIGURATION ---
DEFAULT_DROPLET_NAME="proxmox-node-01"
DEFAULT_REGION="nyc3"
DEFAULT_SIZE="s-4vcpu-8gb"         # Recommended: 8GB RAM for Proxmox
DEFAULT_IMAGE="debian-12-x64"
DEFAULT_LOCAL_KEY_PATH="$HOME/.ssh/id_rsa.pub"

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/../ansible" && pwd)"
INSTALL_PLAYBOOK="$ANSIBLE_DIR/install_proxmox.yml"
LXC_PLAYBOOK="$ANSIBLE_DIR/lxc_provision.yml"
LXC_INVENTORY="$ANSIBLE_DIR/inventory/proxmox_lxc.yml"

# Defaults (can be overridden by env vars or flags)
DROPLET_NAME="${DROPLET_NAME:-$DEFAULT_DROPLET_NAME}"
REGION="${REGION:-$DEFAULT_REGION}"
SIZE="${SIZE:-$DEFAULT_SIZE}"
IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
LOCAL_KEY_PATH="${LOCAL_KEY_PATH:-$DEFAULT_LOCAL_KEY_PATH}"
PROXMOX_HOST_IP="${PROXMOX_HOST_IP:-}"  # If set, skip droplet creation
INTERACTIVE=false
SKIP_LXC=false
ONLY_LXC=false
NO_SSH_KEY_UPLOAD=false
NO_REBOOT=false

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

prompt_secret() {
    local prompt="$1"
    local default="$2"
    local value
    read -r -s -p "$prompt [$default]: " value
    echo ""
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

trim() {
    echo "$1" | xargs
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --interactive) INTERACTIVE=true; shift ;;
        --skip-lxc) SKIP_LXC=true; shift ;;
        --only-lxc) ONLY_LXC=true; shift ;;
        --no-ssh-key-upload) NO_SSH_KEY_UPLOAD=true; shift ;;
        --no-reboot) NO_REBOOT=true; shift ;;
        --droplet-name) DROPLET_NAME="$2"; shift 2 ;;
        --region) REGION="$2"; shift 2 ;;
        --size) SIZE="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --ssh-key-path) LOCAL_KEY_PATH="$2"; shift 2 ;;
        --do-pat) DO_PAT="$2"; shift 2 ;;
        --proxmox-host-ip) PROXMOX_HOST_IP="$2"; shift 2 ;;
        --help|-h) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

if [ "$INTERACTIVE" = true ]; then
    echo ""
    echo "🧭 Interactive setup"
    echo "---------------------"
    DROPLET_NAME=$(prompt_default "Droplet name" "$DROPLET_NAME")
    REGION=$(prompt_default "Region" "$REGION")
    SIZE=$(prompt_default "Droplet size" "$SIZE")
    IMAGE=$(prompt_default "Image slug" "$IMAGE")
    LOCAL_KEY_PATH=$(prompt_default "Local SSH public key path" "$LOCAL_KEY_PATH")
    PROXMOX_HOST_IP=$(prompt_default "Existing Proxmox host IP (leave blank to create)" "$PROXMOX_HOST_IP")
    DO_PAT=$(prompt_secret "DigitalOcean API token (DO_PAT)" "${DO_PAT:-}" )
    DO_PAT=$(trim "$DO_PAT")
    SKIP_LXC_INPUT=$(prompt_default "Skip LXC provisioning? (true/false)" "$SKIP_LXC")
    ONLY_LXC_INPUT=$(prompt_default "Only run LXC provisioning? (true/false)" "$ONLY_LXC")
    NO_SSH_KEY_UPLOAD_INPUT=$(prompt_default "Skip SSH key upload to DO? (true/false)" "$NO_SSH_KEY_UPLOAD")
    NO_REBOOT_INPUT=$(prompt_default "Skip Proxmox reboot? (true/false)" "$NO_REBOOT")
    if [ "$SKIP_LXC_INPUT" = "true" ]; then
        SKIP_LXC=true
    else
        SKIP_LXC=false
    fi
    if [ "$ONLY_LXC_INPUT" = "true" ]; then
        ONLY_LXC=true
    else
        ONLY_LXC=false
    fi
    if [ "$NO_SSH_KEY_UPLOAD_INPUT" = "true" ]; then
        NO_SSH_KEY_UPLOAD=true
    else
        NO_SSH_KEY_UPLOAD=false
    fi
    if [ "$NO_REBOOT_INPUT" = "true" ]; then
        NO_REBOOT=true
    else
        NO_REBOOT=false
    fi
fi

if [ "$ONLY_LXC" = true ] && [ -z "$PROXMOX_HOST_IP" ]; then
    echo "❌ --only-lxc requires --proxmox-host-ip (or PROXMOX_HOST_IP)."
    exit 1
fi

# --- PREREQUISITE CHECKS ---
echo "🔍 [0/7] Checking prerequisites..."

# doctl
if ! command -v doctl &> /dev/null; then
    echo "   ❌ doctl is not installed."
    echo "      Install: https://docs.digitalocean.com/reference/doctl/how-to/install/"
    exit 1
fi

# ansible
if ! command -v ansible-playbook &> /dev/null; then
    echo "   ❌ ansible is not installed."
    exit 1
fi

# Verify the install playbook exists
if [ ! -f "$INSTALL_PLAYBOOK" ]; then
    echo "   ❌ Playbook not found: $INSTALL_PLAYBOOK"
    exit 1
fi

# DigitalOcean auth
if [ -n "$DO_PAT" ]; then
    echo "   🔑 DO_PAT detected. Configuring doctl context..."
    export DIGITALOCEAN_ACCESS_TOKEN="$DO_PAT"
fi

DOCTL_AUTH_ARGS=()
if [ -n "$DO_PAT" ]; then
    DOCTL_AUTH_ARGS=(--access-token "$DO_PAT")
fi

if [ -z "$PROXMOX_HOST_IP" ]; then
    DOCTL_AUTH_OUTPUT=$(doctl "${DOCTL_AUTH_ARGS[@]}" account get 2>&1) || DOCTL_AUTH_RC=$?
    if [ -n "${DOCTL_AUTH_RC:-}" ]; then
        echo "   ❌ doctl is not authenticated."
        if [ -z "$DO_PAT" ]; then
            echo "      DO_PAT is empty. Please export DO_PAT='your-token' or run 'doctl auth init'."
        else
            echo "      DO_PAT was provided but the API call failed."
        fi
        echo "      doctl output: $DOCTL_AUTH_OUTPUT"
        exit 1
    fi
else
    echo "   ℹ️  PROXMOX_HOST_IP provided — skipping droplet creation and doctl auth."
fi

echo "   ✅ All prerequisites satisfied."

if [ "$ONLY_LXC" = true ]; then
    echo ""
    echo "⏭️  [1/7] Skipping droplet provisioning and Proxmox install (--only-lxc)."
else
# --- STEP 1: SSH KEY ---
echo ""
echo "🔑 [1/7] Checking SSH Key..."

if [ ! -f "$LOCAL_KEY_PATH" ]; then
    echo "   ❌ Public key not found at $LOCAL_KEY_PATH"
    echo "      Run 'ssh-keygen' to generate one."
    exit 1
fi

RAW_FINGERPRINT=$(ssh-keygen -l -E md5 -f "$LOCAL_KEY_PATH" | awk '{print $2}' | sed 's/MD5://')
echo "   Fingerprint: $RAW_FINGERPRINT"

if doctl "${DOCTL_AUTH_ARGS[@]}" compute ssh-key get "$RAW_FINGERPRINT" &> /dev/null; then
    echo "   ✅ Key found on DigitalOcean."
    SSH_KEY_REF="$RAW_FINGERPRINT"
else
    if [ "$NO_SSH_KEY_UPLOAD" = true ]; then
        echo "   ⚠️  Key not found on DigitalOcean and --no-ssh-key-upload set."
        echo "      Please upload your key manually or remove --no-ssh-key-upload."
        exit 1
    fi
    echo "   ⚠️  Key not found on DigitalOcean. Uploading..."
    KEY_NAME="$(hostname)-auto-$(date +%s)"
    doctl "${DOCTL_AUTH_ARGS[@]}" compute ssh-key import "$KEY_NAME" --public-key-file "$LOCAL_KEY_PATH"
    SSH_KEY_REF="$RAW_FINGERPRINT"
    echo "   ✅ Key uploaded as '$KEY_NAME'."
fi

if [ -n "$PROXMOX_HOST_IP" ]; then
    IP_ADDRESS="$PROXMOX_HOST_IP"
else
    # --- STEP 2: PROVISION DROPLET ---
    echo ""
    echo "🚀 [2/7] Provisioning Droplet '$DROPLET_NAME' in $REGION..."

    # Check if droplet already exists (idempotent)
    EXISTING_IP=$(doctl "${DOCTL_AUTH_ARGS[@]}" compute droplet list --format Name,PublicIPv4 --no-header 2>/dev/null \
        | grep "^${DROPLET_NAME} " | awk '{print $2}' || true)

    if [ -n "$EXISTING_IP" ]; then
        echo "   ⚠️  Droplet '$DROPLET_NAME' already exists at $EXISTING_IP. Skipping creation."
        IP_ADDRESS="$EXISTING_IP"
    else
                doctl "${DOCTL_AUTH_ARGS[@]}" compute droplet create "$DROPLET_NAME" \
          --region "$REGION" \
          --image "$IMAGE" \
          --size "$SIZE" \
          --ssh-keys "$SSH_KEY_REF" \
          --wait

        # --- STEP 3: RETRIEVE IP ---
        echo ""
        echo "🔍 [3/7] Retrieving IP Address..."
        IP_ADDRESS=$(doctl "${DOCTL_AUTH_ARGS[@]}" compute droplet get "$DROPLET_NAME" --format PublicIPv4 --no-header)

        if [ -z "$IP_ADDRESS" ]; then
            echo "   ❌ Could not retrieve IP address."
            exit 1
        fi
    fi
fi

echo "   ✅ Droplet IP: $IP_ADDRESS"

# Export for the Ansible inventory (proxmox_lxc.yml reads this)
export PROXMOX_HOST_IP="$IP_ADDRESS"

fi

# --- STEP 4: WAIT FOR SSH ---
echo ""
echo "⏳ [4/7] Waiting for SSH to become available..."
sleep 30

echo "   Adding host key to known_hosts..."
ssh-keyscan -H "$IP_ADDRESS" >> ~/.ssh/known_hosts 2>/dev/null

# Verify SSH is actually reachable
RETRIES=10
for i in $(seq 1 $RETRIES); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$IP_ADDRESS" true 2>/dev/null; then
        echo "   ✅ SSH is ready."
        break
    fi
    if [ "$i" -eq "$RETRIES" ]; then
        echo "   ❌ SSH not available after ${RETRIES} attempts."
        exit 1
    fi
    echo "   Attempt $i/$RETRIES — retrying in 10s..."
    sleep 10
done

if [ "$ONLY_LXC" = false ]; then
# --- STEP 5: INSTALL PROXMOX ---
echo ""
echo "🛠️  [5/7] Running Ansible Playbook to install Proxmox VE..."
echo "   Playbook: $INSTALL_PLAYBOOK"
echo "   This will take 5–10 minutes and will reboot the server once."

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

if [ "$NO_REBOOT" = true ]; then
    ansible-playbook \
        -i "$IP_ADDRESS," \
        -u root \
        -e skip_reboot=true \
        "$INSTALL_PLAYBOOK"
else
    ansible-playbook \
        -i "$IP_ADDRESS," \
        -u root \
        "$INSTALL_PLAYBOOK"
fi
fi

# --- STEP 6: RETRIEVE API TOKEN ---
echo ""
echo "🔐 [6/7] Retrieving Proxmox API token from host..."

TOKEN_FILE_CONTENT=$(ssh -o StrictHostKeyChecking=no "root@$IP_ADDRESS" \
    'cat /root/.proxmox_ansible_token 2>/dev/null' || true)

if [ -n "$TOKEN_FILE_CONTENT" ]; then
    # Source the token variables
    eval "$(echo "$TOKEN_FILE_CONTENT" | grep -v '^#')"
    export PROXMOX_API_TOKEN_ID
    export PROXMOX_API_TOKEN_SECRET

    echo "   ✅ API token loaded."
    echo "   Token ID: $PROXMOX_API_TOKEN_ID"
else
    echo "   ⚠️  Token file not found. The token may have been created in a previous run."
    echo "      If you already have the token, export these before proceeding:"
    echo "        export PROXMOX_API_TOKEN_ID=ansible"
    echo "        export PROXMOX_API_TOKEN_SECRET=<your-secret>"

    if [ "$SKIP_LXC" = false ]; then
        echo ""
        echo "   Cannot proceed with LXC provisioning without API credentials."
        echo "   Run again with --skip-lxc, or set the variables and run lxc_provision.yml manually."
        SKIP_LXC=true
    fi
fi

# --- STEP 7: LXC CONTAINER PROVISIONING ---
echo ""
if [ "$SKIP_LXC" = true ]; then
    echo "⏭️  [7/7] Skipping LXC container provisioning (--skip-lxc)."
else
    echo "📦 [7/7] Provisioning LXC containers..."
    echo "   Inventory: $LXC_INVENTORY"
    echo "   Playbook:  $LXC_PLAYBOOK"

    ansible-playbook \
        -i "$LXC_INVENTORY" \
        "$LXC_PLAYBOOK"
fi

# --- DONE ---
echo ""
echo "🎉 Deployment Complete!"
echo "═══════════════════════════════════════════════════════════"
echo "  Proxmox Web UI:  https://$IP_ADDRESS:8006"
echo "  SSH:             ssh root@$IP_ADDRESS"
echo "  Username:        root"
echo ""
echo "  Environment variables for LXC provisioning:"
echo "    export PROXMOX_HOST_IP=$IP_ADDRESS"
[ -n "$PROXMOX_API_TOKEN_ID" ] && \
echo "    export PROXMOX_API_TOKEN_ID=$PROXMOX_API_TOKEN_ID"
[ -n "$PROXMOX_API_TOKEN_SECRET" ] && \
echo "    export PROXMOX_API_TOKEN_SECRET=$PROXMOX_API_TOKEN_SECRET"
echo ""
echo "  To provision LXC containers later:"
echo "    cd $ANSIBLE_DIR"
echo "    ansible-playbook -i inventory/proxmox_lxc.yml lxc_provision.yml"
echo "═══════════════════════════════════════════════════════════"