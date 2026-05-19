# AWS to Azure AI-Assisted Migration — Complete Package Summary

**Date:** April 2026  
**Status:** ✅ Migration Complete — Azure environment live  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Package Overview

This repository contains a complete, end-to-end AI-assisted migration of a real AWS serverless application to Azure, executed using five custom GitHub Copilot agents. It includes all agent definitions, generated migration artifacts, refactored Python code, Bicep infrastructure templates, and a deployed Azure environment.

---

## Documents

| File | Description |
|------|-------------|
| **00-MASTER-INDEX.md** | Document index and quick navigation |
| **01-EXECUTIVE-PRESENTATION.md** | Business case, real ROI, and completed outcomes |
| **03-CUSTOM-AGENT-SPECIFICATIONS.md** | Full agent and instruction file specifications (production-validated) |
| **04-DEMO-PLAN.md** | 30-minute demonstration walkthrough |
| **05-AWS-INFRASTRUCTURE-SETUP.md** | Original AWS environment reference |
| **06-DEMO-EXECUTION-GUIDE.md** | Agent invocation scripts and expected outputs |
| **07-SERVICE-MAPPING-REFERENCE.md** | AWS → Azure service mapping reference guide |
| **08-MCP-SERVER-INTEGRATION.md** | MCP server setup and configuration |

---

## Migration Outputs

| Artifact | Location |
|----------|----------|
| AWS inventory (JSON) | `outputs/aws-migration-artifacts/aws-inventory.json` |
| AWS architecture diagram | `outputs/aws-migration-artifacts/architecture-diagram.mmd` |
| Dependency matrix | `outputs/aws-migration-artifacts/dependency-matrix.csv` |
| Migration assessment | `outputs/aws-migration-artifacts/migration-assessment.md` |
| CloudFormation template (captured) | `outputs/aws-migration-artifacts/cloudformation-template.yaml` |
| Azure architecture diagram | `outputs/azure-architecture-output/architecture-diagram-azure.mmd` |
| Service mapping | `outputs/azure-architecture-output/service-mapping.md` |
| Cost comparison | `outputs/azure-architecture-output/cost-comparison.md` |
| Refactored Azure Functions | `outputs/azure-functions/function_app.py` |
| Bicep templates (deployed) | `outputs/bicep-templates/` |
| Static web app | `outputs/static-web-app/` |

---

## Complete Agent Specifications

### Agent 1: AWS Discovery Agent

**File Location:** `.github/agents/aws-discovery.agent.md`

**Purpose:** Automated, read-only discovery of AWS resources using AWS Cloud Control API MCP Server

**MCP Server Integration:**
- AWS Cloud Control API MCP Server — https://awslabs.github.io/mcp/servers/ccapi-mcp-server
- AWS Knowledge MCP

**Capabilities:**
- Discovers all AWS resources (Lambda, API Gateway, S3, IAM, CloudWatch, KMS, CloudFormation, etc.)
- Maps dependencies between resources
- Generates Mermaid architecture diagrams
- Assesses migration complexity (LOW/MEDIUM/HIGH)
- Estimates migration effort in hours

**Outputs:**
1. `aws-inventory.json` - Complete resource inventory with ARNs, configurations
2. `architecture-diagram.mmd` - Visual Mermaid diagram of current state
3. `dependency-matrix.csv` - Service relationships and mechanisms
4. `migration-assessment.md` - Complexity ratings and effort estimates

**Custom Instructions:** `.github/instructions/discovery.instructions.md`
- Naming conventions for consistent documentation
- Complexity assessment guidelines
- Security and IAM documentation requirements
- Validation steps before completion

**Invocation:**
```
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis
```

---

### Agent 2: Azure Architect Agent

**File Location:** `.github/agents/azure-architect.agent.md`

**Purpose:** Design Azure architecture and generate Infrastructure as Code

**MCP Server Integration:**
- Microsoft Learn MCP Server
- URL: https://learn.microsoft.com/en-us/training/support/mcp

**Service Mappings:**
- AWS Lambda → Azure Functions (Consumption, Premium, or Dedicated plan)
- AWS EKS → Azure Kubernetes Service (AKS)
- AWS RDS → Azure Database for PostgreSQL/MySQL Flexible Server
- AWS S3 → Azure Blob Storage (with lifecycle policies)
- AWS DynamoDB → Azure Cosmos DB
- AWS EventBridge → Azure Event Grid
- AWS SQS/SNS → Azure Service Bus Queues/Topics
- AWS IAM → Azure Managed Identity + RBAC
- AWS Secrets Manager → Azure Key Vault

**Capabilities:**
- Maps AWS services to Azure equivalents using official documentation
- Generates modular Bicep templates
- Applies Azure Well-Architected Framework (5 pillars)
- Creates parameter files per environment (dev/staging/production)
- Provides detailed cost comparison

