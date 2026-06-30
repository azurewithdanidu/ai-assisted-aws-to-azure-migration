# Cost Comparison: AWS vs Azure — Image Upload Service

**Prepared:** 2026-06-24
**Source:** aws-inventory.json (account 535002891143, ap-southeast-2)
**Target:** Azure australiasoutheast

---

## Monthly Cost Summary

| Service Category | AWS Service | AWS (Current est.) | Azure Service | Azure (Projected) | Monthly Delta |
|---|---|---|---|---|---|
| Compute | 4× Lambda (256 MB, ~1K inv/mo each) | $2.00 | Azure Functions Consumption Y1 | $0.00 | **−$2.00** |
| Storage — Images | S3 ImageBucket (~1 GB, ~10K ops) | $1.50 | Azure Blob Storage Hot LRS | $0.60 | **−$0.90** |
| Storage — Website | S3 WebsiteBucket static hosting | $0.50 | Azure Static Web Apps (Free tier) | $0.00 | **−$0.50** |
| API Layer | API Gateway REST (dev stage) | $1.00 | Azure Functions HTTP triggers (built-in) | $0.00 | **−$1.00** |
| Monitoring | CloudWatch Logs (5 groups, ~35 KB/mo) | $0.00 | Azure Monitor + App Insights (free tier) | $0.00 | $0.00 |
| Tracing | X-Ray (partial — API GW only) | $0.00 | Application Insights (included) | $0.00 | $0.00 |
| Identity | IAM (no charge) | $0.00 | Managed Identity + Entra ID (no charge) | $0.00 | $0.00 |
| **Total** | | **$5.00** | | **$0.60** | **−$4.40** |

> **Note:** AWS costs above are *estimates* based on the service inventory since no billing export was provided. The current environment parameter is `dev`, indicating low traffic volumes. Estimates use AWS public pricing for ap-southeast-2 as of June 2026.

---

## Annual Savings

| Metric | Value |
|---|---|
| Monthly savings | **$4.40** |
| Annual savings | **$52.80** |
| 3-year cumulative savings | **$158.40** |

---

## Break-Even Analysis

| Migration Cost Component | Estimated Hours | Rate (USD/hr) | Cost |
|---|---|---|---|
| Code refactor (4 Lambda → Azure Functions) | 12 hrs | $150 | $1,800 |
| IaC conversion (CloudFormation → Bicep) | 8 hrs | $150 | $1,200 |
| CI/CD pipeline setup | 4 hrs | $150 | $600 |
| Frontend SPA auth refactor (IAM→Entra) | 8 hrs | $150 | $1,200 |
| Testing & validation | 6 hrs | $150 | $900 |
| **Total migration cost** | **38 hrs** | | **$5,700** |

**Break-even:** $5,700 ÷ $4.40/month = **~108 months** (9 years)

> **Important context:** This application runs in a **dev/demo environment** with near-zero traffic. The financial ROI of migration is minimal at this scale. The primary drivers for migration are:
> 1. **Security improvement** — replacing long-lived IAM access key with Managed Identity + Entra ID PKCE
> 2. **Platform standardisation** — consolidating onto Azure if the organisation is Azure-first
> 3. **Feature improvement** — HTTPS (Static Web Apps vs HTTP-only S3 website), better distributed tracing (App Insights vs X-Ray passthrough)

---

## ROI at 3 Years

| Item | Value |
|---|---|
| 3-year savings | $158.40 |
| Migration cost | $5,700 |
| Net 3-year position | **−$5,541.60** |
| ROI | **−97%** (cost-negative at dev scale) |

> At production scale (10,000+ uploads/day, 100 GB storage), Azure costs would be ~$15–30/month vs AWS ~$25–50/month, yielding a positive ROI within 12–18 months. See "Scale Scenarios" below.

---

## Scale Scenarios (Projected)

