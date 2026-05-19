# Complete Custom Agent Specifications

**Document Version:** 3.0  
**Date:** April 2026  
**Status:** ✅ All seven agents production-validated on real AWS → Azure migration  
**Application migrated:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → australiaeast)

---

## Overview

This document provides complete specifications for all seven migration agents, updated with production-validated behavior, real outputs, and lessons learned from executing a full AWS to Azure migration.

The architecture has evolved from five independent specialist agents into a **fully orchestrated, modular pipeline** — five specialist agents, one CI/CD pipeline builder, and one project manager agent that coordinates them all end-to-end.

All agent and instruction files are in:

```
.github/
  agents/
    aws-discovery.agent.md              # Agent 1 — Discovery
    aws-discovery-skills.agent.md       # Agent 1 (skills variant — uses SKILL.md)
    azure-architect.agent.md            # Agent 2 — Architecture
    code-refactor.agent.md              # Agent 3 — Code Refactoring
    iac-transformation.agent.md         # Agent 4 — IaC Conversion
    deployment-validation.agent.md      # Agent 5 — Validation
    pipeline-builder-agent.agent.md     # Agent 6 — CI/CD Pipeline Builder
    migration-project-manager.agent.md  # Agent 7 — Orchestrator (PM Agent)
  instructions/
    discovery.instructions.md
    azure-architecture.instructions.md
    code-refactoring.instructions.md
    iac-transformation.instructions.md
    deployment-validation.instructions.md
```

**Important design principle:** No agent uses CLI or PowerShell commands. All agent actions go through MCP servers and VS Code tools only, keeping agents portable and cross-platform.

> **⭐ The Migration Project Manager Agent (Agent 7) is the highlight of this architecture.** A single `@migration-project-manager` invocation runs the entire pipeline — automatically sequencing all six specialist agents, verifying artifacts between phases, running Phase 3 in parallel, and tracking every task in a live plan file. This is what true end-to-end automation looks like.

---

## Repository Setup

Copy the `.github/agents/` and `.github/instructions/` folders to your migration repository. No additional setup is required — agents are invoked directly in GitHub Copilot Chat using `@agent-name`.

---

## Agent 1: AWS Discovery Agent

**File:** `.github/agents/aws-discovery.agent.md`  
**Invocation:** `@aws-discovery`  
**Mode:** Read-only — makes **no changes** to the AWS environment

### Tools
`vscode`, `execute`, `read`, `edit`, `search`, `web`, `azure-mcp/search`, `agent`, `aws-api-mcp-server/*`, `aws-knowledge-mcp/*`, `todo`

### Purpose
Automated, read-only discovery of all AWS resources using the AWS Cloud Control API MCP Server (not AWS CLI). Produces a complete inventory, dependency matrix, architecture diagram, and migration assessment.

### Key Responsibilities
1. Scan all enabled AWS regions for all resource types
2. Map dependencies between services (who calls whom, what IAM roles are used)
3. Generate a Mermaid architecture diagram of the current AWS state
4. Rate migration complexity per service (LOW / MEDIUM / HIGH)
5. Estimate migration effort in engineer-days
6. Capture the CloudFormation template for the stack (if IaC-deployed)

### Real Output (Image Upload Service)
- **18 active resources** discovered: Lambda (4), API Gateway (1), S3 (2), IAM (2 roles, 1 user), CloudWatch (8 log groups), KMS (1 CMK), CloudFormation (1 stack)
- **8 AppStream 2.0 remnant resources** flagged for cleanup
- **Overall complexity: LOW** — clean serverless, no VPC, no database
- **Estimated effort: 2–3 weeks** (actual: accurate)

### Instruction File
`.github/instructions/discovery.instructions.md` — naming conventions, complexity assessment criteria (LOW/MEDIUM/HIGH), IAM documentation requirements, validation checklist.

### Invocation
```
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis
```

**Expected time:** 15–30 minutes

---

## Agent 2: Azure Architect Agent

**File:** `.github/agents/azure-architect.agent.md`  
**Invocation:** `@azure-architect`

### Tools
`vscode`, `execute`, `read`, `edit`, `search`, `web`, `azure-mcp/documentation`, `azure-mcp/search`, `agent`, `aws-knowledge-mcp/*`, `microsoftdocs/mcp/*`, `todo`, `mermaidchart/get_syntax_docs`, `mermaidchart/mermaid-diagram-validator`, `mermaidchart/mermaid-diagram-preview`

### Purpose
Map AWS services to Azure equivalents, produce Well-Architected Azure architecture, generate Bicep IaC, and provide cost comparisons — all without using CLI or PowerShell.

