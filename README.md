# AWS to Azure AI-Assisted Migration

**Status:** ✅ Migration Completed  
**Version:** 2.0  
**Date:** April 2026  
**AWS Account:** 535002891143 (ap-southeast-2 / Sydney)  
**Azure Region:** australiaeast (Sydney — same geographic zone)

---

## What's in This Repository

A complete, end-to-end AI-assisted migration of a real AWS serverless application to Azure, executed using five custom GitHub Copilot agents. This repository contains all agent definitions, generated outputs, refactored code, and infrastructure-as-code ready for reuse on future migrations.

**Application Migrated:** Image Upload Service — a serverless REST API allowing users to upload, list, view, and delete images.

| | AWS (Source) | Azure (Target) |
|---|---|---|
| **Compute** | 4 Lambda functions (Python 3.11) | Azure Functions — Consumption plan (Python 3.11) |
| **API Layer** | API Gateway REST (IAM/SigV4 auth) | Azure Functions HTTP triggers (function key auth) |
| **Object Storage** | S3 (images bucket) | Azure Blob Storage (Managed Identity + RBAC) |
| **Static Website** | S3 static website hosting | Azure Static Web Apps (Free tier) |
| **IaC** | AWS CloudFormation | Azure Bicep (modular, AVM-aligned) |
| **Observability** | CloudWatch Logs | Application Insights + Log Analytics |
| **Secrets** | — | Azure Key Vault (Standard, soft-delete) |
| **Auth** | IAM roles + access keys | System-Assigned Managed Identity + RBAC |

**Cost outcome:** AWS ~$2.92/month → Azure ~$0.54/month at demo scale (81% reduction).

---

## Repository Structure

```
.github/
  agents/               # Five custom GitHub Copilot agent definitions
  instructions/         # Agent-specific instruction files
  skills/               # Reusable skill definitions
  COMPLETION-REPORT.md  # Agent creation completion report
  QUICK-START-GUIDE.md  # 5-minute agent quick-start reference

app-code/
  lambda/               # Original AWS Lambda source (Python 3.11)
    upload/             # upload_handler.py
    list/               # list_handler.py
    view/               # view_handler.py
    delete/             # delete_handler.py
  build/app.html        # Original AWS-SDK frontend (SigV4 auth)
  template.yaml         # AWS SAM / CloudFormation template

outputs/
  aws-migration-artifacts/
    aws-inventory.json           # Full AWS resource inventory (Discovery Agent)
    architecture-diagram.mmd     # Mermaid diagram of AWS architecture
    dependency-matrix.csv        # Service dependency relationships
    migration-assessment.md      # Complexity ratings and effort estimates
    cloudformation-template.yaml # Captured CloudFormation stack template

  azure-architecture-output/
    architecture-diagram-azure.mmd  # Mermaid diagram of Azure target architecture
    service-mapping.md              # Full AWS → Azure service mapping
    cost-comparison.md              # AWS vs Azure cost analysis

  azure-functions/
    function_app.py      # Refactored Python v2 Azure Functions (all 4 endpoints)
    requirements.txt     # azure-functions, azure-storage-blob, azure-identity
    host.json            # Functions host config (extension bundle v4)
    local.settings.json  # Local dev environment variables

  bicep-templates/
    main.bicep           # Entry point — subscription-scoped deployment
    main.json            # Compiled ARM template
    modules/             # Individual resource modules
    parameters/          # dev / staging / prod parameter files

  static-web-app/
    app.html             # Refactored frontend (AWS SDK removed, fetch + function key)
    index.html           # SWA default entry point (required by Azure Static Web Apps)

doc/                     # Project documentation (see below)
scripts/
  deploy.sh              # Deployment helper script
  rollback.sh            # Rollback procedures
  validate-deployment.sh # Post-deployment validation checks
```

---

## Quick Start

**To use the agents on a new migration:**

1. Ensure GitHub Copilot is installed in VS Code
2. Open Copilot Chat (`Ctrl+Shift+I`)
3. Invoke agents in sequence:

```
@aws-discovery Discover all resources in the AWS account and create a complete inventory
```
```
@azure-architect Design Azure architecture based on the discovery output and generate Bicep templates
```
```
@code-refactor Refactor all Lambda functions to Azure Functions using Azure SDKs
```
```
@iac-transformation Convert CloudFormation to Bicep and generate deployment scripts
```
```
@deployment-validation Validate the Azure deployment and confirm functional parity
```

See [.github/QUICK-START-GUIDE.md](.github/QUICK-START-GUIDE.md) and [doc/04-DEMO-PLAN.md](doc/04-DEMO-PLAN.md) for detailed usage.

---

## The Five AI Agents

All agents live in [`.github/agents/`](.github/agents/) and use instruction files from [`.github/instructions/`](.github/instructions/).

### 1. AWS Discovery Agent (`@aws-discovery`)
**File:** `.github/agents/aws-discovery.agent.md`  
**Purpose:** Read-only discovery of all AWS resources using AWS MCP Server (no CLI).  
**Outputs:** `aws-inventory.json`, `architecture-diagram.mmd`, `dependency-matrix.csv`, `migration-assessment.md`, captured CloudFormation template.  
**Tools:** AWS Cloud Control API MCP, AWS Knowledge MCP

