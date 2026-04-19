# Executive Presentation: AWS to Azure AI-Assisted Migration

**Status:** ✅ Migration Completed  
**Date:** April 2026  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Agenda

1. Executive Summary (5 min)
2. The Migration Challenge (5 min)
3. AI-Assisted Solution Overview (10 min)
4. Technical Architecture (10 min)
5. Results and Business Case (10 min)
6. Demonstration Walkthrough (5 min)

---

## 1. Executive Summary

### What Was Done

A complete AWS to Azure migration of a production serverless image-upload application, executed using **seven** custom GitHub Copilot agents integrated with Model Context Protocol (MCP) servers. The migration covered four phases, fully automated by AI — and then orchestrated end-to-end by a single **Migration Project Manager Agent** that sequenced all phases, ran independent work in parallel, and tracked every task in a live plan file:

- **Discovery:** Automated AWS resource inventory and dependency mapping
- **Design:** AI-generated Azure architecture and Infrastructure as Code
- **Refactor:** Automated code transformation from AWS SDKs to Azure SDKs  
- **Deploy:** Automated Bicep generation and validated deployment to Azure

### The Results

**Infrastructure:** 4 Lambda functions + API Gateway + S3 migrated to Azure Functions + Blob Storage + Static Web Apps  
**Cost reduction:** AWS $2.92/month → Azure $0.54/month at demo scale (**81% reduction**)  
**Deployment:** ✅ Live in Azure australiaeast (resource group `img-upload-dev-rg`)  
**Code:** Zero AWS SDK references remain — all replaced with Azure SDKs and Managed Identity  
**IaC:** CloudFormation converted to modular Bicep using Azure Verified Modules (AVM)  
**CI/CD:** GitHub Actions pipeline with OIDC Workload Identity Federation (no long-lived credentials)  
**Orchestration:** Full pipeline coordinated by `@migration-project-manager` — one prompt, end-to-end

---

## 2. The Migration Challenge

### Traditional Migration Approach

**Phase 1: Discovery (3 weeks)**
- Manual inventory of AWS resources
- Spreadsheet-based dependency mapping
- Interview-based architecture documentation
- Error-prone and time-intensive

**Phase 2: Architecture Design (5 weeks)**
- Manual research of Azure equivalents
- Custom architecture design for each service
- Infrastructure as Code creation from scratch
- Requires deep expertise in both platforms

**Phase 3: Code Refactoring (6 weeks)**
- Line-by-line code review and updates
- Manual SDK replacement
- Authentication pattern changes
- High risk of introducing bugs

**Phase 4: Deployment (6 weeks)**
- Manual infrastructure provisioning
- CI/CD pipeline reconfiguration
- Testing and validation
- Rollback planning

**Total Timeline:** 16-20 weeks  
**Total Cost:** $200,000-$400,000 in consulting fees  
**Risk Factors:**
- Variable quality depending on consultant expertise
- Knowledge loss when consultants leave
- Inconsistent application of best practices
- Limited documentation for future reference

### Why Traditional Approaches Fail

1. **Manual Process:** Human error in discovery and translation
2. **Knowledge Silos:** Expertise locked in consultant heads
3. **Inconsistency:** Different approaches for similar problems
4. **No Reusability:** Work doesn't transfer to next migration
5. **Expensive:** High hourly rates for specialized skills

---

## 3. AI-Assisted Solution Overview

### Core Concept

Instead of manual migration, we use specialized AI agents that:
- Understand both AWS and Azure platforms
- Access real-time documentation via MCP servers
- Execute repeatable, consistent workflows
- Generate production-ready code and infrastructure
- Capture knowledge in reusable patterns

### Migration Pipeline — Orchestrated by the PM Agent

The Migration Project Manager Agent (`@migration-project-manager`) is the top-level orchestrator. A single prompt triggers the full pipeline below:

