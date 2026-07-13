---
name: orchestration
description: 'Coordinate the 6-phase AWS-to-Azure migration pipeline. Use when: starting a migration, resuming from discovery or architecture or parallel or validation, verifying artifacts, or escalating blockers in outputs/migration-task-plan.md.'
---

# Orchestration Skill

## Purpose

Coordinate the documented six-phase migration pipeline end to end, keep `outputs/migration-task-plan.md` authoritative, and advance only when upstream artifacts are present, non-empty, and minimally valid.

## When to Use

- At migration start, before any worker agent runs
- After any phase reports completion
- When resuming from `discovery`, `architecture`, `parallel`, or `validation`
- When a user asks for current status without running more work
- When any artifact check fails and a blocker or retry decision is needed

## Inputs

| Path | Why it matters |
|---|---|
| `outputs/migration-task-plan.md` | Durable source of truth for phase state, timestamps, and blockers |
| `outputs/aws-migration-artifacts/aws-inventory.json` | Required to prove Phase 1 completed |
| `outputs/aws-migration-artifacts/architecture-diagram.mmd` | Discovery architecture baseline |
| `outputs/aws-migration-artifacts/dependency-matrix.csv` | Dependency evidence for design and sequencing |
| `outputs/aws-migration-artifacts/migration-assessment.md` | Migration findings and risks |
| `outputs/azure-architecture-output/design-document.md` | Mandatory handoff artifact for all Phase 3 work |
| `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Azure target topology evidence |
| `outputs/azure-architecture-output/cost-comparison.md` | Cost decision evidence |
| `outputs/azure-architecture-output/service-mapping.md` | Service equivalence evidence |
| `outputs/bicep-templates/` | Phase 3a outputs to verify |
| `outputs/azure-functions/` | Phase 3b outputs to verify |
| `.github/workflows/` | Phase 3c outputs to verify |
| `outputs/validation-report.md` | Final validation artifact |

## Outputs

| Path | Expected state |
|---|---|
| `outputs/migration-task-plan.md` | Created at start, then updated after every verification step |
| `outputs/aws-migration-artifacts/` | Discovery artifacts verified before Phase 2 |
| `outputs/azure-architecture-output/` | Architecture artifacts verified before Phase 3 |
| `outputs/bicep-templates/` | IaC outputs verified before validation |
| `outputs/azure-functions/` | Refactored function outputs verified before validation |
| `.github/workflows/` | Pipeline outputs verified before validation |
| `outputs/validation-report.md` | Final `PASSED` or `FAILED` validation report |

## Process

### 1. Pre-flight

1. Read `outputs/migration-task-plan.md` if it already exists.
2. If the file does not exist, create it using the full template from `skills/task-tracking/SKILL.md`.
3. Record the current UTC timestamp in ISO 8601 format.
4. Confirm the run mode:
   - `full` or no argument
   - `resume discovery`
   - `resume architecture`
   - `resume parallel`
   - `resume validation`
   - `status`
5. If the request is `status`, do not invoke worker agents; only read and summarize.

### 2. Write the Phase Summary table at migration start

Copy this section exactly into `outputs/migration-task-plan.md` when initializing a migration:

```markdown
## Phase Summary

| Phase | Owner | Artifact Root | Status | Completed At |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | `outputs/aws-migration-artifacts/` | ⏳ | — |
| 2 — Architecture | azure-architect | `outputs/azure-architecture-output/` | ⏳ | — |
| 3a — IaC Transformation | iac-transformation | `outputs/bicep-templates/` | ⏳ | — |
| 3b — Code Refactor | code-refactor | `outputs/azure-functions/` | ⏳ | — |
| 3c — Pipeline Build | pipeline-builder-agent | `.github/workflows/` | ⏳ | — |
| 4 — Validation | deployment-validation | `outputs/validation-report.md` | ⏳ | — |
```

### 3. Standard execution order

```text
Phase 1 Discovery
    ↓
Phase 2 Architecture
    ↓
Phase 3a IaC  ─┐
Phase 3b Code ─┼─ run together when more than one Phase 3 stream is incomplete
Phase 3c CI/CD ┘
    ↓
