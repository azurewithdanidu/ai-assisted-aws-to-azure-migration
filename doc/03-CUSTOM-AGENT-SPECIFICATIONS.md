# Complete Custom Agent Specifications

**Document Version:** 2.0  
**Date:** April 2026  
**Status:** ✅ All five agents production-validated on real AWS → Azure migration  
**Application migrated:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → australiaeast)

---

## Overview

This document provides complete specifications for all five migration agents, updated with production-validated behavior, real outputs, and lessons learned from executing a full AWS to Azure migration.

All agent and instruction files are in:

```
.github/
  agents/
    aws-discovery.agent.md         # Agent 1
    aws-discovery-skills.agent.md  # Agent 1 (skills variant — uses SKILL.md)
    azure-architect.agent.md       # Agent 2
    code-refactor.agent.md         # Agent 3
    iac-transformation.agent.md    # Agent 4
    deployment-validation.agent.md # Agent 5
  instructions/
    discovery.instructions.md
    azure-architecture.instructions.md
    code-refactoring.instructions.md
    iac-transformation.instructions.md
    deployment-validation.instructions.md
```

**Important design principle:** No agent uses CLI or PowerShell commands. All agent actions go through MCP servers and VS Code tools only, keeping agents portable and cross-platform.

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

## Full Migration Workflow

```
# Step 1: Discovery (15–30 min)
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis

# Step 2: Architecture Design (30–60 min)
@azure-architect Design Azure architecture based on the discovery output and generate Bicep templates with cost comparison

# Step 3: Code Refactoring (15–30 min)
@code-refactor Refactor all Lambda functions to Azure Functions using Azure SDKs

# Step 4: IaC Transformation (30–45 min)
@iac-transformation Convert the CloudFormation template to Bicep using AVM modules

# Step 5: Validation (15–20 min)
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

