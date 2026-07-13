---
name: cost-analysis
description: 'Produce a defendable AWS-versus-Azure cost model. Use when: generating outputs/azure-architecture-output/cost-comparison.md, estimating unknown AWS costs, calculating egress or reservation scenarios, or computing break-even and ROI for the migration.'
---

# Cost Analysis Skill

## Purpose

Create a transparent, evidence-based cost comparison that shows current AWS spend, projected Azure spend, migration one-time cost, break-even timing, reservation scenarios, and the assumptions behind every number.

## When to Use

- After the architecture design defines the target Azure services
- When writing `outputs/azure-architecture-output/cost-comparison.md`
- When current AWS billing data is incomplete and must be estimated from technical evidence
- When stakeholders need pay-as-you-go versus reservation scenarios

## Inputs

| Path | Why it matters |
|---|---|
| `outputs/aws-migration-artifacts/aws-inventory.json` | Source workload inventory for AWS baseline estimation |
| `outputs/aws-migration-artifacts/migration-assessment.md` | Traffic, scale, and risk assumptions |
| `outputs/azure-architecture-output/design-document.md` | Section 10 target-cost assumptions and Section 3 mapping |
| `source-app/doc/` | Existing billing exports, architecture notes, or runbooks |

## Outputs

| Path | Result |
|---|---|
| `outputs/azure-architecture-output/cost-comparison.md` | Complete cost comparison artifact |

## Process

### 1. Build the AWS baseline

1. Look for actual cost exports or documented monthly spend in `source-app/doc/`.
2. If real cost data exists, use it as the primary baseline.
3. If real cost data is incomplete, estimate missing services from `aws-inventory.json` and the source architecture.
4. Record every missing-data assumption in the cost report.

### 2. Estimate unknown AWS costs from instance types and workload shape

Use these fallback formulas when actual AWS billing is unknown:

| AWS service | Estimation method |
|---|---|
| EC2 | `instance_count * hourly_rate(instance_type) * 730 + attached_storage_gb * storage_rate + outbound_data_gb * egress_rate` |
| Lambda | `request_count * request_rate + (memory_gb * avg_duration_seconds * request_count) * GBs_rate` |
| S3 | `stored_gb * storage_rate + PUT_requests * put_rate + GET_requests * get_rate + outbound_gb * egress_rate` |
| RDS | `instance_hours * class_rate + storage_gb * storage_rate + provisioned_iops * iops_rate` |
| DynamoDB | `read_units + write_units + storage_gb + backups + streams if used` |
| NAT Gateway | `hours * hourly_rate + processed_gb * data_processing_rate` |
| CloudWatch | `ingested_gb * log_rate + metrics_count * metric_rate + retained_gb * retention_rate` |

If a service still cannot be estimated precisely:

- pick the closest known instance class or usage tier
- state the proxy explicitly
- add a sensitivity range of at least ±15%

### 3. Azure monthly costing workflow

1. Map each AWS service to the Azure target service from `design-document.md` Section 3.
2. Use current Azure pricing sources for the chosen service tier.
3. Show at least one pay-as-you-go scenario.
4. Show reservation scenarios when the service is eligible and the workload has a stable baseline.
5. Include egress and ancillary costs such as monitoring, DNS, and Front Door where applicable.

### 4. Data egress cost formulas

Always model egress explicitly. Use these formulas and explain the chosen rates:

- **AWS egress monthly**

  `AWS_Egress_Monthly = max(AWS_GB_Out - AWS_Free_GB, 0) * AWS_Egress_Rate_Per_GB`

- **Azure egress monthly**

  `Azure_Egress_Monthly = max(Azure_GB_Out - Azure_Free_GB, 0) * Azure_Egress_Rate_Per_GB`

- **Front Door egress contribution**

  `FrontDoor_Data_Cost = FrontDoor_GB_Out * FrontDoor_Rate_Per_GB`

- **Inter-region transfer**

  `InterRegion_Cost = InterRegion_GB * InterRegion_Rate_Per_GB`

- **Total network cost**

  `Total_Network_Cost = Egress + CDN_or_FrontDoor + InterRegion + NAT_or_Equivalent`

Worked egress example:

- 2,500 GB/month outbound
- 100 GB free allowance
- $0.087 per GB effective rate
- `max(2500 - 100, 0) * 0.087 = $208.80/month`

### 5. Azure Reservations savings calculations

When the workload has predictable baseline compute or database usage, show reservation scenarios.

Formulas:

- `Reserved_1yr_Monthly = PAYG_Monthly * (1 - Savings_Rate_1yr)`
- `Reserved_3yr_Monthly = PAYG_Monthly * (1 - Savings_Rate_3yr)`
- `Savings_Percent = (PAYG_Monthly - Reserved_Monthly) / PAYG_Monthly * 100`

Example using placeholder savings rates:

