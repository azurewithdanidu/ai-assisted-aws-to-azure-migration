# Changelog

All notable changes to `cloud-avengers` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)  
Versioning: [Semantic Versioning](https://semver.org/)

---

## [1.2.0] - 2026-07-14

### Changed

- **Release pipeline validation** — end-to-end test of `version:` PR → `create-release-pr.yml` → `release:` PR → `create-release.yml` flow confirming automated tagging and GitHub Release creation works correctly after pipeline fixes in v1.1.0

---

## [1.1.0] - 2026-07-14

### Added

- **6 new dual-platform scripts** (Bash + PowerShell) with full arg validation and strict error handling:
  - `skills/aws-inventory-scan/scripts/validate-inventory.{sh,ps1}` — validates `aws-inventory.json` schema before downstream agents consume it
  - `skills/migration-assessment/scripts/score-complexity.{sh,ps1}` — scores AWS services by migration complexity tier and prints effort estimates
  - `skills/cost-estimator/scripts/fetch-prices.{sh,ps1}` — queries Azure Retail Prices API (no auth) for live SKU pricing

### Changed

- **Skills overhaul** — all 22 `SKILL.md` files updated:
  - Stripped non-standard frontmatter fields (`allowed-tools`, `compatibility`, `metadata`) — now comply with VS Code Copilot skill spec (`name` + `description` only)
  - 8 thin skills enriched to 200–350 lines with full procedures, input/output specs, templates, edge cases, and decision trees: `orchestration`, `task-tracking`, `architecture-design`, `phase-delegation`, `architecture-diagramming`, `bicep-generation`, `multi-env-strategy`, `cost-analysis`
  - Fixed broken skill path references across all agent files (`skills/<subfolder>/<name>.md` → `skills/<skill-name>/SKILL.md`)
  - Fixed broken script path in `module-organization` (was `.github/skills/…`, now `./scripts/…`)
- **Agent descriptions** improved with keyword-rich `Use when:` trigger phrases for reliable subagent discovery: `aws-discovery`, `azure-architect`, `code-refactor`, `deployment-validation`
- **`skill-evolution-engine`** body enriched with Diagnosis Checklist and Improvement Patterns sections
- **`skill-generator-agent`** renamed to correct `.agent.md` extension; body enriched with Skill Template, Wiring Checklist, and Discovery Validation sections

### Removed

- **`.github/agents/`** — stale drifted copies of product agents with wrong skill path references
- **`.github/skills/agents/`** — legacy pre-restructure skill docs superseded by `skills/`
- **`.github/instructions/`** — per-agent instruction files superseded by inline agent instructions

---

## [1.0.0] - 2026-07-13

### Added

- **10 specialist migration agents** packaged as a publishable plugin for Copilot CLI, Claude Code, and VS Code:
  - `migration-project-manager` — full pipeline orchestrator
  - `aws-discovery` — Phase 1: read-only AWS resource inventory and dependency mapping
  - `azure-architect` — Phase 2: WAF-aligned Azure architecture design and cost analysis
  - `iac-transformation` — Phase 3a: CloudFormation → Bicep (AVM modules) conversion
  - `code-refactor` — Phase 3b: boto3/AWS SDK → Azure SDK rewrite (Python, Node.js)
  - `pipeline-builder-agent` — Phase 3c: GitHub Actions CI/CD pipeline generation with OIDC
  - `azure-deployer` — Phase 3d: manual deployment with three fallback strategies
  - `deployment-validation` — Phase 4: smoke tests, security compliance, cost verification
  - `skill-evolution-engine` — meta-agent to fix and improve skills
  - `skill-generator-agent` — meta-agent to extend the skill ecosystem
- **22 skills** across 8 categories (aws-discovery, azure-architect, code-refactor, iac-transformation, deployment-validation, pipeline-builder, migration-pm, shared)
- **Dual Bash/PowerShell support** on all skill scripts — runtime detection order: `curl`+`jq` → `pwsh` → `powershell.exe`
- **Plugin manifest** at `.claude-plugin/plugin.json` enabling `/plugin install` distribution
- **`commands/run-migration.md`** slash command as the primary user entry point
- **`AGENTS.md`** canonical repo layout guide for humans and AI agents
- Per-agent instructions merged directly into each agent file (self-contained agents)
- `CHANGELOG.md` and semantic versioning on `dev → main` branch model
