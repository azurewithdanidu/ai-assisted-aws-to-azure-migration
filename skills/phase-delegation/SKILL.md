---
name: phase-delegation
description: 'Delegate each migration phase with consistent prompts and verifiable outputs. Use when: sending work to aws-discovery, azure-architect, iac-transformation, code-refactor, pipeline-builder-agent, or deployment-validation and checking returned artifacts for completeness.'
---

# Phase Delegation Skill

## Purpose

Standardize phase handoffs so every worker receives the same instructions, writes to the same paths, updates the shared task plan correctly, and returns artifacts that can be verified objectively.

## When to Use

- Whenever orchestration decides the next phase to run
- When rerunning a failed phase
- When resuming a migration after a partial stop
- When auditing whether a worker produced enough output to count as complete

## Inputs

| Path | Why it is required |
|---|---|
| `outputs/migration-task-plan.md` | Shared status file the worker must update only within its phase section |
| `source-app/` | Read-only application source and docs |
| `outputs/aws-migration-artifacts/` | Required before Phase 2 |
| `outputs/azure-architecture-output/` | Required before Phase 3 and Phase 4 |
| `outputs/bicep-templates/` | Required before Phase 4 |
| `outputs/azure-functions/` | Required before Phase 4 |
| `.github/workflows/` | Required before Phase 4 |

## Outputs

| Path | Result |
|---|---|
| `outputs/aws-migration-artifacts/` | Phase 1 artifacts |
| `outputs/azure-architecture-output/` | Phase 2 artifacts |
| `outputs/bicep-templates/` | Phase 3a artifacts |
| `outputs/azure-functions/` | Phase 3b artifacts |
| `.github/workflows/` | Phase 3c artifacts |
| `outputs/validation-report.md` | Phase 4 artifact |

## Process

1. Read `outputs/migration-task-plan.md` before delegating.
2. Confirm prerequisite artifacts exist for the target phase.
3. Copy the exact prompt block for the phase.
4. Replace only placeholder values such as `<AWS_ACCOUNT_ID>` and `<AWS_REGION>`.
5. Do not paraphrase or shorten the prompt.
6. After the worker returns, verify every required artifact listed for that phase.
7. If any assertion fails, follow the re-delegation procedure at the end of this file.

## Exact Phase Prompts and Acceptance Checks

### Phase 1 — AWS Discovery → `@aws-discovery`

**Copy-paste prompt**

```text
You are executing Phase 1 — AWS Discovery for the AWS-to-Azure migration factory.

AWS Account ID: <AWS_ACCOUNT_ID>
AWS Region: <AWS_REGION>

Inputs:
- Read-only source application: source-app/
- Shared task plan: outputs/migration-task-plan.md

Required outputs:
- outputs/aws-migration-artifacts/aws-inventory.json
- outputs/aws-migration-artifacts/architecture-diagram.mmd
- outputs/aws-migration-artifacts/dependency-matrix.csv
- outputs/aws-migration-artifacts/migration-assessment.md

Requirements:
1. Read skills/aws-inventory-scan/SKILL.md before writing aws-inventory.json,
   architecture-diagram.mmd, and dependency-matrix.csv — it defines the exact schemas,
   output structure, dependency relationship verbs, and validation checklist.
2. Read skills/migration-assessment/SKILL.md before writing migration-assessment.md
   — it defines the required sections, complexity scoring tables, and risk flag catalogue.
3. Use AWS MCP server capabilities only — do not use AWS CLI commands.
4. Read source-app/ (template.yaml, Lambda source files, docs) before writing any outputs
   to cross-check deployed resources and discover implicit boto3 SDK dependencies not
   declared in the CloudFormation/SAM template.
5. Discover resources across all active regions, not just <AWS_REGION>.
6. Generate all four output files even if a partial blocker is encountered —
   record any blocker in migration-assessment.md and continue with remaining outputs.
7. Update only your Phase 1 row and Phase 1 task list in outputs/migration-task-plan.md
   incrementally as you work — do not wait until the end.
8. If MCP authentication fails, stop immediately and report the exact error —
   do not attempt discovery without confirmed credentials.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `outputs/aws-migration-artifacts/aws-inventory.json` | Exists, non-empty, and contains structured JSON content with at least one discovered service or resource record |
| `outputs/aws-migration-artifacts/architecture-diagram.mmd` | Exists, non-empty, and contains `graph` or `flowchart` |
| `outputs/aws-migration-artifacts/dependency-matrix.csv` | Exists, non-empty, and contains at least two lines (header + one data row) |
| `outputs/aws-migration-artifacts/migration-assessment.md` | Exists, non-empty, and contains at least one `##` heading plus findings or recommendations |

