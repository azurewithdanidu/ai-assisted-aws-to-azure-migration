# MCP Server Integration Guide

**Document Version:** 2.0  
**Date:** April 2026  
**Status:** ✅ Validated — all servers used in completed migration  
**Application:** Image Upload Service (AWS account 535002891143, ap-southeast-2 → Azure australiaeast)

---

## Overview

Model Context Protocol (MCP) is a standardized interface that allows AI agents to interact with external systems and tools. This guide covers the MCP servers used by the five migration agents in this repository, based on actual usage during the completed Image Upload Service migration.

**Key design principle:** All five agents operate exclusively through MCP servers and VS Code tools. No agent executes CLI or PowerShell commands — all external data access goes through MCP.

---

## What is MCP?

**Model Context Protocol (MCP):**
- Open standard for connecting AI agents to external tools
- JSON-RPC based communication protocol
- Supports both HTTP and WebSocket transports
- Provides standardized tool discovery and invocation
- Enables secure, authenticated access to APIs and services

**Key Concepts:**
- **MCP Server:** Service that exposes tools via MCP protocol
- **MCP Client:** AI agent that calls MCP server tools
- **Tool:** Specific capability exposed by MCP server
- **Resource:** Data or content accessible via MCP

---

## MCP Servers Used in This Migration

| MCP Server | Used By Agents | Purpose |
|------------|---------------|---------|
| AWS Cloud Control API MCP | `aws-discovery` | Read-only AWS resource discovery |
| AWS Knowledge MCP | `aws-discovery`, `azure-architect`, `code-refactor` | AWS service documentation |
| Microsoft Learn MCP | `azure-architect`, `iac-transformation`, `code-refactor` | Azure docs, AVM modules, best practices |
| Azure MCP | `azure-architect`, `iac-transformation`, `deployment-validation` | Azure resource information |
| Mermaid Chart MCP | `azure-architect` | Architecture diagram generation and validation |

---

## Required MCP Servers

### 1. AWS Cloud Control API MCP Server

**Purpose:** Discovery of AWS resources (read-only)

**Installation:**
```bash
npm install -g @aws/mcp-server-ccapi
```

**Configuration:**
```json
{
  "mcpServers": {
    "aws-ccapi": {
      "command": "npx",
      "args": ["-y", "@aws/mcp-server-ccapi"],
      "env": {
        "AWS_REGION": "ap-southeast-2",
        "AWS_PROFILE": "default"
      }
    }
  }
}
```

**Available Tools:**
- `list_resource_types` - Get all available AWS resource types
- `list_resources` - List resources of specific type
- `get_resource` - Get detailed resource information
- `search_resources` - Search across multiple resource types

**Prerequisites:**
- AWS CLI installed and configured
- Valid AWS credentials in `~/.aws/credentials`
- IAM permissions: Read-only access (`ReadOnlyAccess` policy minimum)

**Testing:**
```bash
aws sts get-caller-identity
npx @aws/mcp-server-ccapi
```

**Documentation:** https://awslabs.github.io/mcp/servers/ccapi-mcp-server

---

### 2. Microsoft Learn MCP Server

**Purpose:** Access Azure documentation, AVM modules, best practices, and code samples

**Installation:**
```bash
npm install -g @microsoft/mcp-server-learn
```

**Configuration:**
```json
{
  "mcpServers": {
    "microsoft-learn": {
      "command": "npx",
      "args": ["-y", "@microsoft/mcp-server-learn"]
    }
  }
}
```

**Available Tools:**
- `search_documentation` - Search Microsoft Learn
- `get_article` - Retrieve specific documentation article
- `list_related` - Find related documentation
- `get_code_samples` - Get code examples including Bicep samples
- `get_quickstart` - Get quickstart guides

**Key use in this migration:**
- Azure Architect Agent: find Azure equivalent services, retrieve AVM module definitions
- IaC Transformation Agent: fetch AVM Bicep module examples for storage, functions, Key Vault
- Code Refactor Agent: find `azure-storage-blob` SDK documentation and code samples

**Testing:**
```bash
npx @microsoft/mcp-server-learn
```

**Documentation:** https://learn.microsoft.com/en-us/training/support/mcp

---

### 3. AWS Knowledge MCP Server

**Purpose:** AWS documentation search and service guidance during discovery

**Used by:** AWS Discovery Agent — to look up service documentation and best practices

