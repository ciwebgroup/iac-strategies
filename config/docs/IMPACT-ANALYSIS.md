# Impact Analysis: Sonnet 4.5 Modified Strategy

## Executive Summary

This document analyzes the impact of proposed modifications to the Sonnet 4.5 WordPress farm architecture. The changes represent a **hybrid cloud/on-premise** approach that significantly alters cost structure, complexity, and capabilities.

**Modification Summary:**
1. Adopt Opus 4.5 dedicated cache tier (Varnish)
2. Add Proxmox Virtual Environment (PVE) with CephFS
3. Replace GlusterFS with CephFS
4. Add comprehensive alerting (Slack/Email/SMS)
5. Create full automation/orchestration tooling

**Overall Impact:** 🟡 MODERATE-HIGH (Architectural paradigm shift)

---

## 🎯 Modification 1: Adopt Opus 4.5 Varnish Implementation

### Change Description
Move from **co-located Varnish** (on manager nodes) to **dedicated cache tier** (3 separate cache nodes)

### Architectural Impact

#### ✅ Positive Impacts
1. **Better Performance Isolation**
   - Cache tier gets dedicated 16GB RAM × 3 = 48GB for caching
   - No resource contention with Traefik/Swarm control plane
   - Predictable cache performance under load

2. **Improved Observability**
   - Clear metric separation between routing and caching
   - Easier troubleshooting (isolated components)
   - Better Grafana dashboards

3. **Independent Scaling**
   - Can scale cache tier without touching control plane
   - Add cache capacity as traffic grows
   - Better granular control

4. **Higher Availability**
   - Cache failures don't affect Swarm managers
   - Reduced blast radius
   - Better fault isolation

#### ❌ Negative Impacts
1. **Increased Cost**
   - +3 cache nodes × $96/month = **+$288/month**
   - Total cost: $3,419 → **$3,707/month**
   - Cost per site: $6.84 → **$7.41/site**

2. **Added Latency**
   - Extra network hop: Traefik → Varnish → WordPress
   - Estimated +1-2ms per request
   - Mitigated by better cache hit ratios

3. **Increased Complexity**
   - More nodes to manage (30 → 33 nodes)
   - Additional health checks and monitoring
   - More components in deployment pipeline

4. **More Networks**
   - Need dedicated `cache-net` overlay network
   - Additional network configuration
   - More firewall rules

### Impact on Other Components

| Component | Impact | Severity | Notes |
|-----------|--------|----------|-------|
| **Traefik** | Modified | 🟡 Medium | Must route to Varnish instead of direct to WordPress |
| **WordPress** | Modified | 🟢 Low | Backend config unchanged, just upstream changes |
| **Monitoring** | Enhanced | 🟢 Low | Better metrics, need cache-specific dashboards |
| **Cost Model** | Increased | 🟠 High | +8.3% cost increase |
| **Network Topology** | Modified | 🟡 Medium | New cache subnet, additional overlay network |
| **Deployment** | More Complex | 🟡 Medium | Additional stack to deploy |

### Recommendation
✅ **APPROVE** - The benefits outweigh costs for a production 500-site farm. The $288/month is insurance against performance issues and provides superior observability.

**Conditions:**
- Implement comprehensive cache monitoring
- Create runbooks for cache tier operations
- Set up proper alerting for cache health

---

## 🎯 Modification 2: Add Proxmox Virtual Environment (PVE)

### Change Description
Introduce **Proxmox VE as hybrid infrastructure** alongside DigitalOcean

### Architectural Impact

#### 🔴 CRITICAL: Infrastructure Paradigm Shift

This changes the **entire deployment model** from:
- **Pure Cloud (DigitalOcean)** → **Hybrid Cloud/On-Premise**

#### ✅ Positive Impacts

1. **Cost Savings (Long-term)**
   - On-prem hardware amortizes over 3-5 years
   - No per-droplet charges for compute
   - Potential 40-60% cost reduction at scale
   - Control over hardware lifecycle

2. **Performance Benefits**
   - Dedicated hardware (no noisy neighbors)
   - Better disk I/O with local NVMe
   - Customizable network topology
   - Lower latency between nodes (local network)

3. **Control & Flexibility**
   - Full hardware control
   - Custom networking (VLANs, etc.)
   - GPU support (if needed for image processing)
   - No vendor lock-in

