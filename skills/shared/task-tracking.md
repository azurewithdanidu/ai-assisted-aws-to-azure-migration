---
name: task-tracking
description: Keep outputs/migration-task-plan.md synchronized with real agent progress — status symbols, update rules, and blocker format
---

# Task Tracking Skill

## Purpose

Keep `outputs/migration-task-plan.md` synchronized with actual agent progress so the migration PM and the user always have an accurate live view of pipeline state.

## When to Use

- At the very start of your assigned phase (before any work begins)
- Each time you complete an individual task within your phase
- When your phase completes successfully
- When you hit a blocker or failure

## Process

**On start (before any work):**
1. Read `outputs/migration-task-plan.md`.
2. Find your phase row in the Phase Summary table.
3. Change the status cell from `⏳` to `🔄`.
4. Update the `Last Updated:` timestamp at the top of the file to the current ISO 8601 UTC timestamp.

**As each task within your phase completes:**
1. Find the specific `- [ ]` checkbox line in your phase section.
2. Change `- [ ]` to `- [x]` and append ` — completed <ISO 8601 UTC timestamp>`.
3. Do this incrementally after each task finishes — never batch all updates at the end.
4. Update `Last Updated:` timestamp on every edit.

**On successful completion of all phase tasks:**
1. Set your phase row status to `✅`.
2. Fill in the `Completed At` column with the current ISO 8601 UTC timestamp.
3. Update `Last Updated:` timestamp.

**On failure or blocker:**
1. Set your phase row status to `❌`.
2. Add a bullet under the `## Blockers` section in exactly this format:
   `- Phase <N> (<agent-name>): <what failed> — <what is needed to unblock>`
3. Stop work and surface the blocker clearly in your response to the user.

## Rules

- **Never modify task rows belonging to other phases.** If phases 3a, 3b, 3c run in parallel, each touches only its own rows.
- **Never mark a task `[x]` unless its output artifact actually exists and is non-empty.** Existence check: read the file or verify it via the file system before marking complete.
- **Always use only these status symbols:** `⏳` (not started) `🔄` (in progress) `✅` (complete) `❌` (failed/blocked).
- **Always re-read the file before each edit** to avoid overwriting concurrent updates from other agents running in parallel.
- **Never revert a `❌` status to `✅`** without re-running the phase and confirming artifacts exist.

## Output

Updated `outputs/migration-task-plan.md` with:
- Phase Summary table row reflecting current status
- Individual task checkboxes checked with timestamps
- Blockers section populated if applicable
- `Last Updated:` timestamp current

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

- **Incremental updates, not batch updates** — mark each task `[x]` the moment it completes. Batch-updating at phase end means the plan is out of sync with reality for the entire duration of the phase.
- **Timestamp every completion** in ISO 8601 UTC (`2026-06-24T10:30:00Z`) — this creates an audit trail that can be used to calculate actual phase durations vs estimates.
- **Re-read before every write** — in parallel phase execution, multiple agents write to the same file concurrently. Always read the latest version before editing to avoid overwriting another agent's updates.
- **Never mark `[x]` without verifying the artifact** — the task plan is only useful if it reflects reality. An artifact that exists but is empty (e.g., `echo '' > file.json`) must be treated as incomplete.
