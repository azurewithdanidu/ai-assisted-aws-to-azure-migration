---
name: architecture-design
description: 'Design the Azure target architecture from AWS discovery artifacts. Use when: creating outputs/azure-architecture-output/design-document.md, choosing Azure services, documenting WAF tradeoffs, or defining Bicep, function, security, networking, monitoring, and CI/CD specifications.'
---

# Architecture Design Skill

## Purpose

Convert AWS discovery evidence into a complete Azure target design that downstream IaC, code-refactor, pipeline, cost, and validation phases can implement without ambiguity.

## When to Use

- During Phase 2, immediately after discovery artifacts are ready
- Before any Bicep, Azure Functions, workflow, or validation work starts
- When a resume run needs to rebuild or repair `design-document.md`
- When Azure service selection, SKU choice, or WAF tradeoffs need to be documented explicitly

## Inputs

| Path | Role |
|---|---|
| `outputs/aws-migration-artifacts/aws-inventory.json` | AWS service inventory and configuration baseline |
| `outputs/aws-migration-artifacts/architecture-diagram.mmd` | Current-state topology clues |
| `outputs/aws-migration-artifacts/dependency-matrix.csv` | Upstream/downstream dependency evidence |
| `outputs/aws-migration-artifacts/migration-assessment.md` | Constraints, blockers, and migration strategy notes |
| `source-app/` | Read-only application code and documentation |
| `skills/aws-to-azure-mapping/SKILL.md` | Service mapping guidance |
| `skills/architecture-diagramming/SKILL.md` | Diagram contract for Section 4 |
| `skills/bicep-generation/SKILL.md` | Module contract for Section 5 |
| `skills/cost-analysis/SKILL.md` | Cost contract for Section 10 |
| `skills/multi-env-strategy/SKILL.md` | CI/CD and environment contract for Section 11 |

## Outputs

| Path | Result |
|---|---|
| `outputs/azure-architecture-output/design-document.md` | Primary design handoff document with all 11 sections |
| `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Azure Mermaid diagram derived from Section 4 |
| `outputs/azure-architecture-output/cost-comparison.md` | Cost document derived from Section 10 |
| `outputs/azure-architecture-output/service-mapping.md` | Detailed AWS-to-Azure mapping companion artifact |

## Process

### 1. Build the design from evidence, not memory

1. Read all four Phase 1 artifacts first.
2. Enumerate every discovered AWS service and workload interaction.
3. For each service, choose the Azure equivalent using the mapping skill and current Azure documentation.
4. Record the reason for each decision, including the primary WAF pillar it optimizes and any tradeoff it creates.
5. Populate `design-document.md` before creating any downstream artifacts.

### 2. Required `design-document.md` sections

The final document must contain these exact top-level sections and enough detail that downstream phases can implement without asking follow-up questions.

| Section | Required content |
|---|---|
| `## 1. Executive Summary` | Migration scope, target Azure pattern, business outcome, success criteria, and major non-goals |
| `## 2. Current State` | AWS workload summary, source regions, integration boundaries, dependencies, pain points, and migration drivers |
| `## 3. Service Mapping` | One row per AWS service showing Azure equivalent, SKU, rationale, and migration notes |
| `## 4. Target Architecture` | Narrative of the Azure topology, ingress path, trust boundaries, data flow, and reference to the Mermaid diagram |
| `## 5. Bicep Module Spec` | One subsection per module with parameters, resources, outputs, security controls, environment differences, and dependencies |
| `## 6. Function Rewrite Spec` | One subsection per Lambda-to-Function rewrite with triggers, SDK changes, env vars, auth, retries, and test notes |
| `## 7. Security Design` | Identity, RBAC, Key Vault, encryption, WAF, secret handling, and compliance controls |
| `## 8. Networking Design` | VNets, subnets, private endpoints, DNS, egress path, ingress path, and boundary decisions |
| `## 9. Monitoring Design` | Logging, metrics, tracing, dashboards, alert thresholds, and ownership |
| `## 10. Cost Estimate` | Cost summary, assumptions, sensitivity ranges, reservation scenarios, and link to `cost-comparison.md` |
| `## 11. CI/CD Spec` | Workflow files, triggers, OIDC, environments, approvals, promotion order, rollback steps, and secrets/variables |