4. **Better for CephFS**
   - Proxmox + Ceph is a proven combination
   - Integrated management
   - Better performance than GlusterFS over network

#### ❌ Negative Impacts

1. **Significantly Increased Complexity** 🔴
   - Manage physical hardware
   - Datacenter/power/cooling considerations
   - Hardware failures require hands-on intervention
   - Need spare hardware inventory
   - Requires on-site or remote hands

2. **Upfront Capital Costs** 💰
   - Hardware purchase: $50,000-$100,000 for 30 nodes
   - Networking equipment: $10,000-$20,000
   - Rack space rental (if colo): $500-$2,000/month
   - Power costs: $500-$1,500/month

3. **Operational Overhead**
   - Need experienced Proxmox/Ceph administrator
   - 24/7 monitoring required
   - Physical access needed for hardware issues
   - Longer MTTR (mean time to repair)

4. **Mixed Infrastructure Challenges**
   - Hybrid cloud = double complexity
   - Need VPN/interconnect between PVE and DO
   - Split-brain scenarios possible
   - Backup strategies more complex

5. **No Auto-Scaling**
   - Can't instantly provision nodes like DO
   - Capacity planning more critical
   - Hardware lead times (weeks)

### Deployment Options

#### Option A: Pure Proxmox (Replace DO Entirely)
```
Pros:
+ Maximum cost savings
+ Unified platform
+ Simpler architecture

Cons:
- Lose DO benefits (auto-scaling, managed services)
- Single datacenter (unless multi-site PVE)
- All eggs in one basket
```

#### Option B: Hybrid (PVE for compute, DO for edge/backup)
```
Pros:
+ Best of both worlds
+ Use DO for edge (Traefik), PVE for workers
+ DO Spaces for backups (cost-effective)
+ Fail-over options

Cons:
- Most complex architecture
- Need VPN/interconnect
- Latency between PVE and DO
- Double learning curve
```

#### Option C: PVE for Dev/Staging, DO for Production
```
Pros:
+ Lower cost for non-prod
+ Test PVE before committing
+ Production stays stable on DO

Cons:
- Environments not identical (drift risk)
- Still managing two platforms
```

### Impact on Other Components

| Component | Impact | Severity | Notes |
|-----------|--------|----------|-------|
| **Cost Structure** | Fundamentally Changed | 🔴 Critical | CapEx vs OpEx model shift |
| **Deployment** | Completely Different | 🔴 Critical | Can't use DO API, need Proxmox API |
| **Networking** | More Complex | 🟠 High | VPN/interconnect needed for hybrid |
| **Disaster Recovery** | More Complex | 🟠 High | Multiple backup paths |
| **Team Skills** | New Requirements | 🟠 High | Need Proxmox/Ceph expertise |
| **Automation** | Rewrite Required | 🔴 Critical | Different APIs, different tooling |
| **Scaling** | Slower | 🟡 Medium | Hardware procurement delays |

### Recommendation

⚠️ **CONDITIONAL APPROVAL** - Only if:

1. **You have dedicated datacenter space** (colo or on-prem)
2. **Team has Proxmox/Ceph experience** (or budget for training)
3. **Hardware budget available** ($60,000-$120,000 initial)
4. **3-5 year commitment** (for ROI)
5. **24/7 operations capability** (on-call staff)

**Alternative Recommendation:**
- **Start with Pure DO** (current Sonnet 4.5)
- **Pilot PVE for dev/staging** environment
- **Evaluate for 6 months** before production migration
- **Keep DO as fallback** during transition

**If proceeding with PVE:**
- Use **Option B (Hybrid)** for best risk mitigation
- Keep Traefik/edge on DO for DDoS protection
- Run workers/database on PVE
- Use DO Spaces for backups regardless

---

## 🎯 Modification 3: Replace GlusterFS with CephFS

### Change Description
Migrate from **GlusterFS** to **CephFS** for distributed storage

### Architectural Impact

#### ✅ Positive Impacts

1. **Better Performance**
   - CephFS generally faster for metadata operations
   - Better small file performance
   - Improved concurrent access
   - Native kernel driver (less overhead)

2. **More Mature Ecosystem**
   - Ceph is industry standard (used by OpenStack, etc.)
   - Better tooling and monitoring
   - Larger community
   - More documentation

3. **Integrated with Proxmox**
   - Native integration if using PVE
   - Unified management interface
   - Easier backup integration
   - Better resource monitoring

