# Migration Guide: Bash to Ansible

**Complete guide for transitioning from the bash script infrastructure management to Ansible.**

---

## 🎯 Why Migrate?

### Benefits of Ansible

✅ **Idempotent** - Safe to re-run without side effects  
✅ **Declarative** - Describe desired state, not steps  
✅ **Testable** - Check mode and diff preview changes  
✅ **Parallel** - Native multi-node execution  
✅ **Maintainable** - Roles and modularity  
✅ **Industry Standard** - Team likely already knows it  
✅ **Error Recovery** - Better failure handling  

### When to Migrate

- ✅ New infrastructure deployment
- ✅ Team comfortable with Ansible
- ✅ Need better change management
- ✅ Want automated testing
- ⚠️ Existing infrastructure works - consider leaving it

---

## 📊 Command Mapping

### Provisioning

| Bash Script | Ansible |
|-------------|---------|
| `./manage-infrastructure.sh provision --all` | `ansible-playbook provision.yml` |
| `./manage-infrastructure.sh provision --managers` | `ansible-playbook provision.yml --tags managers` |
| `./manage-infrastructure.sh provision --workers` | `ansible-playbook provision.yml --tags workers` |
| `./manage-infrastructure.sh provision --cache` | `ansible-playbook provision.yml --tags cache` |

### Deployment

| Bash Script | Ansible |
|-------------|---------|
| `./manage-infrastructure.sh init-swarm` | `ansible-playbook deploy.yml --tags swarm,init` |
| `./manage-infrastructure.sh join-nodes` | `ansible-playbook deploy.yml --tags swarm,join` |
| `./manage-infrastructure.sh label-nodes` | `ansible-playbook deploy.yml --tags labels` |
| `./manage-infrastructure.sh create-networks` | `ansible-playbook deploy.yml --tags networks` |
| `./manage-infrastructure.sh deploy --all` | `ansible-playbook deploy.yml --tags stacks` |
| `./manage-infrastructure.sh deploy --stack traefik` | `ansible-playbook deploy.yml --tags traefik` |

### Site Management

| Bash Script | Ansible |
|-------------|---------|
| `./manage-infrastructure.sh site --create example.com` | `ansible-playbook site.yml -e domain=example.com` |
| `./manage-infrastructure.sh site --delete example.com` | `ansible-playbook site.yml -e domain=example.com -e state=absent` |

### Operations

| Bash Script | Ansible |
|-------------|---------|
| `./manage-infrastructure.sh health` | `ansible-playbook health.yml` |
| `./manage-infrastructure.sh backup --now` | `ansible-playbook backup.yml` |
| `./manage-infrastructure.sh backup --now database` | `ansible-playbook backup.yml --tags database` |
| `./manage-infrastructure.sh backup --cleanup` | `ansible-playbook backup.yml --tags cleanup` |

### Interactive Features

Bash script has interactive pauses. In Ansible:

```bash
# Bash (interactive)
./manage-infrastructure.sh provision --all

# Ansible (check first, then run)
ansible-playbook provision.yml --check  # Preview
ansible-playbook provision.yml          # Execute
```

---

## 🔄 Step-by-Step Migration

### Phase 1: Preparation (1-2 hours)

1. **Install Ansible**
   ```bash
   sudo apt update
   sudo apt install ansible
   
   # Verify
   ansible --version  # Should be 2.9+
   ```

2. **Install Collections**
   ```bash
   cd /var/opt/manage/control-center/ansible
   ansible-galaxy collection install -r requirements.yml
   ```

3. **Verify Environment**
   ```bash
   # Test existing .env works
   cd /var/opt/manage/control-center
   set -a
   source .env
   set +a
   
   # Verify variables
   echo $DO_API_TOKEN
   echo $CF_API_TOKEN
   ```

4. **Test Inventory**
   ```bash
   cd ansible
   ansible-inventory --list
   ansible-inventory --graph
   ```

---

### Phase 2: Parallel Testing (1-2 days)

**Do NOT migrate production immediately. Test first!**

1. **Create Test Environment**
   ```bash
   # Option A: Separate DO project
   # Option B: Different region
   # Option C: Smaller scale (1 of each node)
   
   # Copy .env for testing
   cp ../.env ../test.env
   nano ../test.env  # Modify for test
   ```

2. **Test Provision**
   ```bash
   # Load test environment
   set -a
   source ../test.env
   set +a
   
   # Dry run
   ansible-playbook provision.yml --check
   
   # Provision test infrastructure
   ansible-playbook provision.yml
   
   # Compare with bash script output
   ```

3. **Test Deploy**
   ```bash
   # Deploy services
   ansible-playbook deploy.yml
   
   # Verify
   ansible-playbook health.yml
   ```

