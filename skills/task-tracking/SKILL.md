---
name: task-tracking
description: 'Keep outputs/migration-task-plan.md synchronized with real migration progress. Use when: creating the task plan, updating phase rows, resolving concurrent writes, recording blockers, or resuming a six-phase migration run.'
---

# Task Tracking Skill

## Purpose

Maintain `outputs/migration-task-plan.md` as the durable, phase-by-phase control plane for the migration. Every worker agent updates only its own rows and checkboxes; the plan must always match artifact reality.

## When to Use

- At migration initialization, before Phase 1 starts
- At the start and end of every phase
- Immediately after any task-level artifact is produced
- When a retry, blocker, or resume event changes phase state
- Whenever two or more agents may touch `outputs/migration-task-plan.md` concurrently

## Inputs

| Path | Purpose |
|---|---|
| `outputs/migration-task-plan.md` | File to create, read, update, and reconcile |
| `outputs/aws-migration-artifacts/` | Phase 1 artifact evidence |
| `outputs/azure-architecture-output/` | Phase 2 artifact evidence |
| `outputs/bicep-templates/` | Phase 3a artifact evidence |
| `outputs/azure-functions/` | Phase 3b artifact evidence |
| `.github/workflows/` | Phase 3c artifact evidence |
| `outputs/validation-report.md` | Phase 4 artifact evidence |

## Outputs

| Path | Result |
|---|---|
| `outputs/migration-task-plan.md` | Complete migration plan with status summary, detailed tasks, timestamps, and blockers |

## Process

### 1. Create the plan at migration start

If `outputs/migration-task-plan.md` does not exist, create it with this full template:

```markdown
# Migration Task Plan

Generated: <UTC-ISO-8601>
Last Updated: <UTC-ISO-8601>
Current Resume Point: discovery

## Migration Scope

| Field | Value |
|---|---|
| AWS Account ID | <aws-account-id> |
| AWS Region | <aws-region> |
| Source Application Root | `source-app/` |
| Output Root | `outputs/` |
| Workflow Root | `.github/workflows/` |

## Status Legend

| Symbol | Meaning |
|---|---|
| ⏳ | Not started |
| 🔄 | In progress |
| ✅ | Complete |
| ❌ | Failed / Blocked |

## Phase Summary

| Phase | Owner | Artifact Root | Status | Completed At |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | `outputs/aws-migration-artifacts/` | ⏳ | — |
| 2 — Architecture | azure-architect | `outputs/azure-architecture-output/` | ⏳ | — |
| 3a — IaC Transformation | iac-transformation | `outputs/bicep-templates/` | ⏳ | — |
| 3b — Code Refactor | code-refactor | `outputs/azure-functions/` | ⏳ | — |
| 3c — Pipeline Build | pipeline-builder-agent | `.github/workflows/` | ⏳ | — |
| 4 — Validation | deployment-validation | `outputs/validation-report.md` | ⏳ | — |

## Detailed Task List

### Phase 1 — AWS Discovery
- [ ] Discover AWS services, regions, and dependencies from the source workload
- [ ] Write `outputs/aws-migration-artifacts/aws-inventory.json`
- [ ] Write `outputs/aws-migration-artifacts/architecture-diagram.mmd`
- [ ] Write `outputs/aws-migration-artifacts/dependency-matrix.csv`
- [ ] Write `outputs/aws-migration-artifacts/migration-assessment.md`

### Phase 2 — Azure Architecture
- [ ] Read all artifacts in `outputs/aws-migration-artifacts/`
- [ ] Write `outputs/azure-architecture-output/design-document.md`
- [ ] Write `outputs/azure-architecture-output/architecture-diagram-azure.mmd`
- [ ] Write `outputs/azure-architecture-output/cost-comparison.md`
- [ ] Write `outputs/azure-architecture-output/service-mapping.md`
- [ ] Replace Phase 3 placeholders using Sections 5, 6, and 11 of `design-document.md`

### Phase 3a — IaC Transformation
- [ ] Read Section 5 of `outputs/azure-architecture-output/design-document.md`
- [ ] Write `outputs/bicep-templates/main.bicep`
- [ ] Write module files under `outputs/bicep-templates/modules/`
- [ ] Write `outputs/bicep-templates/parameters/dev.bicepparam`
- [ ] Write `outputs/bicep-templates/parameters/staging.bicepparam`
- [ ] Write `outputs/bicep-templates/parameters/prod.bicepparam`

### Phase 3b — Code Refactor
- [ ] Read Section 6 of `outputs/azure-architecture-output/design-document.md`
- [ ] Write `outputs/azure-functions/function_app.py`
- [ ] Write `outputs/azure-functions/host.json`
- [ ] Write `outputs/azure-functions/requirements.txt`
- [ ] Add one task per function rewrite from Section 6 when the design document is available

### Phase 3c — Pipeline Build
- [ ] Read Section 11 of `outputs/azure-architecture-output/design-document.md`
- [ ] Write workflow files under `.github/workflows/`
- [ ] Add one task per workflow from Section 11.1 when the design document is available
- [ ] Configure OIDC authentication in the workflow YAML
- [ ] Configure GitHub Environments for `dev`, `staging`, and `prod`

### Phase 4 — Validation
- [ ] Re-check Phase 1 through Phase 3 artifacts before validation starts
- [ ] Validate architecture, security, networking, monitoring, and deployment assumptions
- [ ] Write `outputs/validation-report.md`
- [ ] Record final PASSED or FAILED result and any remediation items

## Blockers

- None
```

