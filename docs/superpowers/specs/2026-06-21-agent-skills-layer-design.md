# Agent Skills Layer Design

**Date:** 2026-06-21  
**Status:** Approved

## 1. Problem

The 7 migration pipeline agents (`aws-discovery`, `azure-architect`, `code-refactor`, `iac-transformation`, `deployment-validation`, `pipeline-builder`, `migration-pm`) each embed all their capability logic directly inside their own agent file. This means:

- Shared logic (Bicep generation, service mapping, auth patterns) is duplicated across multiple agent files
- Agent files are IDE-specific (VS Code Copilot `.agent.md` format with `tools:` frontmatter)
- Swapping, improving, or reusing a capability requires editing every agent that embeds it
- No plug-and-play — capabilities are baked in, not composable

## 2. Goal

Introduce a **skills layer** beneath the existing agents. Each skill is a focused, reusable, pure-markdown capability file. Agents become thin orchestrators that declare which skills they use. Skills are IDE-agnostic and can be invoked standalone or by the project manager orchestrator.

**What does NOT change:**
- The 7 existing `.github/agents/*.agent.md` files keep their current names and locations
- The `.github/skills/azure-architecture/` knowledge reference library is untouched
- The `.github/instructions/` files are untouched

**What changes:**
- New `.github/skills/agents/` directory with skill files
- Each agent file gains a `## Skills` section listing which skills it delegates to
- Logic already covered by a skill is removed from the agent file (skill is the single source of truth)

## 3. Skill File Format

Every skill file uses this structure — two lines of YAML frontmatter for discoverability, pure markdown body that any LLM in any IDE can follow:

```markdown
---
name: <kebab-case-name>
description: <one-line description used for discoverability>
---

# <Skill Title>

## Purpose
One sentence on what this skill does and why it exists.

## When to Use
Conditions under which an agent should invoke this skill.

## Process
Step-by-step imperatives the AI follows when this skill is active.

## Rules
Hard constraints (DO / DON'T).

## Output
What this skill produces — file paths, formats, success criteria.
```

The frontmatter is intentionally minimal — no `tools:`, no `applyTo:`, no IDE-specific fields. The body is the entire skill.

## 4. Skill Inventory

### 4.1 Shared Skills

Live in `.github/skills/agents/shared/`. Used by two or more agents.

| File | Used By | Purpose |
|---|---|---|
| `aws-to-azure-mapping.md` | azure-architect, code-refactor | AWS→Azure service equivalents, config differences, migration notes |
| `bicep-generation.md` | azure-architect, iac-transformation | Secure, modular Bicep authoring — naming, decorators, outputs, validation |
| `azure-auth-patterns.md` | code-refactor, iac-transformation | DefaultAzureCredential, Managed Identity, RBAC assignment patterns |
| `azure-security-patterns.md` | iac-transformation, deployment-validation | Private endpoints, NSGs, Key Vault references, encryption at rest |
| `task-tracking.md` | migration-pm, all worker agents | How to read/write `outputs/migration-task-plan.md` — status symbols, update rules, blocker format |

### 4.2 Agent-Specific Skills

Live in `.github/skills/agents/<agent-name>/`.

#### migration-pm
| File | Purpose |
|---|---|
| `orchestration.md` | How to sequence phases, detect blockers, decide when to re-invoke a worker agent |
| `phase-delegation.md` | How to hand off to each worker agent — what inputs to provide, what outputs to expect |

#### aws-discovery
| File | Purpose |
|---|---|
| `aws-inventory-scan.md` | How to read and structure AWS service inventory into `outputs/aws-migration-artifacts/` |
| `migration-assessment.md` | Complexity scoring, risk flags, Service Complexity Matrix population |

#### azure-architect
| File | Purpose |
|---|---|
| `architecture-design.md` | WAF-aligned service selection, reference architecture selection, design constraint enforcement |
| `cost-analysis.md` | Cost comparison methodology, AWS vs Azure pricing, break-even and ROI format |
| `architecture-diagramming.md` | Mermaid diagram generation — resource types, network boundaries, data flows |

#### code-refactor
| File | Purpose |
|---|---|
| `lambda-to-functions.md` | Handler rewrite patterns — trigger types, bindings, response shapes, host.json |
| `sdk-migration.md` | boto3 → azure-sdk package mapping, import paths, client instantiation |

#### iac-transformation
| File | Purpose |
|---|---|
| `module-organization.md` | Bicep module boundaries, dependency ordering, what belongs in root vs module |
| `parameter-management.md` | Environment-specific parameter files, allowed values, `.bicepparam` format |

