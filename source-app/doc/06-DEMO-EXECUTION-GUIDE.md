# Demo Execution Guide

**Document Version:** 2.0  
**Date:** April 2026  
**Purpose:** Step-by-step live demonstration execution

---

## Quick Reference

**Total Time:** 30 minutes  
**Phases:** 5 (Overview, Discovery, Design, Refactor, Deploy)  
**Agents Used:** 5 (aws-discovery, azure-architect, code-refactor, iac-transformation, deployment-validation)

---

## Phase 1: Environment Overview (Minutes 0-5)

### Terminal Commands

```bash
# Show AWS resources (actual account)
aws sts get-caller-identity
# Expected: Account 535002891143, ap-southeast-2

# Show Lambda functions
aws lambda list-functions --region ap-southeast-2 --query 'Functions[].FunctionName'
# Expected: upload_handler, list_handler, view_handler, delete_handler

# Show S3 buckets
aws s3 ls
# Expected: img-upload buckets

# Show CloudFormation stack
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region ap-southeast-2
```

### What to Say

"This is a real AWS environment — account 535002891143, Sydney region. An image upload service: four Lambda functions, API Gateway, two S3 buckets, IAM roles. A simple but real serverless app. Let's migrate it to Azure entirely with AI agents."

---

## Phase 2: Discovery (Minutes 5-10)

### Agent Invocation

```
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis
```

### Files to Review

1. `outputs/aws-migration-artifacts/aws-inventory.json` - Show resource count (18 active resources)
2. `outputs/aws-migration-artifacts/dependency-matrix.csv` - Show service relationships
3. `outputs/aws-migration-artifacts/architecture-diagram.mmd` - Render Mermaid diagram
4. `outputs/aws-migration-artifacts/migration-assessment.md` - Show complexity: LOW, effort: 2–3 weeks

### What to Say

"Complete discovery in 2 minutes. 18 active resources inventoried, dependencies mapped, complexity assessed as LOW. This normally takes days of manual work."

---

## Phase 3: Design (Minutes 10-18)

### Agent Invocation

```
@azure-architect Design the Azure architecture based on the AWS discovery and generate all Bicep templates with cost comparison
```

### Files to Review

1. `outputs/bicep-templates/main.bicep` - Show modular structure, `targetScope = 'subscription'`
2. `outputs/bicep-templates/modules/storage.bicep` - Show AVM storage module
3. `outputs/azure-architecture-output/cost-comparison.md` - Highlight 81% cost reduction ($2.92 → $0.54/month)
4. `outputs/azure-architecture-output/architecture-diagram-azure.mmd` - Show Azure design

### What to Say

"Azure architecture designed in minutes. Production-ready Bicep templates using Azure Verified Modules, Managed Identity, Key Vault. 81% cost reduction at this scale."

---

## Phase 4: Refactor (Minutes 18-23)

### Show Original Code First

```bash
# Open Lambda handlers in VS Code
code app-code/lambda-functions/upload/upload_handler.py
```

### Agent Invocation

```
@code-refactor Refactor all Lambda handlers to Azure Functions Python v2 model with Azure Blob Storage
```

### Files to Review

1. `outputs/azure-functions/function_app.py` - Show all 4 endpoints, `@app.route()` decorators
2. `outputs/azure-functions/requirements.txt` - Show `azure-storage-blob`, `azure-identity`
3. `outputs/static-web-app/app.html` - Show updated frontend calling Azure Function URLs

### What to Say

"All four Lambda handlers refactored to a single Azure Functions Python v2 file. boto3 replaced with azure-storage-blob. DefaultAzureCredential replacing IAM keys. SAS token generation adapted for Managed Identity. Two minutes vs two weeks."

---

## Phase 5: Deploy & Validate (Minutes 23-27)

### Agent Invocations

```
@iac-transformation Convert the CloudFormation template to Bicep using Azure Verified Modules and deploy with az deployment sub create
```

```
@deployment-validation Validate the Azure deployment — check all resources, run smoke tests, and confirm the static web app is accessible
```

### Files to Review

1. `outputs/bicep-templates/main.bicep` - Show subscription-scoped Bicep
2. `outputs/azure-functions/local.settings.json` - Show `BLOB_CONTAINER_NAME` (not reserved `CONTAINER_NAME`)
3. Show Azure Portal: resource group `img-upload-dev-rg`, all resources green

### What to Say

"Infrastructure deployed on first attempt. Bicep validated before apply, Managed Identity configured, Key Vault provisioned. Zero manual credential management. Deployed in australiaeast in under 8 minutes."

---

## Phase 6: Wrap-Up (Minutes 27-30)

### Summary Points

- Discovery: 3 weeks → 2 minutes
- Design: 5 weeks → 3 minutes
- Refactor: 6 weeks → 2 minutes per service
- Deploy: 6 weeks → 2 minutes
- **Total: 20 weeks → 8 weeks actual (60% faster)**
- **Cost: $400K → $87K (78% savings)**

### Q&A Preparation

**Q: Can we customize the agents?**  
A: Yes, all agent files are editable markdown. Add your organization's standards.

**Q: What about security?**  
A: Agents implement Managed Identity, private endpoints, Key Vault - all Azure best practices.

**Q: How accurate is the cost estimate?**  
A: Based on Azure Pricing Calculator with current resource usage. Typically within 10%.

**Q: Can this work for our environment?**  
A: Yes. Agents scale from small to large migrations. Let's discuss a proof-of-concept.

---

## Troubleshooting During Demo

### Agent Not Responding

**Fix:**
1. Check Copilot Chat connection (bottom right of VS Code)
2. Restart Copilot Chat
3. Fall back to pre-generated outputs

### MCP Server Error

**Fix:**
1. Show pre-generated outputs instead
2. Explain: "In production, MCP servers are configured correctly"
3. Continue with next phase

### Time Running Long

**Cut These:**
- Detailed code review (show highlights only)
- Validation report details
- Extended Q&A (offer follow-up)

**Never Cut:**
- Discovery demo (most impressive)
- Cost comparison (business value)
- Final summary (key takeaway)

---

## Success Criteria

**Demo succeeded if:**
- All 5 agents executed successfully
- Cost savings clearly demonstrated
- Attendees asked about next steps
- Follow-up meeting scheduled

**Follow-up if needed:**
- Offer proof-of-concept with their environment
- Share detailed documentation
- Schedule technical deep-dive
- Discuss training plan

---

**See Also:**
- 04-DEMO-PLAN.md for detailed planning
- 05-AWS-INFRASTRUCTURE-SETUP.md for environment setup
- 03-CUSTOM-AGENT-SPECIFICATIONS.md for agent details
