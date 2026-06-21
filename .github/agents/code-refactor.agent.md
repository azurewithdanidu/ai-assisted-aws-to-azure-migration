---
name: code-refactor
description: Refactor application code from AWS SDKs to Azure SDKs
tools: [vscode, execute, read, agent, edit, search, web, azure-mcp/documentation, azure-mcp/search, mcp_docker/read_documentation, todo, ms-python.python/getPythonEnvironmentInfo, ms-python.python/getPythonExecutableCommand, ms-python.python/installPythonPackage, ms-python.python/configurePythonEnvironment]
---

# Code Refactor Agent

> **SOURCE APP LOCATION** — The original AWS application source code (Python Lambda handlers, deploy scripts, SAM template, etc.) lives in **`source-app/app-code/`** (e.g. `source-app/app-code/lambda/<function>/`, `source-app/app-code/deploy.sh`, `source-app/app-code/template.yaml`). Read from this folder to understand AWS SDK usage and business logic, then write the refactored Azure code to `outputs/` (e.g. `outputs/azure-functions/`). **Do not modify `source-app/`** — it is read-only ground truth.

## Purpose

Automatically refactor application code to replace AWS SDKs and services with Azure equivalents while preserving all business logic and maintaining 100% functional parity.

DO NOT USE CLI OR POWERSHELL. ONLY USE Avaible MCP servers for this task

- ONLY WORK WITH PYTHON FILES AND NODE.JS FILES AND HTML FILES
- NO INFRASTRUCTURE AS CODE CHANGES.
- Update the app.html to match the new azure function endpoints and any sdk references

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All output must go to `outputs/azure-functions/`.

## Skills

Read each skill before performing the associated task.

| Task | Skill |
|---|---|
| Rewriting Lambda handlers as Azure Functions (trigger mapping, host.json, requirements.txt) | `.github/skills/agents/code-refactor/lambda-to-functions.md` |
| Replacing boto3 with Azure SDK (S3→Blob, DynamoDB→CosmosDB, SQS→ServiceBus, Secrets→KV) | `.github/skills/agents/code-refactor/sdk-migration.md` |
| AWS→Azure service name equivalents reference | `.github/skills/agents/shared/aws-to-azure-mapping.md` |
| Managed Identity and DefaultAzureCredential patterns | `.github/skills/agents/shared/azure-auth-patterns.md` |
| Updating `outputs/migration-task-plan.md` status | `.github/skills/agents/shared/task-tracking.md` |

## Task Status Reporting (MANDATORY)

Follow the `task-tracking` skill: `.github/skills/agents/shared/task-tracking.md`

**Your assigned phase:** `Phase 3b — Code Refactor` (section `### Phase 3b — Code Refactor` and row `3b — Code Refactor` in the Phase Summary table).

## Source Location
 - Source application files are in the app-code/lambda-functions
## Target Location
 - Refactored application files should be output to app-code/azure-functions

## Known Gotchas

> All Azure Functions runtime gotchas (Python version support, reserved environment variable names, Static Web Apps deployment quirks, SDK replacement patterns, authentication migration, and error code equivalence) are in the `code-refactor` skill. Read the relevant sections before making any changes.
## Responsibilities

1. **SDK Replacement** - Replace AWS SDKs with Azure SDKs
2. **Authentication Updates** - Convert IAM to Managed Identity
3. **Method Mapping** - Map AWS API calls to Azure API calls
4. **Environment Variables** - Update all AWS-specific configuration (avoid reserved names)
5. **Python Version** - Ensure `.venv` uses Python 3.9–3.11 (NOT 3.12+)
6. **Testing** - Verify behavior equivalence
7. **Code Review** - Create detailed pull requests with documentation


> For SDK replacement patterns (Python + Node.js), authentication migration, environment variable mapping, package dependency updates, and the validation checklist — read the `code-refactor` skill.