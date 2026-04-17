# Technical Deep Dive: AI-Assisted Migration Architecture

**Document Version:** 2.0  
**Date:** April 2026  
**Audience:** Technical Architects and Engineering Leads

---

## Table of Contents

1. GitHub Copilot Custom Agents Architecture
2. Model Context Protocol (MCP) Integration
3. Agent Workflow Patterns
4. Repository Structure and Configuration
5. Security and Authentication
6. Error Handling and Resilience
7. Performance and Scalability
8. Extension and Customization

---

## 1. GitHub Copilot Custom Agents Architecture

### What Are Custom Agents?

GitHub Copilot custom agents are repository-specific AI assistants defined in markdown files that:
- Live in `.github/agents/*.agent.md`
- Are invoked using `@agent-name` syntax in GitHub Copilot Chat
- Have access to repository context and file system
- Can call external tools via Model Context Protocol (MCP)
- Maintain conversation state during multi-step workflows
- Follow custom instructions defined in `.github/instructions/`

### Agent Definition Structure

**File Format:** YAML frontmatter + Markdown body

```markdown
---
name: agent-name
description: Short description of agent purpose
tools: ['read', 'edit', 'create_file', 'bash', 'search']
mcp-servers:
  - name: server-name
    url: https://example.com/mcp-server
    tools: ["*"]
---

# Agent Name

You are a [role description]...

## Your Capabilities

[Description of what the agent can do]

## Process

[Step-by-step workflow]

## Output Format

[Expected outputs]
```

### Built-in Tools

**File Operations:**
- `read` - Read files and directories
- `edit` - Modify existing files
- `create_file` - Create new files
- `search` - Search repository content

**Execution:**
- `bash` - Execute shell commands
- `python` - Run Python scripts
- `node` - Run Node.js scripts

### Custom Instructions

**Repository-wide:** `.github/copilot-instructions.md`
- Applies to all Copilot interactions in repository
- Sets coding standards, conventions, patterns

**Path-specific:** `.github/instructions/*.instructions.md`
- Applies when working in specific directories
- Can override or extend repository-wide instructions

**Agent-specific:** Referenced in agent definition
- Loaded when agent is invoked
- Provides context and constraints for agent behavior

---

## 2. Model Context Protocol (MCP) Integration

### MCP Architecture

```
┌─────────────────────────────────────────┐
│   GitHub Copilot Custom Agent          │
│   (Running in VS Code / Copilot Chat)  │
└─────────────────┬───────────────────────┘
                  │
                  │ MCP Protocol
                  │ (JSON-RPC over HTTP/WebSocket)
                  │
┌─────────────────▼───────────────────────┐
│         MCP Server Manager              │
│   (Manages multiple MCP connections)    │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┼──────────┬────────────┬─────────┐
        │         │          │            │         │
┌───────▼─┐ ┌────▼────┐ ┌───▼─────┐ ┌───▼───┐ ┌───▼──────┐
│ AWS     │ │ AWS     │ │Microsoft│ │ Azure │ │ Mermaid  │
│ CCAPI   │ │Knowledge│ │ Learn   │ │  MCP  │ │  Chart   │
│ MCP     │ │  MCP    │ │  MCP    │ │       │ │  MCP     │
└─────────┘ └─────────┘ └─────────┘ └───────┘ └──────────┘
```

### MCP Server Configuration

**Location:** VS Code `mcp.json` (workspace settings — this project)

```json
{
  "mcpServers": {
    "aws-ccapi": {
      "command": "uvx",
      "args": ["awslabs.cdk-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-southeast-2",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "aws-knowledge-mcp": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "microsoft-learn": {
      "command": "npx",
      "args": ["-y", "@microsoft/mcp-server-learn"]
    },
    "azure-mcp": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}",
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}"
      }
    },
    "mermaidchart": {
      "command": "npx",
      "args": ["-y", "@mermaidchart/mcp-server"],
      "env": {
        "MERMAID_CHART_API_KEY": "${MERMAID_CHART_API_KEY}"
      }
    }
  }
}
```

### MCP Tool Invocation

**From Agent Perspective:**

```markdown
When you need to query AWS resources:
1. Use the aws-ccapi MCP server
2. Call the appropriate tool (e.g., list_resources, get_resource)
3. Parse the JSON response
4. Process and return results
```

**MCP Request Flow:**