4. **Test Site Creation**
   ```bash
   ansible-playbook site.yml -e domain=test.example.com
   ansible-playbook dns.yml -e domain=test.example.com
   ```

5. **Document Differences**
   - Timing differences
   - Output differences
   - Any errors encountered
   - Workarounds needed

---

### Phase 3: Production Migration (Planned Maintenance)

#### Option A: New Infrastructure (Recommended)

**Safest approach: Deploy fresh alongside old.**

1. **Deploy New Infrastructure**
   ```bash
   # Full deployment
   ansible-playbook provision.yml
   ansible-playbook deploy.yml
   ```

2. **Migrate Sites**
   ```bash
   # For each site:
   # 1. Backup on old infrastructure
   # 2. Create on new infrastructure
   ansible-playbook site.yml -e domain=site1.example.com
   
   # 3. Restore data
   # 4. Test thoroughly
   # 5. Update DNS
   ansible-playbook dns.yml -e domain=site1.example.com
   ```

3. **Gradual Cutover**
   - Move 10% of sites first
   - Monitor for 24-48 hours
   - Move remainder if successful

4. **Decommission Old**
   ```bash
   # After 1-2 weeks of stability
   # Destroy old infrastructure via DO console
   ```

#### Option B: In-Place Adoption (Advanced)

**Riskier: Use Ansible to manage existing infrastructure.**

1. **Tag Existing Droplets**
   ```bash
   # Add tags via doctl or DO console
   doctl compute droplet tag <droplet-id> --tag-names wordpress-farm,manager
   ```

2. **Verify Inventory**
   ```bash
   ansible-inventory --list
   # Should show existing nodes
   ```

3. **Run Deploy (Idempotent)**
   ```bash
   # Check mode first!
   ansible-playbook deploy.yml --check
   
   # Apply (should be no-op for already configured items)
   ansible-playbook deploy.yml
   ```

4. **Verify Health**
   ```bash
   ansible-playbook health.yml
   ```

5. **Document State**
   - What changed
   - What stayed the same
   - Any issues

---

## 🔑 Key Differences

### Environment Variables

**Bash Script:**
- Sourced directly: `source .env`
- Used in scripts: `$DO_API_TOKEN`

**Ansible:**
- Loaded via `group_vars/all.yml`
- Used with lookup: `"{{ lookup('env', 'DO_API_TOKEN') }}"`
- Can also use Ansible Vault for secrets

### Interactive Pauses

**Bash Script:**
```bash
interactive_pause "Stage Name" "Instructions"
# User must press C to continue
```

**Ansible:**
```bash
# No pauses - use check mode instead
ansible-playbook deploy.yml --check  # Preview
ansible-playbook deploy.yml          # Run
```

If you need pauses:
```yaml
- name: Pause for verification
  pause:
    prompt: "Check the output, then press enter to continue"
```

### Verification Scripts

**Bash Script:**
- Copies scripts to `/opt/verify/`
- User manually runs them

**Ansible:**
- Integrated into playbooks
- `ansible-playbook health.yml` does the checks

Both approaches co-exist. Verification scripts still copied for manual use.

### Error Handling

**Bash Script:**
```bash
set -euo pipefail
# Script exits on any error
```

**Ansible:**
- Continues by default
- Use `ignore_errors: true` if needed
- Better reporting of what succeeded/failed

### Parallelization

**Bash Script:**
```bash
command &  # Background process
wait       # Wait for all
```

**Ansible:**
- Automatic with forks (20 by default)
- Async/poll for long-running tasks
- Much faster for multi-node operations

---

## 📝 Configuration Mapping

### .env Variables → group_vars/all.yml

All environment variables are automatically loaded:

```yaml
# group_vars/all.yml
do_api_token: "{{ lookup('env', 'DO_API_TOKEN') }}"
do_region: "{{ lookup('env', 'DO_REGION') | default('nyc3', true) }}"
```

No changes needed to `.env` file!

### Node Counts

**Bash (.env):**
```bash
MANAGER_NODE_COUNT=3
WORKER_NODE_COUNT=20
```

**Ansible (same):**
```yaml
manager_node_count: "{{ lookup('env', 'MANAGER_NODE_COUNT') | default('3', true) | int }}"
```

Reads from same `.env` file.

---

## 🧪 Testing Strategy

### Pre-Migration Tests

```bash
# 1. Test connectivity
ansible all_nodes -m ping

# 2. Test privilege escalation
ansible all_nodes -m shell -a "whoami" --become

# 3. Test Docker access
ansible all_nodes -m shell -a "docker info"

# 4. Test Swarm status
ansible swarm_managers[0] -m shell -a "docker node ls"
```

### Post-Migration Tests

