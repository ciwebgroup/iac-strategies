# Deployment Sizing Spec & Recommendations

## Audience and purpose

This document is a decision-grade sizing spec for leadership and platform engineers reviewing the current **Proxmox-on-DigitalOcean + LXC + Docker Swarm** deployment path.

It answers:

1. Why service orchestration and forced updates can take a long time on the current host profile.
2. What minimum/practical/recommended infrastructure specs should be used.
3. What trade-offs exist between a single-host deployment and true high-availability (multi-host) deployment.
4. What near-term changes reduce risk and improve responsiveness.

---

## Executive summary

The current behavior (long-running `docker service update --force`, repeated task restarts, scheduling delays) is consistent with an under-provisioned or tightly constrained environment for the number of services currently being deployed.

### Recommendation in one line

If the current topology remains on a **single Proxmox host**, target at least:

- **16 vCPU**
- **48 GB RAM**
- **500 GB NVMe SSD** (high IOPS)

For smoother operations and fewer scheduling stalls:

- **24 vCPU**
- **64 GB RAM**
- **1 TB NVMe SSD**

If production HA is required, move to **3+ physical/VM hosts** and distribute managers/workers across hosts.

---

## Current architecture context

## Platform model in use

- Proxmox VE running on a DigitalOcean droplet.
- LXC containers used for tiered roles (manager, worker, cache, DB, monitor, storage).
- Docker Swarm running inside those LXCs.
- Multiple stacks deployed from `docker-compose-examples`:
  - `traefik-stack.yml`
  - `cache-stack.yml`
  - `database-stack.yml`
  - `monitoring-stack.yml`
  - `management-stack.yml`
  - `backup-stack.yml`
  - `contractor-access-stack.yml`

### Important constraint

Because this is single Proxmox host–centric today, replicas can improve service continuity inside Swarm, but **cannot** provide full infrastructure HA against host-level failure.

---

## Why the force-update command was slow

The command pattern below (or equivalent through Ansible shell module) triggers expensive orchestration work:

- `docker service update --force <service>` across many services.

For each updated service, Swarm may:

1. Recreate tasks even with no config changes.
2. Re-evaluate placement constraints and reservations.
3. Pull/validate images on nodes.
4. Re-run health checks and backoff policy cycles.
5. Retry around mount/port/constraint failures.

When this occurs across cache + DB + contractor services simultaneously, the cumulative overhead is substantial—especially in LXC-based nodes sharing one host CPU scheduler and storage subsystem.

---

## Observed risk signals from current runs

The deployment sessions showed recurring symptoms typical of constrained environments and config-pressure:

- Services stuck at `0/N` for extended periods.
- Frequent `Preparing`/`Rejected` task states.
- Mount-path mismatch failures requiring file/dir seeding.
- Health-check-driven restart loops.
- Scheduling messages indicating insufficient resources or constraints not satisfied.

These are not just “automation slowness”; they are useful capacity and operability signals.

---

## Sizing profiles

## Profile A — Minimum (POC / non-prod)

Use only for test validation, not business-critical workloads.

- **CPU:** 8 vCPU
- **RAM:** 24 GB
- **Storage:** 300 GB NVMe
- **Intended use:** small integration tests, low traffic, reduced replicas, optional services disabled.

### Caveats

- Frequent scheduling pressure likely.
- Slower recoveries after stack changes.
- Limited room for monitoring + database + cache concurrency.

---

## Profile B — Practical baseline (small production / pilot)

Recommended floor if the stack remains broad and feature-rich.

- **CPU:** 16 vCPU
- **RAM:** 48 GB
- **Storage:** 500 GB NVMe
- **IOPS target:** high random I/O and sustained write throughput (DB + logs + overlays).
- **Intended use:** pilot production with conservative replica counts.

### Why this is practical

- Enough headroom for manager/control-plane activity and bursty restarts.
- Better odds of stable scheduling under moderate stack churn.
- Improved image pull/cache behavior and less swap pressure.

---

## Profile C — Recommended for smoother operations (single host)

If budget permits and you want fewer operational stalls while preserving current topology.

- **CPU:** 24 vCPU
- **RAM:** 64 GB
- **Storage:** 1 TB NVMe
- **IOPS target:** enterprise-tier NVMe performance.
- **Intended use:** sustained testing/staging and limited production with careful SLO expectations.

### Benefits

- Faster recovery after force updates.
- Reduced contention between database, cache, and observability services.
- Better tolerance of concurrent rolling updates.

---

## Profile D — True production HA (multi-host)

Use when uptime commitments and failover guarantees are required.

- **Hosts:** minimum 3 hosts (separate failure domains)
- **Managers:** odd count (3 or 5)
- **Workers:** scale by site density and service mix
- **Storage:** dedicated resilient strategy (not single host dependency)

