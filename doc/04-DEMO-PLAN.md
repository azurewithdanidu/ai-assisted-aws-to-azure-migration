# 30-Minute Demonstration Plan

**Document Version:** 2.0  
**Date:** April 2026  
**Status:** ✅ Based on completed real migration  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Demonstration Overview

**Objective:** Walk through the complete AWS to Azure migration of the Image Upload Service that was executed using five custom GitHub Copilot agents.

**Environment:** Real serverless AWS architecture — 4 Lambda functions + API Gateway + 2 S3 buckets, migrated and live on Azure.

**Outcome:** Attendees see all migration artifacts, refactored code, Bicep templates, and the live Azure deployment produced by the AI agents.

---

## Pre-Demo Checklist

### Repository
- [ ] Clone this repository and open in VS Code
- [ ] Verify `.github/agents/` contains all five agent files
- [ ] Verify `.github/instructions/` contains all five instruction files
- [ ] Verify `outputs/` folder contains all generated artifacts

### Azure Access (for live validation)
- [ ] `az login` and `az account show` — confirm australiaeast subscription
- [ ] Confirm `img-upload-dev-rg` resource group exists
- [ ] Confirm Function App `img-upload-dev-func` is running

### Development Environment
- [ ] VS Code with GitHub Copilot extension installed
- [ ] AWS CLI configured (read-only access to account 535002891143)
- [ ] Azure CLI configured with Contributor access

---

## Demonstration Flow

### Minutes 0-5: Show the Original AWS Application

**What to Show:**

1. **Original AWS Lambda code** (2 minutes)
   - Open `app-code/lambda/upload/upload_handler.py`
   - Highlight `boto3` imports and `s3.generate_presigned_post()` pattern
   - Open `app-code/lambda/list/list_handler.py` — show `s3.list_objects_v2()`
   - Open `app-code/build/app.html` — show AWS SDK SigV4 authentication in frontend

2. **AWS Architecture** (2 minutes)
   - Open `outputs/aws-migration-artifacts/architecture-diagram.mmd` — show Mermaid diagram
   - Open `outputs/aws-migration-artifacts/migration-assessment.md`
   - Point out: "18 active resources, LOW complexity, 2–3 weeks estimated"

3. **Repository Structure** (1 minute)
   - Show `.github/agents/` — five agent files
   - "These agents did all four phases of this migration"

**Talking Points:**
- "This is a real AWS account — ap-southeast-2 Sydney"
- "4 Lambda functions, API Gateway with IAM/SigV4 authentication, 2 S3 buckets"
- "The discovery was automated by the first agent in under 30 minutes"

---

### Minutes 5-10: Discovery Phase Results

**What to Show:**

1. **AWS Inventory** (2 minutes)
   - Open `outputs/aws-migration-artifacts/aws-inventory.json`
   - Show Lambda functions, API Gateway routes, S3 buckets, IAM roles, KMS key
   - Highlight AppStream 2.0 remnants flagged for cleanup — "agent found orphaned resources"

2. **Dependency Matrix** (1 minute)
   - Open `outputs/aws-migration-artifacts/dependency-matrix.csv`
   - Show: Lambda → S3, Lambda → IAM role, API Gateway → Lambda

3. **CloudFormation template** (1 minute)
   - Open `outputs/aws-migration-artifacts/cloudformation-template.yaml`
   - "Agent captured the source IaC for conversion to Bicep"

4. **Agent invocation replay** (1 minute)
   ```
   @aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis
   ```

**Talking Points:**
- "Discovery that takes 3 weeks manually took 20 minutes with the agent"
- "Read-only — nothing in AWS was modified"
- "8 orphaned AppStream resources identified — cleanup recommendation included"

---

### Minutes 10-18: Architecture Design and IaC

**What to Show:**

1. **Azure Architecture Diagram** (2 minutes)
   - Open `outputs/azure-architecture-output/architecture-diagram-azure.mmd`
   - Walk through: Browser → Static Web App → Azure Functions → Blob Storage
   - "No APIM — agent determined HTTP triggers are a direct equivalent for this pattern"

2. **Service Mapping** (2 minutes)
   - Open `outputs/azure-architecture-output/service-mapping.md`
   - Show Lambda → Azure Functions (Python 3.11, Consumption plan)
   - Show API Gateway → Functions HTTP triggers (function key auth replaces SigV4)
   - Show S3 images bucket → Azure Blob Storage (Managed Identity + RBAC)
   - Show S3 static site → Azure Static Web Apps (Free tier)

