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

**Purpose:** Refactor application code from AWS SDKs to Azure SDKs

**MCP Server Integration:**
- GitHub MCP Server
- URL: https://github.com/github/github-mcp-server

**SDK Replacements:**

**Node.js:**
- `@aws-sdk/client-s3` → `@azure/storage-blob`
- `@aws-sdk/client-eventbridge` → `@azure/eventgrid`
- `@aws-sdk/client-dynamodb` → `@azure/cosmos`
- `@aws-sdk/client-lambda` → HTTP calls to Azure Functions

**Python:**
- `boto3.client('s3')` → `azure.storage.blob.BlobServiceClient`
- `boto3.client('events')` → `azure.eventgrid.EventGridPublisherClient`
- `boto3.client('dynamodb')` → `azure.cosmos.CosmosClient`

**Authentication Updates:**
- Remove: AWS IAM credentials, access keys, secret keys
- Add: `DefaultAzureCredential` from `@azure/identity`
- Implement: Managed Identity for all service-to-service auth

**Environment Variable Changes:**
```bash
# Remove
AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
S3_BUCKET_NAME, DYNAMODB_TABLE_NAME

# Add
AZURE_STORAGE_ACCOUNT_NAME, AZURE_STORAGE_CONTAINER_NAME
AZURE_EVENT_GRID_ENDPOINT, AZURE_COSMOS_ENDPOINT
```

**Capabilities:**
- Scans repository for AWS SDK usage
- Replaces SDK imports and method calls
- Updates authentication mechanisms
- Maintains 100% functional parity
- Preserves all business logic
- Updates package dependencies
- Updates tests and mocks
- Creates detailed pull requests

**Quality Checklist:**
- All AWS SDK imports removed
- All Azure SDK imports added
- DefaultAzureCredential used
- No hardcoded credentials
- Environment variables updated
- All tests pass
- Code coverage maintained
- Error handling equivalent

**Custom Instructions:** `.github/instructions/code-refactoring.instructions.md`
- Business logic preservation requirements
- Error handling equivalence mapping
- Testing requirements (unit and integration)
- Pull request template and format

**Invocation:**
```
@code-refactor Refactor the order-processor Lambda function to use Azure Functions and Azure SDKs
```

---

### Agent 4: IaC Transformation Agent

**File Location:** `.github/agents/iac-transformation.agent.md`

**Purpose:** Convert CloudFormation to Bicep and update CI/CD pipelines

**MCP Server Integration:**
- Azure MCP Server: https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview
- Buildkite MCP Server: https://buildkite.com/docs/apis/mcp-server

**Capabilities:**
- Converts CloudFormation YAML/JSON to Bicep
- Creates modular Bicep structure (not monolithic)
- Updates Buildkite pipelines for Azure deployment
- Configures Azure service principal authentication
- Implements deployment validation (what-if checks)
- Adds rollback procedures

**CloudFormation to Bicep Patterns:**
```yaml
# CloudFormation
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${EnvironmentName}-bucket'
```

Converts to:

```bicep
// Bicep
@description('The environment name')
param environmentName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${environmentName}storage'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}
```

**Buildkite Pipeline Updates:**
```yaml
# BEFORE (AWS)
steps:
  - label: "Deploy to AWS"
    commands:
      - aws cloudformation deploy \
          --template-file template.yaml \
          --stack-name my-stack

# AFTER (Azure)
steps:
  - label: "Deploy to Azure"
    commands:
      - az deployment group what-if \
          --template-file main.bicep \
          --resource-group my-rg
      - az deployment group create \
          --template-file main.bicep \
          --resource-group my-rg
```

**Outputs:**
- Converted Bicep templates
- Updated Buildkite pipeline.yml
- Deployment validation scripts
- Rollback procedures

**Invocation:**
```
@iac-transformation Convert all CloudFormation templates to Bicep and update the Buildkite pipeline
```

---

### Agent 5: Deployment Validation Agent

**File Location:** `.github/agents/deployment-validation.agent.md`

**Purpose:** Validate deployments and ensure migration success

**MCP Server Integration:**
- Azure MCP Server

**Validation Steps:**

**Pre-Deployment:**
- Run `az bicep build` to validate syntax
- Check Azure Policy compliance
- Estimate costs using what-if
- Verify service limits and quotas

**Post-Deployment:**
- Confirm all resources deployed successfully
- Test application endpoints (smoke tests)
- Verify Managed Identity permissions
- Validate Key Vault access
- Check network connectivity (private endpoints)
- Confirm monitoring and alerting configured

**Security Validation:**
- No public endpoints (except load balancers)
- Private endpoints for PaaS services
- Diagnostic settings enabled
- All resources properly tagged
- RBAC follows least privilege

