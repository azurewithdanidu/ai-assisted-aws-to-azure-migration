---
name: Run Migration
description: "Orchestrate the AWS-to-Azure migration pipeline. Use to start a full run, resume from a specific phase, run a single phase in isolation, or check current status without running anything. Phases: discovery, architecture, parallel, validation."
agent: migration-project-manager
argument-hint: "full | resume <phase> | phase <phase> | status"
tools: ['read', 'edit', 'agent', 'search', 'todo']
---

## Step 1 — Collect Source AWS Details

Before doing anything else, ask the user for the following if they have not already been provided in the argument:

| Input | Description | Default |
|---|---|---|
| **AWS Account ID** | 12-digit AWS account number to migrate from | *(required — no default)* |
| **AWS Region** | Primary AWS region where resources are deployed | `ap-southeast-2` (Sydney) |

If the user supplies both values in their message, use them directly without asking. If either is missing, prompt for them before proceeding to Step 2.

---

## Step 2 — Run the Pipeline

Run the AWS-to-Azure migration pipeline according to the argument provided, passing the confirmed **account ID** and **region** to every worker agent invocation:

| Argument | Behaviour |
|---|---|
| *(none)* or `full` | Run all phases in order: Discovery → Architecture → IaC + Refactor + Pipeline (parallel) → Validation |
| `resume <phase>` | Skip completed phases and continue from `<phase>` through Validation. Valid phases: `discovery`, `architecture`, `parallel`, `validation` |
| `phase <phase>` | Run only the named phase in isolation; stop after it completes its artifact check |
| `status` | Read `outputs/migration-task-plan.md` and print a phase-by-phase status summary — do **not** invoke any worker agent |

Before invoking any worker agent, read `outputs/migration-task-plan.md` (if it exists) to understand the current state of the migration.