**Configuration (VS Code `mcp.json`):**
```json
{
  "mcpServers": {
    "aws-knowledge-mcp": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "env": {
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

**Available Tools (used in this migration):**
- `aws___search_documentation` - Search AWS documentation articles
- `aws___read_documentation` - Retrieve full documentation page
- `aws___list_regions` - Enumerate enabled AWS regions
- `aws___get_regional_availability` - Check service availability per region

**Key use in this migration:**
- AWS Discovery Agent: confirm resource type schemas for Cloud Control API
- Validate which `AWS::` CloudFormation resource types mapped to which AWS services

**Documentation:** https://awslabs.github.io/mcp/servers/aws-documentation-mcp-server/

---

### 4. Azure MCP Server

**Purpose:** Azure resource querying and search during architecture design

**Used by:** Azure Architect Agent — to search existing Azure resources and validate service availability

**Configuration (VS Code `mcp.json`):**
```json
{
  "mcpServers": {
    "azure-mcp": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}",
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}"
      }
    }
  }
}
```

**Available Tools (used in this migration):**
- `azure-mcp/search` - Search Azure resources and documentation

**Prerequisites:**
- Azure CLI installed and logged in: `az login`
- Valid subscription with Contributor role

**Key use in this migration:**
- Azure Architect Agent: validate available Azure services in `australiaeast` region
- Deployment Validation Agent: query deployed resource status

**Documentation:** https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview

---

### 5. Mermaid Chart MCP Server

**Purpose:** Architecture diagram validation and rendering

**Used by:** Azure Architect Agent — to validate Mermaid diagram syntax before saving

**Configuration (VS Code `mcp.json`):**
```json
{
  "mcpServers": {
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

**Available Tools (used in this migration):**
- `mermaidchart.validateMermaidDefinition` - Validates Mermaid diagram syntax

**Key use in this migration:**
- Azure Architect Agent: validates `architecture-diagram-azure.mmd` graph syntax before writing to outputs

**Documentation:** https://www.mermaidchart.com/mcp

---

## MCP Configuration File

**Location:** VS Code `mcp.json` (workspace or user settings)

**Complete configuration used for this migration:**
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

---

## Environment Variables

**Required for this migration project:**
```bash
# AWS Configuration (Discovery Agent)
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

## Testing MCP Servers

### Verify AWS Cloud Control API

```bash
# Check AWS credentials
aws sts get-caller-identity
# Expected: Account 535002891143, ap-southeast-2

# Verify MCP server resolves (via VS Code MCP panel)
# Or test uvx availability:
uvx --version
```

### Verify Microsoft Learn MCP

```bash
# Check npx availability
npx --version

# The server is invoked automatically by VS Code when an agent that
# references microsoftdocs/mcp/* tools is active
```

### Verify Azure MCP

```bash
# Check Azure CLI login
az account show
# Expected: your-subscription-id, australiaeast

# Check npx resolves the package
npx -y @azure/mcp@latest --help
```

---

## Troubleshooting

### MCP Server Won't Start

1. Check `uv` / `uvx` is installed: `uvx --version`  
2. Check `npx` is available: `npx --version` (Node 18+ required)  
3. Restart VS Code — MCP servers are restarted with each session  
4. Check VS Code Output panel → "GitHub Copilot Chat" for MCP error logs

### Authentication Errors — AWS

```bash
aws sts get-caller-identity  # Should return account info
aws configure list            # Check configured region and profile
aws configure --profile default  # Reconfigure if needed
```

### Authentication Errors — Azure

```bash
az account show  # Should return subscription info
az login         # Re-authenticate if needed
az account set --subscription "your-subscription-id"
```

### Agent Can't Access MCP Tools

1. Confirm the tool name in the agent `tools:` frontmatter matches the MCP server's tool namespace  
2. Check VS Code MCP panel (Command Palette → "MCP: List Servers") to see server status  
3. Verify `mcp.json` is in the workspace root or user settings  

---

## Security Best Practices

### Credentials Management

**Do:**
- Store AWS credentials in `~/.aws/credentials` (AWS profile)  
- Store Azure credentials via `az login` (no tokens in files)  
- Add `.env` to `.gitignore` if used  
- Use ReadOnlyAccess for AWS discovery — never write permissions  

**Don't:**
- Hardcode credentials in agent files or `mcp.json`  
- Commit AWS keys or Azure secrets to Git  
- Use admin/root accounts for MCP discovery  

### AWS MCP Permissions

The AWS Cloud Control API MCP server requires only **ReadOnlyAccess** (or equivalent):
- `cloudformation:Describe*`, `cloudformation:List*`
- `s3:GetBucket*`, `s3:ListBucket*`
- `lambda:GetFunction`, `lambda:List*`
- `apigateway:GET`
- `iam:List*`, `iam:Get*`
- `cloudwatch:Describe*`, `cloudwatch:List*`

---

## Summary

| MCP Server | Used By | Purpose |
|---|---|---|
| AWS Cloud Control API | `@aws-discovery` | Enumerate AWS resources read-only |
| AWS Knowledge | `@aws-discovery` | AWS documentation lookups |
| Microsoft Learn | `@azure-architect`, `@iac-transformation` | Azure service docs + AVM module examples |
| Azure MCP | `@azure-architect`, `@deployment-validation` | Azure resource search + validation |
| Mermaid Chart | `@azure-architect` | Diagram syntax validation |

**Design Principle:** No CLI or PowerShell commands inside any agent — all external data access goes through MCP server tools only.

**See Also:**
- [03-CUSTOM-AGENT-SPECIFICATIONS.md](03-CUSTOM-AGENT-SPECIFICATIONS.md) — full agent tool bindings
- [outputs/azure-functions/](../outputs/azure-functions/) — refactored Python Azure Functions
- [outputs/bicep-templates/](../outputs/bicep-templates/) — deployed Bicep infrastructure