3. **Cost Comparison** (1.5 minutes)
   - Open `outputs/azure-architecture-output/cost-comparison.md`
   - Show AWS demo scale: $2.92/month vs Azure: $0.54/month
   - "81% cost reduction at demo scale — Azure Functions free tier covers most of the load"

4. **Bicep Templates** (2 minutes)
   - Open `outputs/bicep-templates/main.bicep`
   - Show `targetScope = 'subscription'` — subscription-scoped deployment
   - Open `outputs/bicep-templates/modules/storage.bicep` — Blob Storage with RBAC assignment
   - Open `outputs/bicep-templates/modules/functions.bicep` — Function App with Managed Identity
   - "Agent used Azure Verified Modules (AVM) from Microsoft Learn MCP"

**Talking Points:**
- "Architecture design and full Bicep IaC generated from discovery output"
- "Well-Architected Framework applied automatically — private access, Managed Identity, Key Vault"
- "Three parameter files generated: dev, staging, prod"

---

### Minutes 18-23: Code Refactoring

**What to Show:**

1. **Original Lambda code vs Refactored Azure Function** (3 minutes)
   - Side-by-side: `app-code/lambda/upload/upload_handler.py` vs `outputs/azure-functions/function_app.py`
   - Before: `boto3.client('s3')` + `generate_presigned_post()`
   - After: `BlobServiceClient` + `DefaultAzureCredential()` + `generate_blob_sas()` with user-delegation key
   - Show `@app.route()` decorator pattern (Azure Functions Python v2)

2. **Requirements file** (30 seconds)
   - Open `outputs/azure-functions/requirements.txt`
   - `boto3` removed — `azure-functions`, `azure-storage-blob`, `azure-identity` added

3. **Refactored Frontend** (1 minute)
   - Open `outputs/static-web-app/app.html`
   - Comment at top: "AWS SDK removed — replaced by plain fetch() with x-functions-key header"
   - Show function key field in the UI — replaces SigV4 auth

4. **Known gotchas the agent captured** (30 seconds)
   - "Python 3.13 not supported — agent pinned to 3.11"
   - "CONTAINER_NAME is reserved — agent used BLOB_CONTAINER_NAME"
   - "These are now in the agent definition for all future migrations"

**Talking Points:**
- "All 4 Lambda functions consolidated into a single Azure Functions v2 app"
- "Zero AWS SDK references remain — full Managed Identity auth"
- "SAS URL pattern preserved — clients still upload/download directly to storage"

4. **Review Refactored Code** (2 minutes)
   - Show updated code:
     ```javascript
     const { BlobServiceClient } = require('@azure/storage-blob');
     const { EventGridPublisherClient } = require('@azure/eventgrid');
     const { DefaultAzureCredential } = require('@azure/identity');
     ```
   - Highlight changes:
     - "S3 → Blob Storage"
     - "EventBridge → Event Grid"
     - "IAM → Managed Identity"
   
   - Show updated package.json:
     ```json
     "dependencies": {
       "@azure/storage-blob": "^12.17.0",
       "@azure/eventgrid": "^5.0.0",
       "@azure/identity": "^4.0.0"
     }
     ```

5. **Show Pull Request** (30 seconds)
   - Open GitHub PR created by agent
   - Show detailed description
   - "All tests passing"
   - "Ready for team review"

**Talking Points:**
- "Code refactoring that takes 2 weeks just took 2 minutes"
- "Agent maintained 100% functional parity"
- "All tests still pass"
- "Authentication now uses Managed Identity (more secure)"
- "Ready for peer review via pull request"

---

### Minutes 23-27: Deployment and Validation

**What to Show:**

1. **Bicep Deployment** (1.5 minutes)
   - Open a terminal, show the command that was used:
     ```
     az deployment sub create --location australiaeast --template-file main.bicep --parameters parameters/dev.bicepparam
     ```
   - "This deployed all six Bicep modules — Storage, Functions, Static Web App, Key Vault, Monitoring, RBAC"
   - Show the Azure Portal: resource group `img-upload-dev-rg`
   - Show Function App `img-upload-dev-func` — Status: Running

2. **Static Web App** (1 minute)
   - Show `outputs/static-web-app/app.html` and `index.html`
   - "Azure Static Web Apps requires index.html — the agent captured this gotcha"
   - "Now deployed on Azure Static Web Apps Free tier at $0/month"

