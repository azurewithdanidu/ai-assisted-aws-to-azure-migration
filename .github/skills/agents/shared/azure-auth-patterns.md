---
name: azure-auth-patterns
description: Authenticate Azure services to each other using Managed Identity and RBAC — never connection strings or access keys
---

# Azure Auth Patterns Skill

## Purpose

Replace all AWS IAM-based authentication patterns with Azure Managed Identity and RBAC, ensuring no long-lived credentials appear in code, environment variables, or configuration files.

## When to Use

- When rewriting Lambda handlers that call AWS services (boto3 clients) into Azure Function equivalents
- When writing Bicep RBAC role assignments
- When configuring app settings that reference downstream services
- Any time a service needs to authenticate to another Azure service

## Process

**In Bicep (infrastructure):**

1. Enable system-assigned managed identity on every compute resource:
   ```bicep
   resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
     identity: {
       type: 'SystemAssigned'
     }
     // ...
   }
   ```

2. Assign the minimum required RBAC role to the principal ID:
   ```bicep
   resource blobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
     scope: storageAccount
     name: guid(resourceGroup().id, functionApp.id, 'blob-contributor')
     properties: {
       roleDefinitionId: subscriptionResourceId(
         'Microsoft.Authorization/roleDefinitions',
         'ba92f5b4-2d11-453d-a403-e96b0029c9fe'  // Storage Blob Data Contributor
       )
       principalId: functionApp.identity.principalId
       principalType: 'ServicePrincipal'
     }
   }
   ```

3. Reference Key Vault secrets in app settings — no SDK call needed at runtime:
   ```bicep
   resource appSettings 'Microsoft.Web/sites/config@2023-01-01' = {
     name: '${functionApp.name}/appsettings'
     properties: {
       'MY_SECRET': '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/MySecret/)'
     }
   }
   ```

**In Python (application code):**

4. Replace all boto3 clients with `DefaultAzureCredential`:
   ```python
   from azure.identity import DefaultAzureCredential
   from azure.storage.blob import BlobServiceClient

   credential = DefaultAzureCredential()
   blob_client = BlobServiceClient(
       account_url=f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
       credential=credential
   )
   ```

5. `DefaultAzureCredential` works locally (via `az login`) and in Azure (via managed identity) — no code changes between environments.

## RBAC Role Reference

| AWS Pattern | Azure Equivalent | Built-in Role | Role GUID |
|---|---|---|---|
| S3 read/write | Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| S3 read-only | Storage Blob Data Reader | `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` |
| Secrets Manager read | Key Vault Secrets User | `4633458b-17de-408a-b874-0445c86b69e6` |
| Secrets Manager write | Key Vault Secrets Officer | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| SQS send | Azure Service Bus Data Sender | `69a216fc-b8fb-44d8-bc22-1f3c2cd27a39` |
| SQS receive | Azure Service Bus Data Receiver | `4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0` |
| DynamoDB read/write | Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` |

## Rules

- **Never use storage account keys or connection strings** — always Storage Blob Data Contributor/Reader via managed identity.
- **Never use Service Bus connection strings** — always Azure Service Bus Data Sender/Receiver roles.
- **Never use Key Vault access policies** — always RBAC (Key Vault Secrets Officer/User).
- **Never store credentials in environment variables** — use Key Vault references in app settings (`@Microsoft.KeyVault(...)`).
- **Never hardcode subscription IDs, tenant IDs, or client IDs** in application code — read from `os.environ`.
- **Always use `DefaultAzureCredential`** in Python, not `ClientSecretCredential` or `ManagedIdentityCredential` directly.

## Output

- Bicep files with `identity: { type: 'SystemAssigned' }` on all compute resources
- Bicep `roleAssignment` resources for every service-to-service access requirement
- Python files importing `DefaultAzureCredential` with no boto3 credential patterns
- App settings using `@Microsoft.KeyVault(...)` references, not plain secret values
