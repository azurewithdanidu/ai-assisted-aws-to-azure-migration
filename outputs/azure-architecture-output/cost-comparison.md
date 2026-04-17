# AWS to Azure Cost Comparison — Image Upload Service

**AWS Account:** 535002891143  
**AWS Region:** ap-southeast-2 (Sydney)  
**Azure Region:** australiaeast (Sydney)  
**Comparison Date:** 2026-04-14  
**Currency:** USD  

> **Pricing Source:** AWS and Azure public pricing as of April 2026.  
> Costs modelled at two scales: **Current Demo/Dev** (actual observed usage) and **Production Scale** (1M API calls/month, 100 GB stored).

---

## Current AWS Costs (Demo/Dev Scale — Observed)

The account runs a **demo-scale** workload deployed since January 2026. Based on the observed resources (4 Lambda functions, 1 API Gateway, 2 S3 buckets), usage is minimal.

| AWS Service | Resource | Usage Estimate | Unit Price | Monthly Cost (USD) |
|-------------|----------|---------------|-----------|-------------------|
| **Lambda** | 4 functions × Python 3.11, 256MB | ~100,000 invocations × 1s avg | $0.0000002/req + $0.0000166667/GB-s | **$0.45** |
| **API Gateway (REST)** | image-upload-api (dev stage) | ~100,000 calls | $3.50/million calls | **$0.35** |
| **S3 Standard** | image-upload-imagebucket (images) | ~5 GB | $0.025/GB (ap-southeast-2) | **$0.13** |
| **S3 Standard** | image-upload-websitebucket (static site) | ~10 MB | $0.025/GB | **$0.00** |
| **S3 Requests** | PUT/GET/LIST/DELETE | ~50,000 requests | $0.005/1000 PUT; $0.0004/1000 GET | **$0.03** |
| **CloudWatch Logs** | 8 log groups, Lambda + API GW | ~500 MB ingested | $0.76/GB ingested (ap-se-2) | **$0.38** |
| **CloudWatch Logs Storage** | 8 log groups | ~200 MB stored | $0.033/GB/month | **$0.01** |
| **KMS** | 1 CMK | 1 key × ~100 API calls | $1.00/key/month + $0.03/10K calls | **$1.00** |
| **Data Transfer OUT** | API Gateway + S3 presigned | ~5 GB | $0.114/GB (ap-southeast-2) | **$0.57** |
| **AppStream remnants** | S3 buckets (empty), IAM roles | Negligible | — | **$0.00** |
| | | | **SUBTOTAL** | **$2.92/month** |

> **Note:** The AWS Free Tier covers: first 1M Lambda requests, 5GB S3 storage, 10GB CloudWatch metrics. This account may still be within free tier limits for some services. Actual bill may be lower.

---

## Projected Azure Costs (Demo/Dev Scale — Equivalent workload)

| Azure Service | Resource | Usage | Unit Price | Monthly Cost (USD) |
|--------------|----------|-------|-----------|-------------------|
| **Azure Functions** | Consumption plan, 4 functions, Python 3.11 | ~100,000 executions × 256MB × 1s | $0.20/million executions + $0.000016/GB-s; **first 1M free** | **$0.00** |
| **Azure Blob Storage (Hot)** | images container, 5 GB | 5 GB stored + operations | $0.020/GB (australiaeast); $0.0052/10K write; $0.00041/10K read | **$0.10** |
| **Azure Static Web Apps** | img-upload-swa | Static HTML/JS hosting | **Free tier** — 100 GB bandwidth, 500 MB storage | **$0.00** |
| **Application Insights** | img-upload-appins | ~500 MB telemetry/month | **First 5 GB/month free** | **$0.00** |
| **Log Analytics Workspace** | img-upload-law | ~500 MB logs | **First 5 GB/month free** | **$0.00** |
| **Azure Key Vault** | img-upload-kv | 1 vault, ~100 operations | $0.00/vault (Standard); $0.03/10K operations; **first 10K free** | **$0.00** |
| **Data Transfer OUT** | Functions + Blob Storage | ~5 GB | $0.087/GB (first 100 GB/month to internet) | **$0.44** |
| | | | **SUBTOTAL** | **$0.54/month** |