### 3. Copy-paste design document template

Use this as the starting structure for `outputs/azure-architecture-output/design-document.md`:

```markdown
# Azure Architecture Design Document

## 1. Executive Summary
- Migration scope:
- Target Azure architecture pattern:
- Primary business outcomes:
- Success criteria:
- Non-goals:

## 2. Current State
### 2.1 Workload Summary
- Business capability:
- Current AWS regions:
- Runtime model:
- Current operational pain points:

### 2.2 AWS Services and Dependencies
| AWS Service | Count / Size | Region | Dependency Notes |
|---|---|---|---|

### 2.3 Constraints and Risks
- Security and compliance constraints:
- Availability / RTO / RPO constraints:
- Data residency constraints:
- Unknowns requiring assumptions:

## 3. Service Mapping
| AWS Service | Current Configuration | Azure Equivalent | Azure SKU / Tier | Decision Rationale | Migration Notes |
|---|---|---|---|---|---|

## 4. Target Architecture
### 4.1 Architecture Overview
- Ingress pattern:
- Compute pattern:
- Data pattern:
- Messaging pattern:
- Secret and identity pattern:

### 4.2 Mermaid Diagram Reference
- File: `outputs/azure-architecture-output/architecture-diagram-azure.mmd`
- Inline summary of subgraphs and flows:

### 4.3 Data Flow Narrative
1. User request path:
2. Async processing path:
3. Observability path:
4. Failure and retry path:

## 5. Bicep Module Spec
### 5.1 `<module-name>` (`modules/<file>.bicep`)
- Purpose:
- Parameters:
- Resources and API versions:
- Required outputs:
- Security controls:
- Environment differences:
- Dependencies:

### 5.n Repeat for every module

## 6. Function Rewrite Spec
### 6.1 `<function-name>`
- Original AWS source path:
- Azure Function trigger type:
- Entry point:
- boto3 to Azure SDK mapping:
- Environment variable mapping:
- Secret retrieval pattern:
- Error handling and retry behavior:
- Required code/config files:

### 6.n Repeat for every function

## 7. Security Design
- Managed identity model:
- RBAC assignments by resource:
- Key Vault secret inventory:
- Encryption at rest / in transit:
- WAF / ingress protection:
- Threats and mitigations:

## 8. Networking Design
- Region and availability zone decision:
- VNet and subnet layout:
- Private endpoints and private DNS zones:
- Public ingress path:
- Outbound egress path:
- Network policy / NSG expectations:

## 9. Monitoring Design
- Application Insights plan:
- Log Analytics workspace plan:
- Metrics and alerts:
- Distributed tracing coverage:
- Dashboard and ownership model:

## 10. Cost Estimate
- Monthly Azure pay-as-you-go estimate:
- 1-year reservation scenario:
- 3-year reservation scenario:
- Top cost drivers:
- Assumptions and sensitivity notes:
- Companion report: `outputs/azure-architecture-output/cost-comparison.md`

## 11. CI/CD Spec
### 11.1 Workflow Inventory
| Workflow File | Trigger | Purpose | Target Environment |
|---|---|---|---|

### 11.2 Authentication and Secrets
- OIDC / workload identity details:
- Required secrets:
- Required variables:
- RBAC needed by the GitHub principal:

### 11.3 Deployment Jobs
- Infra workflow steps:
- App workflow steps:
- Validation / smoke test workflow steps:

### 11.4 Environment Promotion Model
- `dev` gate:
- `staging` gate:
- `prod` gate:

### 11.5 Rollback and Failure Handling
- Rollback triggers:
- Rollback actions:
- Human approval points:
```

### 4. WAF decision tables by service type

Use these tables to justify service selection. Document the chosen row or the reason for deviating.

