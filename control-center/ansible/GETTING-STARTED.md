# 🚀 Getting Started - Ansible WordPress Farm

**Welcome!** You now have a complete Ansible implementation of your WordPress farm infrastructure.

---

## ⚡ TL;DR - Quick Commands

```bash
# Check if ready
cd /var/opt/manage/control-center/ansible
./quick-start.sh check

# Full deployment (45 minutes, creates 33 nodes, $3,613/month)
./quick-start.sh all

# Or step by step
ansible-playbook provision.yml    # Create infrastructure
ansible-playbook deploy.yml       # Deploy services
ansible-playbook health.yml       # Verify

# Create a WordPress site
ansible-playbook site.yml -e domain=example.com

# Configure DNS
ansible-playbook dns.yml -e domain=example.com
```

---

## 📁 What You Have

```
ansible/
├── 📘 README.md                   ← Start here! Complete guide
├── 📗 MIGRATION-GUIDE.md          ← Bash → Ansible migration
├── 📙 ANSIBLE-SUMMARY.md          ← Technical overview
├── 📕 GETTING-STARTED.md          ← This file
│
├── ⚙️ ansible.cfg                 ← Ansible configuration
├── 📦 requirements.yml            ← Dependencies
├── 🚀 quick-start.sh              ← One-command deployment
│
├── 📂 inventory/
│   ├── digitalocean.yml          ← Auto-discovers droplets
│   └── static.yml                ← Manual entries
│
├── 📂 group_vars/                ← Variables per node type
│   ├── all.yml                   ← Global config
│   ├── swarm_managers.yml
│   ├── cache_nodes.yml
│   ├── database_nodes.yml
│   ├── storage_nodes.yml
│   ├── worker_nodes.yml
│   └── monitor_nodes.yml
│
├── 📂 roles/
│   ├── common/                   ← Base system setup
│   └── docker/                   ← Docker installation
│
└── 📂 playbooks/ (in root dir)
    ├── provision.yml             ← Create DO infrastructure
    ├── deploy.yml                ← Deploy all services
    ├── site.yml                  ← Manage WP sites
    ├── health.yml                ← Health checks
    ├── backup.yml                ← Backups
    └── dns.yml                   ← Cloudflare DNS

Total: 24 files
```

---

## 🎯 Your First Deployment

### Option 1: Automated (Recommended)

```bash
cd /var/opt/manage/control-center/ansible

# 1. Check prerequisites (2 minutes)
./quick-start.sh check

# 2. Install dependencies (3 minutes)
./quick-start.sh setup

# 3. Full deployment (45 minutes)
#    ⚠️ This creates 33 droplets ($3,613/month)
./quick-start.sh all
```

### Option 2: Manual (Step by Step)

```bash
cd /var/opt/manage/control-center/ansible

# 1. Prerequisites
sudo apt install ansible
ansible-galaxy collection install -r requirements.yml

# 2. Environment
cd ..
cp scripts/.env.example .env
nano .env  # Configure DO_API_TOKEN, etc.

# 3. Authenticate DigitalOcean
doctl auth init

# 4. Provision infrastructure (15-20 min)
cd ansible
ansible-playbook provision.yml

# 5. Wait for boot
sleep 120

# 6. Deploy services (20-25 min)
ansible-playbook deploy.yml

# 7. Verify
ansible-playbook health.yml

# 8. Create site
ansible-playbook site.yml -e domain=test.yourdomain.com

# 9. Configure DNS
ansible-playbook dns.yml -e domain=test.yourdomain.com
```

---

## 📚 Documentation Guide

### Read in This Order:

1. **GETTING-STARTED.md** (this file)
   - Quick overview and first deployment
   - **Read first!**

2. **README.md**
   - Complete usage guide
   - All playbooks documented
   - Tag reference
   - Troubleshooting
   - **Your main reference!**

3. **MIGRATION-GUIDE.md**
   - Only if migrating from bash script
   - Command mapping
   - Step-by-step migration
   - Team training

4. **ANSIBLE-SUMMARY.md**
   - Technical implementation details
   - Statistics and comparisons
   - For technical deep dive

