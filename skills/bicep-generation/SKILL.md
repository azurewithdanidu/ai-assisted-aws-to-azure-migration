---
name: bicep-generation
description: 'Generate secure modular Azure Bicep templates. Use when: writing outputs/bicep-templates/*.bicep, defining module parameters and outputs, applying naming conventions, or validating that IaC matches the architecture design contract.'
---

# Bicep Generation Skill

## Purpose

Produce deployment-ready Azure Bicep that is modular, secure, environment-aware, and explicit enough for human review and automated deployment.

## When to Use

- When translating Section 5 of `design-document.md` into Bicep files
- When reviewing or repairing generated Bicep modules
- When creating environment parameter files for dev, staging, and prod
- When validation finds drift between design and IaC

## Inputs

| Path | Why it matters |
|---|---|
| `outputs/azure-architecture-output/design-document.md` | Source of truth for Section 5 module specifications |
| `outputs/bicep-templates/` | Target output directory |
| `outputs/bicep-templates/modules/` | Target directory for per-module files |
| `outputs/bicep-templates/parameters/` | Target directory for environment parameter files |

## Outputs

| Path | Result |
|---|---|
| `outputs/bicep-templates/main.bicep` | Root orchestration template |
| `outputs/bicep-templates/modules/*.bicep` | One module per infrastructure concern |
| `outputs/bicep-templates/parameters/dev.bicepparam` | Dev parameter file |
| `outputs/bicep-templates/parameters/staging.bicepparam` | Staging parameter file |
| `outputs/bicep-templates/parameters/prod.bicepparam` | Prod parameter file |

## Process

### 1. Start from the architecture contract

1. Read Section 5 of `outputs/azure-architecture-output/design-document.md` in full.
2. List every module required.
3. Assign each module one primary responsibility.
4. Decide which parameters belong in the root template versus module scope.
5. Write the header block, parameters, variables, resources, and outputs in that order.

### 2. Required Bicep file header comment block

Put this header at the top of every `.bicep` file and adjust the values for the specific module:

```bicep
/*
  Module: modules/<file-name>.bicep
  Purpose: <what this module deploys>
  Source: outputs/azure-architecture-output/design-document.md Section 5
  Inputs: <comma-separated parameter names>
  Outputs: resourceId, name, principalId
  Notes: No hardcoded secrets, no inline resource-name interpolation, API versions 2023 or newer
*/
```

### 3. Mandatory parameter decorator patterns

Every public parameter must include a description. Apply range or allowed-value decorators where the contract requires them.

```bicep
@description('Short workload identifier used in resource naming.')
@minLength(2)
param workload string

@description('Deployment environment.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Azure region short code such as aue or ause.')
@minLength(2)
param regionCode string

@description('Tags applied to every resource in this module.')
param tags object
```

Recommended additional decorators when the contract needs them:

- `@maxLength()` for globally constrained names
- `@secure()` for secrets or protected values
- `@minValue()` / `@maxValue()` for numeric capacity settings

### 4. Naming convention rules

Use deterministic names derived from parameters or variables, not ad hoc literals.

| Resource type | Pattern | Example |
|---|---|---|
| Resource group | `rg-{workload}-{env}-{region}` | `rg-orders-dev-aue` |
| Function App | `func-{workload}-{env}` | `func-orders-dev` |
| App Service plan / Functions plan | `plan-{workload}-{env}` | `plan-orders-dev` |
| Storage account | `st{workload}{env}{region}{suffix}` | `stordersdevaue01` |
| Service Bus namespace | `sb-{workload}-{env}` | `sb-orders-dev` |
| Cosmos DB account | `cosmos-{workload}-{env}` | `cosmos-orders-dev` |
| PostgreSQL server | `psql-{workload}-{env}` | `psql-orders-dev` |
| Key Vault | `kv-{workload}-{env}` | `kv-orders-dev` |
| Log Analytics workspace | `log-{workload}-{env}` | `log-orders-dev` |
| Application Insights | `appi-{workload}-{env}` | `appi-orders-dev` |

Naming rules:

- Compute names once in variables or parameters.
- Keep storage account names lowercase and globally unique.
- Avoid inline interpolation inside resource `name:` properties; assign the final string to a variable first.
- Reuse the same workload, environment, and region tokens everywhere for reviewability.

### 5. Required outputs for every module

Every module must expose these outputs so downstream templates and workflows can compose safely.

