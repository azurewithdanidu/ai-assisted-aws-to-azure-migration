# Contributing to cloud-avengers

Thank you for contributing! This guide covers the branch model, PR conventions, and how to add new skills or agents.

---

## Branch Model

```
feature/... ──► dev  ──► main
               (version: PRs)   (release: PRs only — automated)
```

- **All feature work** targets `dev`. Open PRs with title prefix `version: `.
- **Releases are automated** — never manually create tags, push to `main` directly, or create GitHub Releases by hand.
- `main` only receives release PRs auto-created by `create-release-pr.yml`.

---

## Cutting a Release

1. Bump `"version"` in `.claude-plugin/plugin.json` (semver: `X.Y.Z`).
2. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` with `### Added / Changed / Fixed` subsections.
3. Open a PR to `dev` with title prefix `version: ` (e.g. `version: bump to 1.1.0`).
4. When that PR merges, `create-release-pr.yml` automatically creates a `release: vX.Y.Z` PR from `dev → main`.
5. Approve and merge the release PR — `create-release.yml` tags and publishes the GitHub Release automatically.

---

## Adding a New Skill

1. Create a new directory `skills/<skill-name>/`.
2. Create `skills/<skill-name>/SKILL.md` following the mandatory structure in `agents/skill-generator-agent.md`.
3. Add a row to the owning agent's **Skills** table in `agents/<agent>.agent.md`.
4. If the skill has scripts, add both `scripts/<name>.sh` and `scripts/<name>.ps1` versions inside the new skill directory.
5. Add an eval task in `tests/evals/cloud-avengers/` tagged `skill:<skill-name>`.
6. Add/update a one-to-one `task_scorecard` entry in `tests/evals/cloud-avengers/scorecard.yaml` for each new/updated eval task.

## Adding a New Agent

1. Create `agents/<name>.agent.md` with YAML frontmatter (`name`, `description`, `tools`).
2. Update `AGENTS.md` pipeline overview.
3. Update `agents/migration-project-manager.agent.md` if the agent is part of the pipeline.

## Script Conventions

- Every skill script needs both `.sh` (Bash) and `.ps1` (PowerShell) versions.
- Bash: use `--kebab-case` parameters; PowerShell: use `-PascalCase`.
- Both versions must produce identical output for identical inputs.
- Include runtime detection logic in the skill's `SKILL.md` (see any existing skill for the pattern).

## CI Required Checks

All PRs to `dev` must pass:

| Check | Workflow |
|---|---|
| Unit tests (Pester + bats) | `unit-tests.yml` |
| SkillSpector security scan | `skill-security-scan.yml` |
| Waza mock evals | `eval.yml` |

### Eval Scorecard Rules

- `tests/evals/cloud-avengers/scorecard.yaml` is the source of truth for eval targets and expected outcomes.
- Every task in `tests/evals/cloud-avengers/tasks/**/*.yaml` must map to exactly one `task_scorecard` row (`task_id` 1:1).
- Each `task_scorecard` row must include:
  - `owner_type` (`skill` or `agent`)
  - `owner_id` (e.g. `aws-inventory-scan`, `migration-project-manager`)
  - `criteria.metric`
  - `criteria.expected_outcome`
  - `criteria.target`
- Use `tests/evals/cloud-avengers/scorecard-template.yaml` when creating a new eval suite.

### Per-Skill Eval Workflow

- Keep each skill's suite in `tests/evals/cloud-avengers/skills/<skill-name>/eval.yaml`.
- Keep each skill's dedicated tasks in `tests/evals/cloud-avengers/tasks/skills/<skill-name>/`.
- Use explicit tags (`skill:<skill-name>`) in every skill task so coverage checks can detect ownership.
- Run one skill during focused improvement:
  - `bash tests/evals/run-skill-eval.sh <skill-name> [model]`
- Run all skill suites:
  - `bash tests/evals/run-all-skill-evals.sh [model]`