```
@migration-project-manager
            │
            ▼
PHASE 1: DISCOVERY
[AWS Cloud Control API MCP Server]
          │
          ▼
[Agent 1: AWS Discovery]
          │
          +---> Scans all AWS regions and resource types
          +---> Maps dependencies between services
          +---> Generates architecture diagram + migration assessment
          │
          ▼
[Output: aws-inventory.json + dependency-matrix.csv + migration-assessment.md]
          │
          ▼
PHASE 2: ARCHITECTURE DESIGN
[Microsoft Learn MCP Server + Azure MCP Server]
          │
          ▼
[Agent 2: Azure Architect]
          │
          +---> Maps every AWS service to Azure equivalent
          +---> Designs Well-Architected Azure topology
          +---> Generates Bicep IaC + cost comparison
          │
          ▼
[Output: architecture-diagram-azure.mmd + service-mapping.md + cost-comparison.md]
          │
          ▼
PHASE 3: PARALLEL EXECUTION (3a + 3b + 3c run simultaneously)
  ┌───────────────┬───────────────────┬──────────────────────┐
  │               │                   │                      │
  ▼               ▼                   ▼
[Agent 4: IaC]  [Agent 3: Refactor] [Agent 6: Pipeline Builder]
  │               │                   │
  +-> Bicep       +-> AWS SDK         +-> GitHub Actions
  │   modules     │   → Azure SDK     │   OIDC auth
  │               │                   │   Multi-stage
  ▼               ▼                   ▼
[Output: bicep-templates/] [outputs/azure-functions/] [.github/workflows/]
  │               │                   │
  └───────────────┴───────────────────┘
          │  (all 3 must pass artifact check)
          ▼
PHASE 4: VALIDATION
[Azure MCP Server]
          │
          ▼
[Agent 5: Deployment Validation]
          │
          +---> Bicep syntax + security compliance
          +---> Smoke tests on all deployed endpoints
          +---> Managed Identity + Key Vault verification
          │
          ▼
[Output: validation-report.md + outputs/migration-task-plan.md updated ✅]
```

### Technology Stack

**GitHub Copilot Custom Agents**
- Repository-specific AI agents defined in `.github/agents/*.agent.md`
- Invoked via `@agent-name` in GitHub Copilot Chat
- Context-aware of entire repository
- The PM Agent (`@migration-project-manager`) orchestrates all specialist agents end-to-end
- Modular design: any specialist agent can be independently updated without touching the others

**Model Context Protocol (MCP) Servers**
- Standardised way for agents to access external systems
- Real-time access to AWS/Azure APIs
- Live documentation from Microsoft Learn
- Integration with GitHub and CI/CD tools

**Five Specialized Agents + One Pipeline Builder + One Orchestrator**
1. AWS Discovery Agent — Resource inventory and dependency analysis
2. Azure Architect Agent — Architecture design and Bicep generation
3. Code Refactor Agent — SDK replacement and authentication updates
4. IaC Transformation Agent — CloudFormation to Bicep conversion
5. Deployment Validation Agent — Testing and compliance verification
6. Pipeline Builder Agent — GitHub Actions CI/CD with OIDC auth, multi-stage environments
7. **Migration Project Manager Agent — Orchestrates all six agents end-to-end. The ultimate automation.**

---

## 4. Technical Architecture

### GitHub Copilot Custom Agents

**What Are They?**

Custom agents are repository-specific AI assistants that:
- Are defined in markdown files (`.github/agents/*.agent.md`)
- Have access to repository code and context
- Can use external tools via MCP servers
- Follow custom instructions for specialized tasks
- Maintain conversation history during workflows

**Example Agent Structure:**

```
.github/
├── agents/
│   ├── aws-discovery.agent.md
│   ├── azure-architect.agent.md
│   ├── code-refactor.agent.md
│   ├── iac-transformation.agent.md
│   ├── deployment-validation.agent.md
│   ├── pipeline-builder-agent.agent.md
│   └── migration-project-manager.agent.md  ← orchestrates all others
├── instructions/
│   ├── discovery.instructions.md
│   ├── azure-architecture.instructions.md
│   ├── code-refactoring.instructions.md
│   └── iac-transformation.instructions.md
└── copilot-instructions.md
```

### MCP Server Integration

**AWS Cloud Control API MCP Server**
- Purpose: Discovery phase
- Capabilities: Query all AWS resources via unified API
- Benefits: Single interface for all AWS services
- Documentation: https://awslabs.github.io/mcp/servers/ccapi-mcp-server

**Microsoft Learn MCP Server**
- Purpose: Design phase
- Capabilities: Access Azure documentation and migration guides
- Benefits: Up-to-date service mappings and best practices
- Documentation: https://learn.microsoft.com/en-us/training/support/mcp

