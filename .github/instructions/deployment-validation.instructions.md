---
name: deployment-validation-instructions
description: Custom instructions for Deployment Validation Agent
applyTo: deployment-validation
---

# Deployment Validation Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All inputs come from `outputs/` and all reports go to `outputs/validation-report.md`.

## Validation Requirements by Phase

Golden rule: All critical checks must pass for successful validation. Optional checks should be reviewed and addressed as needed but do not block deployment if they fail.

Golden rule: - Use the detailed design document for reference and guidance in outoputs/azure-architecture-output/ and validate code and configuration against the design specifications.


> All validation checklists, security criteria, performance baselines, compliance standards, cost accuracy checks, reporting standards, and troubleshooting guides are in the `deployment-validation` skill. Read that skill before starting any validation phase.

> The validation report must be written to `outputs/validation-report.md` using the report template in the skill.