```bash
# 1. Health check
ansible-playbook health.yml

# 2. Create test site
ansible-playbook site.yml -e domain=test-$(date +%s).example.com

# 3. Verify backups
ansible-playbook backup.yml --tags verify

# 4. Verify monitoring
# Check Grafana dashboards
# Check Alertmanager
```

---

## 🚨 Rollback Plan

If Ansible deployment fails:

1. **Keep Bash Script Available**
   ```bash
   # Keep old script accessible
   cp scripts/manage-infrastructure.sh scripts/manage-infrastructure.sh.backup
   ```

2. **Document Current State**
   ```bash
   # Before migration
   ./scripts/manage-infrastructure.sh health > pre-migration-state.txt
   ```

3. **Rollback Method**
   
   **Option A: Revert Changes**
   - Stop Ansible-deployed services
   - Restart bash-deployed services
   
   **Option B: Rebuild**
   - Destroy infrastructure
   - Redeploy with bash script

4. **Data Safety**
   - Always backup before major changes
   - Keep multiple backup generations
   - Test restore procedure

---

## ⏱️ Timeline Comparison

### Bash Script Deployment
- Provision: 15-20 minutes
- Deploy: 20-25 minutes
- Total: **35-45 minutes**
- Interactive: Yes (multiple pauses)

### Ansible Deployment
- Provision: 15-20 minutes
- Deploy: 15-20 minutes (faster due to parallelization)
- Total: **30-40 minutes**
- Interactive: No (can run unattended)

**Speedup:** ~10-15% faster, fully automated

---

## 📚 Training Team

### For Bash Script Users

1. **Concept Mapping**
   - Bash function → Ansible task
   - Script → Playbook
   - Verification scripts → Health playbook

2. **Common Operations**
   ```bash
   # Old way
   ./manage-infrastructure.sh provision --all
   ./manage-infrastructure.sh deploy --all
   
   # New way
   ansible-playbook provision.yml
   ansible-playbook deploy.yml
   ```

3. **Troubleshooting**
   ```bash
   # Old way
   ssh root@<ip> "docker service logs <name>"
   
   # New way (same, or)
   ansible swarm_managers[0] -m shell \
     -a "docker service logs <name> --tail 50"
   ```

### Learning Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [DigitalOcean Collection](https://docs.ansible.com/ansible/latest/collections/community/digitalocean/)

---

## ✅ Migration Checklist

### Pre-Migration
- [ ] Ansible installed and tested
- [ ] Collections installed
- [ ] Team trained on basics
- [ ] Test environment validated
- [ ] Rollback plan documented
- [ ] Backups verified

### Migration
- [ ] Provision test infrastructure
- [ ] Deploy services
- [ ] Run health checks
- [ ] Create test sites
- [ ] Load test
- [ ] Compare with bash deployment
- [ ] Document any issues

### Post-Migration
- [ ] Update runbooks
- [ ] Update alerting/monitoring
- [ ] Train team on new commands
- [ ] Deprecate bash script (but keep as backup)
- [ ] Monitor for issues (1-2 weeks)
- [ ] Celebrate! 🎉

---

## 🎓 Pro Tips

1. **Keep Both Methods Initially**
   - Run Ansible for new deployments
   - Keep bash script for emergency fixes
   - Gradually phase out bash after confidence

2. **Use Check Mode Liberally**
   ```bash
   ansible-playbook deploy.yml --check --diff
   ```

3. **Start with Health Checks**
   ```bash
   # Always verify before changes
   ansible-playbook health.yml
   ```

4. **Tag Everything**
   ```bash
   # Run just what you need
   ansible-playbook deploy.yml --tags cache,database
   ```

5. **Use Limits**
   ```bash
   # Test on one node first
   ansible-playbook deploy.yml --limit wp-worker-01
   ```

---

## 🆘 Getting Help

**Ansible-Specific Issues:**
- Check playbook syntax: `ansible-playbook --syntax-check provision.yml`
- Validate inventory: `ansible-inventory --list`
- Test connectivity: `ansible all -m ping`

**Infrastructure Issues:**
- Same as before - check Docker, Swarm, services
- Health playbook covers most checks

**Migration Issues:**
- Compare bash script output vs Ansible
- Check for environment variable differences
- Verify tag-based inventory grouping

---

## 📊 Success Metrics

Migration is successful when:

- ✅ All playbooks run without errors
- ✅ Health checks pass
- ✅ Sites are accessible
- ✅ Backups work
- ✅ Monitoring shows healthy state
- ✅ Team comfortable with Ansible commands
- ✅ Run time <= bash script time
- ✅ Zero downtime migration (if in-place)

---

**Ready to migrate?** Start with Phase 1 (Preparation) and move at your own pace!

📞 **Need help?** Review the troubleshooting section in README.md

🚀 **Good luck!**