**AWS Knowledge MCP Server**
- Purpose: Discovery phase
- Capabilities: Search AWS documentation, retrieve service schemas
- Benefits: Confirms resource type mappings for Cloud Control API
- Documentation: https://awslabs.github.io/mcp/servers/aws-documentation-mcp-server/

**Azure MCP Server**
- Purpose: Architecture design + validation
- Capabilities: Query Azure resources, validate region availability
- Benefits: Confirms deployed resource status during validation
- Documentation: https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview

**Mermaid Chart MCP Server**
- Purpose: Diagram validation
- Capabilities: Validate Mermaid diagram syntax
- Benefits: Ensures generated architecture diagrams render correctly
- Documentation: https://www.mermaidchart.com/mcp

### Agent Workflow Example

**Scenario:** Migrate Lambda handlers to Azure Functions (actual migration)

```
1. Engineer invokes agent:
   "@code-refactor Refactor all Lambda handlers to Azure Functions Python v2 model"

2. Agent workflow:
   a. Reads app-code/lambda-functions/ — upload, list, view, delete handlers
   b. Identifies: boto3.client('s3'), s3.generate_presigned_url()
   c. Replaces with: BlobServiceClient, generate_blob_sas() + get_user_delegation_key()
   d. Updates authentication: IAM execution role → DefaultAzureCredential()
   e. Rewrites handlers to Azure Functions Python v2 @app.route() decorators
   f. Updates requirements.txt: boto3 → azure-storage-blob, azure-identity
   g. Updates local.settings.json with BLOB_CONTAINER_NAME (avoiding reserved CONTAINER_NAME)

3. Output:
   - outputs/azure-functions/function_app.py — all 4 endpoints in single file
   - outputs/azure-functions/requirements.txt — Azure SDK dependencies
   - outputs/static-web-app/app.html — frontend updated to call Azure Function URLs
```

### Service Migration Mappings

**Mappings used in this migration:**

**Compute:**
- AWS Lambda (4 functions) → Azure Functions Python v2, Consumption plan
- AWS API Gateway → Azure Functions built-in HTTP triggers

**Storage:**
- AWS S3 (images bucket) → Azure Blob Storage
- AWS S3 (static site) → Azure Static Web Apps

**Security:**
- AWS IAM Lambda execution role → Azure Managed Identity
- AWS Secrets Manager → Azure Key Vault
- AWS KMS → Azure Key Vault keys

**Monitoring:**
- AWS CloudWatch Logs → Azure Application Insights + Log Analytics

**Infrastructure as Code:**
- AWS CloudFormation → Azure Bicep (modular, subscription-scoped)

**General mappings (for reference — used in larger migrations):**
- AWS EKS → Azure Kubernetes Service (AKS)
- AWS RDS PostgreSQL → Azure Database for PostgreSQL Flexible Server
- AWS DynamoDB → Azure Cosmos DB
- AWS EventBridge → Azure Event Grid
- AWS SQS → Azure Service Bus Queues
- AWS SNS → Azure Service Bus Topics

---

## 5. ROI and Business Case

### Cost Comparison

**Traditional Consulting Approach:**

```
Discovery Phase:        $50,000  (3 weeks × 5 consultants × $200/hr)
Architecture Design:    $80,000  (5 weeks × 4 consultants × $200/hr)
Code Refactoring:      $120,000  (6 weeks × 5 consultants × $200/hr)
Deployment:             $96,000  (6 weeks × 4 consultants × $200/hr)
Project Management:     $54,000  (18 weeks × 1 PM × $150/hr)
----------------------------------------
Total Cost:            $400,000
Total Timeline:        16-20 weeks
```

**AI-Assisted Approach:**

```
Setup Phase:            $5,000   (GitHub Copilot licenses, MCP setup)
Discovery Phase:        $8,000   (1 week × 2 engineers × $200/hr)
Architecture Design:   $12,000   (1.5 weeks × 2 engineers × $200/hr)
Code Refactoring:      $20,000   (2.5 weeks × 2 engineers × $200/hr)
Deployment:            $16,000   (2 weeks × 2 engineers × $200/hr)
Testing & Validation:  $12,000   (1.5 weeks × 2 engineers × $200/hr)
Project Management:     $4,800   (3 weeks × 1 PM × $80/hr — PM Agent handles coordination)
----------------------------------------
Total Cost:            $77,800
Total Timeline:        8-10 weeks
```

