---
name: cost-analysis
description: Produce a credible AWS-vs-Azure cost comparison with monthly delta, break-even, and ROI — read before generating cost-comparison.md
---

# Cost Analysis Skill

## Purpose

Produce an honest, evidence-based cost comparison between current AWS spend and projected Azure spend so stakeholders can make informed migration decisions.

## When to Use

When generating `outputs/azure-architecture-output/cost-comparison.md` (after design document sections 1–5 are complete).

## Process

1. Read `source-app/doc/` for any existing AWS cost data or billing exports.
2. If no cost data exists, estimate from service types and sizes in `aws-inventory.json` using AWS public pricing.
3. For each Azure service selected in the design document, look up the pricing tier:
   - **Functions Consumption:** first 1M executions/month free; then $0.20/million. Memory-seconds: first 400,000 GB-s free; then $0.000016/GB-s.
   - **Blob Storage:** Hot tier ~$0.018/GB/month; Cool ~$0.01/GB/month. Operations: $0.004/10K read, $0.05/10K write (Hot).
   - **Service Bus Standard:** ~$0.10/million operations.
   - **PostgreSQL Flexible (Burstable B2s):** ~$37/month. GP D2s_v3: ~$180/month.
   - **Azure DNS:** ~$0.90/zone/month; ~$0.40/million queries.
   - **Front Door Standard:** ~$35/month + $0.009/GB.
4. Build `outputs/azure-architecture-output/cost-comparison.md`:

```markdown
# Cost Comparison: AWS vs Azure

## Monthly Cost Summary

| Service Category | AWS (Current) | Azure (Projected) | Delta |
|---|---|---|---|
| Compute | $X | $Y | ±$Z |
| Storage | $X | $Y | ±$Z |
| Database | $X | $Y | ±$Z |
| Networking | $X | $Y | ±$Z |
| Monitoring | $X | $Y | ±$Z |
| **Total** | **$X** | **$Y** | **±$Z** |

## Annual Savings: $Z
## Break-even (migration cost amortized): N months
## ROI at 3 years: X%

## Assumptions
- List every assumption made about usage volume
- List any costs not included (support plans, dev environments, etc.)
```

## Rules

- **Never use placeholder costs** — if a cost is genuinely unknown, write the assumption explicitly: "AWS cost unknown — estimated at $X based on Y".
- **Always include data transfer costs** — outbound data is often the largest surprise in cloud migrations.
- **Always show Consumption plan costs at both p50 and p95 load** if the workload has variable traffic.
- **Always list every assumption** in the Assumptions section — reviewers must be able to reproduce the numbers.
- **Read `azure-cost-management/SKILL.md`** before writing costs — it contains current pricing tier guidance.

## Output

`outputs/azure-architecture-output/cost-comparison.md` — non-empty, contains Monthly Cost Summary table, Annual Savings, Break-even months, ROI %, and Assumptions section.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Pricing Calculator | https://azure.microsoft.com/en-us/pricing/calculator/ |
| Azure Retail Prices API | https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices |
| Azure Functions pricing | https://azure.microsoft.com/en-us/pricing/details/functions/ |
| Azure Blob Storage pricing | https://azure.microsoft.com/en-us/pricing/details/storage/blobs/ |
| Azure Service Bus pricing | https://azure.microsoft.com/en-us/pricing/details/service-bus/ |
| Azure Database for PostgreSQL pricing | https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/ |
| Azure Cosmos DB pricing | https://azure.microsoft.com/en-us/pricing/details/cosmos-db/autoscale-provisioned/ |
| Azure Front Door pricing | https://azure.microsoft.com/en-us/pricing/details/frontdoor/ |
| Azure DNS pricing | https://azure.microsoft.com/en-us/pricing/details/dns/ |
| Azure Cost Management overview | https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/overview-cost-management |
| Azure Reservations (savings vs pay-as-you-go) | https://learn.microsoft.com/en-us/azure/cost-management-billing/reservations/save-compute-costs-reservations |

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Pricing Calculator | https://calculator.aws/pricing/2/home |
| AWS Lambda pricing | https://aws.amazon.com/lambda/pricing/ |
| Amazon S3 pricing | https://aws.amazon.com/s3/pricing/ |
| Amazon RDS pricing | https://aws.amazon.com/rds/pricing/ |
| Amazon DynamoDB pricing | https://aws.amazon.com/dynamodb/pricing/ |
| AWS Cost Explorer | https://aws.amazon.com/aws-cost-management/aws-cost-explorer/ |

### Best Practices

- **Use the Azure Retail Prices API for Azure costs** (see `cost-estimator` skill) — never use memory-embedded pricing; prices change monthly.
- **Always include data egress costs** — for workloads that serve data to users, outbound data transfer can exceed compute costs. AWS charges for outbound data; Azure charges are similar.
- **Show both p50 and p95 scenarios** for Consumption plan Functions — the cost difference can be 5–10× depending on traffic spikiness.
- **Azure Reservations** can reduce compute costs by 30–60% compared to pay-as-you-go for predictable workloads — always show the reservation option if the workload has stable baseline traffic.