#### deployment-validation
| File | Purpose |
|---|---|
| `what-if-validation.md` | Pre-deployment what-if checks, how to interpret output, blocking vs warning conditions |
| `smoke-testing.md` | Post-deployment smoke test checklist — endpoint checks, identity checks, secret resolution |

#### pipeline-builder
| File | Purpose |
|---|---|
| `github-actions-oidc.md` | OIDC/Workload Identity Federation setup, federated credential config, required secrets |
| `multi-env-strategy.md` | Branch strategy, environment protection rules, approval gates, secret separation |
| `workflow-generation.md` | GitHub Actions YAML patterns — job structure, artifact handling, rollback strategy |

## 5. Folder Structure

```
.github/
  agents/                          ← unchanged, existing files
    aws-discovery.agent.md
    azure-architect.agent.md
    code-refactor.agent.md
    deployment-validation.agent.md
    iac-transformation.agent.md
    migration-project-manager.agent.md
    pipeline-builder-agent.agent.md
  skills/
    agents/                        ← NEW
      shared/
        aws-to-azure-mapping.md
        bicep-generation.md
        azure-auth-patterns.md
        azure-security-patterns.md
        task-tracking.md
      migration-pm/
        orchestration.md
        phase-delegation.md
      aws-discovery/
        aws-inventory-scan.md
        migration-assessment.md
      azure-architect/
        architecture-design.md
        cost-analysis.md
        architecture-diagramming.md
      code-refactor/
        lambda-to-functions.md
        sdk-migration.md
      iac-transformation/
        module-organization.md
        parameter-management.md
      deployment-validation/
        what-if-validation.md
        smoke-testing.md
      pipeline-builder/
        github-actions-oidc.md
        multi-env-strategy.md
        workflow-generation.md
    azure-architecture/            ← unchanged, existing knowledge library
      ...
  instructions/                    ← unchanged
    ...
```

## 6. Agent Modification Pattern

Each agent file gets a `## Skills` section added near the top (after the Purpose section, before Responsibilities). This section is a table of tasks → skill file paths. Logic already covered by a referenced skill is removed from the agent file body. The test: if a paragraph in the agent file answers the same question as a skill's `## Process` or `## Rules` section, it is removed from the agent. If it adds agent-specific nuance not in the skill, it stays.

**Example — azure-architect.agent.md:**

```markdown
## Skills

Read each skill before performing the associated task.

| Task | Skill |
|---|---|
| Service mapping decisions | `.github/skills/agents/shared/aws-to-azure-mapping.md` |
| Bicep module specification | `.github/skills/agents/shared/bicep-generation.md` |
| Security patterns | `.github/skills/agents/shared/azure-security-patterns.md` |
| Task status updates | `.github/skills/agents/shared/task-tracking.md` |
| Architecture design | `.github/skills/agents/azure-architect/architecture-design.md` |
| Cost analysis | `.github/skills/agents/azure-architect/cost-analysis.md` |
| Mermaid diagrams | `.github/skills/agents/azure-architect/architecture-diagramming.md` |
```

## 7. Authoring Rules for Skills

- **One capability per skill.** If a skill needs a second `## Process`, it should be two skills.
- **Written as imperatives.** "Read the design document. Extract every AWS service. Map each one using the table below." Not prose documentation.
- **No IDE-specific content.** No `tools:` lists, no `@workspace`, no VS Code references.
- **Output is always concrete.** Every skill's `## Output` section names exact file paths and formats.
- **Rules section is mandatory.** At least three hard DO/DON'T constraints per skill.
- **Skills never call other skills.** Agents orchestrate; skills execute. A skill that says "now invoke skill X" is an agent.

## 8. IDE Compatibility

| IDE / Tool | How to use a skill |
|---|---|
| Claude Code | Reference file path in prompt: "Read and follow `.github/skills/agents/shared/bicep-generation.md`" |
| GitHub Copilot Chat | `#file:.github/skills/agents/shared/bicep-generation.md` in the chat message |
| Cursor | `@file` reference or add to `.cursorrules` |
| Any LLM | Paste file contents as system prompt or user context |

## 9. Success Criteria

- [ ] All 21 skill files exist under `.github/skills/agents/`
- [ ] Every skill follows the standard format (frontmatter + 5 sections)
- [ ] Every agent file has a `## Skills` table
- [ ] No skill logic duplicated across two skill files
- [ ] No IDE-specific content in any skill file
- [ ] Shared skills contain no agent-specific assumptions