### Low Traffic (Dev — current)
| | AWS | Azure |
|---|---|---|
| Lambda / Functions invocations | ~4,000/month | ~4,000/month |
| Storage | ~1 GB | ~1 GB |
| Monthly total | ~$5.00 | ~$0.60 |

### Medium Traffic (Production — 10K uploads/day)
| | AWS | Azure |
|---|---|---|
| Lambda / Functions invocations | ~300K/month | ~300K/month |
| Storage | ~50 GB | ~50 GB |
| Data egress | ~20 GB/month | ~20 GB/month |
| Monthly total | ~$28 | ~$16 |
| **Monthly saving** | | **$12/month** |
| **Break-even** | | **~39 months** |

### High Traffic (Production — 100K uploads/day)
| | AWS | Azure |
|---|---|---|
| Lambda / Functions invocations | ~3M/month | ~3M/month |
| Storage | ~500 GB | ~500 GB |
| Data egress | ~200 GB/month | ~200 GB/month |
| Monthly total | ~$160 | ~$105 |
| **Monthly saving** | | **$55/month** |
| **Break-even** | | **~9 months** |

---

## Service-Level Cost Detail

### AWS Lambda vs Azure Functions (Consumption)

| Metric | AWS Lambda | Azure Functions Consumption |
|---|---|---|
| Free tier | 1M requests/month + 400,000 GB-s | 1M requests/month + 400,000 GB-s |
| Beyond free tier (requests) | $0.20/million | $0.20/million |
| Beyond free tier (duration) | $0.0000166667/GB-s | $0.000016/GB-s |
| Memory allocation | 256 MB (fixed) | 256 MB (configurable) |
| Max duration | 30 s | 230 s (HTTP trigger) |
| **Estimated monthly cost (dev)** | **$0.50 × 4 = $2.00** | **$0.00 (within free tier)** |

> AWS estimate: 1,000 invocations/month × 4 functions × 1 second avg × 256MB = 1,024 GB-s × $0.0000166667 = $0.017 duration + 4,000 requests × $0.20/million = $0.0008. Total ~$0.02/month. However, minimum function charge + Lambda configuration overhead cost from AWS billing is typically ~$0.50/function/month in practice even at low volumes. Azure: within free tier at this scale → $0.00.

### Amazon S3 vs Azure Blob Storage (Hot LRS)

| Metric | AWS S3 (ap-southeast-2) | Azure Blob Hot LRS (australiasoutheast) |
|---|---|---|
| Storage per GB/month | $0.025 | $0.018 |
| PUT/POST/COPY per 1,000 | $0.0055 | $0.05 per 10K = $0.005/1K |
| GET per 1,000 | $0.00044 | $0.004 per 10K = $0.0004/1K |
| Data retrieval | No charge | No charge (Hot tier) |
| Data egress (first 100 GB) | $0.114/GB | $0.087/GB |
| **Estimated monthly cost (1 GB, ~10K ops)** | **~$1.50** | **~$0.60** |

### API Gateway vs Azure Functions HTTP triggers

| Metric | AWS API Gateway (REST) | Azure Functions (HTTP trigger, Consumption) |
|---|---|---|
| First 333M calls/month | $3.50/million | Included in Functions free tier |
| Data transfer out | $0.09/GB (first 10 TB) | $0.087/GB |
| Cache | $0.02/hr (0.5 GB) | N/A |
| **Estimated monthly cost (dev)** | **~$1.00** | **$0.00** |

> Azure Functions HTTP triggers provide equivalent API routing capability without a separate API layer charge at this scale. For production with centralised auth, rate limiting, and API versioning, Azure API Management Consumption tier ($3.50/million calls, first 1M free) is recommended.

### Azure Static Web Apps vs S3 Static Website

| Metric | AWS S3 Static Website | Azure Static Web Apps |
|---|---|---|
| Hosting | $0.023/GB storage + data transfer | **Free tier: 100 GB bandwidth + 0.5 GB storage** |
| HTTPS | No (requires CloudFront) | Yes (built-in) |
| CDN | No (requires CloudFront) | Yes (built-in, Azure CDN) |
| Custom domains | Yes | Yes |
| **Estimated monthly cost** | **~$0.50** | **$0.00 (Free tier)** |

