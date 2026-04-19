# AWS to Azure Cost Comparison

**Report Date:** 2026-04-18  
**AWS Account:** 535002891143 (arinco-bootcamp-2025)  
**Source Region:** ap-southeast-2 (Sydney)  
**Target Region:** australiaeast (Sydney)  
**Application:** Image Upload Service (demo/dev scale)  

---

## Current AWS Costs (Monthly Estimate)

> Costs sourced from `aws-inventory.json` `estimated_monthly_cost_usd` fields and AWS public pricing for ap-southeast-2 as of April 2026.

| Service | Resource | Usage Estimate | Monthly Cost (USD) | Notes |
|---|---|---|---|---|
| AWS Lambda | 4 functions × ~10k invocations/mo | Minimal | $0.50 | Well within 1M free-tier invocations; cost negligible at demo scale |
| Amazon API Gateway | 1 REST API, ~40k requests/mo | Minimal | $1.00 | $3.50/M calls after free tier (1M/mo); demo scale effectively free post-free-tier month 1 |
| Amazon S3 (Image bucket) | 1 bucket, ~1 GB, versioning ON | ~1 GB stored, ~10 GB egress | $2.00 | $0.025/GB storage + $0.114/GB data transfer out |
| Amazon S3 (Website bucket) | 1 bucket, public, ~1 MB | Negligible storage; minimal requests | $0.50 | Static hosting requests; negligible at demo scale |
| Amazon CloudWatch | 5 log groups, ~500 KB/mo ingestion | Minimal | $0.50 | $0.57/GB ingestion; $0.033/GB storage beyond free tier |
| AWS IAM / KMS | IAM users, roles, KMS CMK | N/A | $0.00 | IAM is free; KMS CMK ~$1/key/mo but not actively used by stack |
| AWS CloudFormation | 1 stack, ~13 resources | N/A | $0.00 | CloudFormation is free |
| Data Transfer (cross-region) | None — single region deployment | N/A | $0.00 | No cross-region traffic |
| **TOTAL (Active Application)** | | | **~$4.50–7.50** | Range reflects variable S3 egress and API call volume |

**Key AWS cost drivers at this scale:** S3 data egress ($0.114/GB to internet from ap-southeast-2) and IAM user management overhead (security risk, not cost).

---

## Projected Azure Costs (Monthly Estimate)

> Costs based on Azure public pricing for australiaeast (Australia East) as of April 2026. Consumption plans include significant free grants.

| Service | Resource | Usage Estimate | Monthly Cost (USD) | Notes |
|---|---|---|---|---|
| Azure Functions (Consumption) | 1 Function App, 4 functions, ~10k invocations/mo | 10k invocations × avg 200ms × 256MB | **$0.00** | Azure Functions Consumption includes 1M requests/mo FREE + 400,000 GB-seconds/mo FREE. Demo scale is 100% within free grant. |
| Azure Blob Storage (Standard LRS) | 1 storage account, `images` container | ~1 GB stored, ~10 GB egress | **$1.20–2.40** | LRS: $0.018/GB stored; egress: $0.087/GB (first 10 GB/mo) to internet from Australia East. Versioning adds minimal overhead. |
| Azure Static Web Apps (Free tier) | 1 SWA instance | Static HTML/JS, ~100 MB bandwidth | **$0.00** | Free tier includes 100 GB bandwidth/mo, custom domains, and HTTPS. |
| Azure API Management (Consumption) | 1 APIM instance, ~40k API calls/mo | 40k calls | **$0.00–$0.60** | Consumption: $0.0000035/call with 1M calls/mo free. 40k calls ≈ $0.14. Effectively free at demo scale. |
| Log Analytics Workspace | 1 workspace, ~500 MB/mo ingestion | 500 MB ingestion, 30-day retention | **$0.00–$1.00** | First 5 GB/month free per billing account. Demo scale is within free tier. |
| Application Insights | 1 instance (linked to LAW) | ~500 MB telemetry/mo | **$0.00** | First 5 GB/month free. Demo scale within free grant. |
| Azure Key Vault (Standard) | 1 vault, <10 secrets | ~1k operations/mo | **$0.00–$0.05** | $0.03/10k operations; Standard vault has no base fee. Negligible. |
| Data Transfer (egress) | Azure → internet (blob SAS downloads) | ~10 GB/mo | **$0.87** | First 100 GB/month free for some egress; $0.087/GB Australia East egress after free allowance |
| **TOTAL** | | | **~$2.07–4.05** | Lower bound with free grants; upper bound with egress at scale |

---

## Cost Savings Analysis