```
Agent: "List all Lambda functions"
  ↓
MCP Manager: Route to aws-ccapi server
  ↓
AWS CCAPI MCP: Call AWS Cloud Control API
  ↓
AWS API: Return resource list
  ↓
MCP Manager: Format response
  ↓
Agent: Receive structured JSON
  ↓
Agent: Process and generate output
```

### Available MCP Tools by Server

**AWS Cloud Control API MCP:**
- `list_resources` - List all resources of a type
- `get_resource` - Get detailed resource information
- `list_resource_types` - Discover available resource types
- `search_resources` - Search across resource types

**Microsoft Learn MCP:**
- `search_documentation` - Search Microsoft Learn
- `get_article` - Retrieve specific article
- `list_related` - Find related documentation
- `get_code_samples` - Get code examples

**AWS Knowledge MCP:**
- `aws___search_documentation` - Search AWS docs
- `aws___read_documentation` - Retrieve full documentation page
- `aws___list_regions` - List enabled regions
- `aws___get_regional_availability` - Check service availability

**Azure MCP:**
- `azure-mcp/search` - Search Azure resources and documentation

**Mermaid Chart MCP:**
- `mermaidchart.validateMermaidDefinition` - Validate Mermaid diagram syntax

---

## 3. Agent Workflow Patterns

### Pattern 1: Sequential Processing

**Use Case:** Discovery → Design → Refactor → Deploy

```
User invokes: @aws-discovery
  ↓
Agent 1 executes:
  - Scan AWS resources
  - Generate inventory.json
  - Create dependency-matrix.csv
  ↓
Agent 1 completes, outputs files
  ↓
User invokes: @azure-architect
  ↓
Agent 2 reads:
  - inventory.json (from Agent 1)
  - dependency-matrix.csv (from Agent 1)
  ↓
Agent 2 executes:
  - Map services
  - Generate Bicep templates
  ↓
Agent 2 completes, outputs files
```

### Pattern 2: Parallel Execution

**Use Case:** Refactor multiple services simultaneously

```
User invokes: @code-refactor service-1 service-2 service-3
  ↓
Agent spawns parallel workflows:
  ├─ Service 1: Scan → Replace SDKs → Test → PR
  ├─ Service 2: Scan → Replace SDKs → Test → PR
  └─ Service 3: Scan → Replace SDKs → Test → PR
  ↓
All complete, agent summarizes results
```

### Pattern 3: Validation Loop

**Use Case:** Deploy with validation and retry

```
User invokes: @deployment-validation
  ↓
Agent executes pre-deployment:
  - Validate Bicep syntax
  - Check Azure Policy
  - Estimate costs
  ↓
If validation fails:
  - Report errors
  - Suggest fixes
  - Wait for user correction
  ↓
If validation passes:
  - Deploy infrastructure
  - Run smoke tests
  - Report success
```

### Pattern 4: Interactive Refinement

**Use Case:** Architecture design with user feedback

```
User invokes: @azure-architect
  ↓
Agent generates initial design
  ↓
Agent presents to user:
  - Architecture diagram
  - Cost estimate
  - Service choices
  ↓
User provides feedback: "Use Premium Functions instead of Consumption"
  ↓
Agent refines design
  ↓
Agent presents updated version
  ↓
User approves
  ↓
Agent finalizes and outputs files
```

---

## 4. Repository Structure and Configuration

### Complete Repository Layout