- Baseline eligible Azure compute: `$800/month`
- 1-year reservation savings rate: `38%`
- 3-year reservation savings rate: `57%`
- `Reserved_1yr_Monthly = 800 * (1 - 0.38) = $496/month`
- `Reserved_3yr_Monthly = 800 * (1 - 0.57) = $344/month`

Use current documented or calculator-derived savings inputs; do not hardcode stale percentages without citation.

### 6. Break-even formula with worked example

Use this formula whenever migration one-time cost is known or estimated:

- `Monthly_Savings = AWS_Monthly - Azure_Monthly`
- `BreakEven_Months = Migration_OneTime_Cost / Monthly_Savings`

Worked example:

- Current AWS monthly cost: `$2,450`
- Projected Azure pay-as-you-go monthly cost: `$1,850`
- Migration one-time cost: `$18,000`
- `Monthly_Savings = 2450 - 1850 = $600`
- `BreakEven_Months = 18000 / 600 = 30 months`

Reservation comparison:

- Azure 1-year reserved monthly cost: `$1,620` → monthly savings `$830` → break-even `21.7 months`
- Azure 3-year reserved monthly cost: `$1,480` → monthly savings `$970` → break-even `18.6 months`

If `Monthly_Savings <= 0`, state that there is no break-even under the modeled scenario.

### 7. Complete `cost-comparison.md` template

Use this full template for `outputs/azure-architecture-output/cost-comparison.md`:

```markdown
# Cost Comparison: AWS vs Azure

## 1. Executive Summary
- Current AWS monthly estimate:
- Projected Azure monthly estimate:
- Monthly delta:
- One-time migration cost:
- Break-even:

## 2. Scope and Inputs
- Discovery artifacts used:
- Source billing or documentation used:
- Target Azure services modeled:
- Currency and pricing date:

## 3. AWS Current Monthly Cost Baseline
| Service Category | Service | Quantity / Usage | Monthly Cost | Source / Assumption |
|---|---|---|---|---|

## 4. Azure Projected Monthly Cost (Pay-as-you-go)
| Service Category | Azure Service | SKU / Tier | Quantity / Usage | Monthly Cost | Source / Assumption |
|---|---|---|---|---|---|

## 5. Reservation and Commitment Scenarios
| Scenario | Eligible Spend | Monthly Cost | Savings vs PAYG | Notes |
|---|---|---|---|---|
| Pay-as-you-go |  |  |  |  |
| 1-year reservation |  |  |  |  |
| 3-year reservation |  |  |  |  |

## 6. Network and Data Egress
- AWS egress formula and result:
- Azure egress formula and result:
- Front Door or CDN contribution:
- Inter-region data transfer assumptions:

## 7. Monthly Cost Summary
| Category | AWS | Azure PAYG | Azure 1yr Reserved | Azure 3yr Reserved | Delta vs AWS |
|---|---|---|---|---|---|

## 8. Break-even and ROI
- One-time migration cost:
- Monthly savings by scenario:
- Break-even months by scenario:
- 3-year ROI by scenario:

## 9. Assumptions and Unknowns
- Document every assumption.
- Mark every estimated AWS cost explicitly.
- Call out excluded costs such as enterprise support, shared landing zone cost, or team labor if omitted.

## 10. Sensitivity and Risk Notes
- Traffic growth sensitivity:
- Reservation commitment risk:
- Services with the highest estimate uncertainty:

## 11. Recommendation
- Recommended Azure pricing posture:
- Conditions that would change the decision:
- Next pricing validation step:
```

### 8. Edge Cases / Failure Modes

- **Shared AWS account costs:** allocate only the migration workload share and document the allocation method.
- **Bursty traffic:** show at least expected and peak scenarios for Functions or event-driven costs.
- **Missing network volume data:** estimate from request volume and average payload size, then document the formula.
- **Unsupported reservation for a service:** leave it in PAYG and explain why.
- **Azure architecture still changing:** do not finalize a cost recommendation until the target service list is stable enough to compare.

## Rules

- **Never use placeholders such as `$X` or `TBD` in the final cost report.**
- **Always include egress and transfer costs.**
- **Always state whether a number is actual, estimated, or modeled.**
- **Always compute break-even explicitly when migration cost is known.**
- **Always show reservation scenarios when eligible baseline spend exists.**

## Best Practices

- Keep the pricing date visible so readers know when to refresh the analysis.
- Separate one-time migration cost from monthly run cost; mixing them obscures break-even.
- Use a sensitivity range when traffic or storage growth is uncertain.
- Keep the cost report aligned with Section 10 of the design document and the service mapping table.
- Treat unknown AWS costs as an estimation problem, not a reason to omit a line item.

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
| AWS data transfer pricing | https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer |

### Best Practices

- **Model the network explicitly** — egress surprises destroy confidence in otherwise solid comparisons.
- **Document estimate provenance** — each line item should say whether it came from billing data, architecture evidence, or a pricing calculator assumption.
- **Show commitment options separately** — reserved pricing improves the business case only when the workload is stable enough to justify it.
- **A cost report is a decision memo, not just a table** — include recommendation, risk, and next validation step.