4. **Object Storage Bonus**
   - Ceph provides RGW (S3-compatible object storage)
   - Can replace DO Spaces for backups
   - Multi-protocol: Block, File, Object
   - Unified storage platform

5. **Better Reliability**
   - More sophisticated failure detection
   - Faster recovery from node failures
   - Better data balancing
   - Self-healing capabilities

#### ❌ Negative Impacts

1. **Higher Resource Requirements**
   - Ceph more RAM-hungry (recommend 32GB per node)
   - Need separate monitoring nodes (Ceph monitors)
   - Minimum 3 MON + 3 OSD nodes (vs 2 GlusterFS)
   - Higher CPU overhead

2. **Increased Complexity**
   - More components (MON, OSD, MDS, MGR)
   - Steeper learning curve
   - More moving parts to troubleshoot
   - Complex tuning required

3. **Network Requirements**
   - Needs separate cluster network (10Gbps recommended)
   - Public + cluster network (2 networks)
   - Higher bandwidth requirements
   - More network planning needed

4. **Deployment Complexity**
   - More complex initial setup
   - Requires careful planning (CRUSH maps, PG counts)
   - Harder to migrate existing data
   - More prerequisites

### Technical Comparison

| Feature | GlusterFS | CephFS | Winner |
|---------|-----------|--------|--------|
| **Ease of Setup** | ⭐⭐⭐⭐ | ⭐⭐ | GlusterFS |
| **Performance** | ⭐⭐⭐ | ⭐⭐⭐⭐ | CephFS |
| **RAM Usage** | 8GB/node | 16-32GB/node | GlusterFS |
| **Minimum Nodes** | 2 | 3 (MON) + 3 (OSD) | GlusterFS |
| **Feature Set** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | CephFS |
| **Community** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | CephFS |
| **Monitoring** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | CephFS |
| **Recovery Speed** | ⭐⭐⭐ | ⭐⭐⭐⭐ | CephFS |
| **Complexity** | ⭐⭐ | ⭐⭐⭐⭐⭐ | GlusterFS |

### New Resource Requirements

#### Original (GlusterFS - 2 nodes)
```
Storage Nodes: 2 × 16GB/8vCPU = $192/month
Block Storage: 2TB × 2 = 4TB = $400/month
Total: $592/month
```

#### With CephFS (Minimum 3 nodes)
```
Ceph MON nodes: 3 × 16GB/8vCPU = $288/month
Ceph OSD nodes: 3 × 32GB/8vCPU = $432/month (need more RAM)
Block Storage: 1TB × 3 (OSD) = 3TB = $300/month
Total: $1,020/month (+$428/month increase)
```

### Impact on Other Components

| Component | Impact | Severity | Notes |
|-----------|--------|----------|-------|
| **Cost** | +$428/month | 🟠 High | 72% increase in storage costs |
| **Node Count** | +1 node minimum | 🟡 Medium | 2 → 3+ nodes |
| **Memory** | 2x requirement | 🟠 High | Need 32GB nodes for OSD |
| **Network** | New subnet needed | 🟡 Medium | Ceph cluster network |
| **Monitoring** | Enhanced | 🟢 Low | Better dashboards available |
| **WordPress** | Transparent | 🟢 Low | Mount point same, just backend changes |
| **Backup** | Simplified | 🟢 Low | Can use RGW for object storage |
| **Deployment** | More Complex | 🟠 High | More initial setup |

### Recommendation

⚠️ **CONDITIONAL** - Depends on Proxmox decision:

**If using Proxmox:**
✅ **APPROVE CephFS** - Native integration makes this the obvious choice
- Unified management
- Better performance
- Worth the complexity

**If staying pure DigitalOcean:**
❌ **REJECT CephFS** - Stay with GlusterFS
- Not worth 72% cost increase
- Added complexity not justified
- GlusterFS is "good enough"
- Easier to manage

**Hybrid Recommendation:**
- Use CephFS on Proxmox nodes (on-prem storage)
- Keep GlusterFS or use DO Spaces for DO-hosted resources
- Don't try to span CephFS across PVE and DO (too complex)

---

## 🎯 Modification 4: Comprehensive Alerting (Slack/Email/SMS)

### Change Description
Add multi-channel alerting system using Slack, SendGrid, and Twilio

### Architectural Impact

#### ✅ Positive Impacts