### Phase 2 — Architecture → `@azure-architect`

**Copy-paste prompt**

```text
You are executing Phase 2 — Architecture Design for the AWS-to-Azure migration factory.

Inputs:
- AWS Account ID: <AWS_ACCOUNT_ID>
- AWS Region: <AWS_REGION>
- outputs/aws-migration-artifacts/aws-inventory.json
- outputs/aws-migration-artifacts/architecture-diagram.mmd
- outputs/aws-migration-artifacts/dependency-matrix.csv
- outputs/aws-migration-artifacts/migration-assessment.md
- Read-only source application: source-app/
- Shared task plan: outputs/migration-task-plan.md

Required outputs:
- outputs/azure-architecture-output/design-document.md
- outputs/azure-architecture-output/architecture-diagram-azure.mmd
- outputs/azure-architecture-output/cost-comparison.md
- outputs/azure-architecture-output/service-mapping.md

Requirements:
1. Read skills/architecture-design/SKILL.md for WAF-aligned service selection and design decisions.
2. Read skills/aws-to-azure-mapping/SKILL.md for AWS→Azure service equivalents when writing
   service-mapping.md and Section 3.
3. Read skills/architecture-diagramming/SKILL.md before writing architecture-diagram-azure.mmd.
4. Read skills/cost-estimator/SKILL.md and skills/cost-analysis/SKILL.md before writing
   cost-comparison.md.
5. Read skills/azure-security-patterns/SKILL.md and skills/azure-auth-patterns/SKILL.md before
   writing Section 7 (Security Design).
6. Read every discovery artifact before writing anything.
7. Write outputs/azure-architecture-output/design-document.md first.
8. The design document must include all 11 required sections:
   1. Executive Summary
   2. Current State
   3. Service Mapping
   4. Target Architecture
   5. Bicep Module Spec
   6. Function Rewrite Spec
   7. Security Design
   8. Networking Design
   9. Monitoring Design
   10. Cost Estimate
   11. CI/CD Spec
9. Section 5 must specify every Bicep module. Section 6 must specify every Lambda-to-Function
   rewrite. Section 11 must specify every GitHub Actions workflow, OIDC config, and secrets.
10. Update only your Phase 2 row and Phase 2 task list in outputs/migration-task-plan.md
    incrementally as you work.
11. Make the design document explicit enough that Phase 3 and Phase 4 can proceed without
    rediscovery.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `outputs/azure-architecture-output/design-document.md` | Exists, non-empty, and contains all 11 required section headings exactly once or more |
| `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Exists, non-empty, contains Mermaid syntax, and includes at least one `subgraph` |
| `outputs/azure-architecture-output/cost-comparison.md` | Exists, non-empty, and contains a monthly summary table plus break-even analysis |
| `outputs/azure-architecture-output/service-mapping.md` | Exists, non-empty, and contains a table with AWS and Azure mapping columns |

### Phase 3a — IaC Transformation → `@iac-transformation`

**Copy-paste prompt**

```text
You are executing Phase 3a — IaC Transformation for the AWS-to-Azure migration factory.

Inputs:
- outputs/azure-architecture-output/design-document.md
- Read Section 5 (Bicep Module Spec) in full before writing any files.
- Shared task plan: outputs/migration-task-plan.md

Required outputs:
- outputs/bicep-templates/main.bicep
- outputs/bicep-templates/modules/<module>.bicep for every module in Section 5
- outputs/bicep-templates/parameters/dev.bicepparam
- outputs/bicep-templates/parameters/staging.bicepparam
- outputs/bicep-templates/parameters/prod.bicepparam

Requirements:
1. Read skills/bicep-generation/SKILL.md for naming conventions, parameter decorators, and
   required outputs.
2. Read skills/module-organization/SKILL.md for how to organise modules into
   networking/storage/security/compute/messaging/monitoring.
3. Read skills/parameter-management/SKILL.md before writing dev/staging/prod .bicepparam files.
4. Read skills/azure-security-patterns/SKILL.md for private endpoint and NSG patterns.
5. Read skills/azure-auth-patterns/SKILL.md for system-assigned Managed Identity and RBAC role
   assignments in Bicep.
6. Implement every module described in Section 5.
7. Keep main.bicep as the orchestration template and put implementation details in modules/.
8. Use secure defaults, managed identity, and current API versions.
9. Update only your Phase 3a row and Phase 3a task list in outputs/migration-task-plan.md
   incrementally as you work.
10. If Section 5 is incomplete or ambiguous, stop and mark a blocker instead of guessing.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `outputs/bicep-templates/main.bicep` | Exists, non-empty, and contains at least one `module` declaration or root orchestration logic |
| `outputs/bicep-templates/modules/` | Contains at least one non-empty `.bicep` file |
| `outputs/bicep-templates/parameters/dev.bicepparam` | Exists, non-empty, and references `main.bicep` |
| `outputs/bicep-templates/parameters/staging.bicepparam` | Exists and is non-empty |
| `outputs/bicep-templates/parameters/prod.bicepparam` | Exists and is non-empty |

### Phase 3b — Code Refactor → `@code-refactor`

**Copy-paste prompt**

```text
You are executing Phase 3b — Code Refactor for the AWS-to-Azure migration factory.

