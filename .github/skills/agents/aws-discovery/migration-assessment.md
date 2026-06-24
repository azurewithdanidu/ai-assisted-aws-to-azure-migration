---
name: migration-assessment
description: Score each AWS service for migration complexity, flag risks, and produce the Service Complexity Matrix in migration-assessment.md
---

# Migration Assessment Skill

## Purpose

Produce a risk-annotated migration assessment report so the azure-architect agent can make informed design decisions and the project manager can sequence work correctly.

## When to Use

After `aws-inventory-scan` is complete and `aws-inventory.json` exists.

## Process

1. Read `outputs/aws-migration-artifacts/aws-inventory.json`.
2. For each service, assign a complexity score using the **Complexity Scoring** section.
3. Flag risk factors using the **Risk Flag Catalogue**.
4. Sequence migration phases using the dependency matrix.
5. Write `outputs/aws-migration-artifacts/migration-assessment.md` using the template below.

---

## Complexity Scoring

### Effort Estimates by Service

**Lambda Functions:**

| Tier | Criteria | Effort |
|---|---|---|
| Basic | Reads S3 only, no VPC, no layers | 2 days |
| Standard | S3 + DynamoDB, standard triggers | 3–4 days |
| Complex | Multiple services, VPC, custom layers | 5–7 days |
| Very Complex | EKS integration, custom runtime, custom libraries | 8–10 days |

**RDS Databases:**

| Tier | Criteria | Effort |
|---|---|---|
| Small | < 10 GB | 2–3 days |
| Medium | 10–100 GB | 4–7 days |
| Large | > 100 GB | 8–14 days |
| Modifier | Multi-AZ or read replicas | +2–3 days |
| Modifier | Custom parameter group | +1–2 days each |

**EKS / ECS:**

| Tier | Criteria | Effort |
|---|---|---|
| Small | 1–3 nodes / 1–3 pods | 5–7 days |
| Medium | 4–10 nodes / 4–10 pods | 10–15 days |
| Large | 10+ nodes / 10+ pods | 15–20 days |

**S3 Buckets:**

| Tier | Criteria | Effort |
|---|---|---|
| Simple | No special configuration | 1–2 days |
| Versioning + replication | Multi-region or cross-account | 3–5 days |
| Lifecycle policies | Tiered storage transitions | 4–6 days |
| Public / static web hosting | Static site, presigned URLs | 2–3 days |

**EventBridge / SQS / SNS:**

| Tier | Criteria | Effort |
|---|---|---|
| Minimal | 1–2 rules/queues/topics | 1–2 days |
| Standard | 3–5 rules/queues/topics | 2–4 days |
| Moderate | 6–10 rules/queues/topics | 4–6 days |
| Complex | 10+ rules or complex routing/filtering | 6–8 days |

### Composite Complexity Ratings

```
LOW (1–2 weeks total):
- Simple CRUD operations
- Single Lambda + standard DB
- No complex integrations
- < 5 dependencies per resource

MEDIUM (3–5 weeks total):
- Multiple Lambda functions
- Custom business logic
- Medium database size
- 5–15 dependencies
- EventBridge or SQS integration

HIGH (6–10 weeks total):
- EKS/ECS clusters
- Complex event-driven architecture
- Large databases with replication
- 15+ dependencies per resource
- Custom VPC networking (Direct Connect, VPN)
- Multiple regions or accounts

CRITICAL (10+ weeks total):
- Multi-region active-active deployments
- Cross-account IAM access
- Custom CloudFormation constructs requiring re-engineering
- Legacy application modernisation alongside migration
```

---

## Risk Flag Catalogue

Flag these conditions with explicit notes in the Service Complexity Matrix:

| Risk | Impact |
|---|---|
| Lambda layers | Must be re-packaged as Python packages or shared code modules |
| Custom Lambda authorizers | Must be re-implemented as Azure Functions middleware or APIM policies |
| Event source mappings with complex filtering | EventBridge filter patterns differ from Event Grid subscription filters |
| DynamoDB Streams | No direct Cosmos DB equivalent — use Change Feed |
| IAM Permission Boundaries | Re-implement via Azure Policy |
| Custom VPC with Direct Connect / VPN | Requires ExpressRoute or VPN Gateway; extra lead time |
| Lambda in VPC | Azure Functions VNET integration has different subnet delegation requirements |
| S3 presigned URLs | Equivalent via SAS tokens — short-lived, different signature algorithm |
| Step Functions | Durable Functions have different orchestration model |
| Cross-account S3 access | Azure Blob Storage uses separate storage account + managed identity |
| Secrets Manager rotation policies | Key Vault key rotation uses Event Grid — different event model |

---

## Resource Documentation Template

Use this block for each resource in `migration-assessment.md`:

```markdown
## [Service Type] — [Resource Name]

**Type:** [AWS service]
**ARN:** [full ARN]
**Region:** [region]
**Criticality:** CRITICAL | HIGH | MEDIUM | LOW

### Configuration
- Key setting 1: value
- Key setting 2: value

### Dependencies
**Uses:**
- [resource name] — [relationship verb]

**Used By:**
- [resource name] — [relationship verb]

---

## References

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Migration Hub | https://docs.aws.amazon.com/migrationhub/latest/ug/whatishub.html |
| AWS Application Discovery Service | https://docs.aws.amazon.com/application-discovery/latest/userguide/what-is-appdiscovery.html |
| AWS Well-Architected Framework | https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html |
| AWS Lambda pricing | https://aws.amazon.com/lambda/pricing/ |
| Amazon RDS pricing | https://aws.amazon.com/rds/pricing/ |
| Amazon EKS pricing | https://aws.amazon.com/eks/pricing/ |
| Amazon S3 pricing | https://aws.amazon.com/s3/pricing/ |

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Migrate overview | https://learn.microsoft.com/en-us/azure/migrate/migrate-services-overview |
| Azure Well-Architected Framework | https://learn.microsoft.com/en-us/azure/well-architected/ |
| AWS-to-Azure service comparison | https://learn.microsoft.com/en-us/azure/architecture/aws-professional/services |
| Azure architecture center — migration | https://learn.microsoft.com/en-us/azure/architecture/aws-professional/ |

### Best Practices

- **Use AWS Migration Hub** to import discovery data and track migration status across tools.
- **Dependency mapping is mandatory** before scoring complexity — an apparently simple Lambda may depend on 10 services.
- **Always document IAM Permission Boundaries and custom VPC configurations** separately — they are the highest-risk migration blockers.
- **DynamoDB Streams → Cosmos DB Change Feed** is not a 1:1 migration — always flag this as HIGH complexity.

### Security
- IAM Role: [role name]
- VPC: [VPC ID] / None
- Security Groups: [sg-ids]
- Encryption: Yes (KMS key: [alias]) | No

### Costs
- Monthly Estimate: $XX.XX
- Usage metric: [invocations / GB-months / requests]

### Migration Notes
- Complexity: LOW | MEDIUM | HIGH
- Risk Flags: [list]
- Azure Equivalent: [service name]
- [Special considerations]
```

---

## Output File Structure

`outputs/aws-migration-artifacts/migration-assessment.md` must contain all of these sections:

```markdown
# AWS to Azure Migration Assessment

**Assessment Date:** <ISO date>
**Account:** <account_id>
**Assessed By:** AWS Discovery Agent

## Executive Summary
- Total Resources: N
- Services count: N
- Complexity rating: LOW | MEDIUM | HIGH | CRITICAL
- Estimated effort: N weeks (team of N)
- Recommended approach: lift-and-shift modernisation / replatform / rearchitect

## Service Complexity Matrix

| Service | Logical ID | Count | Complexity | Effort (Days) | Risk Flags | Azure Equivalent | Notes |
|---|---|---|---|---|---|---|---|
| Lambda | UploadFunction | 1 | Medium | 3–4 | Custom layer | Azure Functions | Rewrite handler |
| S3 | UploadsBucket | 1 | Low | 1–2 | None | Azure Blob Storage | Config change |

## Dependency Risk Analysis
- Critical path resources (resources that block the most others)
- Cross-service dependency chains
- Network isolation requirements

## Migration Phases (Recommended)

Ordered by dependency (dependencies before dependents):
1. Networking (VPC → VNet, subnets, NSGs)
2. Security (IAM → Managed Identity, Secrets Manager → Key Vault)
3. Storage (S3 → Blob Storage)
4. Database (RDS/DynamoDB → PostgreSQL Flexible/Cosmos DB)
5. Messaging (SQS/SNS → Service Bus/Event Grid)
6. Compute (Lambda → Azure Functions)
7. API Layer (API Gateway → (Azure Functions HTTP trigger / APIM))
8. Monitoring (CloudWatch → Azure Monitor, X-Ray → App Insights)

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Lambda layer re-packaging | Medium | High | Extract to requirements.txt |
| DynamoDB Streams → Change Feed | High | Medium | Use Cosmos DB Change Feed processor |

## Open Questions / Gaps
- [Any service with no clear Azure equivalent]
- [Any information needed from the azure-architect agent]

## Next Steps
1. [Specific, actionable item for azure-architect]
2. [...]
```

---

## Rules

- **Never assign Low complexity to any Lambda function** — all Lambda → Functions conversions require at minimum Medium due to handler signature changes.
- **Never omit services from the matrix** — every service in `aws-inventory.json` must appear in the Service Complexity Matrix.
- **Always include a phase sequencing recommendation** — dependencies must come before the services that depend on them.
- **Flag any service with no clear Azure equivalent** as High complexity with a note in "Open Questions / Gaps".
- **Effort estimates must match the scoring tables** — do not invent numbers.

## Output

- `outputs/aws-migration-artifacts/migration-assessment.md` — non-empty, contains all required sections