---

## 🎓 Learn by Example

### Example 1: Health Check
```bash
# Full health check
ansible-playbook health.yml

# Check specific components
ansible-playbook health.yml --tags swarm
ansible-playbook health.yml --tags cache
ansible-playbook health.yml --tags database
```

### Example 2: Create Multiple Sites
```bash
# Site 1
ansible-playbook site.yml -e domain=site1.example.com
ansible-playbook dns.yml -e domain=site1.example.com

# Site 2
ansible-playbook site.yml -e domain=site2.example.com
ansible-playbook dns.yml -e domain=site2.example.com

# Site 3
ansible-playbook site.yml -e domain=site3.example.com
ansible-playbook dns.yml -e domain=site3.example.com
```

### Example 3: Backups
```bash
# Database backup
ansible-playbook backup.yml --tags database

# WordPress files backup
ansible-playbook backup.yml --tags wordpress

# All backups
ansible-playbook backup.yml

# Cleanup old backups
ansible-playbook backup.yml --tags cleanup

# Check backup health
ansible-playbook backup.yml --tags verify
```

### Example 4: Incremental Deployment
```bash
# Just deploy cache layer
ansible-playbook deploy.yml --tags cache

# Just update monitoring
ansible-playbook deploy.yml --tags monitoring

# Deploy multiple stacks
ansible-playbook deploy.yml --tags cache,database,monitoring
```

---

## 🔧 Common Tasks

### Check Infrastructure Status
```bash
# List all nodes
ansible-inventory --list

# Visual tree
ansible-inventory --graph

# Ping all nodes
ansible all_nodes -m ping

# Check Docker on all nodes
ansible all_nodes -m shell -a "docker info"
```

### Run Ad-hoc Commands
```bash
# Check uptime
ansible all_nodes -m shell -a "uptime"

# Check disk space
ansible all_nodes -m shell -a "df -h"

# Check memory
ansible cache_nodes -m shell -a "free -h"

# Docker service status
ansible swarm_managers[0] -m shell -a "docker service ls"
```

### Deploy to Specific Nodes
```bash
# Only manager nodes
ansible-playbook deploy.yml --limit swarm_managers

# Only one worker
ansible-playbook deploy.yml --limit wp-worker-01

# Only cache nodes
ansible-playbook deploy.yml --limit cache_nodes
```

### Test Before Applying
```bash
# Dry run (shows what would change)
ansible-playbook deploy.yml --check

# With diff
ansible-playbook deploy.yml --check --diff

# Verbose output
ansible-playbook deploy.yml -v
```

---

## 🆚 Ansible vs Bash Script

| Task | Bash Command | Ansible Command |
|------|-------------|-----------------|
| **Provision all** | `./manage-infrastructure.sh provision --all` | `ansible-playbook provision.yml` |
| **Deploy all** | `./manage-infrastructure.sh deploy --all` | `ansible-playbook deploy.yml` |
| **Init Swarm** | `./manage-infrastructure.sh init-swarm` | `ansible-playbook deploy.yml --tags swarm` |
| **Health check** | `./manage-infrastructure.sh health` | `ansible-playbook health.yml` |
| **Create site** | `./manage-infrastructure.sh site --create X` | `ansible-playbook site.yml -e domain=X` |
| **Backup** | `./manage-infrastructure.sh backup --now` | `ansible-playbook backup.yml` |

**Key Differences:**
- ✅ Ansible is **idempotent** (safe to re-run)
- ✅ Ansible has **check mode** (preview changes)
- ✅ Ansible is **parallel** by default (faster)
- ✅ Ansible is **declarative** (easier to understand)

---

## ⚠️ Important Notes

### Before You Deploy

1. **Cost Warning**
   - Full deployment creates **33 droplets**
   - Monthly cost: **$3,613**
   - Make sure you understand the cost!

2. **Environment Setup**
   - Configure `.env` file first
   - Set `DO_API_TOKEN`
   - Set `CF_API_TOKEN` (if using DNS features)
   - Generate secure passwords