1. **Better Incident Response**
   - Multiple notification channels
   - Right message to right person/channel
   - Reduced MTTR (mean time to respond)
   - 24/7 awareness

2. **Flexible Alert Routing**
   - Critical alerts → SMS (PagerDuty style)
   - Warnings → Slack
   - Reports → Email
   - Different severity levels

3. **Team Coordination**
   - Slack for team visibility
   - Threaded conversations
   - Historical alert log
   - Better collaboration

4. **Business Continuity**
   - Redundant channels (if Slack down, SMS works)
   - Escalation paths
   - On-call rotation support

#### ❌ Negative Impacts

1. **Additional Costs**
   - SendGrid: $15-90/month (Pro plan)
   - Twilio SMS: $0.0075/SMS (estimate $50-100/month)
   - Total: **~$65-190/month additional**

2. **Alert Fatigue Risk**
   - Too many channels = ignored alerts
   - Need careful threshold tuning
   - Requires ongoing maintenance
   - Can become noisy

3. **Configuration Complexity**
   - Multiple integrations to set up
   - Need secret management
   - Testing required
   - More things to break

### Implementation Components

```yaml
Alertmanager:
  - Slack receiver (webhook)
  - Email receiver (SendGrid SMTP)
  - Webhook receiver → custom SMS bridge (Twilio)
  
Alert Routing:
  - severity: critical → SMS + Slack
  - severity: warning → Slack
  - severity: info → Email daily digest
  
Throttling:
  - Group alerts (prevent spam)
  - Cooldown periods
  - Time-based routing (business hours vs after-hours)
```

### Impact on Other Components

| Component | Impact | Severity | Notes |
|-----------|--------|----------|-------|
| **Alertmanager** | Extended | 🟢 Low | Add receivers, no core changes |
| **Prometheus** | Enhanced | 🟢 Low | More alert rules |
| **Grafana** | Enhanced | 🟢 Low | Better annotations |
| **Cost** | +$65-190/month | 🟡 Medium | New service fees |
| **Security** | New Secrets | 🟡 Medium | API keys for SendGrid/Twilio |
| **Operations** | Improved | 🟢 Low | Better awareness |

### Recommendation

✅ **APPROVE** - This is a no-brainer for production

**Priority Implementation:**
1. **Start with Slack only** (free, easy)
2. **Add Email** (SendGrid free tier works for alerts)
3. **Add SMS last** (most expensive, only for critical)

**Best Practices:**
- Start with conservative thresholds (avoid alert fatigue)
- Use alert grouping/deduplication
- Implement quiet hours for non-critical alerts
- Create escalation policies
- Weekly review of alert effectiveness

**Estimated Cost:** $20-50/month (conservative use)

---

## 🎯 Modification 5: Full Automation with Orchestration Script

### Change Description
Create comprehensive `manage-infrastructure.sh` script for complete automation

### Architectural Impact

#### ✅ Positive Impacts

1. **Operational Efficiency**
   - One-command deployment
   - Reduces human error
   - Faster operations
   - Repeatable processes

2. **Disaster Recovery**
   - Rebuild infrastructure quickly
   - Documented in code
   - Tested procedures
   - Reliable recovery

3. **Scaling**
   - Add nodes with single command
   - Consistent configuration
   - Faster provisioning
   - Less manual work

4. **Documentation**
   - Script IS the documentation
   - Self-documenting
   - Always up-to-date
   - Easier onboarding

#### ❌ Negative Impacts

1. **Initial Development Time**
   - Significant effort to create (40-80 hours)
   - Testing required
   - Error handling complexity
   - Maintenance burden

2. **Abstraction Risk**
   - Team may not understand underlying systems
   - Harder to troubleshoot when script fails
   - "Magic box" syndrome
   - Knowledge centralization

3. **Dependency Management**
   - Requires specific tools (doctl, terraform, ansible, etc.)
   - Version compatibility issues
   - Installation prerequisites
   - Environment setup needed

### Recommendation

✅ **APPROVE** - Essential for production operations

**Implementation Strategy:**
1. **Phase 1: Core operations** (deploy, scale, backup)
2. **Phase 2: Monitoring** (health checks, status)
3. **Phase 3: Recovery** (restore, failover)
4. **Phase 4: Advanced** (migrations, upgrades)