**Bicep Template Structure:**
```
azure-infrastructure/
├── main.bicep (orchestration)
├── modules/
│   ├── networking.bicep
│   ├── compute.bicep
│   ├── database.bicep
│   ├── storage.bicep
│   ├── messaging.bicep
│   ├── security.bicep
│   └── monitoring.bicep
└── parameters/
    ├── dev.bicepparam
    ├── staging.bicepparam
    └── production.bicepparam
```

**Outputs:**
1. Complete Bicep template set
2. `architecture-diagram-azure.mmd` - Target Azure architecture
3. `cost-comparison.md` - AWS vs Azure monthly costs with savings calculation
4. `service-mapping.md` - Detailed AWS → Azure translations

**Custom Instructions:** `.github/instructions/azure-architecture.instructions.md`
- Bicep best practices (symbolic names, decorators, modularization)
- Security requirements (private endpoints, Managed Identity, Key Vault)
- Cost optimization strategies
- Well-Architected Framework application

**Invocation:**
```
@azure-architect Design the Azure architecture based on the AWS discovery and generate all Bicep templates
```

---

### Agent 3: Code Refactor Agent

**File Location:** `.github/agents/code-refactor.agent.md`

**Purpose:** Refactor Python Lambda handlers to Azure Functions Python v2 model

**Source Directory:** `app-code/lambda-functions/`  
**Target Directory:** `app-code/azure-functions/` (actual output: `outputs/azure-functions/`)

**SDK Replacements:**

Python:
- `boto3.client('s3')` → `azure.storage.blob.BlobServiceClient`
- `boto3.session.Session()` → `azure.identity.DefaultAzureCredential()`
- `s3.generate_presigned_url()` → `generate_sas()` via `get_user_delegation_key()`

**Authentication:** `DefaultAzureCredential()` — works automatically with Managed Identity in Azure, and with `az login` locally

**Production Gotchas (learned from this migration):**

| Issue | Problem | Solution |
|-------|---------|---------|
| Python version | 3.12/3.13 crash with `0xC0000005` in Azure Functions v4 | Use Python 3.9–3.11 only |
| Reserved env var | `CONTAINER_NAME` is reserved by Azure Functions host | Use `BLOB_CONTAINER_NAME` instead |
| Static Web Apps | Rejects root with only `app.html` | Require `index.html` as default |
| SAS with Managed Identity | Must call `get_user_delegation_key()` before `generate_blob_sas()` | See `outputs/azure-functions/function_app.py` |

**Custom Instructions:** `.github/instructions/code-refactoring.instructions.md`

**Invocation:**
```
@code-refactor Refactor all Lambda handlers to Azure Functions Python v2 model with Azure Blob Storage
```

---

### Agent 4: IaC Transformation Agent

**File Location:** `.github/agents/iac-transformation.agent.md`

**Purpose:** Convert CloudFormation templates to modular Bicep and generate deployment scripts

**Source:** `outputs/aws-migration-artifacts/cloudformation-template.yaml`  
**Target:** `outputs/bicep-templates/`

**MCP Server Integration:**
- Microsoft Learn MCP — retrieves Azure Verified Module (AVM) definitions

**Bicep Template Architecture Generated:**
```
outputs/bicep-templates/
├── main.bicep              (targetScope = 'subscription')
├── modules/
│   ├── storage.bicep       (AVM: avm/res/storage/storage-account)
│   ├── functions.bicep     (AVM: avm/res/web/site)
│   ├── staticweb.bicep
│   ├── keyvault.bicep
│   ├── monitoring.bicep
│   └── rbac.bicep
└── parameters/
    ├── dev.bicepparam
    ├── staging.bicepparam
    └── prod.bicepparam
```

**Outputs:**
- Modular Bicep template set (deployed successfully to `img-upload-dev-rg`, australiaeast)
- Environment-specific parameter files

**Custom Instructions:** `.github/instructions/iac-transformation.instructions.md`

**Invocation:**
```
@iac-transformation Convert the CloudFormation template to Bicep using Azure Verified Modules and deploy with az deployment sub create
```

---

### Agent 5: Deployment Validation Agent

**File Location:** `.github/agents/deployment-validation.agent.md`

**Purpose:** Validate Azure deployment and confirm migration success

**Validation Steps Performed:**

**Pre-Deployment:**
- `az bicep build` — syntax validation
- `az deployment sub what-if` — preview resource changes

**Post-Deployment:**
- All Bicep outputs accessible (storage account name, function app URL)
- Managed Identity has `Storage Blob Data Contributor` role on storage account
- HTTP smoke tests: upload, list, view URL, delete endpoints all return expected status codes
- Static web app serving `index.html` correctly

**Security Validation:**
- No hardcoded credentials in function code
- Key Vault configured for any future secrets
- Application Insights connected for observability
- `BLOB_CONTAINER_NAME` used (not the reserved `CONTAINER_NAME`)

**Custom Instructions:** `.github/instructions/deployment-validation.instructions.md`

**Invocation:**
```
@deployment-validation Validate the Azure deployment — check all resources, run smoke tests, and confirm the static web app is accessible
```