### 2. Azure Architect Agent (`@azure-architect`)
**File:** `.github/agents/azure-architect.agent.md`  
**Purpose:** Map AWS services to Azure equivalents, generate Bicep IaC, produce cost comparisons using Microsoft Learn MCP.  
**Outputs:** `architecture-diagram-azure.mmd`, `service-mapping.md`, `cost-comparison.md`, Bicep templates.  
**Tools:** Microsoft Learn MCP, Azure MCP, Mermaid Chart validator

### 3. Code Refactor Agent (`@code-refactor`)
**File:** `.github/agents/code-refactor.agent.md`  
**Purpose:** Convert Python Lambda handlers to Azure Functions (Python v2 model). Replaces `boto3` with `azure-storage-blob` + `azure-identity`. Updates the frontend to remove the AWS SDK.  
**Source:** `app-code/lambda/` → **Target:** `outputs/azure-functions/`  
**Key gotchas captured in agent:**
- Python 3.13 is **not supported** by Azure Functions v4 — use Python 3.11
- `CONTAINER_NAME` is a **reserved** Azure Functions environment variable — use `BLOB_CONTAINER_NAME`
- Azure Static Web Apps requires `index.html` as the default entry point
- `StaticSitesClient.exe` correct arguments: `upload --skipAppBuild --workdir <dir> --app "." --apiToken <token>`

### 4. IaC Transformation Agent (`@iac-transformation`)
**File:** `.github/agents/iac-transformation.agent.md`  
**Purpose:** Convert AWS CloudFormation to Azure Bicep using AVM modules. Generate deployment validation scripts and rollback procedures.  
**Source:** `outputs/aws-migration-artifacts/cloudformation-template.yaml` → **Target:** `outputs/bicep-templates/`  
**Tools:** Azure MCP, Microsoft Learn MCP (AVM modules)

### 5. Deployment Validation Agent (`@deployment-validation`)
**File:** `.github/agents/deployment-validation.agent.md`  
**Purpose:** Pre- and post-deployment validation — Bicep syntax, policy compliance, security checks, smoke tests, and AWS vs Azure functional parity verification.

---

## Migration Outputs

### AWS Discovery Results
- **18 active resources** discovered across Lambda, API Gateway, S3, IAM, CloudWatch, KMS, CloudFormation
- **8 AppStream 2.0 remnant resources** identified for cleanup
- **Overall complexity: LOW** — clean serverless architecture
- **Estimated effort: 2–3 weeks** (1–2 engineers), validated as accurate

### Azure Architecture
```
Browser
  └─→ Azure Static Web Apps (index.html / app.html)
         └─→ Azure Functions HTTP Triggers (Consumption, Python 3.11)
                  POST   /api/upload              → upload_function     → Blob Storage (SAS PUT URL)
                  GET    /api/files               → list_files_function → Blob Storage (list blobs)
                  GET    /api/files/{id}/view-url → get_view_url_function→ Blob Storage (SAS GET URL)
                  DELETE /api/files/{id}          → delete_file_function → Blob Storage (delete blob)

Identity: System-Assigned Managed Identity → Storage Blob Data Contributor RBAC
Secrets:  Azure Key Vault (Standard, soft-delete, purge-protected)
Logs:     Log Analytics Workspace → Application Insights
```

### Bicep Deployment
- Deployed via `az deployment sub create` — subscription-scoped
- Modules: Storage, Functions, Static Web App, Key Vault, Monitoring, RBAC
- Three parameter files: `dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam`
- **Deployment status: ✅ Successful** (australiaeast, resource group `img-upload-dev-rg`)

### Cost Comparison

| Scale | AWS | Azure | Saving |
|-------|-----|-------|--------|
| Demo/Dev | $2.92/month | $0.54/month | **81%** |
| Production (1M calls, 100 GB) | ~$148.80/month | ~$108.80/month | **27%** |

---

## Key Features

### No CLI in Agents
All five agents operate exclusively through MCP servers and VS Code tools — no PowerShell or CLI commands are run inside agent workflows, keeping them portable and cross-platform.

### Managed Identity Throughout
AWS IAM roles and access keys are fully replaced by Azure System-Assigned Managed Identity with RBAC, following the principle of least privilege. No credentials are stored in environment variables or code.

### SAS URL Pattern Preserved
The pre-signed URL pattern (clients upload/download directly to storage, API only generates the URL) is preserved identically using Azure Blob SAS tokens generated via user-delegation keys.

### Production-Ready Bicep
Generated templates use Azure Verified Modules (AVM) where available, include environment-specific parameter files, and are validated with `az deployment sub validate` before deployment.

---

## Technology Stack

### AI Orchestration
- **GitHub Copilot** — custom agents in VS Code agent mode
- **Agent definition files** — `.github/agents/*.agent.md`
- **Custom instructions** — `.github/instructions/*.instructions.md`