Phase 4 Validation
```

1. Do not advance to a downstream phase until the current phase passes verification.
2. Treat Phase 3 as a coordination group, not a single artifact.
3. Read `design-document.md` Sections 5, 6, and 11 after Phase 2 and expand the Phase 3 task lists before any Phase 3 verification is finalized.

### 4. Resume-from-phase procedure

Follow this exact recovery workflow:

1. Read the latest `outputs/migration-task-plan.md`.
2. Identify the requested resume point or the first phase that is not `✅`.
3. Re-run artifact checks for every prerequisite phase.
4. If a prerequisite row shows `✅` but the artifact check fails, immediately change that row to `❌`, add a blocker, and stop.
5. If a prerequisite row is stale (`⏳` or `🔄`) but all required artifacts exist and pass checks, repair the row to `✅` and write the recovery timestamp.
6. Mark the resumed phase `🔄` only after prerequisites pass.
7. Re-read the plan again before each write so concurrent updates are not lost.

#### Resume `discovery`

- Allowed when no later phase has valid artifacts yet, or when Phase 1 artifacts are missing or invalid.
- Before running, confirm that later phases are either `⏳`, `🔄`, or already marked `❌` because of discovery issues.
- After success, reset downstream phases only if their artifacts are now inconsistent with the new discovery set.

#### Resume `architecture`

- Require all Phase 1 artifacts to exist and be non-empty.
- Re-check these paths before invoking the architect:
  - `outputs/aws-migration-artifacts/aws-inventory.json`
  - `outputs/aws-migration-artifacts/architecture-diagram.mmd`
  - `outputs/aws-migration-artifacts/dependency-matrix.csv`
  - `outputs/aws-migration-artifacts/migration-assessment.md`
- If any are missing, downgrade the run to `resume discovery` and record why.

#### Resume `parallel`

- Require all Phase 2 artifacts to exist and be non-empty.
- Re-check these paths before invoking any Phase 3 stream:
  - `outputs/azure-architecture-output/design-document.md`
  - `outputs/azure-architecture-output/architecture-diagram-azure.mmd`
  - `outputs/azure-architecture-output/cost-comparison.md`
  - `outputs/azure-architecture-output/service-mapping.md`
- Inspect Phase 3a, 3b, and 3c individually:
  - if two or three streams are incomplete, launch all incomplete streams in parallel
  - if exactly one stream is incomplete, rerun only that stream
  - if any stream is `❌`, repair or re-delegate only the failing stream unless the architecture artifact changed

#### Resume `validation`

- Require all completed Phase 3 streams to pass artifact checks.
- If any Phase 3 artifact is missing or invalid, do not run validation; route back to the failing stream.
- Only when 3a, 3b, and 3c all pass may Phase 4 start.

### 5. Artifact checklist per phase

A phase is not complete until every listed artifact exists, is non-empty, and meets the minimum content assertion.

| Phase | Required artifact | Minimum assertion |
|---|---|---|
| 1 | `outputs/aws-migration-artifacts/aws-inventory.json` | Valid JSON-like content, not an empty object or empty array |
| 1 | `outputs/aws-migration-artifacts/architecture-diagram.mmd` | Contains `graph` or `flowchart` |
| 1 | `outputs/aws-migration-artifacts/dependency-matrix.csv` | At least a header row plus one dependency row |
| 1 | `outputs/aws-migration-artifacts/migration-assessment.md` | Contains at least one `##` heading and migration findings |
| 2 | `outputs/azure-architecture-output/design-document.md` | Contains all 11 required section headings |
| 2 | `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Contains Mermaid graph syntax plus at least one `subgraph` |
| 2 | `outputs/azure-architecture-output/cost-comparison.md` | Contains a monthly summary table and break-even section |
| 2 | `outputs/azure-architecture-output/service-mapping.md` | Contains AWS and Azure mapping columns |
| 3a | `outputs/bicep-templates/main.bicep` | References modules and builds logically from Section 5 |
| 3a | `outputs/bicep-templates/modules/*.bicep` | At least one module file exists and is non-empty |
| 3a | `outputs/bicep-templates/parameters/dev.bicepparam` | References `../main.bicep` or `main.bicep` |
| 3b | `outputs/azure-functions/function_app.py` | Contains Azure Functions app definition |
| 3b | `outputs/azure-functions/requirements.txt` | Lists `azure-functions` and needed Azure SDK packages |
| 3b | `outputs/azure-functions/host.json` | Non-empty JSON configuration |
| 3c | `.github/workflows/*.yml` or `.github/workflows/*.yaml` | At least one workflow file exists |
| 3c | one workflow file with `infra` or `deploy` in the file name | Contains Azure login and deployment steps |
| 4 | `outputs/validation-report.md` | Starts with `## Status: PASSED` or `## Status: FAILED` |

### 6. Decision tree: invoke Phase 3 in parallel or serial

Use this decision tree every time Phase 3 is reached or resumed:

```text
Have Phase 2 artifacts passed verification?
├─ No  → Stop. Fix or rerun Phase 2.
└─ Yes
   ↓
How many of 3a, 3b, 3c are not yet ✅?
├─ 3 incomplete → Launch 3a + 3b + 3c in one batched parallel block.
├─ 2 incomplete → Launch the two incomplete streams in parallel.
├─ 1 incomplete → Run only the remaining stream serially.
└─ 0 incomplete → Do not rerun Phase 3; proceed to Phase 4.
```

Additional rules:

- `full` runs from the start always launch all three Phase 3 streams together.
- `resume parallel` launches only the incomplete streams, but still launches them together when more than one remains.
- `phase 3a`, `phase 3b`, or `phase 3c` isolation requests are allowed to run serially because the user explicitly asked for a single stream.
- Verification can happen serially after the parallel launch completes, but invocation should not be artificially serialized when more than one stream remains.

### 7. Verification workflow after each phase

1. Read the worker response for claimed output paths.
2. Ignore the success claim until the artifacts are opened and checked.
3. Verify file existence first.
4. Verify non-empty content second.
5. Verify minimum content assertions third.
6. Update `outputs/migration-task-plan.md` only after the checks pass.
7. If any check fails, add a blocker entry immediately.

### 8. Error escalation runbook

Use this runbook to keep failures consistent and recoverable:

| Severity | Trigger | Required response |
|---|---|---|
| Level 1 — Missing file | Expected artifact path does not exist | Re-read the phase prompt, re-delegate once with the missing file list, keep phase `🔄` during retry |
| Level 2 — Empty or malformed file | File exists but is empty, whitespace-only, or lacks required headings/content | Mark the phase `❌`, record the exact failing assertion, then re-delegate only if the defect is repairable without changing upstream design |
| Level 3 — Upstream/downstream mismatch | Phase output contradicts a prerequisite artifact, for example Bicep modules not present in Section 5 | Mark the current phase `❌`, add a blocker naming the conflicting upstream source, stop and route back to the prerequisite phase owner |
| Level 4 — External dependency failure | Credentials, MCP servers, required tooling, or repository permissions unavailable | Mark the phase `❌`, note the external dependency in `## Blockers`, stop and surface the unblock action |

**Blocker format:**

```markdown
- Phase <phase-id> (<owner>): <what failed> — <exact unblock action>
```

### 9. Edge Cases / Failure Modes

- **Stale success row:** `migration-task-plan.md` says `✅`, but the file was deleted later. Treat the artifact as authoritative and downgrade the row to `❌`.
- **Partial Phase 3 completion:** One Phase 3 stream is `✅`, another `🔄`, another `❌`. Re-run only the failing or incomplete streams unless Phase 2 changed.
- **Architecture drift after Phase 2:** If `design-document.md` is rewritten, re-check whether existing Phase 3 artifacts still align before accepting them.
- **Concurrent worker writes:** Always re-read the plan immediately before editing. Do not overwrite other phase rows.
- **Whitespace-only output:** A file containing just a heading or comment still fails the minimum-content rule.
- **Ambiguous resume point:** If multiple earlier phases are incomplete or invalid, resume from the earliest invalid prerequisite.

## Rules

- **Never trust an agent success message without reading the artifacts.**
- **Never advance to a later phase while an earlier prerequisite is `❌`.**
- **Never overwrite another phase row or task list during a parallel run.**
- **Never skip the `design-document.md` read before coordinating Phase 3.**
- **Never mark a phase `✅` if the artifact exists but is empty, placeholder-only, or structurally incomplete.**
- **Always stop after recording a blocker when the runbook says to stop.**

## Best Practices

- Keep the task plan open as the operational dashboard and re-read it before every update.
- Prefer the earliest valid resume point rather than patching downstream artifacts blindly.
- Treat Phase 2 as the contract for Phase 3; if the contract changes, verify all dependent work again.
- Write blocker messages that a different agent could act on without additional explanation.
- When fixing a failed phase, cite the exact artifact path and assertion that failed.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Migrate overview | https://learn.microsoft.com/en-us/azure/migrate/migrate-services-overview |
| Cloud Adoption Framework — migrate | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/migrate/ |
| Cloud Adoption Framework — migration landing zone | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/migrate/azure-migration-guide/ |
| Azure DevOps migration guide | https://learn.microsoft.com/en-us/azure/devops/migrate/migration-overview |

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Migration Hub | https://docs.aws.amazon.com/migrationhub/latest/ug/whatishub.html |
| AWS Migration Acceleration Program | https://aws.amazon.com/migration-acceleration-program/ |
| AWS 7 Rs migration strategies | https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-retiring-applications/apg-gloss.html |

### Best Practices

- **Phase 3 parallelism is a throughput optimization, not a correctness shortcut** — prerequisite validation still happens before and after the parallel wave.
- **Artifacts beat memory** — the plan file and generated outputs are the source of truth, not prior agent replies.
- **Resume by evidence** — use the earliest invalid artifact, not the latest claimed status, to decide where to restart.
- **Block fast, unblock precisely** — each blocker should name the broken file, the failed assertion, and the next owner action.
