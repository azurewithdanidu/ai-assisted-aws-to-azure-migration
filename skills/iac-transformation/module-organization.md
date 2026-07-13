---
name: module-organization
description: Decide what belongs in root main.bicep vs child modules, AVM module selection, dependency ordering, and how to avoid circular dependencies and common Bicep pitfalls
---

# Module Organization Skill

## Purpose

Structure Bicep templates into focused, reusable modules with clear boundaries so the deployment is maintainable, testable, and free of circular dependencies. Incorporates AVM (Azure Verified Modules) selection guidance.

## When to Use

Before writing any Bicep file — this skill defines the file structure and AVM module choices that all other IaC work follows.

## Process

1. **Configure `bicepconfig.json`** — mandatory first step (Step 1 below).
2. Read `outputs/azure-architecture-output/design-document.md` Section 5 for the full module list.
3. **Select AVM modules** using the decision tree (Step 2 below).
4. **Resolve module versions** using Step 3 below.
5. Create one module file per logical resource group.
6. Write `main.bicep` with parameters, module calls, and outputs only.
7. Run the pitfalls check (Step 4 below) before declaring templates complete.

---

## Step 1 — Configure bicepconfig.json (Mandatory First)

Every project that uses AVM modules MUST have this file at the Bicep root (`outputs/bicep-templates/bicepconfig.json`):

```json
{
  "$schema": "https://aka.ms/bicep-config",
  "moduleAliases": {
    "br": {
      "public": {
        "registry": "mcr.microsoft.com",
        "modulePath": "bicep"
      }
    }
  }
}
```

**CRITICAL:** `modulePath` must be `"bicep"` — NOT `"bicep/public"`.
- Correct: `mcr.microsoft.com/bicep/avm/res/storage/storage-account:0.32.0`
- Wrong: `mcr.microsoft.com/bicep/public/avm/res/...` (does not exist — causes "artifact does not exist in registry" error)

Reference syntax in Bicep:
```bicep
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = { ... }
```

---

## Step 2 — AVM Module Selection Decision Tree

```
Is there an AVM ptn/ (pattern) module that covers the full scenario?
  YES → Use ptn/ module (preferred — bundles networking, RBAC, monitoring wiring)
  NO  → Is there an AVM res/ (resource) module for the Azure service?
          YES → Use res/ module
          NO  → Write raw Bicep resource declaration
```

**Prefer pattern modules:**
- Multi-spoke hub networking → `ptn/network/hub-networking`
- AKS full cluster → `ptn/azd/aks`
- Container Apps full stack → `ptn/azd/container-apps-stack`
- Private DNS zones for Private Link → `ptn/network/private-link-private-dns-zones`
- RBAC role assignment (cross-scope) → `ptn/authorization/role-assignment`
- AI Foundry stack → `ptn/ai-ml/ai-foundry`

### AWS → Azure → AVM Module Mapping

**Compute:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| Lambda (event-driven) | Azure Functions | `res/web/site` + `res/web/serverfarm` (kind='functionapp,linux') |
| Lambda (container) | Azure Container Apps Job | `res/app/job` |
| ECS Fargate | Azure Container Apps | `res/app/container-app` + `res/app/managed-environment` |
| EKS | AKS | `res/container-service/managed-cluster` or `ptn/azd/aks` |
| EC2 | Azure Virtual Machine | `res/compute/virtual-machine` |
| Elastic Beanstalk | App Service | `res/web/site` + `res/web/serverfarm` (kind='app') |

**Storage:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| S3 | Azure Blob Storage | `res/storage/storage-account` (kind='StorageV2') |
| S3 Static Website | Static Web App | `res/web/static-site` |
| EFS | Azure Files | `res/storage/storage-account` (fileServices enabled) |
| EBS | Managed Disk | `res/compute/disk` |

**Database:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| RDS PostgreSQL | Azure Database for PostgreSQL Flexible | `res/db-for-postgre-sql/flexible-server` |
| RDS MySQL | Azure Database for MySQL Flexible | `res/db-for-my-sql/flexible-server` |
| RDS SQL Server | Azure SQL Database | `res/sql/server` |
| DynamoDB | Cosmos DB | `res/document-db/database-account` (NoSQL API) |
| ElastiCache Redis | Azure Cache for Redis | `res/cache/redis` |