**Tool Requirements:**
- `doctl` (DigitalOcean CLI)
- `terraform` (if using IaC)
- `ansible` (configuration management)
- `kubectl` or `docker` (depending on orchestrator)
- Standard Unix tools (jq, curl, ssh)

---

## 📊 Combined Impact Summary

### Cost Comparison

| Configuration | Monthly Cost | Change | Cost/Site |
|---------------|--------------|--------|-----------|
| **Original Sonnet 4.5** | $3,419 | baseline | $6.84 |
| + Dedicated Cache Tier | $3,707 | +$288 | $7.41 |
| + CephFS (DO nodes) | $4,135 | +$428 | $8.27 |
| + Alerting Services | $4,185 | +$50 | $8.37 |
| **Total (Pure DO)** | **$4,185** | **+$766** | **$8.37** |
| | | **(+22%)** | **(+22%)** |

### Proxmox Scenario (Hybrid)

**CapEx (One-time):**
```
30 × Proxmox Nodes (Dell R640 or similar): $75,000
Networking (10Gbps switches): $15,000
Rack/PDU/Cables: $5,000
TOTAL CapEx: $95,000
```

**OpEx (Monthly):**
```
Colo Space (20U): $800/month
Power (5kW): $600/month
Bandwidth (10Gbps): $500/month
DO Services (edge + backup): $500/month
Alerting: $50/month
TOTAL OpEx: $2,450/month
```

**Break-even:** ~17 months (compared to pure DO at $4,185/month)

### Node Count Changes

| Configuration | Managers | Workers | Cache | Database | Storage | Monitor | Total |
|---------------|----------|---------|-------|----------|---------|---------|-------|
| **Original Sonnet** | 3 | 20 | 0 | 3 | 2 | 2 | **30** |
| + Cache Tier | 3 | 20 | **+3** | 3 | 2 | 2 | **33** |
| + CephFS | 3 | 20 | 3 | 3 | **3+** | 2 | **34+** |
| **Total** | **3** | **20** | **3** | **3** | **3** | **2** | **34** |

### Complexity Score (1-10, 10=most complex)

| Configuration | Score | Change | Notes |
|---------------|-------|--------|-------|
| Original Sonnet 4.5 | 6/10 | baseline | Moderate complexity |
| + Dedicated Cache | 7/10 | +1 | More components |
| + CephFS (DO) | 8/10 | +2 | Storage complexity |
| + Proxmox Hybrid | **10/10** | **+4** | Maximum complexity |
| + Alerting | 7.5/10 | +0.5 | Minor increase |
| + Automation | 7/10 | -0.5 | Actually reduces operational complexity |

---

## 🎯 Final Recommendations

### Scenario A: **Pure Cloud (Recommended for Most)**

✅ **Adopt:**
- Dedicated cache tier (Opus 4.5 style)
- Comprehensive alerting
- Full automation scripts
- Stay with GlusterFS
- Stay with DigitalOcean

❌ **Reject:**
- Proxmox (unless you have specific requirements)
- CephFS (not worth cost on DO)

**Result:**
- Cost: $3,757/month ($7.51/site)
- Complexity: 7/10 (manageable)
- Time to deploy: 2-3 weeks
- Team size: 2-3 DevOps engineers

---

### Scenario B: **Hybrid Cloud (For Cost-Conscious at Scale)**

✅ **Adopt:**
- Proxmox for worker nodes (compute)
- CephFS on Proxmox
- DigitalOcean for edge (Traefik) and backups
- Dedicated cache tier
- Comprehensive alerting
- Full automation

**Result:**
- CapEx: $95,000 (one-time)
- OpEx: $2,450/month ($4.90/site)
- Complexity: 10/10 (very high)
- Time to deploy: 2-3 months
- Team size: 4-6 engineers (need Proxmox/Ceph expertise)
- Break-even: 17 months

---

### Scenario C: **Gradual Migration (Lowest Risk)**

**Phase 1 (Months 1-3):** Deploy on pure DigitalOcean
- Sonnet 4.5 + dedicated cache tier
- Alerting + automation
- GlusterFS
- Cost: $3,757/month

**Phase 2 (Months 4-6):** Build Proxmox dev/staging
- Pilot PVE cluster (smaller scale)
- Test CephFS
- Evaluate performance
- Additional cost: ~$500/month (small PVE cluster)

**Phase 3 (Months 7-12):** Migrate non-critical to PVE
- Move dev/staging
- Move low-traffic sites
- Keep production on DO
- Hybrid cost: ~$3,000/month