**Performance Validation:**
- API response times comparable to AWS
- Database query performance
- Storage access latency
- Function cold start times

**Outputs:**
- Validation report with pass/fail for each check
- Security compliance scorecard
- Performance comparison (AWS vs Azure)
- Cost validation (estimate vs actual)

**Invocation:**
```
@deployment-validation Validate the Azure deployment and run all compliance checks
```

---

## AWS Demo Reference Architecture

### Overview

Complex, production-like AWS environment for demonstration:

**Components:**
1. **EKS Cluster** - 3 microservices (Order API, Payment Service, Inventory Service)
2. **Lambda Functions** - 3 functions (Order Validator, Email Notifier, Inventory Sync)
3. **RDS PostgreSQL** - Shared database
4. **S3 Buckets** - 3 buckets (invoices, images, backups)
5. **EventBridge** - Event-driven communication
6. **CloudFormation** - Infrastructure as Code
7. **Buildkite** - CI/CD pipeline

### CloudFormation Templates

**Template 1: VPC and Networking**
- VPC with CIDR 10.0.0.0/16
- 2 public subnets, 2 private subnets across 2 AZs
- Internet Gateway and NAT Gateway
- Route tables and subnet associations
- Security groups for EKS and RDS
- DB subnet group

**Template 2: EKS Cluster**
- EKS cluster version 1.28
- Managed node groups (t3.medium, 2-5 nodes)
- Cluster IAM role
- Node group IAM role
- VPC CNI and CoreDNS add-ons

**Template 3: RDS Database**
- PostgreSQL 15.4
- db.t3.medium instance
- Multi-AZ deployment
- 100 GB storage with auto-scaling
- 7-day backup retention
- Encryption at rest
- Private subnet deployment

**Template 4: S3 Buckets**
- order-invoices bucket (versioning enabled)
- product-images bucket (public read)
- backup-archives bucket (lifecycle policy to Glacier)
- Server-side encryption
- Bucket policies

**Template 5: Lambda Functions**
- Order Validator (Node.js 18, 512 MB, API Gateway trigger)
- Email Notifier (Python 3.11, 256 MB, EventBridge trigger)
- Inventory Sync (Go 1.21, 256 MB, scheduled trigger)
- IAM execution roles
- Environment variables
- VPC configuration for RDS access

### Deployment Commands

```bash
# 1. Deploy VPC (5 minutes)
aws cloudformation deploy \
  --template-file aws-infrastructure/vpc-network.yaml \
  --stack-name demo-network \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

# 2. Deploy RDS (15 minutes)
aws cloudformation deploy \
  --template-file aws-infrastructure/rds-database.yaml \
  --stack-name demo-database \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides \
    VPCStackName=demo-network \
    DBUsername=postgres \
    DBPassword=SecurePassword123!

# 3. Deploy S3 Buckets (2 minutes)
aws cloudformation deploy \
  --template-file aws-infrastructure/s3-buckets.yaml \
  --stack-name demo-storage \
  --region us-east-1

# 4. Deploy Lambda Functions (5 minutes)
aws cloudformation deploy \
  --template-file aws-infrastructure/lambda-functions.yaml \
  --stack-name demo-lambda \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides \
    VPCStackName=demo-network \
    DBStackName=demo-database

# 5. Deploy EKS Cluster (20 minutes)
aws cloudformation deploy \
  --template-file aws-infrastructure/eks-cluster.yaml \
  --stack-name demo-eks \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides VPCStackName=demo-network

# Total deployment time: ~45 minutes
```

---

## 30-Minute Demonstration Plan

### Pre-Demo Setup (Complete 24 hours before)

1. Deploy AWS reference architecture (45 minutes)
2. Set up GitHub repository with custom agents (15 minutes)
3. Configure MCP servers (15 minutes)
4. Test all agents once (30 minutes)
5. Prepare Azure subscription (5 minutes)

**Total Pre-Work:** ~2 hours

### Demonstration Flow

**Minutes 0-5: Environment Overview**
- Show AWS Console with deployed resources
- Walk through architecture diagram
- Explain complexity (EKS + Lambda + RDS + S3 + Events)
- Show CloudFormation templates
- Show Buildkite pipeline

**Minutes 5-10: Discovery Phase**
- Open VS Code with repository
- Invoke: `@aws-discovery Discover all resources`
- Show agent scanning AWS account
- Review generated aws-inventory.json
- Show dependency-matrix.csv
- Display architecture-diagram.mmd rendering
- Review migration-assessment.md (complexity ratings)

