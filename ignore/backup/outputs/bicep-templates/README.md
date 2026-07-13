# Image Upload Service — Bicep Templates

## Overview

This directory contains the Azure Bicep IaC templates for migrating the AWS image-upload service (ap-southeast-2) to Azure (australiasoutheast). All resources are declared using [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) via `br/public:avm/...` — no raw resource declarations (except `Microsoft.Authorization/roleAssignments` in `modules/rbac.bicep`, which are built-in ARM types scoped to specific resources).

## File Structure

```
outputs/bicep-templates/
├── bicepconfig.json                   # AVM registry alias (modulePath: "bicep")
├── main.bicep                         # Root orchestration — params, modules, outputs only
├── modules/
│   ├── monitoring.bicep               # Log Analytics workspace + Application Insights
│   ├── storage.bicep                  # StorageV2 account, blob service, images container
│   ├── function-app.bicep             # Y1 plan + Function App (Python 3.11) + Key Vault
│   ├── static-web-app.bicep           # Static Web App (Free tier SPA host)
│   └── rbac.bicep                     # Role assignments for Function App MI
├── parameters/
│   ├── dev.bicepparam                 # Development — LRS, 30d retention
│   ├── staging.bicepparam             # Staging — ZRS, 60d retention
│   └── prod.bicepparam                # Production — GRS, 90d retention
└── scripts/
    ├── validate-deployment.sh         # Pre-deployment: bicep restore + build + what-if
    ├── deploy.sh                      # Incremental deployment to a resource group
    └── rollback.sh                    # Re-deploy previous successful deployment template
```

## AVM Modules Selected

Per the `module-organization` skill (`avm/res/...` modules preferred for single-resource scopes):

| Module file | AVM module | Version | Selected per skill |
|---|---|---|---|
| `modules/monitoring.bicep` | `avm/res/operational-insights/workspace` | `0.15.0` | CloudWatch Logs → Log Analytics mapping |
| `modules/monitoring.bicep` | `avm/res/insights/component` | `0.7.1` | X-Ray → Application Insights mapping |
| `modules/storage.bicep` | `avm/res/storage/storage-account` | `0.32.0` | S3 → Blob Storage mapping |
| `modules/function-app.bicep` | `avm/res/web/serverfarm` | `0.7.0` | Lambda hosting plan |
| `modules/function-app.bicep` | `avm/res/web/site` | `0.22.0` | Lambda → Azure Functions mapping |
| `modules/function-app.bicep` | `avm/res/key-vault/vault` | `0.13.3` | Secrets Manager → Key Vault mapping |
| `modules/static-web-app.bicep` | `avm/res/web/static-site` | `0.9.3` | S3 Static Website → Static Web Apps mapping |

## AWS → Azure Resource Mapping

| AWS Resource | Azure Resource | Bicep Module |
|---|---|---|
| Lambda (4 functions) | Azure Functions (Python 3.11 Consumption Y1) | `modules/function-app.bicep` |
| S3 bucket (private images) | Azure Blob Storage `Standard_LRS` container `images` | `modules/storage.bicep` |
| S3 bucket (static website) | Azure Static Web Apps (Free) | `modules/static-web-app.bicep` |
| API Gateway REST API | Azure Functions HTTP triggers (direct) | `modules/function-app.bicep` |
| IAM Role (LambdaExecutionRole) | System-assigned Managed Identity + RBAC | `modules/function-app.bicep` + `modules/rbac.bicep` |
| IAM User (ApiUser) | Microsoft Entra ID app registration | Post-deployment step |
| CloudWatch Logs | Azure Monitor / Log Analytics | `modules/monitoring.bicep` |
| X-Ray | Application Insights | `modules/monitoring.bicep` |
| Secrets Manager / SSM | Azure Key Vault (Standard) | `modules/function-app.bicep` |

## Quick Start

### Prerequisites

- Azure CLI >= 2.50 with `az bicep` extension
- Contributor access to the target subscription
- Target resource group created (or use `deploy.sh` which creates it)

### Deploy to Dev

```bash
# 1. Validate before deploying
./scripts/validate-deployment.sh dev rg-image-upload-dev

# 2. Deploy
./scripts/deploy.sh dev rg-image-upload-dev
```

### Deploy to Staging / Prod

```bash
./scripts/validate-deployment.sh staging rg-image-upload-stg
./scripts/deploy.sh staging rg-image-upload-stg

./scripts/validate-deployment.sh prod rg-image-upload-prd
./scripts/deploy.sh prod rg-image-upload-prd
```

### Roll Back

```bash
./scripts/rollback.sh dev rg-image-upload-dev
```

## Post-Deployment Steps

### 1. Update CORS Origins

After the first deployment, get the Static Web App hostname from the deployment outputs and add it to the `corsAllowedOrigins` parameter, then re-deploy:

```bash
SWA_HOST=$(az deployment group show \
  --name <deployment-name> \
  --resource-group rg-image-upload-dev \
  --query "properties.outputs.staticWebAppHostname.value" \
  --output tsv)

echo "Add 'https://${SWA_HOST}' to corsAllowedOrigins in parameters/dev.bicepparam"
```

### 2. Configure Microsoft Entra ID Authentication

App Service Authentication requires an Entra app registration (client ID) created after deployment. Configure it via Azure Portal or CLI:

```bash
az webapp auth microsoft update \
  --name img-upload-func-dev-ase \
  --resource-group rg-image-upload-dev \
  --client-id <entra-app-client-id> \
  --client-secret-setting-name MICROSOFT_PROVIDER_AUTHENTICATION_SECRET \
  --unauthenticated-client-action RedirectToLoginPage
```

### 3. Grant Function App MI access to generate User Delegation SAS Keys

The `Storage Blob Data Contributor` role (assigned by `modules/rbac.bicep`) is sufficient to generate user delegation keys for SAS URL creation. Verify with:

```bash
az role assignment list \
  --assignee <principalId-from-outputs> \
  --scope /subscriptions/.../resourceGroups/.../providers/Microsoft.Storage/storageAccounts/imguploaddevase
```

## Known Constraints and Design Decisions

| Decision | Rationale |
|---|---|
| Static Web App location defaults to `eastasia` | SWA Free tier has limited region availability — `australiasoutheast` is not supported |
| No APIM in dev | Lowest cost; Functions HTTP triggers used directly (per design-document.md §3.3) |
| `allowSharedKeyAccess: false` on Storage | Forces managed identity authentication; disables storage key use |
| Raw `roleAssignment` resources in `rbac.bicep` | `ptn/authorization/role-assignment` is designed for subscription-scope; resource-scoped assignments use raw API |
| `AzureWebJobsStorage__accountName` pattern | Avoids storage connection strings; uses managed identity credential flow |

## Breaking Changes Applied

Per `module-organization` skill §Step 4:

- **`avm/res/storage/storage-account:0.32.0`** — `deleteRetentionPolicy.{enabled,days}` flattened to `deleteRetentionPolicyEnabled` + `deleteRetentionPolicyDays`
- **`avm/res/web/serverfarm:0.7.0`** — `skuTier` removed; `skuName: 'Y1'` only; `kind: 'linux'` + `reserved: true` required for Linux plans

## Deployment Dependency Order

```
monitoring ──→ storage ──→ function-app ──→ rbac
                                         ↗
static-web-app (independent)
```

1. `monitoring` — creates Log Analytics workspace + App Insights (no deps)
2. `storage` — creates storage account with images container (no deps)
3. `function-app` — needs App Insights connection string + storage account name
4. `rbac` — needs Function App principal ID + storage account resource ID
5. `static-web-app` — independent, deployed last