```
migration-project/
├── .github/
│   ├── agents/
│   │   ├── aws-discovery.agent.md
│   │   ├── azure-architect.agent.md
│   │   ├── code-refactor.agent.md
│   │   ├── iac-transformation.agent.md
│   │   └── deployment-validation.agent.md
│   ├── instructions/
│   │   ├── discovery.instructions.md
│   │   ├── azure-architecture.instructions.md
│   │   ├── code-refactoring.instructions.md
│   │   ├── iac-transformation.instructions.md
│   │   └── deployment-validation.instructions.md
│   ├── workflows/
│   │   ├── validate-bicep.yml
│   │   └── deploy-azure.yml
│   ├── copilot-instructions.md
│   └── mcp-config.json
├── aws-infrastructure/
│   ├── vpc-network.yaml
│   ├── eks-cluster.yaml
│   ├── rds-database.yaml
│   ├── s3-buckets.yaml
│   └── lambda-functions.yaml
├── azure-infrastructure/
│   ├── main.bicep
│   ├── modules/
│   │   ├── networking.bicep
│   │   ├── compute.bicep
│   │   ├── database.bicep
│   │   ├── storage.bicep
│   │   ├── messaging.bicep
│   │   ├── security.bicep
│   │   └── monitoring.bicep
│   └── parameters/
│       ├── dev.bicepparam
│       ├── staging.bicepparam
│       └── production.bicepparam
├── application/
│   ├── order-api/
│   │   ├── src/
│   │   ├── tests/
│   │   ├── package.json
│   │   └── Dockerfile
│   ├── payment-service/
│   └── inventory-service/
├── lambda-functions/
│   ├── order-validator/
│   ├── email-notifier/
│   └── inventory-sync/
├── migration-artifacts/
│   ├── aws-inventory.json
│   ├── architecture-diagram.mmd
│   ├── dependency-matrix.csv
│   ├── migration-assessment.md
│   ├── cost-comparison.md
│   └── service-mapping.md
├── .env.example
└── README.md
```

### Environment Configuration

**.env.example:**

```bash
# AWS Configuration (Discovery phase)
AWS_REGION=ap-southeast-2
AWS_PROFILE=default
AWS_ACCOUNT_ID=535002891143

# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_TENANT_ID=your-tenant-id

# Mermaid Chart (optional — for diagram validation)
MERMAID_CHART_API_KEY=your-api-key
```

---

## 5. Security and Authentication

### Authentication Patterns

**AWS Resources (Discovery Phase):**

```
Engineer's Workstation
  ↓
AWS CLI configured with profile
  ↓
MCP Server uses AWS SDK
  ↓
AWS SDK uses credentials from:
  - AWS_PROFILE environment variable
  - ~/.aws/credentials file
  - IAM role (if running on EC2/ECS)
  ↓
AWS Cloud Control API
```

**Azure Resources (Deploy Phase):**

```
Engineer's Workstation
  ↓
Azure CLI configured (az login)
  ↓
MCP Server uses Azure SDK
  ↓
Azure SDK uses credentials from:
  - DefaultAzureCredential
  - Azure CLI token cache
  - Service Principal (CI/CD)
  ↓
Azure Resource Manager
```

**GitHub Operations:**

```
GitHub Copilot
  ↓
Uses personal access token
  ↓
Stored in:
  - GITHUB_TOKEN environment variable
  - GitHub CLI credential storage
  ↓
GitHub API
```

### Secrets Management

**Development:**
- Store in `.env` file (git-ignored)
- Use environment variables
- Reference in MCP configuration

**CI/CD:**
- Store in Azure DevOps pipeline variables or GitHub Actions secrets
- Inject as environment variables at deployment time
- Use Azure Key Vault references in Bicep

**Production:**
- All secrets in Azure Key Vault
- Application code uses Managed Identity
- No credentials in code or configuration files

### RBAC Requirements

**AWS:**
- Read access to all resources (discovery)
- CloudFormation read access (IaC analysis)
- IAM read access (policy analysis)

**Azure:**
- Contributor role on subscription (deployment)
- Key Vault Administrator (secrets management)
- AKS Cluster Admin (Kubernetes operations)

**GitHub:**
- Repository write access (create PRs)
- Actions write access (update workflows)
- Packages read access (container registry)

---

## 6. Error Handling and Resilience

### Agent Error Patterns

**Network Failures:**

```markdown
When calling MCP servers:
1. Implement retry logic (3 attempts, exponential backoff)
2. If all retries fail, provide user-friendly error
3. Suggest troubleshooting steps
4. Continue with degraded functionality if possible
```

**Resource Not Found:**

```markdown
When AWS resource doesn't exist:
1. Log the missing resource
2. Continue discovery for other resources
3. Report missing resources in assessment
4. Don't fail entire discovery process
```

**Invalid Configuration:**

```markdown
When Bicep template has errors:
1. Run az bicep build to get specific errors
2. Report errors with line numbers
3. Suggest fixes based on error messages
4. Allow user to correct before continuing
```

### MCP Server Health Checks

**Pre-flight Validation:**

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check Azure credentials
az account show

# Check GitHub token
gh auth status