3. **Test First**
   - Consider testing in a separate DO project
   - Or use smaller node counts for testing:
     ```bash
     ansible-playbook provision.yml \
       -e manager_node_count=1 \
       -e worker_node_count=2 \
       -e cache_node_count=1 \
       -e database_node_count=1 \
       -e storage_node_count=1 \
       -e monitor_node_count=1
     ```

### During Deployment

- Provisioning takes **15-20 minutes**
- Deployment takes **20-25 minutes**
- Total time: **~45 minutes**
- Playbooks show progress in real-time
- Can be run unattended (no interactive prompts)

### After Deployment

1. **Verify everything**
   ```bash
   ansible-playbook health.yml
   ```

2. **Access services**
   - Grafana: `https://grafana.yourdomain.com`
   - Portainer: `https://portainer.yourdomain.com`

3. **Create sites**
   ```bash
   ansible-playbook site.yml -e domain=example.com
   ```

---

## 🐛 Troubleshooting

### "Ansible not found"
```bash
sudo apt update
sudo apt install ansible
```

### "Collection not found"
```bash
ansible-galaxy collection install -r requirements.yml
```

### "DO_API_TOKEN not set"
```bash
cd /var/opt/manage/control-center
nano .env  # Add DO_API_TOKEN=your_token
```

### "SSH connection failed"
```bash
# Wait for droplets to boot
sleep 120

# Or check manually
ssh -i ~/.ssh/wp-farm-key root@<ip>
```

### "Dynamic inventory empty"
```bash
# Check doctl works
doctl compute droplet list

# Clear cache
rm -rf /tmp/ansible_digitalocean_cache

# Refresh
ansible-inventory --list
```

**More troubleshooting:** See `README.md` section on troubleshooting

---

## 📞 Need Help?

1. **Check documentation**
   - `README.md` - Complete guide
   - `MIGRATION-GUIDE.md` - Bash → Ansible
   - `ANSIBLE-SUMMARY.md` - Technical details

2. **Test commands**
   ```bash
   # Check connectivity
   ansible all_nodes -m ping
   
   # Check inventory
   ansible-inventory --list
   
   # Verify syntax
   ansible-playbook deploy.yml --syntax-check
   ```

3. **Verbose output**
   ```bash
   ansible-playbook deploy.yml -vvv
   ```

4. **Community resources**
   - [Ansible Docs](https://docs.ansible.com/)
   - [DigitalOcean Collection](https://docs.ansible.com/ansible/latest/collections/community/digitalocean/)

---

## ✅ Checklist

Before first deployment:

- [ ] Ansible installed (`ansible --version`)
- [ ] Collections installed (`ansible-galaxy collection list`)
- [ ] `.env` file configured
- [ ] `DO_API_TOKEN` set
- [ ] `doctl` authenticated (`doctl auth list`)
- [ ] Understand the cost ($3,613/month for 33 nodes)
- [ ] Read `README.md`

Ready to deploy!

---

## 🎉 Quick Win

Want to see Ansible in action quickly?

```bash
# 1. Check prerequisites (30 seconds)
./quick-start.sh check

# 2. Test inventory (if you have existing droplets)
ansible-inventory --graph

# 3. If no droplets, do a small test (10 minutes)
ansible-playbook provision.yml \
  -e manager_node_count=1 \
  -e worker_node_count=1 \
  --tags managers,workers

# 4. Deploy to test droplets (5 minutes)
ansible-playbook deploy.yml --tags base,docker

# 5. Verify
ansible-playbook health.yml --tags nodes

# 6. Clean up
# (destroy via DO console)
```

---

## 🚀 Next Steps

1. ✅ You are here: Getting Started
2. ⏳ Run `./quick-start.sh check`
3. ⏳ Read `README.md` (your main reference)
4. ⏳ Test deployment (small scale first)
5. ⏳ Full production deployment
6. ⏳ Create WordPress sites
7. ⏳ Train team on Ansible commands
8. ⏳ Enjoy fully automated infrastructure! 🎉

---

**Ready?** Run:

```bash
cd /var/opt/manage/control-center/ansible
./quick-start.sh check
```

Then read `README.md` for complete documentation.

**Good luck! 🚀**
