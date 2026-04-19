# 30-Minute Demonstration Plan

**Document Version:** 3.0  
**Date:** April 2026  
**Status:** ✅ Based on completed real migration  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Demonstration Overview

**Objective:** Walk through the complete AWS to Azure migration of the Image Upload Service, executed by seven custom GitHub Copilot agents — culminating in the **Migration Project Manager Agent**, which orchestrates the entire pipeline with a single prompt.

**Environment:** Real serverless AWS architecture — 4 Lambda functions + API Gateway + 2 S3 buckets, migrated and live on Azure.

**Outcome:** Attendees see all migration artifacts, refactored code, Bicep templates, and the live Azure deployment. The headline moment is showing how `@migration-project-manager` replaces weeks of manual coordination with one command.

### The Story Arc

This demo tells a story of **progressive automation**:

1. "Here’s the original AWS application" — real code, real infrastructure
2. "Here are the five specialist agents we built" — discovery, architecture, refactor, IaC, validation
3. "Here’s what they each produced" — walk the output artifacts
4. "But there’s a problem with five separate agents..." — you still have to coordinate them manually
5. **"So we built the Project Manager Agent" — this is the breakthrough moment**
6. Show `@migration-project-manager` — one command, full pipeline, live task tracking

Every phase you show builds the case for why the PM Agent is the logical conclusion of this architecture.

---

## Pre-Demo Checklist

### Repository
- [ ] Clone this repository and open in VS Code
- [ ] Verify `.github/agents/` contains all seven agent files (including `migration-project-manager.agent.md` and `pipeline-builder-agent.agent.md`)
- [ ] Verify `.github/instructions/` contains all five instruction files
- [ ] Verify `outputs/` folder contains all generated artifacts
- [ ] Verify `outputs/migration-task-plan.md` exists (shows PM Agent output)

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
   - Show `.github/agents/` — **seven** agent files
   - Point them out: five specialists + one pipeline builder + one project manager
   - "These agents are the cast. The Project Manager Agent is the director."
   - Tease: "We'll come back to that last one \u2014 it\u2019s the most important"

**Talking Points:**
- "This is a real AWS account \u2014 ap-southeast-2 Sydney"
- "4 Lambda functions, API Gateway with IAM/SigV4 authentication, 2 S3 buckets"
- "The discovery was automated by the first agent in under 30 minutes"
- "We started with five specialist agents. Then we asked: what if you didn\u2019t have to coordinate them at all?"

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

### Minutes 23-27: The Migration Project Manager Agent ⭐

**This is the highlight of the demo.** Everything shown so far was produced by five specialist agents invoked one at a time. Now show what happens when a single agent orchestrates all of them.

**What to Show:**

1. **Frame the problem** (30 seconds)
   - "We had five great specialist agents. But you still had to know which to run, in what order, with the right prompts, and verify the outputs between phases."
   - "That\u2019s still a lot of coordination. So we built a sixth layer \u2014 a Project Manager Agent."

2. **Show the agent file** (30 seconds)
   - Open `.github/agents/migration-project-manager.agent.md`
   - Scroll through briefly \u2014 show the pipeline diagram in the agent, show Phase 3 runs in parallel
   - "This agent doesn\u2019t write code or Bicep. Its job is to manage the plan, invoke the right agents, and verify the outputs."

3. **Show the live task plan** (1 minute)
   - Open `outputs/migration-task-plan.md`
   - "This file was created and maintained by the PM Agent throughout the migration."
   - Walk through the phase summary table \u2014 all \u2705, all with timestamps
   - Show how Phase 3 tasks are enriched with per-module and per-function tasks extracted from the architecture design document
   - "This is the audit trail. Anyone can see exactly what ran, when, and what was produced."

4. **Show the invocation** (30 seconds)
   - Type out (or show pre-prepared card):
     ```
     @migration-project-manager Run the full AWS to Azure migration pipeline
     ```
   - "That\u2019s it. That one prompt ran the entire migration. Discovery, architecture, code refactoring, IaC, CI/CD pipeline, and validation. In the right order. With parallelism where possible. With artifact checks between phases."