### 2. Update rules during execution

**On phase start:**

1. Re-read the plan.
2. Change the phase row from `⏳` to `🔄`.
3. Update `Last Updated:`.
4. If this is a resume, also update `Current Resume Point:`.

**On task completion:**

1. Re-read the plan.
2. Change the specific `- [ ]` task to `- [x]`.
3. Append `— completed <UTC-ISO-8601>`.
4. Update `Last Updated:`.

**On phase completion:**

1. Re-read the plan.
2. Set the phase row to `✅`.
3. Write the `Completed At` timestamp.
4. Update `Current Resume Point:` to the next incomplete phase.
5. Update `Last Updated:`.

**On blocker or failure:**

1. Re-read the plan.
2. Set the phase row to `❌`.
3. Add or replace a bullet under `## Blockers` using the required format.
4. Update `Last Updated:`.
5. Stop writing unrelated plan changes.

### 3. Concurrent-write conflict resolution

Use this optimistic-lock pattern whenever multiple agents may write the same file:

1. **Read** the latest `outputs/migration-task-plan.md`.
2. **Prepare** a minimal edit affecting only your phase row and your phase task list.
3. **Re-read immediately before write**.
4. **Compare** the second read against the version you based your edit on.
5. If the file changed:
   - replay your edit onto the newest copy
   - never revert another phase from `✅` to `⏳`
   - never delete another agent's completion timestamp
6. **Write** the merged version.
7. If another change lands between steps 5 and 6, retry up to three times.
8. On the third failed retry, add a blocker noting a plan write conflict and stop.

#### Merge precedence rules

| Conflict type | Resolution |
|---|---|
| Same phase row, one copy is `❌` | Keep `❌` until artifacts are re-verified |
| Same task checkbox, one copy is `[x]` | Keep `[x]`; never downgrade to `[ ]` |
| Different timestamps for same completed item | Keep the newer timestamp only if the artifact still exists |
| Another phase changed while your phase did not | Replay your edit onto the newer file |
| Another phase inserted a blocker | Preserve it; append yours below if needed |

### 4. Timestamp format examples

Use UTC ISO 8601 timestamps only inside the plan file.

**Good examples**

- `2026-07-14T00:14:16Z`
- `2026-07-14T00:21:39Z`
- `Generated: 2026-07-14T00:14:16Z`
- `Last Updated: 2026-07-14T00:42:07Z`
- `- [x] Write outputs/aws-migration-artifacts/aws-inventory.json — completed 2026-07-14T00:21:39Z`

**Bad examples**

- `14/07/2026 10:14 PM`
- `2026-07-14 00:14:16`
- `Tue Jul 14 00:14:16 2026`
- `2026-07-14T10:14:16+10:00` inside the plan file

### 5. Mid-migration example

This is what a filled-in plan should look like after Phase 2 is complete and the parallel Phase 3 wave is underway:

```markdown
# Migration Task Plan

Generated: 2026-07-14T00:14:16Z
Last Updated: 2026-07-14T01:06:54Z
Current Resume Point: parallel

## Migration Scope

| Field | Value |
|---|---|
| AWS Account ID | 123456789012 |
| AWS Region | ap-southeast-2 |
| Source Application Root | `source-app/` |
| Output Root | `outputs/` |
| Workflow Root | `.github/workflows/` |

## Status Legend

| Symbol | Meaning |
|---|---|
| ⏳ | Not started |
| 🔄 | In progress |
| ✅ | Complete |
| ❌ | Failed / Blocked |

## Phase Summary

| Phase | Owner | Artifact Root | Status | Completed At |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | `outputs/aws-migration-artifacts/` | ✅ | 2026-07-14T00:28:04Z |
| 2 — Architecture | azure-architect | `outputs/azure-architecture-output/` | ✅ | 2026-07-14T00:54:41Z |
| 3a — IaC Transformation | iac-transformation | `outputs/bicep-templates/` | 🔄 | — |
| 3b — Code Refactor | code-refactor | `outputs/azure-functions/` | 🔄 | — |
| 3c — Pipeline Build | pipeline-builder-agent | `.github/workflows/` | ✅ | 2026-07-14T01:05:12Z |
| 4 — Validation | deployment-validation | `outputs/validation-report.md` | ⏳ | — |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover AWS services, regions, and dependencies from the source workload — completed 2026-07-14T00:18:50Z
- [x] Write `outputs/aws-migration-artifacts/aws-inventory.json` — completed 2026-07-14T00:21:39Z
- [x] Write `outputs/aws-migration-artifacts/architecture-diagram.mmd` — completed 2026-07-14T00:24:18Z
- [x] Write `outputs/aws-migration-artifacts/dependency-matrix.csv` — completed 2026-07-14T00:25:02Z
- [x] Write `outputs/aws-migration-artifacts/migration-assessment.md` — completed 2026-07-14T00:27:44Z

### Phase 2 — Azure Architecture
- [x] Read all artifacts in `outputs/aws-migration-artifacts/` — completed 2026-07-14T00:32:10Z
- [x] Write `outputs/azure-architecture-output/design-document.md` — completed 2026-07-14T00:43:22Z
- [x] Write `outputs/azure-architecture-output/architecture-diagram-azure.mmd` — completed 2026-07-14T00:46:19Z
- [x] Write `outputs/azure-architecture-output/cost-comparison.md` — completed 2026-07-14T00:49:10Z
- [x] Write `outputs/azure-architecture-output/service-mapping.md` — completed 2026-07-14T00:52:51Z
- [x] Replace Phase 3 placeholders using Sections 5, 6, and 11 of `design-document.md` — completed 2026-07-14T00:54:41Z

### Phase 3a — IaC Transformation
- [x] Read Section 5 of `outputs/azure-architecture-output/design-document.md` — completed 2026-07-14T00:56:18Z
- [x] Generate `modules/networking.bicep` — virtual network, subnets, private DNS — completed 2026-07-14T00:58:37Z
- [x] Generate `modules/function-app.bicep` — function app, plan, identity — completed 2026-07-14T01:01:12Z
- [ ] Write `outputs/bicep-templates/main.bicep`
- [ ] Write `outputs/bicep-templates/parameters/dev.bicepparam`

### Phase 3b — Code Refactor
- [x] Read Section 6 of `outputs/azure-architecture-output/design-document.md` — completed 2026-07-14T00:55:49Z
- [ ] Refactor `upload-handler` to HTTP-trigger Azure Function
- [ ] Refactor `processor-handler` to Service Bus-trigger Azure Function
- [ ] Write `outputs/azure-functions/requirements.txt`
- [ ] Write `outputs/azure-functions/host.json`

### Phase 3c — Pipeline Build
- [x] Read Section 11 of `outputs/azure-architecture-output/design-document.md` — completed 2026-07-14T00:55:11Z
- [x] Create `.github/workflows/deploy-infra.yml` — completed 2026-07-14T00:59:26Z
- [x] Create `.github/workflows/deploy-functions.yml` — completed 2026-07-14T01:02:40Z
- [x] Configure OIDC authentication in the workflow YAML — completed 2026-07-14T01:04:18Z
- [x] Configure GitHub Environments for `dev`, `staging`, and `prod` — completed 2026-07-14T01:05:12Z

### Phase 4 — Validation
- [ ] Re-check Phase 1 through Phase 3 artifacts before validation starts
- [ ] Validate architecture, security, networking, monitoring, and deployment assumptions
- [ ] Write `outputs/validation-report.md`
- [ ] Record final PASSED or FAILED result and any remediation items

## Blockers

- None
```

### 6. Edge Cases / Failure Modes

- **Empty Blockers section drift:** Replace `- None` only when the first real blocker is added; restore it only when all blockers are cleared and the phase has been rerun successfully.
- **Plan file missing during resume:** Recreate it from artifacts, then mark recovered phases `✅` only after re-verification.
- **Placeholder tasks left after Phase 2:** Do not start Phase 3 verification until placeholders are replaced with concrete items from the design document.
- **Out-of-order timestamps:** If a completion timestamp predates the phase start timestamp, treat it as a write error and correct it on the next update.
- **Worker updated another phase accidentally:** Preserve valid evidence but correct ownership and add a note in the blocker if the accidental edit caused ambiguity.

## Rules

- **Never mark `[x]` unless the underlying artifact exists and is non-empty.**
- **Never modify another phase section during a parallel run.**
- **Never use local time or mixed time zones in the plan file.**
- **Never remove evidence of a failure without re-running and re-verifying the phase.**
- **Always re-read before every write.**

## Best Practices

- Keep edits minimal and scoped to the phase you own.
- Add completion timestamps immediately, not at the end of the phase.
- Expand Phase 3 tasks from the design document as soon as Phase 2 finishes.
- Treat the plan as an audit artifact; future agents should be able to resume from it without chat history.
- Prefer blocker entries that point directly to the broken file path and next owner action.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Cloud Adoption Framework — project management | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/manage/ |
| Azure DevOps work items | https://learn.microsoft.com/en-us/azure/devops/boards/work-items/about-work-items |

### GitHub Documentation

| Topic | Link |
|---|---|
| GitHub Projects — project tracking | https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects |
| GitHub Issues | https://docs.github.com/en/issues/tracking-your-work-with-issues/about-issues |

### Best Practices

- **Incremental updates beat batch updates** — they keep the plan reliable during long-running phases.
- **Optimistic locking is mandatory in parallel Phase 3 runs** — the plan is shared state.
- **UTC timestamps make resume logic deterministic** — no timezone math is required.
- **A checked box is an evidence claim** — only check it when the artifact can be opened and inspected.