**Messaging & Events:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| SQS | Azure Service Bus (queue) | `res/service-bus/namespace` |
| SNS | Azure Service Bus (topic) or Event Grid | `res/service-bus/namespace` or `res/event-grid/topic` |
| EventBridge | Azure Event Grid | `res/event-grid/namespace` or `res/event-grid/topic` |
| Kinesis Data Streams | Azure Event Hubs | `res/event-hub/namespace` |

**Security & Identity:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| IAM Role (service) | Managed Identity | `res/managed-identity/user-assigned-identity` |
| IAM Role (user) | Azure RBAC role assignment | `ptn/authorization/role-assignment` |
| Secrets Manager | Azure Key Vault | `res/key-vault/vault` |
| KMS | Azure Key Vault (keys) | `res/key-vault/vault` |
| SSM Parameter Store | App Configuration or Key Vault | `res/app-configuration/configuration-store` |

**Networking:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| VPC | Virtual Network | `res/network/virtual-network` |
| Security Group | Network Security Group | `res/network/network-security-group` |
| ALB | Application Gateway | `res/network/application-gateway` |
| Route 53 (public) | Azure DNS Zone | `res/network/dns-zone` |
| Route 53 (private) | Private DNS Zone | `res/network/private-dns-zone` |
| VPC Endpoint | Private Endpoint | `res/network/private-endpoint` |
| NAT Gateway | NAT Gateway | `res/network/nat-gateway` |
| CloudFront | Azure Front Door | `res/cdn/profile` |
| VPC Peering | VNet Peering | `res/network/virtual-network-peering` |
| Direct Connect | ExpressRoute | `res/network/express-route-circuit` |

**Monitoring:**

| AWS Service | Azure Equivalent | AVM Module |
|---|---|---|
| CloudWatch Logs | Log Analytics Workspace | `res/operational-insights/workspace` |
| CloudWatch Alarms | Azure Monitor Alerts | `res/insights/metric-alert` |
| X-Ray | Application Insights | `res/insights/component` |
| CloudTrail | Azure Monitor Activity Log | `res/insights/diagnostic-setting` |

---

## Step 3 — Resolve Module Versions

**Never hardcode a version without verifying it exists.** Always resolve from the official CHANGELOG:

```
CHANGELOG URL pattern:
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/<provider>/<module>/CHANGELOG.md

Examples:
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/storage/storage-account/CHANGELOG.md
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/web/site/CHANGELOG.md
```

Use the script at `.github/skills/iac-transformation/scripts/resolve-avm-version.sh` to automate:
```bash
./scripts/resolve-avm-version.sh storage/storage-account
# Returns: 0.32.0
```

**Confirmed working versions (May 2026 — verify before use):**

| Module | Version |
|---|---|
| `avm/res/operational-insights/workspace` | `0.15.0` |
| `avm/res/insights/component` | `0.7.1` |
| `avm/res/web/serverfarm` | `0.7.0` |
| `avm/res/web/site` | `0.22.0` |
| `avm/res/key-vault/vault` | `0.13.3` |
| `avm/res/web/static-site` | `0.9.3` |
| `avm/res/storage/storage-account` | `0.32.0` |

Always run `./scripts/resolve-avm-version.sh` to get the latest — the table above is a starting point.

### After Writing Bicep — Restore and Validate

```bash
# Pull modules into local .bicep/modules cache
az bicep restore --file outputs/bicep-templates/main.bicep --force

# Validate compilation — must exit 0 with no errors
az bicep build --file outputs/bicep-templates/main.bicep
```

---

## Module File Structure

Create one module per logical resource group:

| Module file | Responsibility |
|---|---|
| `modules/networking.bicep` | VNet, subnets, NSGs, private DNS zones |
| `modules/storage.bicep` | Storage accounts, private endpoints for storage |
| `modules/security.bicep` | Key Vault, private endpoints for KV, RBAC assignments |
| `modules/compute.bicep` | Function App, App Service Plan, App Insights |
| `modules/messaging.bicep` | Service Bus namespace and queues (if used) |
| `modules/monitoring.bicep` | Log Analytics workspace, diagnostic settings |

Root `main.bicep` — only parameters, module calls, and outputs:

```bicep
param environment string
param location string = resourceGroup().location
param workload string

module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: { environment: environment, location: location, workload: workload }
}

module security 'modules/security.bicep' = {
  name: 'security'
  params: {
    environment: environment
    location: location
    subnetId: networking.outputs.appSubnetId
  }
}

module compute 'modules/compute.bicep' = {
  name: 'compute'
  params: {
    environment: environment
    location: location
    keyVaultName: security.outputs.keyVaultName
    storageAccountName: storage.outputs.storageAccountName
  }
  dependsOn: [security, storage]
}
```

Dependency order (deploy in this sequence):
1. `networking` — no deps
2. `security` — depends on networking (subnet IDs)
3. `storage` — depends on networking (subnet IDs)
4. `monitoring` — no deps
5. `compute` — depends on security, storage, monitoring
6. `messaging` — depends on networking

---

## Step 4 — Common Pitfalls Checklist

Run through these before declaring Bicep complete.

### 1. App Service Plan Must Set `kind` and `reserved` for Linux

```bicep
module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'appPlanAvmDeploy'
  params: {
    name: planName
    skuName: 'Y1'
    kind: 'linux'    // REQUIRED for Linux
    reserved: true   // REQUIRED for Linux
  }
}
```
Omitting `kind: 'linux'` and `reserved: true` silently creates a Windows plan — Function App deploys but fails at runtime.

### 2. Set `linuxFxVersion` Explicitly

```bicep
siteConfig: {
  linuxFxVersion: 'PYTHON|3.11'   // uppercase, pipe-separated
  appSettings: [
    { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
  ]
}
```
Azure defaults to oldest registered runtime (Python 3.6) when `linuxFxVersion` is blank.

### 3. Storage Account Name Length (≤ 24 chars, alphanumeric only)

```bicep
// ✅ CORRECT — take(16) + 8 suffix = 24 chars max
var storageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}funcstor'
```
No hyphens in storage account names — they are alphanumeric only.

### 4. Role Assignment Name and Scope Cannot Use Module Outputs

ARM resolves `name` and `scope` at deployment start — module outputs are not available yet:

```bicep
// ✅ GOOD — compute locally using same formula as the module
var storageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}store'
resource containerRef 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${storageAccountName}/default/images'
}
resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-data-contributor')
  scope: containerRef
}
```

### 5. Subscription-Scope Deployments Require `scope: rg` on Modules

```bicep
targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module networking 'modules/networking.bicep' = {
  name: 'networkingDeploy'
  scope: rg   // ← required
  params: { ... }
}
```

### 6. Duplicate Deployment ID — Append `Avm` to Inner Module Names

Every module `name:` is an ARM nested deployment ID. If the name in `main.bicep` matches a name inside a child module, ARM throws a duplicate deployment ID error.

**Convention:** Append `Avm` to all inner AVM module `name:` values:
- Outer in `main.bicep`: `name: 'storageAccountDeploy'`
- Inner in `modules/storage.bicep`: `name: 'storageAccountAvmDeploy'`

### 7. Known Breaking Version Changes

| Module | Version | Breaking Change |
|---|---|---|
| `avm/res/web/serverfarm` | `0.7.0` | `skuTier` removed — use `skuName` only |
| `avm/res/storage/storage-account` | `0.32.0` | `deleteRetentionPolicy.{enabled,days}` flattened to `deleteRetentionPolicyEnabled` + `deleteRetentionPolicyDays` |

### 8. Do Not Set `experimentalFeaturesEnabled` in bicepconfig.json

```json
// ❌ Causes build warnings — remove this section entirely
{
  "experimentalFeaturesEnabled": { "extensibility": true }
}
```

---

## CloudFormation → Bicep Type Mapping

| CloudFormation | Bicep | Notes |
|---|---|---|
| `AWSTemplateFormatVersion` | Removed | Not needed in Bicep |
| `Parameters` | `param` | Parameter declarations |
| `Variables` | `var` | Variable declarations |
| `Resources` | `resource` or `module` | Resource declarations |
| `Outputs` | `output` | Output declarations |
| `!Ref` | `resourceName.id` / `resourceName.properties.xxx` | Context-dependent |
| `!Sub '${Var}text'` | `'${varName}text'` | Bicep string interpolation |
| `!GetAtt Resource.Attr` | `resourceName.properties.xxx` | Property path from resource type |
| `!Join ['', [a, b]]` | `'${a}${b}'` | Use interpolation or `join()` |
| `Fn::Select [i, list]` | `list[i]` | Array indexing |
| `Fn::If` | ternary `condition ? a : b` | Bicep conditional expressions |