| Service type | Default Azure choice | Security decision | Reliability decision | Cost decision | Performance decision | Operational decision |
|---|---|---|---|---|---|---|
| Public HTTP ingress | Azure Front Door Standard or Premium | WAF, origin shielding, TLS termination | Global edge presence and health probes | Use Standard unless Premium features are required | Edge caching and routing reduce latency | Centralized ingress policy and cert management |
| Stateless API / event handler | Azure Functions | Managed identity, least privilege, no secrets in code | Consumption for bursty traffic, Premium for VNet or low cold-start tolerance | Serverless-first to minimize idle cost | Scale on demand | Simple deploy and strong platform integration |
| Async messaging | Azure Service Bus | RBAC over connection strings | Dead-lettering and duplicate detection if needed | Standard unless Premium isolation/features are required | Reliable queue/topic throughput | Mature ops model and diagnostics |
| Object storage | Azure Blob Storage | Disable public access, use private endpoints | Redundancy tier based on RPO/RTO | Hot/Cool/Archive chosen by access pattern | High throughput for binary payloads | Native lifecycle policies |
| Document / event store | Azure Cosmos DB | RBAC or managed identity access where supported | Multi-region only if explicitly required | Serverless/autoscale for variable load | Low-latency global data model | Rich diagnostics and backup options |
| Relational database | Azure Database for PostgreSQL Flexible Server | Private access, Entra auth where feasible | Zone redundancy only if justified | Burstable or General Purpose sized from evidence | Right-size compute and storage independently | Managed backups and patching |
| Secret store | Azure Key Vault | Purge protection, soft delete, RBAC | Geo-redundancy only if required | Low infrastructure overhead | Acceptable performance for secret lookups | Centralized secret and certificate lifecycle |

### 5. Service-specific design rules

#### Azure Functions

- Default to the Python v2 programming model when the codebase is Python.
- Use Consumption for bursty, internet-facing event workloads; switch to Premium only when private networking, predictable warm instances, or longer-running needs are documented.
- Every Function App must use managed identity for downstream Azure access.
- Do not make API Management the primary ingress unless a separate gateway requirement is explicitly documented.
- Document trigger type, retry model, and idempotency expectations in Section 6.

#### Azure Blob Storage

- Disable anonymous public access unless a public object hosting requirement is explicitly documented.
- Choose Hot, Cool, or Archive from measured access patterns, not guesswork.
- Prefer private endpoints and private DNS for application access.
- Record lifecycle policies if uploads, processed artifacts, or logs require retention management.
- Document encryption, replication, and container separation requirements.

#### Azure Service Bus

- Prefer queues for point-to-point processing and topics/subscriptions for fan-out patterns.
- Use Standard by default; justify Premium only for throughput isolation, VNet, or advanced feature needs.
- Capture retry, lock duration, dead-letter handling, and poison message behavior.
- Use managed identity or secure secret retrieval for connection details; avoid embedding connection strings in code.
- Make downstream consumers idempotent and document that expectation in Section 6.

#### Azure Cosmos DB

- Choose the API and partition key deliberately; both decisions must be documented.
- Use serverless or autoscale when workload shape is variable and the discovery data supports it.
- Document consistency level, backup strategy, and regional distribution explicitly.
- If change feed replaces DynamoDB Streams or other eventing, record the operational tradeoffs.
- Capture private endpoint and network boundary expectations in Section 8.

#### Azure Database for PostgreSQL

- Use Flexible Server unless a stronger reason exists.
- Prefer private networking and managed backups by default.
- Size from current CPU, memory, storage, and connection evidence rather than a best guess.
- Document HA, maintenance window, connection pooling, and migration cutover considerations.
- If cost or latency pressure suggests a different data tier, explain why PostgreSQL remains the correct choice.

#### Azure Key Vault