5. **Emphasise the modularity** (30 seconds)
   - "Because each specialist agent is completely independent, any one of them can be updated, replaced, or extended without touching the others."
   - "Add a new cloud service mapping? Update Agent 2. Change your Bicep standards? Update Agent 4. The PM Agent doesn\u2019t care \u2014 it just checks that the artifact exists and moves on."
   - "This is what makes the system scalable \u2014 modular by design, orchestrated by AI."

**Talking Points:**
- "Five specialist agents is a toolkit. The PM Agent is the automation."
- "The task plan file is the difference between \u2018AI helped us\u2019 and \u2018AI ran it\u2019 \u2014 you have a full audit trail"
- "Phase 3 ran IaC transformation, code refactoring, and CI/CD pipeline build in parallel \u2014 the PM Agent managed that automatically"
- "The PM Agent can also resume from any phase \u2014 if validation fails, you fix the issue and run `@migration-project-manager Start from validation` \u2014 it picks up exactly where it left off"

---

---

### Minutes 27-30: Results and Q&A

**What to Show:**

1. **Live Azure Portal** (1 minute)
   - Show `img-upload-dev-rg` resource group with all deployed resources
   - Function App `img-upload-dev-func` running, Static Web App live
   - Application Insights dashboard with telemetry

2. **Summary** (1 minute)
   - Display real results:
     ```
     Application: Image Upload Service (AWS account 535002891143, ap-southeast-2)

     AI-Assisted Migration Results (7 Agents):
       - Discovery:    26 resources, complexity LOW, effort 2–3 weeks estimated
       - Design:       Azure Functions + Blob Storage + Static Web Apps + App Insights + Key Vault
       - Refactoring:  4 Lambda (boto3) → 4 Azure Functions (azure-storage-blob + azure-identity)
       - IaC:          CloudFormation → 6 Bicep modules, deployed to australiaeast ✅
       - CI/CD:        GitHub Actions pipeline with OIDC auth, 3-stage (dev/staging/prod) ✅
       - Orchestrated: By @migration-project-manager — one prompt, full pipeline ✅

     Cost Outcome:
       - AWS demo scale:   $2.92/month
       - Azure demo scale: $0.54/month
       - Reduction:        81%

     Agents for Future Migrations:
       - All gotchas captured (Python version, reserved env vars, SWA entry point)
       - PM Agent resumes from any phase — no wasted work
       - Each specialist agent is independently improvable
     ```

3. **Q&A** (1 minute)
   - Common questions:
     - "Can we customize the agents for our standards?" → Yes, edit `.github/instructions/` files
     - "What about security?" → Managed Identity, RBAC, Key Vault, no access keys
     - "Can the PM Agent handle bigger migrations?" → Yes — same orchestration pattern, more specialist agents if needed
     - "What if a phase fails?" → PM Agent surfaces the blocker clearly; fix the issue and resume from that phase
     - "What MCP servers are needed?" → AWS Cloud Control API, AWS Knowledge, Microsoft Learn, Azure, Mermaid

**Talking Points:**
- "This migration is live on Azure right now \u2014 not theoretical"
- "Every lesson learned is embedded in the agents for the next migration"
- "The PM Agent is what takes this from \u2018AI-assisted\u2019 to \u2018AI-automated\u2019"
- "Same approach scales to any application regardless of complexity \u2014 the modularity is the key"

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

"Good morning/afternoon everyone. Today I'm going to show you something that will change how you think about cloud migrations. We're going to migrate a real AWS serverless application to Azure — completely — and I'm not going to write a single line of code or configuration. Instead, I'm going to use seven AI agents that we've built specifically for this. But the real headline isn't the seven agents. It's the eighth thing we built to coordinate them all."

[Show AWS Console]

"Here's what we're starting with: A real image upload service running in AWS. Four Lambda functions handling upload, listing, viewing, and deletion of images. API Gateway fronting those functions. Two S3 buckets. This is a real AWS account — account 535002891143, Sydney region. Traditionally, migrating something like this takes 3–4 weeks and costs hundreds of thousands in consulting fees. Watch what happens when AI runs every part of the process."

### Discovery (Minute 5)

