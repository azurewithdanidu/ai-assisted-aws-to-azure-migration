# MCP Server Integration Guide

**Document Version:** 1.0  
**Date:** December 2024  
**Purpose:** Model Context Protocol server setup and configuration

---

## Overview

Model Context Protocol (MCP) is a standardized interface that allows AI agents to interact with external systems and tools. This guide covers setup, configuration, and usage of MCP servers for AWS to Azure migration.

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

## Required MCP Servers

### 1. AWS Cloud Control API MCP Server

**Purpose:** Discovery of AWS resources

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
        "AWS_REGION": "us-east-1",
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
- IAM permissions: Read access to all resources

**Testing:**
```bash
# Test AWS credentials
aws sts get-caller-identity

# Test MCP server
npx @aws/mcp-server-ccapi
```

**Documentation:** https://awslabs.github.io/mcp/servers/ccapi-mcp-server

---

### 2. Microsoft Learn MCP Server

**Purpose:** Access Azure documentation for accurate service mappings

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
- `get_code_samples` - Get code examples from docs
- `get_quickstart` - Get quickstart guides

**Use Cases:**
- Find Azure equivalent for AWS service
- Get Bicep template examples
- Retrieve best practices documentation
- Find migration guides

**Testing:**
```bash
npx @microsoft/mcp-server-learn
```

**Documentation:** https://learn.microsoft.com/en-us/training/support/mcp

---

### 3. GitHub MCP Server

**Purpose:** Repository operations, PR creation, code analysis

**Installation:**
```bash
npm install -g @github/mcp-server
```

**Configuration:**
```json
{
  "mcpServers": {
    "github-mcp": {
      "command": "npx",
      "args": ["-y", "@github/mcp-server"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

**Available Tools:**
- `list_repositories` - List accessible repositories
- `get_file` - Read file content from repository
- `search_code` - Search code across repositories
- `create_pull_request` - Create PR with changes
- `list_issues` - List repository issues
- `create_issue` - Create new issue

**Prerequisites:**
- GitHub personal access token
- Permissions: `repo`, `workflow`, `write:packages`

**Creating GitHub Token:**
1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo`, `workflow`
4. Copy token and save to environment variable

**Testing:**
```bash
export GITHUB_TOKEN="your-token-here"
npx @github/mcp-server
```

**Documentation:** https://github.com/github/github-mcp-server

---

### 4. Azure MCP Server

**Purpose:** Azure resource deployment and management

**Installation:**
```bash
npm install -g @azure/mcp-server
```

**Configuration:**
```json
{
  "mcpServers": {
    "azure-mcp": {
      "command": "npx",
      "args": ["-y", "@azure/mcp-server"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}",
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}"
      }
    }
  }
}
```

**Available Tools:**
- `list_resources` - List Azure resources
- `get_resource` - Get resource details
- `create_deployment` - Deploy Bicep/ARM template
- `what_if` - Preview deployment changes
- `list_locations` - Get available Azure regions
- `get_pricing` - Get resource pricing information

**Prerequisites:**
- Azure CLI installed and configured
- Valid Azure credentials: `az login`
- Subscription access (Contributor role)

**Testing:**
```bash
az account show
npx @azure/mcp-server
```

**Documentation:** https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/overview

---

### 5. Buildkite MCP Server

**Purpose:** CI/CD pipeline management

**Installation:**
```bash
npm install -g @buildkite/mcp-server
```

**Configuration:**
```json
{
  "mcpServers": {
    "buildkite-mcp": {
      "command": "npx",
      "args": ["-y", "@buildkite/mcp-server"],
      "env": {
        "BUILDKITE_TOKEN": "${BUILDKITE_TOKEN}",
        "BUILDKITE_ORG": "your-org-slug"
      }
    }
  }
}
```

**Available Tools:**
- `list_pipelines` - List all pipelines
- `get_pipeline` - Get pipeline configuration
- `update_pipeline` - Update pipeline YAML
- `trigger_build` - Start a build
- `get_build` - Get build status
- `list_agents` - List available agents

**Prerequisites:**
- Buildkite API token
- Organization access

**Creating Buildkite Token:**
1. Go to Buildkite → Settings → API Access Tokens
2. Create new token with scopes: `read_pipelines`, `write_pipelines`, `read_builds`, `write_builds`
3. Copy token and save to environment variable

**Testing:**
```bash
export BUILDKITE_TOKEN="your-token-here"
export BUILDKITE_ORG="your-org"
npx @buildkite/mcp-server
```

**Documentation:** https://buildkite.com/docs/apis/mcp-server

---

## MCP Configuration File

**Location:** `.github/mcp-config.json`

**Complete Configuration:**
```json
{
  "mcpServers": {
    "aws-ccapi": {
      "command": "npx",
      "args": ["-y", "@aws/mcp-server-ccapi"],
      "env": {
        "AWS_REGION": "us-east-1",
        "AWS_PROFILE": "default"
      }
    },
    "microsoft-learn": {
      "command": "npx",
      "args": ["-y", "@microsoft/mcp-server-learn"]
    },
    "github-mcp": {
      "command": "npx",
      "args": ["-y", "@github/mcp-server"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "azure-mcp": {
      "command": "npx",
      "args": ["-y", "@azure/mcp-server"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}",
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}"
      }
    },
    "buildkite-mcp": {
      "command": "npx",
      "args": ["-y", "@buildkite/mcp-server"],
      "env": {
        "BUILDKITE_TOKEN": "${BUILDKITE_TOKEN}",
        "BUILDKITE_ORG": "your-org"
      }
    }
  }
}
```

---

## Environment Variables