**Minutes 10-18: Design Phase**
- Invoke: `@azure-architect Design Azure architecture`
- Show agent accessing Microsoft Learn for service mappings
- Review generated Bicep templates (main.bicep, modules)
- Show parameter files (dev/staging/prod)
- Display architecture-diagram-azure.mmd
- Review cost-comparison.md (AWS $850/mo → Azure $620/mo = $230 savings)

**Minutes 18-23: Refactor Phase**
- Invoke: `@code-refactor Refactor order-validator Lambda`
- Show agent scanning code for AWS SDKs
- Watch automated replacement (aws-sdk → @azure/storage-blob)
- Review authentication update (IAM → DefaultAzureCredential)
- Show generated pull request with before/after code
- Display test results (all passing)

**Minutes 23-27: Deploy Phase**
- Invoke: `@iac-transformation Convert CloudFormation to Bicep`
- Show CloudFormation → Bicep conversion
- Review updated Buildkite pipeline
- Invoke: `@deployment-validation Validate deployment`
- Show validation report (all checks passing)

**Minutes 27-30: Results and Q&A**
- Show deployed Azure resources in Azure Portal
- Compare side-by-side (AWS vs Azure)
- Review total time saved: 16 weeks → 8 weeks
- Review cost saved: $400K → $87K
- Open for questions

---

## Business Case Summary

### Traditional Approach

**Timeline:** 16-20 weeks  
**Cost:** $200,000 - $400,000  
**Team:** 5-8 external consultants  
**Risk:** Knowledge loss, inconsistent quality

### AI-Assisted Approach

**Timeline:** 8-10 weeks (60% faster)  
**Cost:** $50,000 - $100,000 (75% savings)  
**Team:** 2-3 internal engineers  
**Benefit:** Knowledge retained, reusable agents

### ROI Calculation

**First Migration:**
- Investment: $87,400
- Traditional Cost: $400,000
- Savings: $312,600 (78% reduction)
- Time Saved: 10 weeks

**Subsequent Migrations:**
- Investment: $50,000 (agents already exist)
- Traditional Cost: $300,000
- Savings: $250,000 (83% reduction)
- Time Saved: 12 weeks (faster with experience)

**3-Year Projection (3 migrations):**
- Total Investment: $187,400
- Traditional Cost: $1,150,000
- Total Savings: $962,600 (84% reduction)

---

## Next Steps

### Week 1: Proof of Concept
- Select 1-2 non-critical services
- Execute full migration with agents
- Validate time and cost estimates
- Document lessons learned

### Week 2-3: Team Training
- Train engineers on GitHub Copilot and custom agents
- Refine agent prompts based on POC
- Create internal documentation
- Set up Azure environments

### Week 4-10: Full Migration
- Migrate remaining services systematically
- Batch similar services
- Maintain AWS in parallel during transition
- Gradual traffic cutover

### Post-Migration: Optimization
- Fine-tune agents based on experience
- Build library of reusable patterns
- Measure actual ROI
- Plan future migrations

---

## Technical Requirements

### Tooling
- GitHub Copilot Business ($19/user/month)
- Azure OpenAI Service (~$50/month)
- Azure subscription
- MCP servers (can run locally, minimal cost)

### Team
- 2 engineers (80% allocated, 8-10 weeks)
- 1 architect (20% allocated for guidance)
- 1 project manager (50% allocated for coordination)

### Skills
- Familiarity with AWS and Azure (agents provide guidance)
- Infrastructure as Code experience (CloudFormation/Bicep)
- Application development (Node.js, Python, or Go)
- CI/CD pipeline knowledge (Buildkite or similar)

---

## Success Criteria

**Migration completed when:**
- All AWS resources migrated to Azure
- All application code refactored
- All tests passing in Azure
- CI/CD pipelines updated and working
- Monitoring and alerting configured
- Security validation passed
- Performance equivalent to AWS
- AWS resources decommissioned

**Success metrics:**
- Timeline: 8-10 weeks actual vs 8-10 weeks estimate
- Cost: $50K-$100K actual vs estimate
- Quality: Zero critical defects in first 30 days
- Performance: Response times within 10% of AWS baseline
- Security: Pass all Azure Security Center checks

---

## Document Status

**Completed:**
- Master index and navigation
- Executive presentation (45 minutes)
- Agent specifications summary

**Available for Creation:**
- Detailed agent specification files (all 5 agents)
- Complete CloudFormation templates (all 5 stacks)
- Demo execution scripts
- Service mapping reference guide
- MCP server setup guide

**Ready For:**
- Executive review and approval
- Technical team review
- Proof-of-concept execution
- Live demonstration

---

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