Inputs:
- outputs/azure-architecture-output/design-document.md
- Read Section 6 (Function Rewrite Spec) in full before writing any files.
- Read-only source application: source-app/
- Shared task plan: outputs/migration-task-plan.md

Required outputs:
- outputs/azure-functions/function_app.py
- outputs/azure-functions/requirements.txt
- outputs/azure-functions/host.json
- any supporting files needed by the rewritten Azure Functions app

Requirements:
1. Read skills/lambda-to-functions/SKILL.md for trigger mapping, host.json format, and
   requirements.txt structure.
2. Read skills/sdk-migration/SKILL.md for boto3→Azure SDK replacement patterns
   (S3→Blob, DynamoDB→CosmosDB, SQS→Service Bus, Secrets→Key Vault).
3. Read skills/azure-auth-patterns/SKILL.md for DefaultAzureCredential and Managed Identity
   patterns.
4. Rewrite each Lambda handler described in Section 6 as an Azure Function.
5. Use the trigger type, authentication pattern, SDK mapping, and environment variable names
   defined in the design document.
6. Read source-app/ (Lambda handlers, SAM template) to understand existing business logic
   before rewriting — do not modify source-app/.
7. Update only your Phase 3b row and Phase 3b task list in outputs/migration-task-plan.md
   incrementally as you work.
8. If the rewrite specification is incomplete, stop and record a blocker instead of inventing
   interfaces.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `outputs/azure-functions/function_app.py` | Exists, non-empty, and contains an Azure Functions application definition such as `FunctionApp` |
| `outputs/azure-functions/requirements.txt` | Exists, non-empty, and includes `azure-functions` plus required Azure SDK packages |
| `outputs/azure-functions/host.json` | Exists, non-empty, and contains JSON configuration |

### Phase 3c — Pipeline Build → `@pipeline-builder-agent`

**Copy-paste prompt**

```text
You are executing Phase 3c — Pipeline Build for the AWS-to-Azure migration factory.

Inputs:
- outputs/azure-architecture-output/design-document.md
- Read Section 11 (CI/CD Spec) in full before writing any files.
- Shared task plan: outputs/migration-task-plan.md

Required outputs:
- one or more workflow files under .github/workflows/
- at least one infrastructure deployment workflow
- environment and OIDC references aligned with the CI/CD specification

Requirements:
1. Read skills/github-actions-oidc/SKILL.md for app registration, federated credential
   creation, and azure/login@v2 YAML snippet.
2. Read skills/multi-env-strategy/SKILL.md for branch-to-environment mapping and GitHub
   Environment protection rules.
3. Read skills/workflow-generation/SKILL.md for IaC deployment YAML patterns
   (what-if + deploy + rollback) and Functions deployment YAML.
4. Implement every workflow listed in Section 11.1.
5. Use OIDC / workload identity, not long-lived Azure secrets.
6. Encode dev, staging, and prod promotion logic in the workflow design.
7. Update only your Phase 3c row and Phase 3c task list in outputs/migration-task-plan.md
   incrementally as you work.
8. If Section 11 lacks exact deployment details, stop and record a blocker instead of
   inventing workflow behavior.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `.github/workflows/` | Contains at least one `.yml` or `.yaml` file |
| one workflow file with `infra` or `deploy` in the file name | Contains Azure login and deployment steps |
| every created workflow file | Non-empty and includes a valid `on:` trigger block |

### Phase 4 — Validation → `@deployment-validation`

**Copy-paste prompt**

```text
You are executing Phase 4 — Validation for the AWS-to-Azure migration factory.