> **Note:** PM Agent reduces human project management effort by ~70% — sequencing, artifact verification, task tracking, and phase coordination are fully automated. Human PM oversight is still recommended for stakeholder communication and blockers.

**Savings:**
- **Cost Reduction:** $322,200 (80% savings vs traditional approach)
- **Time Reduction:** 8-10 weeks faster (60% time savings)
- **Added Value:** Reusable agents for future migrations, automated orchestration

### Time Breakdown Comparison

```
Phase                  Traditional    AI-Assisted    Savings
================================================================
Discovery              3 weeks        4 days         80%
Architecture Design    5 weeks        1.5 weeks      70%
Code Refactoring       6 weeks        2.5 weeks      58%
Deployment             6 weeks        2 weeks        67%
----------------------------------------------------------------
TOTAL                  20 weeks       8 weeks        60%
```

### Qualitative Benefits

**Knowledge Retention:**
- All migration patterns captured in reusable agents
- No knowledge loss when team members leave
- Documentation auto-generated during migration
- Future migrations leverage existing agents

**Quality Improvement:**
- Consistent application of Azure best practices
- Automated security validation
- Standardized Infrastructure as Code
- Comprehensive test coverage maintained

**Risk Reduction:**
- Repeatable process reduces human error
- Automated validation catches issues early
- Clear audit trail of all changes
- Easy rollback procedures

**Scalability:**
- First migration takes 8 weeks (setup + learning)
- Subsequent migrations take 4-5 weeks (PM Agent handles sequencing automatically)
- Parallel migration of multiple services possible — PM Agent tracks each independently
- Specialist agents improve with each use; PM Agent benefits automatically
- Modular architecture means updating one agent standard doesn't affect others

### Total Cost of Ownership (3-Year View)

**Scenario:** Migrate 10 services from AWS to Azure

**Traditional Approach:**
```
Initial Migration:     $400,000 × 1 = $400,000
Future Migrations:     $300,000 × 2 = $600,000
Ongoing Consulting:    $50,000 × 3  = $150,000
------------------------------------------------
Total 3-Year Cost:                  $1,150,000
```

**AI-Assisted Approach:**
```
Initial Migration:     $87,400 × 1  = $87,400
Future Migrations:     $50,000 × 2  = $100,000
Agent Maintenance:     $10,000 × 3  = $30,000
------------------------------------------------
Total 3-Year Cost:                  $217,400
```

**3-Year Savings:** $932,600 (81% reduction)

---

## 6. Demonstration Preview and Next Steps

### 30-Minute Live Demonstration

**What We'll Show:**

**Minute 0-5: Environment Overview**
- Real AWS serverless application (account 535002891143, ap-southeast-2)
  - 4 Lambda functions (upload, list, view, delete)
  - API Gateway REST endpoint
  - 2 S3 buckets (images + artifacts)
  - IAM execution roles / CloudFormation stack / 8 CloudWatch log groups
- Seven agent files in `.github/agents/` — the cast is introduced, PM Agent teased

**Minute 5-10: Discovery Phase**
- Walk through `outputs/aws-migration-artifacts/` — produced by `@aws-discovery`
- 26 resources discovered, dependency matrix, architecture diagram, complexity assessment

**Minute 10-18: Architecture Design + IaC + Code Refactoring**
- Walk through Azure architecture diagram, service mapping, and cost comparison
- Show Bicep templates — 6 modules, subscription-scoped, AVM-compliant
- Side-by-side: boto3 Lambda → azure-storage-blob Azure Function (Python v2)
- Show requirements.txt change, no more AWS SDK dependencies

**Minute 18-23: Deployment and Validation**
- Show `az deployment sub create` result and live Azure Portal
- Show validation checklist: HTTPS, Managed Identity, Key Vault, all endpoints 200/40x
- `img-upload-dev-rg` resource group running in australiaeast

**Minute 23-27: The Migration Project Manager Agent ⭐**
- Open `.github/agents/migration-project-manager.agent.md` — show the pipeline diagram
- Open `outputs/migration-task-plan.md` — live task plan maintained by the PM Agent
- Show the one-line invocation: `@migration-project-manager Run the full AWS to Azure migration pipeline`
- Emphasise: this is not a script, it's an agent that coordinates other agents intelligently
- "Five specialist agents is a toolkit. The PM Agent is the automation."