---

## Demo/Dev Scale — Side-by-Side Comparison

| | AWS (Current) | Azure (Projected) | Difference |
|-|--------------|-----------------|------------|
| **Compute** | $0.45 | $0.00 (free tier) | -$0.45 |
| **API Gateway** | $0.35 | $0.00 (HTTP trigger, no gateway) | -$0.35 |
| **Object Storage** | $0.13 | $0.10 | -$0.03 |
| **Storage Operations** | $0.03 | $0.00 | -$0.03 |
| **Static Website** | $0.00 | $0.00 | $0.00 |
| **Logging & Monitoring** | $0.39 | $0.00 (free tier) | -$0.39 |
| **Key Management** | $1.00 | $0.00 | -$1.00 |
| **Data Transfer** | $0.57 | $0.44 | -$0.13 |
| **TOTAL** | **$2.92** | **$0.54** | **-$2.38 (-82%)** |

---

## Production Scale Cost Comparison

Modelled at: **1 million API calls/month, 100 GB images stored, 50 GB data transfer out**

### AWS Production Costs

| Service | Usage | Unit Price | Monthly Cost (USD) |
|---------|-------|-----------|-------------------|
| **Lambda** | 1M invocations × 256MB × 1.5s avg | $0.0000002/req + $0.0000166667/GB-s | **$6.60** |
| **API Gateway (REST)** | 1M API calls | $3.50/million | **$3.50** |
| **S3 Standard** | 100 GB storage | $0.025/GB | **$2.50** |
| **S3 Requests** | 500K PUT/GET/LIST/DELETE | Mixed rates | **$0.63** |
| **CloudWatch Logs** | 5 GB ingested | $0.76/GB | **$3.80** |
| **CloudWatch Logs Storage** | 5 GB retained | $0.033/GB/month | **$0.17** |
| **KMS** | 1 key + 50K API calls | $1.00 + $0.15 | **$1.15** |
| **Data Transfer OUT** | 50 GB | $0.114/GB | **$5.70** |
| **TOTAL** | | | **$24.05/month** |

### Azure Production Costs

| Service | Usage | Unit Price | Monthly Cost (USD) |
|---------|-------|-----------|-------------------|
| **Azure Functions (Consumption)** | 1M executions × 256MB × 1.5s | $0.20/M exec + $0.000016/GB-s; **first 1M exec + 400K GB-s free** | **$2.40** |
| **Azure Blob Storage (Hot)** | 100 GB + operations | $0.020/GB; $0.0052/10K write; $0.00041/10K read | **$2.00** |
| **Azure Static Web Apps** | ~20 GB bandwidth | Free tier (100 GB/month) | **$0.00** |
| **Application Insights** | 5 GB telemetry | First 5 GB free, $2.76/GB after | **$0.00** |
| **Log Analytics Workspace** | 5 GB logs | First 5 GB free, $2.76/GB after | **$0.00** |
| **Azure Key Vault** | 1 vault + 50K ops | $0.03/10K ops | **$0.15** |
| **Data Transfer OUT** | 50 GB | First 100 GB/month free | **$0.00** |
| **TOTAL** | | | **$4.55/month** |

---

## Production Scale — Side-by-Side Comparison

| | AWS (Production) | Azure (Production) | Savings |
|-|-----------------|-------------------|---------|
| **Compute** | $6.60 | $2.40 | $4.20 (64%) |
| **API Gateway** | $3.50 | $0.00 (HTTP trigger, no gateway) | $3.50 (100%) |
| **Object Storage** | $2.50 | $2.00 | $0.50 (20%) |
| **Storage Operations** | $0.63 | included | $0.63 |
| **Logging & Monitoring** | $3.97 | $0.00 | $3.97 (100%) |
| **Key Management** | $1.15 | $0.15 | $1.00 (87%) |
| **Data Transfer** | $5.70 | $0.00 | $5.70 (100%) |
| **TOTAL** | **$24.05** | **$4.55** | **$19.50 (81%)** |