### Why this matters

Single-host replicas do not protect against host outage. Multi-host does.

---

## Resource pressure by stack (practical view)

### Highest pressure domains

1. **Database stack** (`database-stack.yml`)
   - Stateful, latency-sensitive, writes + backups + exporters.
2. **Cache stack** (`cache-stack.yml`)
   - Memory-heavy services (Redis/Varnish) with strict startup checks.
3. **Monitoring stack** (`monitoring-stack.yml`)
   - Can become noisy and expensive if all components run with high defaults.

### Moderate pressure domains

- **Management stack** (`management-stack.yml`) — mostly control-plane/ops utilities.
- **Contractor stack** (`contractor-access-stack.yml`) — many bind mounts, image pulls, and optional services.

### Operational implication

For a single host, keep optional components disabled until the core path (ingress + DB + cache + essential app) is stable.

---

## Recommendations by horizon

## Immediate (this week)

1. Standardize on **Profile B** minimum for continued testing.
2. Keep replicas conservative; avoid broad `--force` updates across many services at once.
3. Apply updates in waves (cache → DB → contractor) and verify between waves.
4. Continue using seeded bind paths and config prechecks to avoid retry storms.

## Near-term (2–6 weeks)

1. Move to **Profile C** if current service portfolio remains enabled.
2. Add explicit capacity budgets per stack (CPU/RAM reservations aligned to actual host limits).
3. Separate “core” vs “optional” service groups and deploy optional groups only when baseline is green.

## Strategic (quarterly)

1. Decide whether target is:
   - **Cost-optimized single host** (accept lower HA), or
   - **Multi-host HA platform** (higher cost, higher resilience).
2. If HA is required, plan migration to at least 3 hosts and rebalance swarm role placement.

---

## Decision matrix

| Option | Infra shape                          | Cost pressure |  Operational risk | HA posture | Recommendation           |
| ------ | ------------------------------------ | ------------: | ----------------: | ---------: | ------------------------ |
| A      | 8 vCPU / 24 GB / 300 GB single host  |           Low |              High |        Low | POC only                 |
| B      | 16 vCPU / 48 GB / 500 GB single host |        Medium |            Medium |    Low-Med | **Minimum practical**    |
| C      | 24 vCPU / 64 GB / 1 TB single host   |   Medium-High |           Low-Med |    Low-Med | **Best single-host UX**  |
| D      | 3+ hosts, distributed swarm          |          High | Low (if well-run) |       High | **Production HA target** |

---

## Reproducibility references

### Key paths

- `control-center/ansible/inventory/proxmox_lxc.yml`
- `control-center/ansible/deploy.yml`
- `control-center/scripts/setup-proxmox.sh`
- `control-center/docker-compose-examples/cache-stack.yml`
- `control-center/docker-compose-examples/database-stack.yml`
- `control-center/docker-compose-examples/monitoring-stack.yml`
- `control-center/docker-compose-examples/management-stack.yml`
- `control-center/docker-compose-examples/contractor-access-stack.yml`

### Key environment variables

- `PROXMOX_HOST_IP`
- `PROXMOX_API_TOKEN_ID`
- `PROXMOX_API_TOKEN_SECRET`
- `LXC_SSH_KEY_PATH`
- `DO_API_TOKEN`

### Key workflows

- Proxmox setup and LXC provisioning via `setup-proxmox.sh` and Ansible playbooks.
- Stack deployment via `ansible/deploy.yml` tags (`config`, `stacks`, and stack-specific tags).

---

## Caveats for leadership review

1. **Single-host limitation:** no amount of in-host replication replaces host-level redundancy.
2. **IOPS is critical:** DB/caching/monitoring failure modes often present as “slow deploys” first.
3. **Constraint complexity:** strict placement + mount assumptions can amplify rollout duration.
4. **Update strategy matters:** broad force-updates are operationally expensive under constrained capacity.

---

## Final recommendation for approval

Approve a two-step path:

1. **Short term:** size current environment to **Profile B (minimum practical)** or **Profile C (recommended)**.
2. **Medium term:** decide if business SLOs require **Profile D multi-host HA** and budget accordingly.

If the manager wants one default decision now: choose **Profile C (24 vCPU / 64 GB / 1 TB NVMe)** for the current stack scope, then evaluate multi-host HA as the next architecture milestone.

---

## Sign-off checklist

- [ ] Agreed target profile (A/B/C/D)
- [ ] Budget approved for CPU/RAM/storage class
- [ ] Defined “core” vs “optional” stacks
- [ ] Documented rollout policy (wave-based updates)
- [ ] Defined HA requirement (single-host accepted vs multi-host mandated)

---

**Document owner:** Platform Engineering  
**Last updated:** 2026-02-12  
**Status:** Draft for management review
