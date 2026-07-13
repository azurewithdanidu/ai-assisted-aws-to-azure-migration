---
name: orchestration
description: Coordinate the 6-phase migration pipeline — sequence phases, verify artifacts, detect blockers, and ensure migration-task-plan.md reflects reality
---

# Orchestration Skill

## Purpose

Run the migration pipeline phases in the correct dependency order, verify output artifacts after each phase, and maintain `outputs/migration-task-plan.md` as the durable source of truth.

## When to Use

At the start of a migration run, after each phase completes, and whenever resuming from a specific phase.

## Process

**Phase sequencing:**

```
Phase 1 (Discovery) → Phase 2 (Architecture) → Phase 3a + 3b + 3c (parallel) → Phase 4 (Validation)
```

1. Read `outputs/migration-task-plan.md` — check the Phase Summary table.
2. Find the first phase row with status `⏳`. Verify all prerequisite phases are `✅`.
3. Delegate to the worker agent using the prompts in the `phase-delegation` skill.
4. After delegation, verify artifacts exist and are non-empty (read the files — do not trust the agent's text response).
5. If artifacts pass: mark phase `✅`, proceed to next.
6. If artifacts fail: mark phase `❌`, populate `## Blockers`, stop and report to user.

**Phase 3 parallel rule (MANDATORY):**
- Phases 3a (iac-transformation), 3b (code-refactor), and 3c (pipeline-builder-agent) have no dependencies on each other.
- Invoke all three in a single batched tool-call block — one assistant turn, three parallel subagent calls.
- Never serialize these three phases. Never verify 3a before 3b and 3c have been launched.
- Only after all three return, check all three artifact sets together.

**After Phase 2 completes:**
- Read `design-document.md` Sections 5, 6, and 11.
- Replace the placeholder comment lines in Phase 3a/3b/3c task sections with per-module/per-function/per-workflow tasks.

## Rules

- **Never skip phase artifact verification** — always read the output file; never assume success from agent text.
- **Never invoke Phase N+1 until Phase N passes artifact check.**
- **Never invoke 3a, 3b, 3c sequentially** — parallel-only.
- **Always re-read `migration-task-plan.md` before each edit** to avoid overwriting concurrent worker updates.
- **Stop on any `❌` phase** — report what failed and what the user's options are before proceeding.
- **On resume:** verify prerequisite artifacts exist, load current task plan state, continue from the correct phase.

## Output

All phases `✅` in `migration-task-plan.md`, or a clear blocker report identifying which phase failed and what is needed to unblock.

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

- **Phase 3 parallelism is mandatory, not optional** — IaC transformation, code refactoring, and pipeline building have no inter-dependencies. Serializing them doubles the time for no benefit.
- **Always verify artifacts by reading files, not by trusting agent text** — agents can hallucinate success. The only reliable signal is the artifact file existing and being non-empty.
- **Blockers must surface immediately** — never proceed past a `❌` phase. Downstream agents depend on correct artifacts from upstream phases; proceeding with corrupt inputs compounds failures.
- **AWS 7 Rs mapping:** Most resources in this pipeline follow the "Replatform" strategy (lift-and-modify to managed services). Some may be "Rearchitect" (Lambda → Durable Functions, DynamoDB Streams → Cosmos DB Change Feed). Document the R-strategy for each service in the design document.
