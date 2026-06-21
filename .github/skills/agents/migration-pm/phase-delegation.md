---
name: phase-delegation
description: Exact prompts, input artifacts, and output artifact checks for handing off each phase to the correct worker agent
---

# Phase Delegation Skill

## Purpose

Provide the exact delegation prompt, required input artifacts, and artifact completion checks for each of the 6 migration pipeline phases so handoffs are consistent and verifiable.

## When to Use

When the `orchestration` skill determines the next phase to run.

## Process

For each phase below: send the exact prompt to the agent, then run the listed artifact checks.

---

### Phase 1 — AWS Discovery → `@aws-discovery`

**Prompt:**
```
Perform a complete discovery of the AWS account. Generate all four output files:
- outputs/aws-migration-artifacts/aws-inventory.json
- outputs/aws-migration-artifacts/architecture-diagram.mmd
- outputs/aws-migration-artifacts/dependency-matrix.csv
- outputs/aws-migration-artifacts/migration-assessment.md
Do not use AWS CLI commands; use the AWS MCP server for discovery.
```

**Artifact checks (all must exist and be non-empty):**
- `outputs/aws-migration-artifacts/aws-inventory.json`
- `outputs/aws-migration-artifacts/architecture-diagram.mmd`
- `outputs/aws-migration-artifacts/dependency-matrix.csv`
- `outputs/aws-migration-artifacts/migration-assessment.md`

---

### Phase 2 — Architecture → `@azure-architect`

**Prompt:**
```
Read all AWS discovery artifacts in outputs/aws-migration-artifacts/ and produce:
- outputs/azure-architecture-output/design-document.md  (all 11 sections)
- outputs/azure-architecture-output/architecture-diagram-azure.mmd
- outputs/azure-architecture-output/cost-comparison.md
- outputs/azure-architecture-output/service-mapping.md
Section 5 must specify every Bicep module. Section 6 must specify every Lambda-to-Function rewrite.
Section 11 must specify every GitHub Actions workflow, OIDC config, and secrets.
```

**Artifact checks:**
- `outputs/azure-architecture-output/design-document.md` — must contain `## 11. CI/CD Pipeline Architecture`
- `outputs/azure-architecture-output/architecture-diagram-azure.mmd`
- `outputs/azure-architecture-output/cost-comparison.md`
- `outputs/azure-architecture-output/service-mapping.md`

---

### Phase 3a — IaC Transformation → `@iac-transformation`

**Prompt:**
```
Read Section 5 of outputs/azure-architecture-output/design-document.md. Generate every Bicep module described there. Write all output to outputs/bicep-templates/. Use only MCP servers — no CLI commands.
```

**Artifact checks:**
- `outputs/bicep-templates/main.bicep`
- At least one file under `outputs/bicep-templates/modules/`
- `outputs/bicep-templates/parameters/dev.bicepparam`

---

### Phase 3b — Code Refactor → `@code-refactor`

**Prompt:**
```
Read Section 6 of outputs/azure-architecture-output/design-document.md. Rewrite each Lambda handler as an Azure Function using the trigger type, SDK packages, environment variable names, and auth pattern specified. Write output to outputs/azure-functions/. Use only MCP servers — no CLI commands.
```

**Artifact checks:**
- `outputs/azure-functions/function_app.py`
- `outputs/azure-functions/requirements.txt`
- `outputs/azure-functions/host.json`

---

### Phase 3c — Pipeline Build → `@pipeline-builder-agent`

**Prompt:**
```
Read Section 11 of outputs/azure-architecture-output/design-document.md. Implement every GitHub Actions workflow in Section 11.1 using the OIDC config from 11.2, job specs from 11.3, multi-env strategy from 11.4, and dependency order from 11.5. Write all workflows to .github/workflows/.
```

**Artifact checks:**
- At least one `.yml` file under `.github/workflows/`
- An IaC deployment workflow file exists (filename contains `infra` or `deploy`)

---

### Phase 4 — Validation → `@deployment-validation`

**Prompt:**
```
Validate the full Azure migration using the checklist in Section 10 of outputs/azure-architecture-output/design-document.md. Run all pre-deployment checks, smoke tests, and security compliance checks. Write the final report to outputs/validation-report.md with PASSED or FAILED status at the top.
```

**Artifact checks:**
- `outputs/validation-report.md` — must begin with `## Status: PASSED` or `## Status: FAILED`

---

## Rules

- **Always send the exact prompt** — do not paraphrase or abbreviate.
- **Always verify artifacts by reading the file**, not by trusting the agent response.
- **If an artifact check fails**, mark the phase `❌` and stop — do not proceed.

## Output

Completed artifact checks for the delegated phase; updated `migration-task-plan.md` with phase status.
