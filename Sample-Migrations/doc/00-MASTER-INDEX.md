# AWS to Azure AI-Assisted Migration — Document Index

**Document Version:** 2.0  
**Date:** April 2026  
**Status:** ✅ Migration Complete  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Document Index

### Executive Documents

**01-EXECUTIVE-PRESENTATION.md**  
Business case, ROI, and completed migration outcomes. Includes real cost comparison data (AWS $2.92/month → Azure $0.54/month at demo scale).

**02-TECHNICAL-DEEP-DIVE.md**  
Technical architecture of the five GitHub Copilot agents, MCP server integration, and the complete migration approach.

### Agent Specifications

**03-CUSTOM-AGENT-SPECIFICATIONS.md**  
Complete specifications for all five custom GitHub Copilot agents including prompts, instructions, MCP tool bindings, and lessons learned from production use.

### Demonstration Materials

**04-DEMO-PLAN.md**  
30-minute demonstration plan showing the complete migration workflow using the five agents against the real migrated application.

**05-AWS-INFRASTRUCTURE-SETUP.md**  
Reference documentation for the original AWS environment (Lambda + API Gateway + S3 serverless stack).

**06-DEMO-EXECUTION-GUIDE.md**  
Step-by-step execution guide with exact agent invocations and expected outputs.

### Reference Materials

**07-SERVICE-MAPPING-REFERENCE.md**  
Detailed AWS to Azure service mapping for the Image Upload Service, including configuration differences, gotchas, and cost data.

**08-MCP-SERVER-INTEGRATION.md**  
MCP server configuration and usage guide for all servers used in this migration.

---

## Quick Navigation

**For Executives:** Start with Document 01  
**For Architects:** Read Documents 01, 02, and 07  
**For Technical Leads:** Read Documents 02, 03, and 08  
**For Demo Setup:** Follow Documents 04 and 06 in sequence  
**For Agent Reuse:** Start with Document 03, then `.github/QUICK-START-GUIDE.md`

---

## Document Purpose Summary

**Document 01:** Business case, completed migration outcomes, and real ROI data  
**Document 02:** Technical architecture — agents, MCP servers, Python v2 model  
**Document 03:** Full agent definitions with production-validated gotchas  
**Document 04:** 30-minute demonstration flow  
**Document 05:** Original AWS environment reference  
**Document 06:** Agent invocation scripts with expected outputs  
**Document 07:** Service-by-service AWS → Azure mapping with real config data  
**Document 08:** MCP server setup and configuration guide

---

## Completed Migration Deliverables

| Artifact | Location | Description |
|----------|----------|-------------|
| AWS inventory | `outputs/aws-migration-artifacts/aws-inventory.json` | Full resource inventory (18 active + 8 remnant) |
| Architecture diagrams | `outputs/aws-migration-artifacts/architecture-diagram.mmd` | AWS Mermaid diagram |
| Migration assessment | `outputs/aws-migration-artifacts/migration-assessment.md` | Complexity: LOW, Effort: 2–3 weeks |
| CloudFormation template | `outputs/aws-migration-artifacts/cloudformation-template.yaml` | Captured source IaC |
| Azure architecture | `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Azure Mermaid diagram |
| Service mapping | `outputs/azure-architecture-output/service-mapping.md` | Full AWS → Azure mapping |
| Cost comparison | `outputs/azure-architecture-output/cost-comparison.md` | 81% reduction at demo scale |
| Refactored functions | `outputs/azure-functions/function_app.py` | Python v2 Azure Functions (4 endpoints) |
| Bicep templates | `outputs/bicep-templates/` | Deployed to australiaeast ✅ |
| Static web app | `outputs/static-web-app/` | Deployed to Azure Static Web Apps ✅ |

---

## Technology Stack

**AI Orchestration:**
- GitHub Copilot custom agents (VS Code agent mode)
- Repository-specific instruction files (`.github/instructions/`)
- No CLI or PowerShell inside agent workflows — MCP only

**MCP Servers Used:**
- AWS Cloud Control API MCP — read-only AWS discovery
- AWS Knowledge MCP — AWS service documentation
- Microsoft Learn MCP — Azure docs and AVM modules
- Azure MCP — Azure resource information
- Mermaid Chart MCP — diagram generation and validation

**Migration Stack:**
- 4 AWS Lambda (Python 3.11) → 4 Azure Functions (Python 3.11, v2 model)
- S3 presigned URLs → Azure Blob SAS tokens (user-delegation key)
- IAM roles + access keys → System-Assigned Managed Identity + RBAC
- S3 static website → Azure Static Web Apps (Free tier)
- CloudFormation → Bicep (modular, subscription-scoped, AVM-aligned)

---

## Getting Started with Agent Reuse

1. Clone this repository into your migration project
2. Copy `.github/agents/` and `.github/instructions/` to the target repo
3. Configure MCP servers (see Document 08)
4. Open VS Code with GitHub Copilot, invoke agents in order (see Document 04)
5. Review outputs in `outputs/` folder structure

---

**Total Package:** 8 documents + 10 agent/instruction files + complete migration outputs