**Create `.env` file:**
```bash
# AWS Configuration
AWS_REGION=us-east-1
AWS_PROFILE=default
AWS_ACCOUNT_ID=123456789012

# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_TENANT_ID=your-tenant-id

# GitHub Configuration
GITHUB_TOKEN=ghp_your_token_here

# Buildkite Configuration
BUILDKITE_TOKEN=your-buildkite-token
BUILDKITE_ORG=your-org-slug

# MCP Server Configuration
MCP_SERVER_HOST=localhost
MCP_SERVER_PORT=8080
```

**Load Environment Variables:**
```bash
# Option 1: Source .env file
source .env

# Option 2: Use direnv
echo "export $(cat .env | xargs)" > .envrc
direnv allow

# Option 3: Load in shell profile
echo 'export $(cat ~/migration-project/.env | xargs)' >> ~/.bashrc
```

---

## Testing MCP Servers

### Test AWS Cloud Control API

```bash
# Set up
export AWS_REGION=us-east-1
export AWS_PROFILE=default

# Start MCP server
npx @aws/mcp-server-ccapi &

# Test with curl
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "list_resource_types"
    },
    "id": 1
  }'

# Expected: List of AWS resource types
```

### Test Microsoft Learn MCP

```bash
# Start MCP server
npx @microsoft/mcp-server-learn &

# Search for Azure Functions documentation
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "search_documentation",
      "arguments": {
        "query": "Azure Functions migrate from AWS Lambda"
      }
    },
    "id": 1
  }'

# Expected: Relevant documentation articles
```

### Test GitHub MCP

```bash
# Set up
export GITHUB_TOKEN=your_token

# Start MCP server
npx @github/mcp-server &

# List repositories
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "list_repositories"
    },
    "id": 1
  }'

# Expected: List of accessible repositories
```

---

## Troubleshooting

### MCP Server Won't Start

**Issue:** Server fails to start

**Solutions:**
1. Check Node.js version: `node --version` (requires v16+)
2. Clear npm cache: `npm cache clean --force`
3. Reinstall: `npm uninstall -g @aws/mcp-server-ccapi && npm install -g @aws/mcp-server-ccapi`
4. Check logs: `npx @aws/mcp-server-ccapi --verbose`

### Authentication Errors

**Issue:** MCP server can't authenticate to AWS/Azure/GitHub

**Solutions:**

**For AWS:**
```bash
aws sts get-caller-identity  # Should return account info
aws configure list  # Check configuration
```

**For Azure:**
```bash
az account show  # Should return subscription info
az login  # Re-authenticate if needed
```

**For GitHub:**
```bash
gh auth status  # Check token validity
# Create new token if expired
```

### Agent Can't Connect to MCP Server

**Issue:** Agent reports "MCP server unavailable"

**Solutions:**
1. Verify MCP config: `cat .github/mcp-config.json`
2. Check environment variables: `env | grep AWS`
3. Restart VS Code / GitHub Copilot
4. Test MCP server manually (see testing section above)

### Slow Response Times

**Issue:** MCP server responds slowly

**Solutions:**
1. Run MCP servers locally instead of remotely
2. Cache frequently accessed data
3. Use parallel requests when possible
4. Increase timeout values in MCP config

---

## Security Best Practices

### Credentials Management

**Do:**
- Store tokens in environment variables
- Use `.env` file (add to `.gitignore`)
- Rotate tokens regularly
- Use minimum required permissions

**Don't:**
- Hardcode tokens in configuration
- Commit tokens to Git
- Share tokens in chat/email
- Use root/admin accounts

### Access Control

**AWS:**
- Create dedicated IAM user for MCP
- Attach ReadOnlyAccess policy
- Enable MFA for IAM user

**Azure:**
- Create service principal for MCP
- Assign Reader role
- Limit to specific subscriptions

**GitHub:**
- Create fine-grained personal access token
- Limit to specific repositories
- Set expiration date (90 days max)

### Network Security

**Production:**
- Run MCP servers behind firewall
- Use HTTPS/WSS for communication
- Implement rate limiting
- Log all MCP requests

---

## Advanced Configuration

### Custom MCP Server

**Create organization-specific MCP server:**

```typescript
// custom-mcp-server.ts
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

const server = new Server({
  name: 'company-internal-mcp',
  version: '1.0.0',
}, {
  capabilities: {
    tools: {},
  },
});

// Define custom tool
server.setRequestHandler('tools/list', async () => {
  return {
    tools: [{
      name: 'get_deployment_history',
      description: 'Get deployment history from internal database',
      inputSchema: {
        type: 'object',
        properties: {
          service: { type: 'string' }
        }
      }
    }]
  };
});

server.setRequestHandler('tools/call', async (request) => {
  if (request.params.name === 'get_deployment_history') {
    // Query internal database
    const history = await db.query(
      'SELECT * FROM deployments WHERE service = ?',
      [request.params.arguments.service]
    );
    return { content: [{ type: 'text', text: JSON.stringify(history) }] };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

**Register in mcp-config.json:**
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

---

## Summary

MCP servers enable AI agents to access external systems securely and efficiently. Proper setup and configuration is essential for successful AI-assisted migration.

**Key Points:**
- 5 MCP servers cover all migration phases
- Each server requires specific credentials
- Configuration stored in `.github/mcp-config.json`
- Environment variables for sensitive data
- Test each server before demo/production use

**Next Steps:**
1. Install all MCP servers
2. Configure credentials
3. Test each server
4. Update `.github/mcp-config.json`
5. Run agents to verify integration

**See Also:**
- 02-TECHNICAL-DEEP-DIVE.md for architecture
- 03-CUSTOM-AGENT-SPECIFICATIONS.md for agent usage
