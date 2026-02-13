# Proxmox LXC Container Provisioning

## Overview

This solution automates creation and management of **LXC containers on a Proxmox VE host** running inside a DigitalOcean Droplet. Because DigitalOcean Droplets already use KVM, nested KVM is not available — only **LXC containers** are supported.

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  DigitalOcean Droplet (Proxmox VE)                         │
│  Public IP: $PROXMOX_HOST_IP                               │
│                                                             │
│  ┌──────────── vmbr0 (10.10.10.1/24, NAT) ──────────────┐  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │  │
│  │  │ lxc-manager  │  │ lxc-worker   │  │ lxc-cache   │  │  │
│  │  │ 10.10.10.10  │  │ 10.10.10.20  │  │ 10.10.10.30 │  │  │
│  │  └──────────────┘  └──────────────┘  └─────────────┘  │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │  │
│  │  │ lxc-db       │  │ lxc-storage  │  │ lxc-monitor │  │  │
│  │  │ 10.10.10.40  │  │ 10.10.10.50  │  │ 10.10.10.60 │  │  │
│  │  └──────────────┘  └──────────────┘  └─────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Proxmox API Token

Create an API token on the Proxmox host so Ansible can authenticate without a password:

```bash
# SSH into the Proxmox host
ssh root@<PROXMOX_HOST_IP>

# Create an API token (--privsep=0 gives full privileges)
pveum user token add root@pam ansible --privsep=0
```

Save the returned **Token ID** and **Secret** — you will need them for environment variables.

### 2. Environment Variables

Export these before running the playbook:

```bash
export PROXMOX_HOST_IP="your.proxmox.public.ip"
export PROXMOX_API_TOKEN_ID="ansible"
export PROXMOX_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export LXC_ROOT_PASSWORD="a-strong-password"     # optional — SSH key auth is primary
```

### 3. Ansible Collections

```bash
ansible-galaxy collection install community.general
```

### 4. LXC Template

The playbook will **auto-download** the Debian 12 template if it is not already present. You can also download it manually:

```bash
# On the Proxmox host
pveam update
pveam download local debian-12-standard_12.7-1_amd64.tar.zst
```

## File Structure

```
ansible/
├── lxc_provision.yml                    # Main provisioning playbook
├── lxc_destroy.yml                      # Teardown playbook
├── inventory/
│   ├── static.yml                       # Existing DO droplet inventory
│   └── proxmox/proxmox_lxc.yml          # NEW — LXC container inventory
├── group_vars/
│   ├── all.yml                          # Global vars (existing)
│   ├── proxmox_hosts.yml               # NEW — Proxmox host credentials
│   └── lxc_containers.yml              # NEW — Shared LXC defaults
└── roles/
    └── proxmox_lxc/
        ├── defaults/main.yml            # Default variable values
        ├── meta/main.yml                # Role metadata
        ├── vars/main.yml                # Internal computed variables
        └── tasks/
            ├── main.yml                 # Task orchestration
            ├── preflight.yml            # Input validation
            ├── template.yml             # Template download
            ├── create.yml               # Container creation (idempotent)
            ├── ssh.yml                  # SSH key injection via pct exec
            └── start.yml               # Start + connectivity check
```

## Usage

### Provision All Containers

```bash
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_provision.yml
```

### Provision a Subset

```bash
# Only database containers
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_provision.yml --limit lxc_database_nodes

# Only workers and cache
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_provision.yml --limit 'lxc_worker_nodes:lxc_cache_nodes'
```

### Dry Run

```bash
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_provision.yml --check
```

### Re-run SSH Setup on Existing Containers

```bash
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_provision.yml -e _lxc_force_ssh_setup=true
```

### Destroy Containers

```bash
ansible-playbook -i inventory/proxmox/proxmox_lxc.yml lxc_destroy.yml
```

## Connection Model — Jump Host / ProxyCommand

The containers sit on a **private bridge** (`10.10.10.0/24`) and are not directly reachable from your workstation. To reach them, SSH bounces through the Proxmox host using `ProxyCommand`.

This is already configured in the inventory under `lxc_containers.vars.ansible_ssh_common_args`:

```yaml
ansible_ssh_common_args: >-
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p root@{{ proxmox_public_ip }}"
```

### How It Works

```
Your Machine                 Proxmox Host               LXC Container
─────────────────────────────────────────────────────────────────────
ansible-playbook ──SSH──▶  root@<public_ip>  ──SSH──▶  root@10.10.10.x
                         (ProxyCommand jump)           (private network)
```

1. **Ansible connects to the Proxmox host** using its public IP.
2. **The `-W %h:%p` flag** tells SSH to forward the TCP connection to the container's private IP and port 22.
3. **The container sees a direct SSH session** — it does not know about the jump.

### Manual SSH Access

You can also SSH into a container manually using the same pattern:

```bash
# Using ProxyJump (modern SSH, recommended)
ssh -J root@<PROXMOX_HOST_IP> root@10.10.10.10

# Using ProxyCommand (compatible with older SSH)
ssh -o ProxyCommand="ssh -W %h:%p root@<PROXMOX_HOST_IP>" root@10.10.10.10
```

### SSH Config Shortcut

Add this to `~/.ssh/config` for convenience:

```ssh-config
# Proxmox Jump Host
Host proxmox
    HostName <PROXMOX_HOST_IP>
    User root
    IdentityFile ~/.ssh/id_rsa

# LXC containers via jump
Host 10.10.10.*
    User root
    IdentityFile ~/.ssh/id_rsa
    ProxyJump proxmox
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Then simply: `ssh root@10.10.10.10`

## Adding More Containers

Edit `inventory/proxmox/proxmox_lxc.yml` and add a new host entry under the appropriate group:

```yaml
lxc_worker_nodes:
  hosts:
    # ... existing ...
    lxc-worker-03: # New container
      ansible_host: 10.10.10.22
      lxc_vmid: 122
      lxc_hostname: lxc-worker-03
      lxc_cores: 4
      lxc_memory: 4096
      lxc_disk_size: 40
```

Then run the provision playbook — it is **idempotent** and will only create the new container.

## IP Address Scheme

| Group      | VMID Range | IP Range       | Purpose                     |
| ---------- | ---------- | -------------- | --------------------------- |
| Managers   | 110–119    | 10.10.10.10–19 | Docker Swarm managers       |
| Workers    | 120–129    | 10.10.10.20–29 | WordPress application nodes |
| Cache      | 130–139    | 10.10.10.30–39 | Varnish + Redis             |
| Database   | 140–149    | 10.10.10.40–49 | MariaDB / Galera            |
| Storage    | 150–159    | 10.10.10.50–59 | GlusterFS / NFS             |
| Monitoring | 160–169    | 10.10.10.60–69 | Prometheus / Grafana        |

## Idempotency

The `community.general.proxmox` module checks whether a container with the given `vmid` already exists:

- **Container exists** → task reports `ok` (no change)
- **Container missing** → task creates it and reports `changed`
- **SSH setup** only runs when the container was just created (or when `_lxc_force_ssh_setup=true`)

## Security Notes

- Containers are created as **unprivileged** (`unprivileged: true`)
- SSH root login is restricted to **key-based authentication only** (`PermitRootLogin prohibit-password`)
- The `LXC_ROOT_PASSWORD` is a fallback for console access via the Proxmox UI; SSH key auth is the primary mechanism
- API tokens use `--privsep=0` for simplicity — consider creating a restricted token for production
- The `nesting=1` feature flag is enabled to allow running Docker/systemd inside containers