- Enable soft delete and purge protection.
- Prefer RBAC authorization mode over legacy access policies unless a specific integration requires otherwise.
- Minimize the number of secrets by preferring managed identity to direct credentials.
- Document certificate, secret rotation, and bootstrap requirements.
- Show every consumer of each secret or certificate in Sections 7 and 11.

#### Azure Front Door

- Use Front Door as the default public ingress for global routing, WAF, and TLS termination.
- Choose Standard unless Premium is required for advanced private origin or security features.
- Document custom domains, health probes, origin failover, and caching behavior.
- Label every edge to Front Door in the architecture diagram with protocol and auth context.
- Capture WAF rules, rate limiting, and bot or geo protections in Section 7.

### 6. Edge Cases / Failure Modes

- **Unknown traffic profile:** Provide low / expected / peak assumptions and call out the uncertainty in Section 10.
- **Unsupported direct service mapping:** Document the bridge pattern or redesign needed instead of forcing a false one-to-one mapping.
- **Conflicting RTO/RPO vs budget:** Prefer the documented business requirement, then surface the cost tradeoff explicitly.
- **Multi-region pressure without evidence:** Default to single-region plus zone redundancy unless discovery or policy requires more.
- **Security requirement blocks serverless default:** Upgrade to Premium or another service only when the requirement is concrete and documented.

## Rules

- **Serverless-first:** prefer Azure Functions unless the source workload proves a different compute model is required.
- **Single-region by default:** multi-region is opt-in, not assumed.
- **Design document before build artifacts:** Bicep, workflow, and code generation depend on it.
- **Cite the evidence source:** each major choice should trace back to a discovery artifact, a skill, or current Azure documentation.
- **Do not invent AWS facts:** if a value is missing, state the assumption and mark it in the cost and risk sections.

## Best Practices

- Keep Section 5 granular enough that each Bicep module has one clear responsibility.
- Keep Section 6 concrete enough that a refactor agent can translate code without rediscovering triggers or SDKs.
- Mirror Section 4 and the Mermaid file so diagram and prose never diverge.
- Capture both the default decision and the reason not to choose the obvious alternative when the tradeoff matters.
- Write the CI/CD section as implementation guidance, not a conceptual summary.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Well-Architected Framework | https://learn.microsoft.com/en-us/azure/well-architected/ |
| WAF Reliability pillar | https://learn.microsoft.com/en-us/azure/well-architected/reliability/ |
| WAF Security pillar | https://learn.microsoft.com/en-us/azure/well-architected/security/ |
| WAF Cost Optimization pillar | https://learn.microsoft.com/en-us/azure/well-architected/cost-optimization/ |
| WAF Operational Excellence pillar | https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/ |
| WAF Performance Efficiency pillar | https://learn.microsoft.com/en-us/azure/well-architected/performance-efficiency/ |
| Azure Architecture Center | https://learn.microsoft.com/en-us/azure/architecture/ |
| Cloud design patterns | https://learn.microsoft.com/en-us/azure/architecture/patterns/ |
| Azure for AWS professionals | https://learn.microsoft.com/en-us/azure/architecture/aws-professional/ |
| Azure Functions hosting options | https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale |
| Azure Container Apps vs AKS decision guide | https://learn.microsoft.com/en-us/azure/container-apps/compare-options |
| Azure regions availability | https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/ |
| Azure availability zones | https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview |
| Azure Front Door documentation | https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview |
| Azure Key Vault best practices | https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices |

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Well-Architected Framework | https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html |
| AWS Architecture Center | https://aws.amazon.com/architecture/ |
| AWS Migration whitepaper | https://docs.aws.amazon.com/whitepapers/latest/aws-migration-whitepaper/welcome.html |

### Best Practices

- **Security is a gating pillar, not a tie-breaker** — reject architectures that require long-lived secrets or uncontrolled public exposure.
- **Document module and function contracts explicitly** — they are the backbone of downstream automation.
- **State assumptions where facts are missing** — hidden assumptions become failed deployments later.
- **Keep service mapping, architecture narrative, and cost model aligned** — mismatches between the three cause cascading Phase 3 failures.
