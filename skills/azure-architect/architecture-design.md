---
name: architecture-design
description: Select Azure services and produce a WAF-aligned design document — service selection rules, design constraints, and required section checklist
---

# Architecture Design Skill

## Purpose

Translate AWS discovery output into a complete Azure architecture design, selecting services according to the Well-Architected Framework and this project's design constraints.

## When to Use

As the primary workflow for Phase 2, before writing any Bicep, diagrams, or cost analysis.

## Process

1. Read `outputs/aws-migration-artifacts/aws-inventory.json` and `migration-assessment.md`.
2. For each AWS service, look up the Azure equivalent in `.github/skills/agents/shared/aws-to-azure-mapping.md`.
3. Apply design constraints (see Rules below).
4. For each Azure service you select, read the matching knowledge skill in `.github/skills/azure-architecture/<service>/SKILL.md` before finalizing — use its SKU guidance and anti-patterns section.
5. For each service selection, document: which WAF pillar it optimizes, what trade-off it makes, and cite the knowledge skill consulted.
6. Populate `outputs/azure-architecture-output/design-document.md` sections 1–10 **before** generating any other output files (diagrams, cost reports, Bicep).
7. Only after the design document is complete, proceed to `cost-analysis` and `architecture-diagramming` skills.

**WAF pillar decision framework:**

| Priority | Pillar | Key question |
|---|---|---|
| 1 | Security | Is data protected at rest and in transit? Is access via managed identity only? |
| 2 | Reliability | What is the RTO/RPO? Does the design meet it with Availability Zones? |
| 3 | Cost Optimization | Is the cheapest tier that meets the SLA selected? |
| 4 | Operational Excellence | Is everything deployable via IaC? Is monitoring configured? |
| 5 | Performance Efficiency | Is auto-scaling configured? Is caching used where appropriate? |

## Rules

- **Serverless-first:** Always prefer Azure Functions over Container Apps over AKS unless the discovery output shows the workload requires containers or persistent connections.
- **Single-region default:** Deploy to a single Azure region unless `migration-assessment.md` explicitly shows multi-region requirements.
- **No API Management as primary router:** APIM is prohibited as the primary ingress. Use Azure Functions HTTP triggers or Front Door instead.
- **Never write Bicep or diagrams before `design-document.md` sections 1–6 are complete.**
- **Always read the matching `.github/skills/azure-architecture/<service>/SKILL.md`** before finalizing a service choice — never rely on training knowledge for SKU selection.
- **Always cite the knowledge skill consulted** in Section 3 of the design document: `> Consulted: azure-functions/SKILL.md §Compute Plans`.

## Output

`outputs/azure-architecture-output/design-document.md` with all 11 sections populated — the authoritative handoff artifact for iac-transformation, code-refactor, deployment-validation, and pipeline-builder agents.

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

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Well-Architected Framework | https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html |
| AWS Architecture Center | https://aws.amazon.com/architecture/ |
| AWS Migration whitepaper | https://docs.aws.amazon.com/whitepapers/latest/aws-migration-whitepaper/welcome.html |

### Best Practices

- **WAF Security is always Pillar 1** — a design that is cheap but insecure is not a valid design. Security trade-offs require explicit stakeholder sign-off.
- **Single-region by default:** Multi-region adds 2× infrastructure cost and significant operational complexity. Only add it if `migration-assessment.md` documents a sub-1-hour RTO requirement that cannot be met with Availability Zones.
- **Read the service-specific knowledge skill before finalizing** — SKU defaults and anti-patterns in memory may be outdated. The knowledge skills contain verified current guidance.
- **Always specify Section 5 fully:** Downstream iac-transformation, code-refactor, and pipeline-builder agents receive Section 5 (Bicep modules), 6 (Function rewrites), and 11 (CI/CD spec) as their primary inputs. Incomplete sections cause cascading failures.