# Test MCP server connectivity
curl http://localhost:8080/health
```

### Graceful Degradation

**If MCP server unavailable:**
- Discovery agent: Use AWS CLI fallback
- Architect agent: Use cached documentation
- Refactor agent: Proceed with manual review
- Deploy agent: Use Azure CLI fallback

---

## 7. Performance and Scalability

### Optimization Strategies

**Parallel Resource Discovery:**

```
Instead of sequential:
  Lambda 1 → Lambda 2 → Lambda 3 → ... (slow)

Use parallel:
  ├─ Lambda 1, 2, 3
  ├─ RDS 1, 2, 3
  ├─ S3 buckets
  └─ EKS clusters
  (fast)
```

**Caching:**

```
Cache MCP responses for:
- Microsoft Learn documentation (1 day)
- AWS resource types (1 hour)
- Azure service SKUs (1 day)

Invalidate cache on:
- User request
- Version changes
- Schema updates
```

**Batch Operations:**

```
Instead of:
  Create PR for service 1
  Create PR for service 2
  Create PR for service 3

Batch:
  Create single PR with all services
  Organized by folder
  Clear commit messages
```

### Resource Limits

**AWS API Rate Limits:**
- Cloud Control API: 100 requests/second
- Implement exponential backoff
- Use pagination for large result sets

**Azure API Rate Limits:**
- Resource Manager: 12,000 reads/hour
- Batch requests when possible
- Use async operations for deployments

**GitHub API Rate Limits:**
- 5,000 requests/hour (authenticated)
- Use GraphQL for efficient queries
- Cache repository data

---

## 8. Extension and Customization

### Adding New Agents

**Process:**

1. Create agent file: `.github/agents/new-agent.agent.md`
2. Define capabilities and MCP servers needed
3. Create instructions: `.github/instructions/new-agent.instructions.md`
4. Test with sample workload
5. Document in repository README

**Example: Cost Optimization Agent**

```markdown
---
name: cost-optimizer
description: Analyzes Azure costs and suggests optimizations
tools: ['read', 'bash']
mcp-servers:
  - name: azure-mcp
    url: https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview
    tools: ["*"]
---

# Cost Optimization Agent

You analyze Azure resource configurations and suggest cost optimizations.

## Process

1. Query current Azure resources
2. Get cost data from Azure Cost Management
3. Identify optimization opportunities:
   - Over-provisioned resources
   - Unused resources
   - Reserved instance opportunities
   - Storage tier optimizations
4. Generate recommendations report

## Output

cost-optimization-report.md with:
- Current monthly cost: $X
- Potential savings: $Y
- Specific recommendations with impact
```

### Custom MCP Servers

**Creating Organization-Specific MCP Server:**

```typescript
// custom-mcp-server.ts
import { MCPServer } from '@modelcontextprotocol/server';

const server = new MCPServer({
  name: 'company-internal',
  version: '1.0.0'
});

server.tool('get_deployment_history', async (params) => {
  // Query internal deployment database
  const history = await db.query('SELECT * FROM deployments');
  return { deployments: history };
});

server.tool('check_compliance', async (params) => {
  // Check against company policies
  const result = await complianceChecker.validate(params.resourceConfig);
  return { compliant: result.passed, violations: result.violations };
});

server.listen(9000);
```

**Register in MCP config:**

```json
{
  "mcpServers": {
    "company-internal": {
      "command": "node",
      "args": ["./mcp-servers/custom-mcp-server.js"],
      "env": {
        "DATABASE_URL": "${INTERNAL_DB_URL}"
      }
    }
  }
}
```

### Extending Agent Capabilities

**Add Custom Tools:**

```markdown
---
name: enhanced-discovery
tools: ['read', 'bash', 'python']
mcp-servers:
  - name: aws-ccapi
  - name: company-internal
---

You can now:
1. Use standard discovery from AWS
2. Cross-reference with internal CMDB via company-internal MCP
3. Run custom Python scripts for advanced analysis
```

---

## Summary

This technical architecture provides:

1. **Modular Design** - Agents are independent and composable
2. **Extensible** - Easy to add new agents and MCP servers
3. **Secure** - Proper authentication and secrets management
4. **Resilient** - Error handling and graceful degradation
5. **Scalable** - Parallel processing and caching
6. **Maintainable** - Clear structure and documentation

**Next Document:** 03-CUSTOM-AGENT-SPECIFICATIONS.md for complete agent definitions
