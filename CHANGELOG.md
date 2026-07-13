# Changelog

All notable changes to `cloud-avengers` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)  
Versioning: [Semantic Versioning](https://semver.org/)

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
