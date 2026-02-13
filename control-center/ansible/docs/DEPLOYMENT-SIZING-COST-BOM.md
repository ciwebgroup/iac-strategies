# Deployment Cost BOM (Sizing Profiles)

## Purpose

This companion document provides a **costed bill of materials (BOM)** for the sizing profiles in:

- `control-center/ansible/docs/DEPLOYMENT-SIZING-RECOMMENDATIONS.md`

It is designed for management review and budget planning.

---

## Scope and assumptions

## What is included

- Host compute sizing by profile
- Storage and managed-service cost buckets
- Monthly estimate ranges and sensitivity bands
- Decision guidance (cost vs risk vs availability)

## What is not included

- Exact real-time cloud provider pricing (prices change frequently)
- Data transfer overages and incident-response labor costs
- One-time migration engineering effort

## Important pricing note

All values here are **planning estimates**, not a billing guarantee. Final numbers should be validated against current provider calculators at approval time.

---

## Canonical profiles

This BOM uses the same profile set as the sizing spec:

- **Profile A**: Minimum (POC / non-prod)
- **Profile B**: Practical baseline (pilot/small production)
- **Profile C**: Recommended single-host (best current UX)
- **Profile D**: Multi-host HA target (production resilience)

---

## BOM structure

## Cost components

For each profile, monthly cost is estimated as:

$$
\text{Total Monthly Cost} = \text{Compute} + \text{Storage} + \text{Managed Services} + \text{Observability/Backups Overhead}
$$

Where:

- **Compute** = host/node monthly costs
- **Storage** = block/NVMe/backup storage costs
- **Managed Services** = DNS, object storage, optional managed add-ons
- **Overhead** = monitoring retention growth, image registry growth, backup retention growth

---

## Profile BOM tables

## Profile A — Minimum (POC / non-prod)

### Technical target

- 8 vCPU / 24 GB RAM / 300 GB NVMe
- Reduced replicas and optional services disabled

### Cost BOM (monthly)

| Component                  |      Quantity |   Unit assumption | Monthly estimate |
| -------------------------- | ------------: | ----------------: | ---------------: |
| Compute host(s)            |             1 | small/medium host |        $120–$260 |
| High-speed storage         |        300 GB |  NVMe/block blend |          $25–$90 |
| Object storage / backups   |   light usage |      starter tier |          $10–$35 |
| Monitoring + misc overhead | low retention |               low |          $15–$50 |
| **Estimated total**        |               |                   |    **$170–$435** |

### Risk note

Lowest cost, highest operational risk; useful for validation only.

---

## Profile B — Practical baseline (pilot/small production)

### Technical target

- 16 vCPU / 48 GB RAM / 500 GB NVMe
- Conservative replicas, essential stacks only

### Cost BOM (monthly)

| Component                  |           Quantity |   Unit assumption | Monthly estimate |
| -------------------------- | -----------------: | ----------------: | ---------------: |
| Compute host(s)            |                  1 | medium/large host |        $280–$520 |
| High-speed storage         |             500 GB |  NVMe/block blend |         $45–$140 |
| Object storage / backups   |     moderate usage |     moderate tier |          $20–$70 |
| Monitoring + misc overhead | moderate retention |            medium |         $40–$130 |
| **Estimated total**        |                    |                   |    **$385–$860** |

### Risk note

Minimum practical floor for your current broad stack scope on a single host.

---

## Profile C — Recommended single-host (best current UX)

### Technical target

- 24 vCPU / 64 GB RAM / 1 TB NVMe
- Better tolerance for update waves, health checks, and restarts

### Cost BOM (monthly)

| Component                  |                Quantity |  Unit assumption | Monthly estimate |
| -------------------------- | ----------------------: | ---------------: | ---------------: |
| Compute host(s)            |                       1 |       large host |        $480–$980 |
| High-speed storage         |                    1 TB | NVMe/block blend |         $90–$260 |
| Object storage / backups   |           moderate/high |      higher tier |         $30–$120 |
| Monitoring + misc overhead | moderate/high retention |      medium-high |         $60–$220 |
| **Estimated total**        |                         |                  |  **$660–$1,580** |

### Risk note

Strongest single-host option for operator experience, but still a single failure domain.

---

## Profile D — Multi-host HA target (production resilience)

### Technical target

- 3+ hosts, odd manager quorum, distributed workers
- Role separation and resilient storage strategy

### Cost BOM (monthly)