---

## Rules

- **Never put resources directly in `main.bicep`** — use modules only.
- **Never create circular module dependencies** — if A needs B and B needs A, extract the shared resource into a third module.
- **Never create a module that exceeds ~150 lines** — split it.
- **Always output `resourceId`, `resourceName`, and `principalId`** (where applicable) from every module.
- **Use output references not `dependsOn`** wherever possible — output references are self-documenting.
- **Use `dependsOn` explicitly** only when the dependency exists but is not expressed through an output reference.
- **Every resource must use an AVM module** (`br/public:avm/res/...` or `br/public:avm/ptn/...`) — no raw `resource` declarations unless no AVM module exists.
- **Never vendor or copy AVM source into the repo** — reference modules via `br/public:avm/...`.
- **Cite the AVM module** in `outputs/bicep-templates/README.md` for each resource: "Selected per module-organization skill — `avm/res/storage/storage-account:0.32.0`".

## Output

- `outputs/bicep-templates/bicepconfig.json` — present with `modulePath: "bicep"`
- `outputs/bicep-templates/main.bicep` — contains only parameters, module declarations, and outputs
- `outputs/bicep-templates/modules/*.bicep` — one file per logical resource group, each under ~150 lines
- `az bicep restore --file outputs/bicep-templates/main.bicep --force` exits 0
- `az bicep build --file outputs/bicep-templates/main.bicep` exits 0

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/resolve-avm-version.ps1` | Resolves the latest published version tag for any AVM module from its CHANGELOG |
| `scripts/resolve-avm-version.sh` | Bash equivalent of the above |
| `scripts/validate-bicep.ps1` | Runs `az bicep restore` + `az bicep build` on every `.bicep` file; optionally runs what-if per environment |

Agents should run `validate-bicep.ps1` immediately after generating or modifying any Bicep file:

```powershell
./.github/skills/agents/iac-transformation/scripts/validate-bicep.ps1 \
    -ResourceGroup "rg-dev-migration" -Environment dev
```

Look up the correct AVM module version before pinning it in a `.bicepparam`:

```powershell
./.github/skills/agents/iac-transformation/scripts/resolve-avm-version.ps1 \
    -ModulePath "storage/storage-account"
```

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Verified Modules (AVM) home | https://azure.github.io/Azure-Verified-Modules/ |
| AVM Bicep resource modules index | https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/ |
| AVM Bicep pattern modules index | https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-pattern-modules/ |
| AVM versioning and changelog guidance | https://azure.github.io/Azure-Verified-Modules/specs/shared/versioning/ |
| Bicep modules documentation | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/modules |
| bicepconfig.json module aliases | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-config-modules |
| `az bicep restore` command | https://learn.microsoft.com/en-us/cli/azure/bicep#az-bicep-restore |
| ARM role assignment resource | https://learn.microsoft.com/en-us/azure/templates/microsoft.authorization/roleassignments |
| CloudFormation to Bicep migration | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/migrate-template |
| Bicep dependency management | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/resource-dependencies |
| Azure deployment scopes | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-to-subscription |

### AWS Documentation

| Topic | Link |
|---|---|
| CloudFormation resource type reference | https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html |
| CloudFormation intrinsic function reference | https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference.html |
| SAM resource and property reference | https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-specification-resources-and-properties.html |

### Best Practices

- **Always run `az bicep restore --force` before `az bicep build`** — AVM module references require the cache to be populated first; the build will fail with `artifact does not exist` if the cache is stale.
- **`modulePath: "bicep"` in bicepconfig.json is the only correct value** — `"bicep/public"` does not exist in MCR and causes a confusing registry error.
- **Append `Avm` to all inner AVM module `name:` values** — duplicate deployment IDs cause ARM 409 conflicts when the same name is used at both the outer and inner module level.
- **Always validate breaking changes** between AVM versions before upgrading — check the CHANGELOG at `https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/<module>/CHANGELOG.md`.