Inputs:
- outputs/azure-architecture-output/design-document.md
- outputs/azure-architecture-output/architecture-diagram-azure.mmd
- outputs/azure-architecture-output/cost-comparison.md
- outputs/bicep-templates/
- outputs/azure-functions/
- .github/workflows/
- Shared task plan: outputs/migration-task-plan.md

Required output:
- outputs/validation-report.md

Requirements:
1. Read skills/what-if-validation/SKILL.md before running any what-if checks.
2. Read skills/smoke-testing/SKILL.md for HTTP endpoint checks, Managed Identity verification,
   Key Vault resolution, and end-to-end tests.
3. Read skills/azure-security-patterns/SKILL.md for security pattern verification checks.
4. Validate the generated solution against the architecture, security, networking, monitoring,
   and CI/CD specifications in the design document.
5. Confirm that the report begins with either `## Status: PASSED` or `## Status: FAILED`.
6. Summarize what was checked, what passed, what failed, and what must be remediated next.
7. Update only your Phase 4 row and Phase 4 task list in outputs/migration-task-plan.md.
8. If prerequisite artifacts are missing, mark the phase as failed and name the missing
   prerequisite explicitly.
```

**Artifact acceptance checks**

| Path | Minimum assertion |
|---|---|
| `outputs/validation-report.md` | Exists, non-empty, and begins with `## Status: PASSED` or `## Status: FAILED` |
| `outputs/validation-report.md` | Contains a summary of checks performed and remediation notes for failures |

## Re-delegation Procedure for Incomplete Artifacts

Use this workflow when a phase returns but the artifact checks do not pass:

1. Read the returned artifacts and list the exact failing assertions.
2. Update `outputs/migration-task-plan.md` with the failing phase status:
   - keep `🔄` only if you are immediately retrying once
   - use `❌` if a blocker must be surfaced before retry
3. Re-read the prerequisite inputs to ensure the worker did not fail because of missing upstream context.
4. Re-send the same phase prompt unchanged, then append this repair section:

```text
Repair Request:
- Reuse the same output paths.
- Fix only the failed assertions listed below.
- Do not overwrite valid artifacts unnecessarily.
- Failed assertions:
  - <assertion 1>
  - <assertion 2>
```

5. Verify the repaired artifacts again from disk.
6. If the second attempt still fails the same assertion, stop, mark the phase `❌`, and record a blocker with the broken file path and next owner action.

## Edge Cases / Failure Modes

- **Worker wrote to the wrong directory:** treat as failed even if the content is good; the pipeline depends on exact paths.
- **Worker updated the wrong phase rows:** preserve evidence, correct the plan, and note the conflict if it obscures ownership.
- **Partial success:** accept only the subset that passed, but do not mark the phase `✅` until all required artifacts pass.
- **Upstream ambiguity:** if the design document is missing detail, route the failure back to architecture instead of improvising in Phase 3 or Phase 4.
- **Whitespace-only output or stub headings:** fail the artifact; placeholders are not deliverables.

## Rules

- **Always send the exact prompt block.**
- **Always verify artifacts from the filesystem, not from chat text.**
- **Never change output paths unless the architecture skill itself changed the contract.**
- **Never accept a phase with only some required artifacts present.**
- **Never let a downstream phase compensate for an upstream missing artifact.**

## Best Practices

- Keep failure feedback concrete: file path plus failed assertion.
- Re-delegate once for repairable defects; escalate quickly when the upstream contract is the real problem.
- Substitute placeholders only; any wording drift in the prompt increases output variance.
- Use the task-tracking skill conventions during every retry so the plan remains trustworthy.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Migrate — migration execution guide | https://learn.microsoft.com/en-us/azure/migrate/migrate-services-overview |
| Cloud Adoption Framework — migration checklist | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/migrate/azure-migration-guide/migrate |
| Cloud Adoption Framework — validate and promote | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/migrate/azure-migration-guide/optimize-and-transform |

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Migration Hub — tracking migrations | https://docs.aws.amazon.com/migrationhub/latest/ug/tracking-migration-tasks.html |
| AWS Migration Evaluator | https://aws.amazon.com/migration-evaluator/ |

### Best Practices

- **Prompts are contracts** — the exact wording and output paths matter because downstream verification depends on them.
- **A missing or malformed file is a phase failure, not a cosmetic issue** — capture it precisely and route it to the right owner.
- **Repair only what failed** — preserve valid work when issuing a re-delegation request.