| Component                       |             Quantity | Unit assumption |   Monthly estimate |
| ------------------------------- | -------------------: | --------------: | -----------------: |
| Manager nodes                   |                    3 |    medium-large |        $720–$1,800 |
| Worker/caching/db/storage nodes |                3–12+ |           mixed |        $900–$5,500 |
| Resilient storage + backups     |    multi-node/object |     higher tier |        $250–$1,400 |
| Observability + overhead        | full stack retention |            high |          $180–$900 |
| **Estimated total**             |                      |                 | **$2,050–$9,600+** |

### Risk note

Higher spend, significantly better resilience and failure isolation.

---

## Profile D mapping (current DO fleet)

Based on your current production footprint:

- **Provider:** DigitalOcean
- **Server count:** 32
- **Server class:** 8 vCPU / 16 GB RAM / ~320 GB NVMe
- **Per-server cost:** $112/month
- **Backups:** AWS S3, estimated 5–6 TB

### Compute

$$
32 \times \$112 = \$3{,}584\ \text{per month}
$$

### S3 storage estimate (AWS S3 Standard, $0.023/GB‑month baseline)

- 5 TB (≈ 5,120 GB): **$117.76/month**
- 6 TB (≈ 6,144 GB): **$141.31/month**

### Request/restore buffer

Add **$25–$100/month** for request and restore overhead.

### Estimated all‑in total

$$
\$3{,}584 + (\$118–\$141) + (\$25–\$100) \approx \$3{,}727–\$3{,}825\ \text{per month}
$$

**Interpretation:** Your current 32‑node DO fleet already maps to **Profile D**, with total monthly cost in the **$3.7k–$3.8k** range (compute + S3 estimate + buffer).

---

## Existing repo reference points (historical)

From project strategy docs, previous modeled architectures include larger multi-node production footprints with totals around:

- **$3,613/month** (optimized 33-node architecture snapshot)
- With additional staged optimizations, modeled outcomes down to approximately **$2,389–$2,581/month** in those scenarios.

These values are useful as strategic reference points and align with a broader multi-node production model, not the current single-host constrained path.

---

## Sensitivity analysis (what moves the bill fastest)

Top drivers:

1. **Worker node count and per-node size**
2. **Database/storage performance tier** (IOPS-class storage)
3. **Observability retention horizon**
4. **Backup retention + offsite/object storage policy**
5. **Overprovisioned reservations vs actual utilization**

### Practical formula for quick what-if modeling

$$
\text{Delta Cost} \approx \sum(\Delta \text{node count} \times \text{node unit cost}) + \Delta \text{storage tier} + \Delta \text{retention overhead}
$$

---

## Recommendation ladder for management

## If budget sensitivity is highest

- Start with **Profile B**
- Deploy only core services first
- Expand optional stacks after baseline stability metrics are met

## If delivery speed and operator productivity matter most

- Choose **Profile C** now
- Adopt wave-based updates (avoid broad force-updates)
- Reassess at 30/60/90 days

## If uptime/SLO guarantees are mandatory

- Fund **Profile D** (multi-host HA)
- Treat single-host as staging/transition only

---

## Approval-ready decision table

| Decision axis           | Profile B        | Profile C                 | Profile D             |
| ----------------------- | ---------------- | ------------------------- | --------------------- |
| Monthly cost pressure   | Medium           | Medium-High               | High                  |
| Operational smoothness  | Medium           | High (single host)        | High                  |
| Host failure resilience | Low              | Low                       | High                  |
| Best fit                | Pilot/small prod | Current stack on one host | Production SLA-driven |

---

## Action plan after approval

1. Select profile target (B/C/D) and budget guardrail.
2. Freeze service scope into **core** vs **optional** stacks.
3. Enforce rollout policy: update in waves with checkpoint verification.
4. Re-baseline costs after 30 days using actual utilization data.
5. Publish a quarterly right-sizing review.

---

## Appendix: quick estimator worksheet

Use this worksheet in planning meetings:

| Input                        | Value     | Notes                                     |
| ---------------------------- | --------- | ----------------------------------------- |
| Target profile               | B / C / D |                                           |
| Planned host count           |           |                                           |
| Planned vCPU per host        |           |                                           |
| Planned RAM per host         |           |                                           |
| Planned storage tier + size  |           |                                           |
| Backup retention days        |           |                                           |
| Observability retention days |           |                                           |
| Optional stacks enabled      |           | contractor/backup/extended monitoring     |
| Estimated monthly total      |           | use provider calculator + this BOM ranges |

---

**Document owner:** Platform Engineering  
**Last updated:** 2026-02-13  
**Status:** Draft for management review