**Phase 4 (Month 13+):** Full migration decision
- Based on 6 months of PVE experience
- Migrate production if successful
- Or stay hybrid
- Target cost: $2,450/month

---

## ✅ Recommended Strategy: **Scenario A with Path to C**

**Immediate Implementation:**
```
1. Deploy Sonnet 4.5 on DigitalOcean
2. Add dedicated cache tier (Opus 4.5 style)
3. Keep GlusterFS (simpler, adequate)
4. Implement alerting (Slack → Email → SMS)
5. Create automation scripts
```

**Cost:** $3,757/month ($7.51/site)  
**Complexity:** 7/10  
**Timeline:** 3-4 weeks

**Future Option:**
- After 6 months of stable operations
- Evaluate Proxmox for cost reduction
- Pilot on dev/staging first
- Migrate gradually if successful

---

## 🚦 Decision Matrix

| Priority | Implementation | Cost Impact | Complexity | ROI | Decision |
|----------|----------------|-------------|------------|-----|----------|
| **1. Dedicated Cache** | 3 weeks | +$288/mo | +1 | High | ✅ DO IT |
| **2. Alerting** | 1 week | +$50/mo | +0.5 | High | ✅ DO IT |
| **3. Automation** | 4 weeks | $0 | -0.5 | Very High | ✅ DO IT |
| **4. GlusterFS→CephFS** | 2 weeks | +$428/mo | +2 | Low (on DO) | ❌ SKIP (for now) |
| **5. Proxmox** | 3 months | -$1,935/mo* | +4 | Medium** | ⚠️ PILOT FIRST |

\* After break-even period  
\** High ROI if you have datacenter expertise

---

## 📝 Implementation Checklist

### Immediate (Week 1-4)
- [ ] Deploy base Sonnet 4.5 on DigitalOcean
- [ ] Add 3 dedicated cache nodes
- [ ] Configure Varnish + Redis on cache tier
- [ ] Set up Slack alerting
- [ ] Create basic automation script

### Short-term (Month 2-3)
- [ ] Add Email alerting (SendGrid)
- [ ] Enhance automation (all operations)
- [ ] Create comprehensive monitoring dashboards
- [ ] Document runbooks
- [ ] Load testing and optimization

### Medium-term (Month 4-6)
- [ ] Add SMS alerting for critical events
- [ ] Evaluate Proxmox pilot program
- [ ] Create disaster recovery procedures
- [ ] Optimize costs
- [ ] Team training

### Long-term (Month 7-12)
- [ ] Decision: Continue pure cloud or migrate to hybrid
- [ ] If hybrid: Gradual migration to Proxmox
- [ ] If pure cloud: Optimize DO setup
- [ ] Continuous improvement

---

## 🎓 Lessons & Best Practices

1. **Don't Over-Engineer Early**
   - Start simple, add complexity as needed
   - Prove value before large CapEx

2. **Measure Before Migrating**
   - Establish baseline performance on DO
   - Pilot PVE before committing
   - Compare apples to apples

3. **Automate from Day 1**
   - Scripts save time immediately
   - Documentation in code
   - Easier to maintain

4. **Monitor Everything**
   - Can't optimize what you can't measure
   - Alerting prevents surprises
   - Data drives decisions

5. **Plan for Failure**
   - Every component will fail
   - Redundancy at every layer
   - Test recovery procedures

---

## 🎯 My Professional Recommendation

**For a production 500-site WordPress farm:**

**Start with:** Sonnet 4.5 + Dedicated Cache + Alerting + Automation (Pure DO)

**Why:**
- Proven technology stack
- Manageable complexity (7/10)
- Reasonable cost ($7.51/site)
- Fast deployment (3-4 weeks)
- Team of 2-3 can manage
- Low risk

**Don't:**
- Rush into Proxmox without experience
- Migrate to CephFS on cloud infrastructure
- Over-complicate early

**Do Later:**
- Pilot Proxmox after 6 months of stable ops
- Migrate to hybrid if cost reduction justifies complexity
- Add CephFS only if using Proxmox

This gives you:
- ✅ Production-ready in 1 month
- ✅ Excellent performance
- ✅ Good observability
- ✅ Path to lower costs (Proxmox option later)
- ✅ Manageable risk

---

**Next Steps:** Approve this analysis, and I'll proceed with implementation of the recommended components.