| Output | Type | Required behavior |
|---|---|---|
| `resourceId` | `string` | Always output the ARM resource ID of the primary resource |
| `name` | `string` | Always output the deployable resource name |
| `principalId` | `string` | Output the managed identity principal ID, or an empty string if the module has no identity |

Recommended optional outputs when relevant:

- `hostname`
- `endpoint`
- `privateEndpointId`
- `connectionSettingName`

### 6. Anti-patterns to reject

Do not accept any of the following:

- Hardcoded subscription IDs, tenant IDs, secrets, or passwords
- Inline string interpolation directly in resource `name:` properties
- API versions older than 2023
- One giant module that mixes networking, security, compute, and data responsibilities
- Public network access enabled on sensitive data services without an explicit design exception
- Output omission for `resourceId`, `name`, or `principalId`
- Environment-specific literals embedded in module code when they belong in parameter files
- **`targetScope = 'resourceGroup'` in main.bicep when the template creates its own resource group** — this makes `az deployment group create` fail because the resource group does not yet exist
- **`az deployment group create` against a subscription-scoped template** — always use `az deployment sub create`
- **Module calls in main.bicep without `scope: rg`** — every module call must be scoped to the resource group resource
- **`resourceGroup().location` inside a subscription-scoped template** — the `resourceGroup()` function is unavailable at subscription scope; use the `location` parameter instead

### 7. Subscription-scope main.bicep pattern (Mandatory)

When main.bicep creates a resource group (which is the standard pattern for this migration factory), the template **MUST** be subscription-scoped. This is a hard rule — not optional.

#### Why this matters

A `targetScope = 'resourceGroup'` template cannot create its own resource group because the resource group must already exist before `az deployment group create` runs. Attempting to do so produces a 404 or "resource group not found" error mid-deployment.

#### Required structure for main.bicep

```bicep
/*
  Module: main.bicep
  Purpose: Subscription-scope orchestration — creates resource group and delegates to modules.
  Source: outputs/azure-architecture-output/design-document.md Section 5
  Inputs: environment, location, resourceGroupName, workload, tags
  Outputs: (none — consumed by caller/CI)
  Notes: targetScope MUST be 'subscription'. Every module call MUST carry scope: rg.
*/

targetScope = 'subscription'

@description('Deployment environment.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources.')
param location string = 'australiaeast'

@description('Resource group name.')
param resourceGroupName string = 'rg-${workload}-${environment}'

@description('Short workload identifier.')
param workload string

@description('Tags applied to every resource.')
param tags object = {
  Environment: environment
  Application: workload
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module storageModule 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: rg          // ← mandatory on EVERY module call
  params: {
    workload: workload
    environment: environment
    location: location
    tags: tags
  }
}

module functionModule 'modules/function-app.bicep' = {
  name: 'deploy-function'
  scope: rg          // ← mandatory on EVERY module call
  params: {
    workload: workload
    environment: environment
    tags: tags
  }
}
```

#### Required parameter file entries

Every `.bicepparam` file must include `location` and `resourceGroupName`:

```bicep
using '../main.bicep'

param environment = 'dev'
param location = 'australiaeast'
param resourceGroupName = 'rg-migration-dev'
param workload = 'migration'
```

#### Correct deployment commands

```bash
# Deploy (subscription scope)
az deployment sub create \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters @outputs/bicep-templates/parameters/dev.bicepparam

# What-if preview (subscription scope)
az deployment sub what-if \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters @outputs/bicep-templates/parameters/dev.bicepparam
```

#### FORBIDDEN commands for subscription-scoped templates

```bash
# ❌ WRONG — cannot create resource groups at group scope
az deployment group create --resource-group rg-migration-dev --template-file main.bicep ...

# ❌ WRONG — same problem
az deployment group what-if --resource-group rg-migration-dev --template-file main.bicep ...
```

### 8. Example Bicep module skeleton (module files — not main.bicep)

```bicep
/*
  Module: modules/function-app.bicep
  Purpose: Deploy the Azure Function App and its managed identity.
  Source: outputs/azure-architecture-output/design-document.md Section 5
  Inputs: workload, environment, location, tags, storageAccountName, appInsightsConnectionString
  Outputs: resourceId, name, principalId
  Notes: No hardcoded secrets, no inline resource-name interpolation, API versions 2023 or newer
*/

targetScope = 'resourceGroup'

@description('Short workload identifier used in resource naming.')
@minLength(2)
param workload string

@description('Deployment environment.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string

@description('Azure location for the resource group deployment.')
param location string = resourceGroup().location

@description('Tags applied to the Function App resources.')
param tags object

@description('Existing storage account name used by the Function App.')
@minLength(3)
param storageAccountName string

@description('Application Insights connection string.')
@secure()
param appInsightsConnectionString string

var functionAppName = 'func-${workload}-${environment}'
var siteConfigAppSettings = [
  {
    name: 'APPINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
]

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    httpsOnly: true
    siteConfig: {
      appSettings: siteConfigAppSettings
    }
  }
}

output resourceId string = functionApp.id
output name string = functionApp.name
output principalId string = functionApp.identity.principalId ?? ''
```