| Metric | Value |
|---|---|
| **AWS Monthly Cost** | ~$4.50–7.50 |
| **Azure Monthly Cost** | ~$2.07–4.05 |
| **Monthly Savings** | ~$2.43–3.45 |
| **Savings Percentage** | **~35–55%** |
| **Annual Savings** | ~$29–41 |
| **3-Year Savings** | ~$87–124 |

> At demo/dev scale, both platforms are effectively free due to free tier grants. Azure's Consumption billing model (pay-per-invocation) better matches low-traffic workloads than the API Gateway $3.50/M model, and Azure Blob egress rates are lower than S3 egress from Sydney.

---

## Factors in Azure's Favour

| Factor | Benefit |
|---|---|
| **Azure Functions Consumption Free Grant** | 1M requests + 400k GB-s/mo free — demo and low-traffic workloads cost $0 |
| **Azure Static Web Apps Free Tier** | 100 GB bandwidth, HTTPS, and custom domains free — S3 website hosting charges per request |
| **Lower Blob Egress Pricing** | AU East egress: $0.087/GB vs S3 Sydney egress: $0.114/GB (~24% cheaper) |
| **APIM Consumption** | $0/mo fixed cost; $0.0000035/call vs API Gateway $3.50/M after free tier |
| **No IAM User Access Key Risk** | Eliminates the security risk (and potential compliance cost) of the long-lived access key `AKIAXZEFIIOD2OIWPRPK` embedded in CloudFormation output |
| **Integrated Observability** | Application Insights included in Functions; no equivalent to separate CloudWatch Logs cost |
| **No VPC costs** | Functions Consumption has no VNet fee; AWS Lambda VPC ENI provisioning adds latency (not applicable here but relevant for growth) |

---

## Break-Even Analysis

| Item | Value |
|---|---|
| **Estimated one-time migration cost** | ~30 engineer-hours × $100/hr = $3,000 |
| **Monthly savings** | ~$2.43–3.45/mo (at demo scale) |
| **Break-even at demo scale** | >72 months (cost of migration exceeds savings at this traffic level) |
| **Break-even at 100× traffic** | Monthly savings scale to ~$50–100/mo → break-even ~18–30 months |
| **Break-even at 1000× traffic** | Monthly savings scale to ~$500–1,000/mo → break-even ~3–6 months |

> **Note:** The primary driver for this migration is **elimination of security risk** (long-lived IAM access key in browser), **alignment with Azure organisation standards**, and **developer experience** — not cost alone. At demo scale, cost savings are negligible. At production scale (10M+ invocations/mo, 1TB+ storage), Azure's pricing advantage becomes significant.

---

## ROI Calculation (Production Scale Projection)

Assuming 10× growth (100k invocations/mo, 10 GB stored, 100 GB egress):

| Service | AWS/mo | Azure/mo |
|---|---|---|
| Compute (Lambda / Functions) | $2.00 | $0.20 |
| Storage (S3 / Blob) | $12.50 | $8.50 |
| API Layer (API GW / APIM) | $3.50 | $0.35 |
| Egress (100 GB to internet) | $11.40 | $8.70 |
| Monitoring | $3.00 | $0.00 (within free grant) |
| **Total** | **$32.40** | **$17.75** |
| **Monthly Saving** | | **$14.65 (45%)** |
| **Annual Saving** | | **$175.80** |
| **3-Year Saving** | | **$527.40** |
| **ROI on $3,000 migration cost** | | **Break-even ~17 months** |

---

## Cost Optimisation Recommendations

1. **Enable Blob Storage lifecycle policies** — move blobs older than 30 days to Cool tier ($0.01/GB vs $0.018/GB); archive after 90 days ($0.001/GB)
2. **APIM Consumption vs Standard** — remain on Consumption at ≤1M calls/mo; evaluate Standard ($658/mo) only if 99.95% SLA is contractually required
3. **Log Analytics data cap** — set daily ingestion cap in dev to avoid unexpected log ingestion costs if verbose logging is enabled
4. **Azure Blob reserved capacity** — 100 GB LRS 1-year reserved at $0.014/GB vs $0.018/GB on-demand (22% saving) if storage grows to 100+ GB
5. **Functions Premium (EP1, ~$130/mo)** — only required if cold-start latency becomes a problem (>10 second cold starts under sustained load); Consumption is optimal for this workload

---

## AWS Post-Migration Savings

Decommissioning the AWS CloudFormation stack after migration saves:
- ~$4.50–7.50/mo in AWS charges
- Eliminates the exposed IAM access key security risk
- Stops CloudWatch log ingestion billing
- Removes AppStream residual bucket storage costs