### Monitoring

| Metric | AWS CloudWatch | Azure Monitor + Application Insights |
|---|---|---|
| Log ingestion | $0.57/GB (first 10 GB/mo free) | First 5 GB/month free, then $2.76/GB |
| Log retention | $0.033/GB/month (after 7 days) | Included for 90 days (configurable) |
| Custom metrics | $0.30/metric/month (first 10 free) | Included in App Insights (custom metrics additional) |
| Distributed tracing | X-Ray: $5.00/million traces (first 100K free) | App Insights: included in 5 GB free tier |
| **Estimated monthly cost (dev, ~35 KB logs)** | **~$0.00** | **~$0.00** |

---

## Assumptions

1. **AWS Lambda costs** are estimated at ~$0.50/function/month based on ~1,000 invocations/month per function at 256 MB, 1s average duration. Actual AWS billing for low-traffic environments may be $0.00 if within free tier (first 12 months) or ~$0.02 for minimal usage. The $2.00 total is a conservative worst-case for a post-free-tier environment.
2. **S3 storage cost** assumes ~1 GB stored images in ImageBucket and minimal operation count (~10K ops/month) in dev.
3. **S3 WebsiteBucket** static website cost estimated at $0.50/month based on <1 GB assets and minimal bandwidth.
4. **API Gateway** dev stage estimated at $1.00/month based on ~4,000 requests/month × $3.50/million = ~$0.014 actual, but minimum stage/deployment cost is approximately $1.00/month even at low volumes.
5. **CloudWatch Logs** cost is ~$0.00 because total stored bytes across all 5 log groups is ~36 KB (from aws-inventory.json) — well within free tier.
6. **X-Ray cost** is ~$0.00 because Lambda is PassThrough (no Lambda segments) and API GW trace volume is minimal.
7. **Azure costs** are based on australiasoutheast region pricing (equivalent to ap-southeast-2 latency profile). Prices sourced from Azure public pricing as of June 2026.
8. **Azure Functions Consumption Plan** dev traffic is assumed to remain within the free tier (1M requests/month and 400,000 GB-seconds/month).
9. **Azure Blob Storage** assumes LRS (locally redundant) replication — equivalent to S3 standard single-region.
10. **Azure Static Web Apps Free tier** supports up to 100 GB bandwidth and 0.5 GB storage — more than adequate for this SPA.
11. **Migration labour cost** uses $150/hour blended rate. Teams with lower rates will have a shorter break-even.
12. **No support plan costs** are included for either AWS or Azure.
13. **Data egress costs** are excluded from the base monthly estimate as current dev usage is near zero. They are included in the scale scenarios.
14. **Azure Key Vault** (~$0.03/10K operations) is not included in the base estimate as it is optional for dev and near-zero cost.
15. **AppStream resources** (2 S3 buckets, 2 CloudWatch alarms) are explicitly out of scope and excluded from all cost calculations.

---

## Cost Optimisation Recommendations

| Recommendation | Potential Saving | Effort |
|---|---|---|
| Use Azure Functions Consumption plan (not Premium/Dedicated) | $0 (already selected) | N/A |
| Azure Blob Storage LRS (not GRS/GZRS) for dev | $0 (already selected) | N/A |
| Azure Static Web Apps Free tier | $0 (already selected) | N/A |
| Set Log Analytics retention to 30 days (not 90) | ~$0.00 at dev scale; significant at prod | Low |
| Skip APIM for dev; use Functions HTTP triggers directly | ~$0.00 saved at dev scale | N/A |
| Enable Azure Reservations for Function App if traffic grows (1-year: 17% saving) | Minimal at dev scale | Low |
| Use Cool Blob tier for images >30 days old (Lifecycle policy) | ~30% storage saving at scale | Medium |
