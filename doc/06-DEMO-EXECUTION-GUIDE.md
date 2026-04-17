# Demo Execution Guide

**Document Version:** 1.0  
**Date:** December 2024  
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
# Show AWS resources
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

# Show EKS cluster
aws eks list-clusters
kubectl get nodes

# Show Lambda functions
aws lambda list-functions --query 'Functions[].FunctionName'

# Show RDS
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'

# Show S3
aws s3 ls
```

### What to Say

"This is our production-like AWS environment with EKS, Lambda, RDS, S3, and EventBridge. Traditionally, migrating this takes 4-5 weeks. Let's do it in 30 minutes with AI agents."

---

## Phase 2: Discovery (Minutes 5-10)

### Agent Invocation

```
@aws-discovery Discover all resources in the AWS account and create a complete inventory with dependency analysis
```

### Files to Review

1. `migration-artifacts/aws-inventory.json` - Show resource count
2. `migration-artifacts/dependency-matrix.csv` - Show relationships
3. `migration-artifacts/architecture-diagram.mmd` - Render diagram
4. `migration-artifacts/migration-assessment.md` - Show complexity ratings

### What to Say

"Complete discovery in 2 minutes. Every resource inventoried, dependencies mapped, complexity assessed. This normally takes 3 weeks of manual work."

---

## Phase 3: Design (Minutes 10-18)

### Agent Invocation

```
@azure-architect Design the Azure architecture based on the AWS discovery and generate all Bicep templates with cost comparison
```

### Files to Review

1. `azure-infrastructure/main.bicep` - Show modular structure
2. `azure-infrastructure/modules/database.bicep` - Show PostgreSQL configuration
3. `migration-artifacts/cost-comparison.md` - Highlight $230/month savings
4. `migration-artifacts/architecture-diagram-azure.mmd` - Show Azure design

### What to Say

"Azure architecture designed in 3 minutes. Production-ready Bicep templates, best practices applied automatically, 27% cost savings. Normally takes 5 weeks."

---

## Phase 4: Refactor (Minutes 18-23)

### Show Original Code First

```bash
# Open in VS Code
code lambda-functions/order-validator/index.js
```

### Agent Invocation

```
@code-refactor Refactor the order-validator Lambda function to use Azure Functions and Azure SDKs
```

### Files to Review

1. Updated `index.js` - Show Azure SDK replacements
2. Updated `package.json` - Show new dependencies
3. GitHub Pull Request - Show automated PR

### What to Say

"Code refactored in 2 minutes. AWS SDKs replaced with Azure, authentication updated to Managed Identity, all tests passing. Normally takes 2 weeks per service."

---

## Phase 5: Deploy & Validate (Minutes 23-27)

### Agent Invocations

```
@iac-transformation Convert all CloudFormation templates to Bicep and update the Buildkite pipeline for Azure deployment
```

```
@deployment-validation Validate the Bicep templates and run security compliance checks
```

### Files to Review

1. Updated `.buildkite/pipeline.yml` - Show Azure deployment steps
2. Validation report - Show all checks passing
3. Cost estimate - Confirm $620/month

### What to Say

"Infrastructure transformed in 2 minutes. CloudFormation to Bicep, pipeline updated, security validated. Normally takes 2 weeks. Everything ready for production deployment."

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
