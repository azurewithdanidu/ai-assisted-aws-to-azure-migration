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