**Minute 27-30: Results and Q&A**
- Azure Portal: all resources live
- 81% cost reduction, full audit trail, modular architecture
- Q&A: customisation, security, reusability, scaling to larger migrations

### Demonstration Outcomes

After 30 minutes, attendees will see:
1. Complete AWS infrastructure discovered and assessed (26 resources)
2. Azure architecture designed with Well-Architected Framework applied
3. All 4 Lambda functions refactored to Azure Functions Python v2
4. Infrastructure as Code converted from CloudFormation to 6 modular Bicep templates
5. GitHub Actions CI/CD pipeline with OIDC auth and multi-stage deployment
6. Azure environment deployed and validated (australiaeast) — confirmed live
7. 81% cost reduction confirmed ($2.92 → $0.54/month at demo scale)
8. **One prompt to the PM Agent runs the entire pipeline \u2014 end-to-end**

### Immediate Next Steps

**Week 1: Proof of Concept**
- Select 1-2 non-critical services for pilot
- Set up GitHub Copilot and MCP servers
- Execute end-to-end migration
- Validate time and cost estimates

**Week 2-3: Team Training**
- Train engineers on custom agents
- Document lessons learned
- Refine agent prompts
- Create internal runbooks

**Week 4-8: Scaled Migration**
- Migrate remaining services systematically
- Batch similar services together
- Maintain AWS environment in parallel
- Gradual traffic cutover

**Month 3+: Optimization**
- Fine-tune agents based on experience
- Build library of reusable patterns
- Measure ROI achievement
- Plan future migrations

### Decision Points

**Proceed if:**
- Proof of concept validates time/cost savings
- Team comfortable with GitHub Copilot
- Azure costs confirmed 20%+ lower than AWS
- No critical technical blockers identified

**Pause if:**
- Pilot reveals unexpected complexity
- Cost projections not materializing
- Team bandwidth insufficient
- Organizational readiness concerns

### Investment Required

**Tooling:**
- GitHub Copilot Business: $19/user/month
- Azure OpenAI Service: ~$50/month for GPT-4 usage
- MCP server hosting: Minimal (can run locally)

**Team:**
- 2 engineers (80% allocated for 8-10 weeks)
- 1 architect (20% allocated for review/guidance)
- 1 project manager (50% allocated for coordination)

**Total Investment:** ~$87,000 for first migration  
**Expected Savings:** ~$313,000 vs traditional approach  
**Net Benefit:** ~$226,000 first migration, improving with each subsequent migration

---

## Summary

### Key Takeaways

1. **AI-assisted migration reduces time by 60% and cost by 78%**
2. **Five specialized GitHub Copilot agents handle all migration phases**
3. **MCP servers provide real-time access to AWS, Azure, and tooling**
4. **Knowledge captured in reusable agents, not consultant heads**
5. **First migration pays for itself, subsequent migrations even faster**

### The Opportunity

- Proven technology (GitHub Copilot, MCP)
- Clear ROI (8-10 weeks vs 16-20 weeks, $87K vs $400K)
- Competitive advantage (faster time to market)
- Knowledge retention (reusable for future projects)

### Recommendation

**Proceed with proof-of-concept migration:**
- Select 1-2 services
- Budget 2-3 weeks
- Validate approach
- Scale based on results

---

## Questions and Discussion

**Common Questions:**

**Q: What if our AWS environment is more complex?**  
A: Agents handle complexity well - more resources just means longer discovery, but same automation benefits.

**Q: Can we customize the agents?**  
A: Yes, all agent prompts and instructions are in markdown files that you can modify.

**Q: What about ongoing maintenance?**  
A: Agents are reusable and improve over time. Team maintains and enhances them like any other code.

**Q: Do we need specialized Azure expertise?**  
A: Agents leverage Microsoft Learn MCP for up-to-date best practices, reducing expertise requirements.

**Q: What's the risk if this doesn't work?**  
A: Low risk - proof of concept is 2-3 weeks and $10-15K investment. Easy to pivot back to traditional if needed.

---

**Thank you. Ready for questions and discussion.**