### Key Responsibilities
1. Read `outputs/aws-migration-artifacts/aws-inventory.json` and `migration-assessment.md`
2. Map every AWS service to its Azure equivalent
3. Design Azure architecture applying the Well-Architected Framework
4. Generate `architecture-diagram-azure.mmd` (validated with Mermaid MCP)
5. Produce `cost-comparison.md` with AWS vs Azure monthly/annual costs
6. Produce `service-mapping.md` with full configuration differences

### Real Output (Image Upload Service)
- **Architecture:** Azure Functions (Consumption, Python 3.11) + Blob Storage + Static Web Apps + Application Insights + Key Vault + Log Analytics
- **No APIM used** — Functions HTTP triggers are a direct equivalent of API Gateway + Lambda proxy for this pattern
- **Cost:** AWS $2.92/month → Azure $0.54/month at demo scale (81% reduction)

### Instruction File
`.github/instructions/azure-architecture.instructions.md` — Bicep best practices, security requirements (private endpoints, Managed Identity, Key Vault), cost optimization, AVM module usage, Well-Architected Framework application.

### Invocation
```
@azure-architect Design Azure architecture based on the discovery output and generate Bicep templates with cost comparison
```

**Expected time:** 30–60 minutes

---

## Agent 3: Code Refactor Agent

**File:** `.github/agents/code-refactor.agent.md`  
**Invocation:** `@code-refactor`

### Tools
`vscode`, `execute`, `read`, `edit`, `search`, `web`, `agent`, `aws-knowledge-mcp/*`, `microsoftdocs/mcp/*`, `ms-python.python/getPythonEnvironmentInfo`, `ms-python.python/getPythonExecutableCommand`, `ms-python.python/installPythonPackage`, `ms-python.python/configurePythonEnvironment`, `todo`

### Purpose
Convert Python Lambda handler code to Azure Functions (Python v2 programming model). Replaces `boto3` with `azure-storage-blob` and `azure-identity`. Updates the static HTML frontend to remove the AWS SDK and use Azure Function key auth.