### 9. Validation workflow

1. Ensure every module file has the required header block.
2. Ensure every parameter has `@description`.
3. Ensure any bounded string or enum-like parameter also has `@minLength` or `@allowed` as applicable.
4. Ensure every module emits `resourceId`, `name`, and `principalId`.
5. Ensure main.bicep declares `targetScope = 'subscription'` and that every module call has `scope: rg`.
6. Build and sanity-check the templates using the existing repo or ecosystem validation commands where available.

```bash
# Syntax check
az bicep build --file outputs/bicep-templates/main.bicep

# Subscription-scope what-if (must use sub — not group)
az deployment sub what-if \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters @outputs/bicep-templates/parameters/dev.bicepparam
```

### 9. Edge Cases / Failure Modes

- **No managed identity on a resource:** still output `principalId` as an empty string to keep the module contract stable.
- **Global naming collision:** introduce a suffix variable or parameter rather than changing the naming scheme ad hoc.
- **One resource type needs an older API version:** escalate to architecture or document the exception explicitly; the default rule is 2023 or newer.
- **Design document omits a required module:** do not invent the module purpose; route the issue back to architecture.
- **Private endpoint requirements absent:** if the security design says private networking is mandatory, treat the omission as a contract issue.

## Rules

- **Every module must have one primary responsibility.**
- **Every public parameter must have `@description`.**
- **Use `@minLength` and `@allowed` whenever the contract implies them.**
- **No inline interpolation in resource names; compute names in variables first.**
- **No API versions older than 2023.**
- **Every module must output `resourceId`, `name`, and `principalId`.**
- **main.bicep MUST declare `targetScope = 'subscription'` when it creates a resource group.** Using `targetScope = 'resourceGroup'` makes `az deployment group create` fail because the group doesn't exist yet.
- **Every module call in main.bicep MUST include `scope: rg`.** Omitting it silently deploys to the wrong scope and causes cryptic errors.
- **Deploy subscription-scoped templates with `az deployment sub create --location <region>`.** Never use `az deployment group create` for templates that create their own resource group.
- **Never use `resourceGroup().location` inside a subscription-scoped template.** Use the `location` parameter instead.

## Best Practices

- Keep root `main.bicep` thin and module-focused.
- Put environment differences in `.bicepparam` files instead of branching inside modules.
- Prefer consistent variable names like `functionAppName`, `serviceBusNamespaceName`, and `keyVaultName`.
- Reuse the same `tags` object across modules for auditability.
- Make module outputs predictable so CI/CD workflows can consume them without file-specific logic.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Bicep overview | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview |
| Bicep best practices | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices |
| Bicep parameters | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters |
| Bicep variables | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/variables |
| Bicep modules | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules |
| Bicep outputs | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/outputs |
| Bicep decorators | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters#parameter-decorators |
| bicepconfig.json reference | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-config |
| `az bicep build` CLI reference | https://learn.microsoft.com/en-us/cli/azure/bicep#az-bicep-build |
| `az deployment sub create` CLI | https://learn.microsoft.com/en-us/cli/azure/deployment/sub#az-deployment-sub-create |
| `az deployment sub what-if` CLI | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if |
| `uniqueString()` function | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-string#uniquestring |
| Azure Verified Modules (AVM) | https://azure.github.io/Azure-Verified-Modules/ |
| AVM Bicep resource modules index | https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/ |
| AVM Bicep pattern modules index | https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-pattern-modules/ |
| ARM API versions per resource type | https://learn.microsoft.com/en-us/azure/templates/ |

### Best Practices

- **Module contracts matter as much as resources** — the outputs drive downstream workflows and composition.
- **Name once, reuse everywhere** — deterministic names reduce review errors and environment drift.
- **Header comments help human review** — they keep module purpose and contract visible at the top of the file.
- **Reject obsolete API versions by default** — old versions quietly remove needed capabilities and policy support.