[Open VS Code]

"I'm going to invoke our first agent — the AWS Discovery Agent. Watch what happens."

[Type command]

"The agent is now using the AWS Cloud Control API MCP Server to scan the entire environment. It's discovering Lambda functions, analyzing S3 buckets, mapping IAM dependencies — everything. And here are the results..."

[Open files in `outputs/aws-migration-artifacts/`]

"Complete JSON inventory with every resource, a dependency matrix showing how services interact, a Mermaid architecture diagram, and a migration assessment. Complexity: LOW. Recommended effort: 2–3 weeks. This discovery process normally takes days — just took two minutes."

### Design (Minute 10)

"Now for the architecture design. I'll invoke the Azure Architect agent."

[Type command]

"The agent is accessing Microsoft Learn documentation to find the correct Azure equivalents. Lambda maps to Azure Functions, S3 maps to Azure Blob Storage, API Gateway is replaced by Azure Functions' built-in HTTP triggers. It's generating production-ready Bicep templates following Azure best practices and Azure Verified Modules."

[Open `outputs/azure-architecture-output/`]

"Here's the generated service mapping and cost comparison. Azure will cost $0.54 per month versus $2.92 on AWS at demo scale — 81% reduction. Architecture design done in minutes, not weeks."

### Refactor (Minute 18)

[Show `app-code/lambda-functions/`]

"Here are our Lambda handlers using boto3, the AWS Python SDK. Let's refactor them for Azure."

[Type command]

"The agent is replacing boto3 with azure-storage-blob and azure-identity, converting the Lambda handler signatures to Azure Functions Python v2 `@app.route()` decorators, and implementing SAS token generation using the Managed Identity delegation pattern."

[Show `outputs/azure-functions/function_app.py`]

"Here's the result. A single Azure Functions file with all 4 endpoints. DefaultAzureCredential instead of IAM credentials. Two minutes versus two weeks."

### The PM Agent — The Capstone Moment (Minute 23)

[Open `.github/agents/migration-project-manager.agent.md`]

"So we built five specialist agents. Discovery, architecture, refactoring, IaC, validation. Each one does its job beautifully. But you still had to know the right order, the right prompts, and check the outputs between phases. That's still coordination overhead. So we built one more agent."

[Show the pipeline diagram inside the agent file]

"The Migration Project Manager Agent. It doesn't write code. It doesn't write Bicep. What it does is orchestrate every other agent in the right sequence, verify the artifacts between phases, run IaC transformation, code refactoring, and CI/CD pipeline build in parallel, and maintain a live task plan file so you always know where the pipeline is."

[Show `outputs/migration-task-plan.md`]

"Here's what that task plan looks like. Created automatically. Updated after every phase. Full audit trail — who ran what, when, and what was produced. Every task enriched with the actual module names and function names from the architecture design."

"And the invocation? One line:"

[Type slowly for effect]
```
@migration-project-manager Run the full AWS to Azure migration pipeline
```

"That's it. That one prompt is the entire migration. The PM Agent does the rest."

### Deploy (Minute 26)

"Let's validate and deploy the Bicep infrastructure."

[Show `outputs/bicep-templates/`]

"The IaC Transformation agent generated this modular Bicep structure — one file per Azure resource, subscription-scoped deployment, parameters per environment. The Deployment Validation agent already ran syntax checks and security validation."

[Show deployed resources in Azure Portal]

"And here's the running environment — resource group `img-upload-dev-rg` in australiaeast. Storage account, Function App, Static Web App, Key Vault, Application Insights. All deployed via a single `az deployment sub create` command. Zero manual steps."

### Closing (Minute 28)

[Show results panel]

"In less than 30 minutes, we've shown you what traditionally takes 3–4 weeks: discovery, architecture, code refactoring, IaC, CI/CD pipeline, and validation. Seven AI agents. One orchestrator. 81% cost reduction. Zero hardcoded credentials. And all of this is modular — need to change your Bicep standards? Update one agent file. Change your security policy? Update one instruction file. The PM Agent doesn't care — it just verifies the output and moves on."

"This is what AI-automated migration looks like. Not AI-assisted. Automated."

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