**Scope:**
- Source: `app-code/lambda/` (Python + HTML files only)
- Target: `outputs/azure-functions/` and `outputs/static-web-app/`
- Not in scope: Infrastructure as Code changes (that is Agent 4's role)

### Key SDK Mapping

```python
# BEFORE (AWS boto3)
import boto3
s3 = boto3.client('s3', region_name='ap-southeast-2')
url = s3.generate_presigned_url('put_object',
    Params={'Bucket': os.environ['BUCKET_NAME'], 'Key': key},
    ExpiresIn=3600)

# AFTER (Azure)
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.identity import DefaultAzureCredential

client = BlobServiceClient(
    account_url=f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
    credential=DefaultAzureCredential()
)
udk = client.get_user_delegation_key(start, expiry)
sas = generate_blob_sas(account_name=..., user_delegation_key=udk, ...)
url = f"https://{account}.blob.core.windows.net/{container}/{blob}?{sas}"
```

### Production Gotchas (Embedded in Agent)

| Issue | Detail |
|-------|--------|
| **Python 3.13 not supported** | Azure Functions v4 crashes (`0xC0000005`) on Python 3.12+. Use Python 3.11. |
| **`CONTAINER_NAME` is reserved** | Azure Functions host reserves this name. Use `BLOB_CONTAINER_NAME`. |
| **SWA requires `index.html`** | Azure Static Web Apps rejects root deployments without `index.html`. |
| **`StaticSitesClient.exe` args** | `upload --skipAppBuild --workdir <dir> --app "." --apiToken <token>` |
| **User-delegation key for SAS** | Managed Identity SAS requires `get_user_delegation_key()` — no account key available. |

### Instruction File
`.github/instructions/code-refactoring.instructions.md` — business logic preservation rules, error handling equivalence, Python version requirements, reserved environment variable list.

### Invocation
```
@code-refactor Refactor all Lambda functions in app-code/lambda/ to Azure Functions using Azure SDKs
```

**Expected time:** 15–30 minutes for 4 simple functions

---

## Agent 4: IaC Transformation Agent

**File:** `.github/agents/iac-transformation.agent.md`  
**Invocation:** `@iac-transformation`

### Tools
`vscode`, `execute`, `read`, `agent`, `edit`, `search`, `web`, `aws-knowledge-mcp/*`, `azure-mcp/*`, `microsoftdocs/mcp/*`, `todo`

### Purpose
Convert AWS CloudFormation to Azure Bicep using AVM (Azure Verified Modules) where available. Generate deployment scripts, validation checks, and rollback procedures. No CLI or PowerShell inside the agent.

### Source and Target
- **Source:** `outputs/azure-architecture-output/service-mapping.md` + `outputs/aws-migration-artifacts/cloudformation-template.yaml`
- **Target:** `outputs/bicep-templates/`

### Key Responsibilities
1. Look up AVM modules via Microsoft Learn MCP for each resource type
2. Write modular Bicep templates (one module per Azure service)
3. Generate subscription-scoped `main.bicep` entry point
4. Produce three parameter files: `dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam`
5. Create deployment and rollback scripts in `scripts/`

### Real Output (Image Upload Service)
Bicep modules: `storage.bicep`, `functions.bicep`, `staticweb.bicep`, `keyvault.bicep`, `monitoring.bicep`, `rbac.bicep`  
Deployment scope: `targetScope = 'subscription'`  
Status: **✅ Deployed successfully** (australiaeast, resource group `img-upload-dev-rg`)

### Instruction File
`.github/instructions/iac-transformation.instructions.md` — Bicep conversion standards, AVM module usage, deployment safety (what-if before apply), parameter management, rollback procedures.

### Invocation
```
@iac-transformation Convert the CloudFormation template to Bicep using AVM modules and generate deployment scripts
```

**Expected time:** 30–45 minutes

---

## Agent 5: Deployment Validation Agent

**File:** `.github/agents/deployment-validation.agent.md`  
**Invocation:** `@deployment-validation`

### Purpose
Pre- and post-deployment validation. Validates Bicep syntax, policy compliance, security requirements, smoke-tests deployed endpoints, and confirms functional parity with the AWS original.

### Key Responsibilities
1. **Pre-deployment:** Bicep syntax check, `az deployment validate`, policy compliance, tag completeness
2. **Post-deployment:** HTTP smoke tests (all function routes), Managed Identity RBAC check, Key Vault access
3. **Security:** No unexpected public IPs, Managed Identity in use, Key Vault soft-delete enabled, HTTPS-only
4. **Performance:** Response time within 10% of AWS baseline
5. **Cost:** Actual spend vs projected

### Instruction File
`.github/instructions/deployment-validation.instructions.md` — validation phases, security criteria, performance baselines, compliance standards, reporting format.

### Invocation
```
@deployment-validation Validate the Azure deployment end-to-end and confirm functional parity with the AWS version
```

**Expected time:** 15–20 minutes

---

## Agent 6: Pipeline Builder Agent

**File:** `.github/agents/pipeline-builder-agent.agent.md`  
**Invocation:** `@pipeline-builder-agent`

### Purpose
Design and build production-ready GitHub Actions CI/CD pipelines that deploy to Azure. Specialises in OIDC Workload Identity Federation (no long-lived credentials), multi-stage environments, and Azure-native deployment patterns.

### Key Responsibilities
1. Generate GitHub Actions workflow files for Bicep IaC deployments
2. Generate workflow files for Azure Functions and Static Web App deployments
3. Configure OIDC authentication (no Service Principal secrets stored as plain text)
4. Set up multi-stage pipelines: dev → staging → prod with approval gates
5. Configure rollback strategies and deployment protection rules

### Instruction File
Built-in to the agent definition via YAML frontmatter. Security-first principles: OIDC always preferred, least-privilege RBAC, idempotent steps, fail-fast validation before deploy.

### Invocation
```
@pipeline-builder-agent Create a multi-stage GitHub Actions pipeline for Bicep IaC + Azure Functions with OIDC auth
```

**Expected time:** 20–30 minutes

---

## Agent 7: Migration Project Manager Agent ⭐

**File:** `.github/agents/migration-project-manager.agent.md`  
**Invocation:** `@migration-project-manager`

### This Is the Ultimate Automation

The Migration Project Manager Agent is the **orchestrator** of the entire migration pipeline. Instead of invoking six specialist agents one at a time, a single prompt to the PM Agent runs the whole migration end-to-end — sequencing phases correctly, running independent phases in parallel, verifying artifacts after each phase, and surfacing blockers clearly.

This is what separates a collection of useful scripts from a **real production automation system.**

### Pipeline Architecture

```
@migration-project-manager
        │
        ▼
Phase 1 ──► Phase 2 ──► Phase 3a ─┐
Discovery   Architecture  IaC      ├──► Phase 4
(Agent 1)   (Agent 2)   (Agent 4) │   Validation
                        Phase 3b ─┤   (Agent 5)
                        Refactor  │
                        (Agent 3) │
                        Phase 3c ─┘
                        Pipeline
                        (Agent 6)
```

Phases 3a, 3b, and 3c are independent and run as parallel agent sessions. All three must pass their artifact checks before Phase 4 starts.

### Key Capabilities

1. **Pre-flight check** — inspects existing artifacts and resumes from the correct phase (skip already-done work)
2. **Live task plan** — creates and maintains `outputs/migration-task-plan.md` with real-time status across all phases
3. **Artifact verification** — reads each output file after phase completion and fails fast if anything is missing or malformed
4. **Task enrichment** — reads the architecture design document after Phase 2 and populates the Phase 3 task list with exact per-module, per-function tasks derived from the design
5. **Blocker surfacing** — if a specialist agent hits a wall, PM Agent reports it clearly with context rather than silently failing
6. **Resumability** — can be told to start from any phase (`"architecture"`, `"parallel"`, `"validation"`) without re-running completed work

### Tools
`read`, `edit`, `agent`, `search`, `todo`

**This agent does not write application code or Bicep.** Its job is to manage the plan, invoke specialist agents, read artifacts to verify completion, and keep `outputs/migration-task-plan.md` authoritative.

### Task Tracking — Two Layers

**Layer 1 — Session Todo List (in-chat):** Live view in the current conversation.  
**Layer 2 — Persistent Task Plan File:** `outputs/migration-task-plan.md` — durable across sessions, each phase updates it with status and timestamps.

### Invocation

**Full pipeline (start to finish):**
```
@migration-project-manager Run the full AWS to Azure migration pipeline
```

**Resume from a specific phase:**
```
@migration-project-manager Start from the parallel phase (IaC + Refactor + Pipeline)
```

**Start from validation only:**
```
@migration-project-manager Start from validation
```

**Expected time:** 2–3 hours full pipeline (vs 2–3 weeks manually)

---

## Full Migration Workflow

### Option A — Orchestrated (Recommended)

One prompt. The PM Agent does everything.

```
@migration-project-manager Run the full AWS to Azure migration pipeline
```

The agent handles sequencing, parallelism, artifact verification, and task tracking automatically.

### Option B — Manual Phase-by-Phase

For engineers who prefer hands-on control or need to run individual phases:

```
# Step 1: Discovery (15–30 min)
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis

# Step 2: Architecture Design (30–60 min)
@azure-architect Design Azure architecture based on the discovery output and generate Bicep templates with cost comparison

# Step 3a: IaC Transformation (30–45 min) — run in parallel with 3b and 3c
@iac-transformation Convert the CloudFormation template to Bicep using AVM modules

# Step 3b: Code Refactoring (15–30 min) — run in parallel with 3a and 3c
@code-refactor Refactor all Lambda functions to Azure Functions using Azure SDKs

# Step 3c: CI/CD Pipeline (20–30 min) — run in parallel with 3a and 3b
@pipeline-builder-agent Create GitHub Actions workflows for Bicep IaC and Azure Functions

# Step 4: Validation (15–20 min)
@deployment-validation Validate the Azure deployment and confirm functional parity
```

---

## Production Lessons Learned Summary

All lessons below are embedded in the relevant agent definitions:

| Lesson | Agent | Description |
|--------|-------|-------------|
| Python runtime constraint | `code-refactor` | Python 3.11 maximum for Azure Functions v4 |
| Reserved env var `CONTAINER_NAME` | `code-refactor` | Use `BLOB_CONTAINER_NAME` instead |
| SWA needs `index.html` | `code-refactor` | Azure Static Web Apps requires a default root file |
| No APIM for simple APIs | `azure-architect` | HTTP triggers are a direct Lambda + API GW equivalent |
| User-delegation key for SAS | `code-refactor` | Required for Managed Identity SAS URL generation |
| Subscription-scoped Bicep | `iac-transformation` | Required when resource group is created inside the template |

---

## Customization for Other Organizations

Edit `.github/instructions/*.instructions.md` to add organization-specific rules:

```markdown
## Organization Standards

### Required Tags
All resources must include CostCenter, Environment, Owner, and Project tags.

### Security Requirements
- All database connections must use private endpoints
- No public IP addresses except approved load balancers
- All secrets must be stored in Azure Key Vault

### Deployment Regions
Deploy only to approved regions (e.g., australiaeast primary, australiasoutheast DR)
```

**Next Document:** [04-DEMO-PLAN.md](04-DEMO-PLAN.md) — 30-minute demonstration workflow

### During Migration

1. **Work incrementally:** One service at a time
2. **Review outputs:** Don't blindly accept agent suggestions

