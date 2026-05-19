# AWS → Azure Cost Comparison

**Workload:** Image Upload Service (4 Lambdas, 1 API GW, 2 S3 buckets, IAM, CW Logs)
**Assumed traffic profile (production):** 100,000 API requests/month, 50 GB blob storage, 200 GB egress/month, 4 functions averaging 256 MB × 500 ms
**Pricing reference date:** 2026-05 list pricing (USD), `ap-southeast-2` (AWS) and `australiaeast` (Azure)
**Design constraint:** APIM is excluded per cost-first design.

## 1. Current AWS Monthly Cost

| AWS Service | Usage | Unit Cost | Monthly Cost |
|---|---|---|---|
| Lambda invocations | 100k req | $0.20 per 1M req | $0.02 |
| Lambda compute | 100k × 256 MB × 500 ms = 12,500 GB-s | $0.0000166667/GB-s | $0.21 |
| API Gateway REST | 100k req | $3.50 per 1M req | $0.35 |
| API Gateway data out | 200 GB | $0.09/GB | $18.00 |
| S3 ImageBucket storage | 50 GB Standard | $0.025/GB | $1.25 |
| S3 PUT/COPY/POST/LIST | ~150k req | $0.0055 per 1k | $0.83 |
| S3 GET | ~300k req | $0.00044 per 1k | $0.13 |
| S3 WebsiteBucket storage | 0.1 GB | $0.025/GB | $0.01 |
| S3 data egress | 200 GB | $0.114/GB (Sydney) | $22.80 |
| CloudWatch Logs ingestion | 5 GB | $0.50/GB ingest | $2.50 |
| CloudWatch Logs storage (never-expire) | 60 GB cumulative est. | $0.03/GB | $1.80 |
| X-Ray traces | 100k | $5.00 per 1M | $0.50 |
| IAM | — | Free | $0.00 |
| **AWS TOTAL** | — | — | **~$48.40/month** |

## 2. Projected Azure Monthly Cost

| Azure Service | Usage / SKU | Unit Cost | Monthly Cost |
|---|---|---|---|
| Azure Functions (Consumption Y1) execution | 100k exec | $0.20 per 1M (after free 1M) | $0.00 (within free) |
| Azure Functions compute (GB-s) | 12,500 GB-s | $0.000016/GB-s (after free 400k GB-s) | $0.00 (within free) |
| Storage Account (LRS Hot, images) | 50 GB | $0.0196/GB | $0.98 |
| Storage transactions (write) | 150k | $0.0625 per 10k (write) | $0.94 |
| Storage transactions (read) | 300k | $0.005 per 10k (read) | $0.15 |
| Storage Account (AzureWebJobsStorage backing) | ~1 GB + minor txn | — | $0.05 |
| Azure Static Web Apps | Free SKU | $0 | $0.00 |
| Bandwidth / egress | 200 GB (first 100 GB free, then $0.087/GB AU East) | — | $8.70 |
| Application Insights ingestion | 5 GB (first 5 GB free) | $2.30/GB beyond | $0.00 |
| Log Analytics Workspace | 30-day retention default included | — | $0.00 |
| Key Vault (Standard) | <10k operations | $0.03 per 10k | $0.03 |
| User-Assigned Managed Identity | — | Free | $0.00 |
| **Azure TOTAL** | — | — | **~$10.85/month** |

## 3. Savings Summary

| Metric | Value |
|---|---|
| Monthly AWS cost | $48.40 |
| Monthly Azure cost | $10.85 |
| **Monthly savings** | **$37.55 (~78% reduction)** |
| Annual savings | $450.60 |
| 3-year savings | $1,351.80 |

### Drivers of Azure savings
1. **Functions Consumption free grant** (1M exec + 400k GB-s/month) absorbs all compute cost at this traffic level.
2. **No API Gateway charge** — replaced by Function HTTP trigger (saves $0.35/M req + $18 in API GW egress).
3. **Static Web Apps Free SKU** replaces S3 static website + would-be CDN cost.
4. **Lower egress pricing in AU East** ($0.087/GB vs $0.114/GB) plus 100 GB/month free.
5. **App Insights free grant** (5 GB) covers full observability cost.

## 4. Cost at Higher Scale (1M req/month, 500 GB storage, 2 TB egress)

| Component | AWS | Azure |
|---|---|---|
| Compute (Lambda / Functions) | $2.30 | $0.00 (still in free grant for exec, partial for GB-s ≈ $1.20) |
| API tier | $35.00 (API GW) | $0.00 (Functions HTTP) |
| Storage 500 GB | $12.50 | $9.80 |
| Egress 2 TB | $228.00 | $174.00 (after 100 GB free) |
| Observability | $20.00 | $5.50 |
| **Total** | **~$298** | **~$190** |
| **Monthly savings at scale** | — | **~$108 (36%)** |

## 5. Migration Investment & Break-Even

| Item | Estimate |
|---|---|
| Engineer-days (per discovery assessment) | 5 days |
| Loaded engineering cost @ $800/day | $4,000 |
| Azure data migration (azcopy) | <$5 (one-off egress from AWS) |
| **Total one-off migration cost** | **~$4,005** |
| Monthly savings (current scale) | $37.55 |
| Monthly savings (10× scale) | $108 |

**Break-even:** ~106 months at current scale; **~37 months at 10× scale**.
> Cost savings are real but modest because the workload is already in the free tier on both clouds. The stronger justifications for migration are **strategic** (Azure consolidation, eliminating long-lived IAM access keys, Managed Identity, free TLS+CDN via SWA, native App Insights tracing) rather than pure cost.

## 6. ROI Considerations Beyond Hard Dollars

| Benefit | Estimated Value |
|---|---|
| Eliminate long-lived IAM access key (security debt) | Avoids 1 likely audit finding |
| Free TLS + global CDN via SWA | Equivalent CloudFront cost on AWS ≈ $10-30/mo |
| Native distributed tracing (App Insights) | Equivalent third-party APM ≈ $50/mo per node |
| Managed Identity (no secret rotation) | Reduces ops toil; eliminates rotation tickets |
| Bicep IaC (modular) | Faster future env spin-up |

## 7. Cost Optimization Levers Applied

✅ Functions Consumption Y1 (not Premium)
✅ APIM excluded — direct Function HTTP triggers
✅ LRS storage redundancy (not GRS/ZRS) for dev/staging; only prod opt-in to ZRS if required
✅ Static Web Apps **Free SKU**
✅ Key Vault **Standard** tier (not Premium HSM)
✅ Log Analytics retention capped at **30 days**
✅ Blob lifecycle policy: Hot → Cool @ 30 d → Archive @ 180 d
✅ Single region deployment (no paired-region DR overhead)
✅ No private endpoints (public endpoints + RBAC + SAS sufficient; private endpoints would add ~$7/mo each)