3. **Validation Agent invocation** (1 minute)
   ```
   @deployment-validation Validate the Azure deployment end-to-end and confirm functional parity
   ```
   - Walk through validation checklist:
     - Bicep syntax: ✅ Valid
     - ARM template validation: ✅ Valid  
     - HTTPS only: ✅ Enforced
     - Managed Identity: ✅ Active
     - Key Vault: ✅ Accessible, soft-delete enabled
     - Function endpoints: ✅ All 4 routes return 200/40x as expected
     
**Talking Points:**
- "Infrastructure deployed successfully on first attempt — Bicep validated before apply"
- "Deployment validation confirmed functional parity with the AWS original"
- "Everything secured with Managed Identity — no access keys anywhere"
   - Show updated `.buildkite/pipeline.yml`:
     ```yaml
     steps:
       - label: "Validate Bicep"
         command: az bicep build --file main.bicep
       
       - label: "Preview Changes"
         command: az deployment group what-if
       
       - label: "Deploy to Azure"
         command: az deployment group create
       
       - label: "Run Tests"
         command: npm test --env=azure
     ```
   - "Now deploys to Azure instead of AWS"
   - "Added validation step"
   - "Rollback procedure included"

5. **Invoke Validation Agent** (30 seconds)
   ```
   @deployment-validation Validate the Bicep templates and run security compliance checks
   ```

6. **Review Validation Report** (1.5 minutes)
   - Open validation report
   - Show checks:
     - Bicep syntax: PASS
     - Security scan: PASS
     - Cost estimate: $620/month (within budget)
     - Azure Policy: PASS
     - Performance estimate: Equivalent to AWS
   - "Everything validated and ready to deploy"

**Talking Points:**
- "Infrastructure transformation that takes 2 weeks just took 2 minutes"
- "CloudFormation automatically converted to Bicep"
- "CI/CD pipeline updated for Azure"
- "Security validation passed"
- "Ready for production deployment"

---

### Minutes 27-30: Results and Q&A

**What to Show:**

1. **Summary** (1 minute)
   - Display real results:
     ```
     Application: Image Upload Service (AWS account 535002891143, ap-southeast-2)

     AI-Assisted Migration Results:
       - Discovery:    26 resources, complexity LOW, effort 2–3 weeks estimated
       - Design:       Azure Functions + Blob Storage + Static Web Apps + App Insights + Key Vault
       - Refactoring:  4 Lambda (boto3) → 4 Azure Functions (azure-storage-blob + azure-identity)
       - IaC:          CloudFormation → 6 Bicep modules, deployed to australiaeast ✅

     Cost Outcome:
       - AWS demo scale:  $2.92/month
       - Azure demo scale: $0.54/month
       - Reduction:        81%

     Agents Reused for Future Migrations:
       - All gotchas captured (Python version, reserved env vars, SWA entry point)
       - Agents improve with each migration
     ```

2. **Live Azure Portal** (1 minute)
   - Show `img-upload-dev-rg` resource group with all deployed resources
   - Function App running, Static Web App live
   - Application Insights dashboard with telemetry

3. **Q&A** (1 minute)
   - Common questions:
     - "Can we customize the agents for our standards?" → Yes, edit `.github/instructions/` files
     - "What about security?" → Managed Identity, RBAC, Key Vault, no access keys
     - "Can we use this for other migrations?" → Yes, agents are 100% reusable
     - "What MCP servers are needed?" → AWS Cloud Control API, AWS Knowledge, Microsoft Learn, Azure, Mermaid

**Talking Points:**
- "This migration is live on Azure right now — not theoretical"
- "Every lesson learned is embedded in the agents for the next migration"
- "Same approach scales to any application regardless of complexity"

---

## Backup Plans

### If Agent Fails

**Have prepared:**
- Pre-recorded demo video (15 minutes)
- Static screenshots of each phase
- Pre-generated outputs in repository

**Switch to:**
- "Let me show you the outputs from a previous run"
- Walk through pre-generated files
- Show final results

### If Network Issues

**Have prepared:**
- Offline slides with screenshots
- Local copies of all outputs
- Architecture diagrams as static images

**Switch to:**
- "Let me walk you through what we've already validated"
- Show static content
- Focus on business value discussion

### If Time Runs Over

**Priority cuts:**
1. Skip detailed code review (show highlights only)
2. Skip validation report review
3. Shorten Q&A (offer follow-up meeting)