---

## Actual AWS Application (Migrated)

### Image Upload Service

A serverless image upload and management service originally built on AWS:

**Components:**
- **4 Lambda Functions** — upload, list, view (pre-signed URL), delete
- **AWS API Gateway** — REST API fronting all functions
- **2 S3 Buckets** — one for uploaded images, one for build artifacts
- **IAM Roles** — Lambda execution roles + S3 access policies
- **AWS CloudFormation** — infrastructure as code
- **CloudWatch** — 8 log groups (one per function + API Gateway)

**AWS Account:** 535002891143  
**AWS Region:** ap-southeast-2 (Sydney)

### Azure Target Architecture

| AWS Component | Azure Equivalent | Deployed |
|---|---|---|
| AWS Lambda (4 functions) | Azure Functions (Python v2, single file) | ✅ `function_app.py` |
| AWS API Gateway | Azure Functions HTTP triggers | ✅ (built-in) |
| S3 image bucket | Azure Blob Storage container | ✅ `img-upload-dev-sa` |
| S3 static site | Azure Static Web Apps | ✅ `outputs/static-web-app/` |
| IAM Lambda role | Azure Managed Identity | ✅ `DefaultAzureCredential()` |
| CloudFormation | Bicep templates | ✅ `outputs/bicep-templates/` |
| CloudWatch Logs | Application Insights + Log Analytics | ✅ `monitoring.bicep` |
| AWS Secrets Manager | Azure Key Vault | ✅ `keyvault.bicep` |

---

## Real Cost Comparison

| Scale | AWS Monthly | Azure Monthly | Saving |
|---|---|---|---|
| Demo (minimal traffic) | $2.92 | $0.54 | **81% reduction** |
| Production (1M calls, 100GB) | ~$148.80 | ~$108.80 | **27% reduction** |

Source: `outputs/azure-architecture-output/cost-comparison.md`

---

## Production Lessons Learned

1. **Python runtime constraint** — Azure Functions v4 only supports Python 3.9–3.11. Python 3.12 and 3.13 crash the worker with access violation `0xC0000005`.

2. **Reserved environment variable** — `CONTAINER_NAME` is reserved by the Azure Functions host. Using it caused silent failures; switched to `BLOB_CONTAINER_NAME`.

3. **Static Web App root file** — Azure SWA rejects deployments where `index.html` does not exist at root. Added `index.html` redirecting to `app.html`.

4. **Managed Identity SAS tokens** — Pre-signed URL generation with Managed Identity requires a two-step process: `get_user_delegation_key()` then `generate_blob_sas()`. Not identical to `boto3.generate_presigned_url()`.

5. **No CLI inside agents** — All agent tool access goes through MCP servers exclusively. No PowerShell or Azure CLI commands are issued inside agent prompts.

---

## Migration Statistics

| Metric | Value |
|---|---|
| AWS resources discovered | 18 active |
| Lambda functions migrated | 4 |
| Lines of Python refactored | ~250 |
| Bicep modules created | 6 |
| Deployment time | ~8 minutes |
| Manual interventions | 0 |
| Cost reduction (demo) | 81% |

---

## Document Status

| Document | Status |
|---|---|
| 00-MASTER-INDEX.md | ✅ Updated — v2.0 |
| 01-EXECUTIVE-PRESENTATION.md | ✅ Updated — completed migration results |
| 03-CUSTOM-AGENT-SPECIFICATIONS.md | ✅ Updated — actual tool bindings + production gotchas |
| 04-DEMO-PLAN.md | ✅ Updated — real Image Upload Service demo flow |
| 05-AWS-INFRASTRUCTURE-SETUP.md | Reference only — original AWS setup |
| 06-DEMO-EXECUTION-GUIDE.md | Reference — agent invocation scripts |
| 07-SERVICE-MAPPING-REFERENCE.md | ✅ Updated — v2.0 header |
| 08-MCP-SERVER-INTEGRATION.md | ✅ Updated — actual 5 MCP servers used |
| COMPLETE-PACKAGE-SUMMARY.md | ✅ This file |

---

*Generated by GitHub Copilot custom agents — AI-Assisted AWS to Azure Migration*


## Recommendations

**Immediate Action:**
1. Review this package with technical leadership
2. Approve proof-of-concept budget ($15K, 2-3 weeks)
3. Select pilot services for POC
4. Schedule demonstration for stakeholders

**30-Day Plan:**
1. Week 1: Execute POC with 1-2 services
2. Week 2-3: Train team on agents
3. Week 4: Review results and decide on full migration
4. If approved: Begin systematic migration

**Success Factors:**
- Executive sponsorship
- Dedicated team time
- Clear success criteria
- Iterative approach with early wins
- Regular stakeholder updates

---

**This package provides everything needed to begin AI-assisted AWS to Azure migration.**

**Next Step:** Schedule executive presentation to review approach and approve proof-of-concept.
