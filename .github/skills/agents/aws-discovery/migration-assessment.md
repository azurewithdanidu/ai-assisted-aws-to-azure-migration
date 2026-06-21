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
2. For each service, assign a complexity score:
   - **Low** — Direct Azure equivalent exists; configuration change only; no code changes needed (e.g. S3 → Blob Storage, CloudWatch → Azure Monitor)
   - **Medium** — Azure equivalent exists but code changes are needed (e.g. Lambda → Azure Functions, SQS → Service Bus)
   - **High** — Architectural redesign required or no direct equivalent (e.g. Step Functions → Durable Functions, Kinesis Analytics → Stream Analytics)
3. Flag risk factors for each service:
   - Custom VPC configuration with complex routing
   - Lambda layers that must be re-packaged
   - Custom Lambda authorizers (must be re-implemented as Azure Functions middleware)
   - Event source mappings with complex filtering
   - DynamoDB streams (no direct Cosmos DB equivalent — use Change Feed)
   - IAM Permission Boundaries (re-implement via Azure Policy)
4. Write `outputs/aws-migration-artifacts/migration-assessment.md`:

```markdown
# Migration Assessment

## Summary
- Total services: <N>
- Low complexity: <N>
- Medium complexity: <N>
- High complexity: <N>
- Top risks: <top 3 risk factors>

## Service Complexity Matrix

| Service | Logical ID | Complexity | Risk Flags | Migration Notes |
|---|---|---|---|---|
| Lambda | UploadFunction | Medium | Custom layer | Rewrite handler; replace boto3 |
| S3 | UploadsBucket | Low | None | Config change only |

## Phase Sequencing Recommendation

List services in suggested migration order (dependencies before dependents):
1. Networking (VPC → VNet)
2. Storage (S3 → Blob)
3. Compute (Lambda → Functions)
4. Messaging (SQS → Service Bus)
```

## Rules

- **Never assign Low complexity to any Lambda function** — all Lambda → Functions conversions require at minimum Medium due to handler signature changes.
- **Never omit services from the matrix** — every service in `aws-inventory.json` must appear.
- **Always include a phase sequencing recommendation** — dependencies must come before the services that depend on them.
- **Flag any service with no clear Azure equivalent** as High complexity with a note.

## Output

- `outputs/aws-migration-artifacts/migration-assessment.md` — non-empty, contains `## Service Complexity Matrix` section