**Never cut:**
- Environment overview (sets context)
- Discovery demo (most impressive)
- Cost comparison (business value)

---

## Post-Demo Follow-Up

### Immediate (Same Day)

- [ ] Share recording link
- [ ] Email demo repository URL
- [ ] Send cost comparison spreadsheet
- [ ] Schedule follow-up meeting

### Week 1

- [ ] Provide detailed agent specifications
- [ ] Share CloudFormation templates
- [ ] Offer proof-of-concept support
- [ ] Answer technical questions

### Week 2

- [ ] Check if decision made
- [ ] Provide additional resources if needed
- [ ] Discuss pilot project scope
- [ ] Plan training sessions

---

## Demonstration Script (Word-for-Word)

### Opening (Minute 0)

"Good morning/afternoon everyone. Today I'm going to show you something that will change how you think about cloud migrations. We're going to migrate a complex, production-like AWS environment to Azure - completely - in the next 30 minutes. And I'm not going to write a single line of code or configuration. Instead, I'm going to use five AI agents that we've created to do all the work."

[Show AWS Console]

"Here's what we're starting with: A production-grade environment with an EKS cluster running three microservices, three Lambda functions, a Multi-AZ RDS PostgreSQL database, S3 buckets, and EventBridge for event-driven communication. Traditionally, this would take about 20 weeks to migrate. Let's see how fast we can do it with AI."

### Discovery (Minute 5)

[Open VS Code]

"I'm going to invoke our first agent - the AWS Discovery Agent. Watch what happens."

[Type command]

"The agent is now using the AWS Cloud Control API to scan our entire environment. It's discovering Lambda functions, analyzing the EKS cluster, mapping dependencies - everything. And here are the results..."

[Open files]

"Complete inventory with every resource, a dependency matrix showing how services interact, an architecture diagram the agent generated, and a migration assessment with complexity ratings. This discovery process that normally takes three weeks just took two minutes."

### Design (Minute 10)

"Now for the architecture design. I'll invoke the Azure Architect agent."

[Type command]

"The agent is accessing Microsoft Learn documentation to find the correct Azure equivalents. Lambda maps to Azure Functions, EKS to AKS, RDS to Azure Database for PostgreSQL. It's generating production-ready Bicep templates following Azure best practices."

[Open Bicep files]

"Here's the generated infrastructure code. Notice it's modular, uses private endpoints, implements Managed Identity. And look at this cost comparison..."

[Open cost file]

"Azure will cost us $620 per month versus $850 on AWS. That's $230 monthly savings, or $2,760 per year, calculated automatically by the agent. Architecture design that takes five weeks just took three minutes."

### Refactor (Minute 18)

[Show original code]

"Here's our Lambda function using AWS SDKs. Let's refactor it for Azure."

[Type command]

"The agent is replacing AWS SDKs with Azure equivalents, updating authentication from IAM to Managed Identity, running all the tests to ensure nothing breaks."

[Show refactored code]

"Here's the result. Azure Blob Storage instead of S3, Event Grid instead of EventBridge, Managed Identity instead of IAM credentials. All tests pass. Ready for production. Two minutes versus two weeks."

### Deploy (Minute 23)

"Finally, let's update our CI/CD pipeline and validate everything."

[Type commands]

"The agent is converting our CloudFormation to Bicep, updating the Buildkite pipeline to deploy to Azure, and running security validation."

[Show validation report]

"Everything passes. Bicep syntax valid, security compliant, costs within budget. Ready to deploy."

### Closing (Minute 27)

[Show summary slide]

"So in the last 30 minutes, we've done what traditionally takes 20 weeks. Five AI agents automated discovery, design, code refactoring, infrastructure transformation, and validation. 60% time savings, 78% cost savings, and all the knowledge stays with your team in these reusable agents."

"Questions?"

---

## Success Metrics

**Demo is successful if attendees:**
- Understand the business value (time and cost savings)
- See working automation (not just slides)
- Believe it can work for their environment
- Want to schedule follow-up meeting

**Red flags:**
- Attendees confused about what they saw
- Questions focus on "but what about X edge case"
- Skepticism about agent capabilities
- No follow-up interest

**Recovery:**
- Refocus on business value
- Acknowledge complexity exists but show how agents handle it
- Offer proof-of-concept to address concerns
- Schedule technical deep-dive for skeptics

---

**Next Document:** 06-DEMO-EXECUTION-GUIDE.md for detailed step-by-step execution