---

## Cost Savings Summary

| Scale | AWS Monthly | Azure Monthly | Monthly Saving | Annual Saving |
|-------|------------|--------------|---------------|--------------|
| Demo/Dev | $2.92 | $0.54 | **$2.38** | **$28.56** |
| Production (1M calls, 100GB) | $24.05 | $4.55 | **$19.50** | **$234.00** |

---

## Break-Even Analysis

Assuming a **one-time migration cost of $10,000** (2 engineers × 2 weeks):

| Scale | Monthly Saving | Break-Even Point |
|-------|---------------|-----------------|
| Production (1M calls/month) | $19.50 | **43 years** *(migration cost exceeds savings at this scale)* |
| Production (10M calls/month) | ~$195/month | **4.3 years** |
| Production (100M calls/month) | ~$1,950/month | **5.1 months** |

> **Key insight:** For this demo application, the financial ROI on cloud-to-cloud migration is not the primary driver. The migration delivers **security improvements, operational simplicity, and platform alignment** — not direct cost reduction at demo scale.

---

## Azure Cost Optimisation Recommendations

### Immediate (Apply at Migration)
1. **Use Azure Static Web Apps Free tier** — eliminates S3 website hosting + data transfer costs entirely
2. **Use Application Insights free quota (5 GB/month)** — covers logging at this scale with $0 cost
3. **Use Functions HTTP triggers directly** — eliminates API Gateway cost entirely; no APIM overhead for simple proxy routes
4. **Enable Blob lifecycle policies** — auto-tier old images from Hot → Cool → Archive

### Medium Term (Post-Migration)
5. **Enable Azure Functions Premium plan** if sustained throughput > 100K calls/hour (avoids cold start latency, predictable billing)
6. **Azure Monitor Cost Analysis** — set budget alerts at $10/month to catch unexpected growth
7. **Restrict CORS origins** — avoids unintended public data transfer costs
8. **Enable Blob soft-delete** — recovers accidental deletes without storage cost overhead

### Reserved / Committed Use (Production)
9. **Azure Blob Reserved Capacity** — 1-year reservation for 100 GB: saves ~18% vs on-demand
10. **Azure Functions Premium Reserved** — if moving to Premium plan at scale

---

## Azure Cost Monitoring Setup

```bicep
// Budget alert in Bicep
resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: 'img-upload-monthly-budget'
  properties: {
    category: 'Cost'
    amount: 25
    timeGrain: 'Monthly'
    timePeriod: { startDate: '2026-05-01' }
    notifications: {
      actual80Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: ['platform-team@example.com']
        thresholdType: 'Actual'
      }
      forecast100Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: ['platform-team@example.com']
        thresholdType: 'Forecasted'
      }
    }
  }
}
```

---

## Pricing Assumptions & Disclaimers

| Assumption | Value |
|-----------|-------|
| AWS pricing source | AWS Public Pricing (ap-southeast-2, April 2026) |
| Azure pricing source | Azure Pricing Calculator (australiaeast, April 2026) |
| Exchange rate | N/A — all prices in USD |
| Free tier credits | AWS Free Tier not applied to AWS estimates (account is >12 months old); Azure Perpetual Free tier applied |
| Reserved instances | Neither platform uses reserved pricing in estimates |
| Support plans | Not included |
| Egress pricing | AWS: $0.114/GB out from ap-southeast-2; Azure: Free first 100 GB/month to internet |
| Lambda/Functions execution time | Estimated 1s avg (demo scale), 1.5s (production scale) |
| S3/Blob PUT operations | Estimated at 20% of total requests |

*Prices are estimates only. Actual costs depend on exact usage patterns. Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) and [AWS Pricing Calculator](https://calculator.aws.amazon.com/) for binding estimates.*

---

*Generated by: Azure Architect Agent | AWS Account: 535002891143 | 2026-04-14*