### MCP Servers Used
| MCP Server | Used By | Purpose |
|------------|---------|---------|
| AWS Cloud Control API MCP | Discovery Agent | Read-only AWS resource discovery |
| AWS Knowledge MCP | Discovery, Architect, Refactor | AWS service documentation |
| Microsoft Learn MCP | Architect, IaC, Refactor | Azure service documentation and AVM modules |
| Azure MCP | Architect, IaC, Validation | Azure resource information |
| Mermaid Chart MCP | Architect | Diagram generation and validation |

### Infrastructure as Code
- **Bicep** — modular, subscription-scoped, AVM-aligned
- **Azure Verified Modules (AVM)** — used where available
- **Parameter files** — per-environment (`dev`, `staging`, `prod`)

### Azure Runtime
- **Azure Functions v4** — Python 3.11, Consumption plan
- **Azure Blob Storage** — Hot tier, Standard LRS (dev) / ZRS (prod)
- **Azure Static Web Apps** — Free tier
- **Application Insights + Log Analytics** — full observability
- **Azure Key Vault** — Standard tier, soft-delete enabled

---

## Documentation

All documentation is in the [`doc/`](doc/) folder:

| Document | Purpose |
|----------|---------|
| [00-MASTER-INDEX.md](doc/00-MASTER-INDEX.md) | Document index and navigation |
| [01-EXECUTIVE-PRESENTATION.md](doc/01-EXECUTIVE-PRESENTATION.md) | Business case, ROI, and outcomes |
| [02-TECHNICAL-DEEP-DIVE.md](doc/02-TECHNICAL-DEEP-DIVE.md) | Technical architecture details |
| [03-CUSTOM-AGENT-SPECIFICATIONS.md](doc/03-CUSTOM-AGENT-SPECIFICATIONS.md) | Full agent definitions and instructions |
| [04-DEMO-PLAN.md](doc/04-DEMO-PLAN.md) | Step-by-step demonstration guide |
| [05-AWS-INFRASTRUCTURE-SETUP.md](doc/05-AWS-INFRASTRUCTURE-SETUP.md) | Original AWS environment reference |
| [06-DEMO-EXECUTION-GUIDE.md](doc/06-DEMO-EXECUTION-GUIDE.md) | Live demo execution script |
| [07-SERVICE-MAPPING-REFERENCE.md](doc/07-SERVICE-MAPPING-REFERENCE.md) | AWS to Azure service translation guide |
| [08-MCP-SERVER-INTEGRATION.md](doc/08-MCP-SERVER-INTEGRATION.md) | MCP server setup and configuration |

---

## Lessons Learned

Key issues discovered during the actual migration (all captured in the agent definitions for future use):

1. **Python version:** Azure Functions v4 supports Python 3.9–3.11 only. Python 3.12 and 3.13 cause worker crashes (`0xC0000005`). Always create `.venv` with Python 3.11.
2. **Reserved env var:** `CONTAINER_NAME` is reserved by the Azure Functions host. Use `BLOB_CONTAINER_NAME` for Blob Storage container references.
3. **Static Web App entry point:** Azure Static Web Apps requires `index.html` (or `Index.html`) as the default file. A standalone `app.html` is not served as the root.
4. **SAS token auth:** Azure Functions Consumption plan does not support Managed Identity for Blob SAS generation at scale without user-delegation keys — use `get_user_delegation_key()` from `BlobServiceClient`.
5. **No APIM needed:** For a simple Lambda + API Gateway → Azure Functions migration, Azure Functions HTTP triggers are a direct equivalent. APIM adds cost and complexity only when gateway features (rate limiting, transformation) are required.

---

## Requirements for Reuse

### Tooling
- VS Code with GitHub Copilot extension
- AWS CLI configured with read access to source account
- Azure CLI with Contributor access to target subscription
- MCP servers: AWS Cloud Control API, AWS Knowledge, Microsoft Learn, Azure, Mermaid Chart

### Permissions
- **AWS:** Read-only (IAM `ReadOnlyAccess` policy minimum)
- **Azure:** Contributor on subscription + User Access Administrator (for RBAC assignments)

---

## Migration Statistics

| Metric | Value |
|--------|-------|
| AWS resources discovered | 26 (18 active + 8 AppStream remnants) |
| Lambda functions migrated | 4 |
| Lines of Python refactored | ~600 |
| Bicep modules generated | 6 (storage, functions, staticweb, keyvault, monitoring, rbac) |
| Cost reduction (demo scale) | 81% ($2.92 → $0.54/month) |
| Cost reduction (prod scale) | 27% ($148.80 → $108.80/month) |
| Agent files created | 10 (5 agents + 5 instruction files) |
| Deployment status | ✅ Live in australiaeast |

---

## Contact and Status

**Completed:** April 2026  
**Version:** 2.0  
**Status:** ✅ Migration complete — Azure environment live

**Milestones:**
- [x] AWS discovery completed
- [x] Azure architecture designed
- [x] Code refactored (4 Lambda → 4 Azure Functions)
- [x] Bicep templates generated and validated
- [x] Azure infrastructure deployed (`img-upload-dev-rg`, australiaeast)
- [x] Static web app deployed to Azure Static Web Apps
- [x] Functional parity confirmed
- [x] Cost reduction validated
