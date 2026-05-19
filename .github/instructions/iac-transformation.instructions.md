---
name: iac-transformation-instructions
description: Custom instructions for IaC Transformation Agent
applyTo: iac-transformation
---

# IaC Transformation Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All output must go to `outputs/bicep-templates/`.

### Golden Rule
- Use the detailed design document for reference and guidance in outoputs/azure-architecture-output/

## Bicep Conversion Standards

### CloudFormation to Bicep Type Mapping

**Structural Elements:**

| CloudFormation | Bicep | Notes |
|---|---|---|
| `AWSTemplateFormatVersion` | Removed | Not needed in Bicep |
| `Parameters` | `param` | Parameter declarations |
| `Variables` | `var` | Variable declarations |
| `Resources` | `resource` | Resource declarations |
| `Outputs` | `output` | Output declarations |
| `!Ref` | Reference expression | `resourceName.id` or `resourceName.properties.xxx` |
| `!Sub` | String interpolation | `'${variable}text${variable}'` |
| `!GetAtt` | Property access | `resourceName.id` or `resourceName.properties.xxx` |
| `!Join` | String functions | Built-in `join()` function |

### Example: Full Template Conversion

**CloudFormation:**
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'AWS Resources'

Parameters:
  EnvironmentName:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]

Resources:
  MyRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${EnvironmentName}-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: 'sts:AssumeRole'

Outputs:
  RoleArn:
    Value: !GetAtt MyRole.Arn
```

**Bicep:**
```bicep
param environmentName string = 'dev'

@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = environmentName

resource myRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' = {
  name: guid(subscription().id, '${environment}-role')
  properties: {
    roleName: '${environment}-role'
    // ... other properties
  }
}

output roleId string = myRole.id
```

## AVM Module Registry Configuration

### bicepconfig.json Setup

**CRITICAL:** The `modulePath` must be set to `"bicep"` — do **not** use `"bicep/public"`:

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

The AVM registry resolves to: `mcr.microsoft.com/bicep/avm/res/...`
Using `"bicep/public"` incorrectly resolves to `mcr.microsoft.com/bicep/public/avm/res/...` (does not exist → "artifact does not exist in registry" error on all modules).

### AVM Module Version Verification

**Always verify module versions from the official CHANGELOG — do not guess:**

```bash
# CHANGELOG URL pattern:
# https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/<provider>/<module>/CHANGELOG.md
# Examples:
# https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/web/site/CHANGELOG.md
# https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/storage/storage-account/CHANGELOG.md
```

**After updating module versions, always restore and validate:**

```bash
# Restore modules to local cache after any version change
az bicep restore --file main.bicep --force

# Validate compilation — must exit with no errors
az bicep build --file main.bicep
```

**Always read the CHANGELOG for breaking changes between versions.** AVM modules regularly alter parameter schemas (flattening nested objects, removing deprecated params) between releases.

### Confirmed Working AVM Module Versions

The following versions were verified and produce clean builds:

| Module | Version |
|---|---|
| `avm/res/operational-insights/workspace` | `0.15.0` |
| `avm/res/insights/component` | `0.7.1` |
| `avm/res/web/serverfarm` | `0.7.0` |
| `avm/res/web/site` | `0.22.0` |
| `avm/res/key-vault/vault` | `0.13.3` |
| `avm/res/web/static-site` | `0.9.3` |
| `avm/res/storage/storage-account` | `0.32.0` |

## Bicep Common Pitfalls

### RoleAssignment Name and Scope

**CRITICAL:** `roleAssignment` `name` and `scope` must use values ARM can compute at deployment start — **never use module outputs**:

```bicep
// ❌ BAD - scope/name derived from module output (ARM cannot resolve at deploy start)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.outputs.storageAccountName, ...)
  scope: someContainer
  ...
}

// ✅ GOOD - compute the storage name locally using the same formula as the module
var imagesStorageAccountNameLocal = take(toLower(replace('${resourceNamePrefix}store', '-', '')), 24)

resource imagesContainerRef 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${imagesStorageAccountNameLocal}/default/images'
}

resource funcStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-data-contributor')
  scope: imagesContainerRef
  properties: { ... }
}
```

### Storage Account Name Length

Storage account names must be **1–24 characters**, lowercase, alphanumeric only (no hyphens). When building concatenated names, account for the full resulting length:

```bicep
// ❌ BAD - 'funcstor' is 8 chars; take(17) + 8 = 25 chars (exceeds 24-char max)
var funcStorageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 17)}funcstor'

// ✅ GOOD - take(16) + 8 = 24 chars (exactly at limit)
var funcStorageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}funcstor'
```

### AVM Schema Changes Between Versions

AVM modules introduce breaking parameter changes between releases. Always read CHANGELOG before upgrading.

**Known breaking changes:**

| Module | Version | Change |
|---|---|---|
| `avm/res/web/serverfarm` | `0.7.0` | Only `skuTier` was removed. `kind` and `reserved` are **still required** for Linux plans. Always set `kind: 'linux'` and `reserved: true` — omitting them silently creates a **Windows** App Service Plan. |
| `avm/res/storage/storage-account` | `0.32.0` | `blobServices.deleteRetentionPolicy.{enabled,days}` flattened to top-level `blobServices.deleteRetentionPolicyEnabled` and `blobServices.deleteRetentionPolicyDays` (same pattern for `containerDeleteRetentionPolicy*`) |

### App Service Plan OS — Always Derive from Reference Documents

**Before writing any App Service Plan or Function App Bicep**, check the architecture reference documents to determine the target OS:
- `outputs/azure-architecture-output/azure-architecture-summary.md`
- `outputs/azure-architecture-output/service-mapping.md`

Then apply the correct parameters for `avm/res/web/serverfarm`:

| Target OS | Required params | Function App `kind` |
|---|---|---|
| **Linux** | `kind: 'linux'`, `reserved: true` | `'functionapp,linux'` |
| **Windows** | `kind: 'app'` (or omit — default) | `'functionapp'` |

> **Why this matters:** Omitting `kind`/`reserved` silently defaults to **Windows**, even when the Function App or runtime (e.g. Python, Node on Linux) requires Linux. Azure will not error at plan creation — it fails later when the site is deployed.

```bicep
// ✅ Linux Consumption plan (Python / Node on Linux)
module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  params: {
    name: 'my-plan'
    skuName: 'Y1'
    kind: 'linux'
    reserved: true
  }
}

// ✅ Windows Consumption plan (.NET / PowerShell)
module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  params: {
    name: 'my-plan'
    skuName: 'Y1'
    kind: 'app'
    // reserved defaults to false — Windows
  }
}
```

This applies to all SKUs (Y1 Consumption, EP1/EP2/EP3 Premium, B1/P1v3 dedicated).

### Function App linuxFxVersion — Always Set Explicitly

**Always** set `siteConfig.linuxFxVersion` to the runtime version required by the application code. Leaving it as an empty string causes Azure to default to the **oldest registered runtime** (e.g. `PYTHON|3.6`), not the latest.

- Format: `LANGUAGE|version` in **uppercase** (e.g. `PYTHON|3.11`, `NODE|20`, `DOTNET|8`)
- Check the application code and `requirements.txt` / `package.json` to determine the correct version
- Azure Functions v4 supports Python **3.9, 3.10, 3.11 only** — use `PYTHON|3.11` unless the reference docs specify otherwise

```bicep
// ❌ BAD — Azure defaults to Python 3.6 (oldest registered runtime)
siteConfig: {
  linuxFxVersion: ''
}

// ✅ GOOD — explicitly pin to the version required by the application code
siteConfig: {
  linuxFxVersion: 'PYTHON|3.11'
  appSettings: [
    { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
  ]
}
```

### Avoid Unnecessary experimentalFeaturesEnabled

Do **not** set `experimentalFeaturesEnabled` in `bicepconfig.json` unless explicitly required by a feature. Leaving it causes build warnings. Remove the section entirely if it is not needed.

### Duplicate Nested Deployment Names

**CRITICAL:** Every `module` declaration has a `name:` property that ARM uses as the nested deployment ID within its scope. If the outer module name in `main.bicep` matches the inner AVM module name inside the child module file, ARM throws:

```
Duplicate parent and nested deployment ID '.../<name>' found in deployment.
```

**Rule:** The `name:` inside an AVM module call (inside a child `.bicep` file) must **never match** the `name:` used for that child module in `main.bicep`.

```bicep
// main.bicep
module staticWebApp 'modules/staticweb.bicep' = {
  name: 'staticWebAppDeploy'   // ← outer name
  ...
}

// modules/staticweb.bicep — inner AVM call
// ❌ BAD — same name causes duplicate deployment ID error
module staticWebApp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'staticWebAppDeploy'   // ← clashes with outer name above
}

// ✅ GOOD — suffix inner AVM calls with 'Avm' to guarantee uniqueness
module staticWebApp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'swaAvmDeploy'
}
```

**Convention:** Suffix all inner AVM module `name:` values with `Avm` (e.g. `swaAvmDeploy`, `kvAvmDeploy`, `storageAccountAvmDeploy`) so they can never collide with the outer module names in `main.bicep`.

### Subscription-Scope Deployments

When `targetScope = 'subscription'`, inline `resource` declarations cannot reference resources in a resource group. Follow this pattern:

1. **Create the resource group** as a `resource` in `main.bicep`:
   ```bicep
   resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
     name: resolvedResourceGroupName
     location: location
   }
   ```

2. **Add `scope: rg` to every module** call in `main.bicep`.

3. **Move any `existing` resource + role assignment** that targets a resource-group-scoped resource into a dedicated module (e.g. `modules/rbac.bicep`) and call it with `scope: rg`. ARM does not allow an `existing` resource at a different scope than the Bicep file's own `targetScope`.

## Pipeline Update Standards

### Buildkite Pipeline Structure

**Required Sections:**

```yaml
env:
  # Azure environment variables
  AZURE_SUBSCRIPTION_ID: "${BUILDKITE_PIPELINE_SLUG}"
  AZURE_RESOURCE_GROUP: "rg-${BUILDKITE_BRANCH}"

steps:
  # 1. Validation stage
  - label: "Validate"
    commands:
      - "az bicep build --file main.bicep"
    
  # 2. What-if preview stage
  - label: "Plan"
    commands:
      - "az deployment group what-if ..."
    
  # 3. Deployment stage (with approval gate for prod)
  - label: "Deploy"
    commands:
      - "az deployment group create ..."
    block: |
      Production deployment requires approval
    if: build.branch == "main"
    
  # 4. Validation and testing stage
  - label: "Validate Deployment"
    commands:
      - "npm run test:integration"
```

### Service Principal Authentication

**Setup in Buildkite:**

```bash
# Set these secrets in Buildkite
# AZURE_CLIENT_ID
# AZURE_CLIENT_SECRET
# AZURE_TENANT_ID
# AZURE_SUBSCRIPTION_ID
```

**Use in pipeline:**

```yaml
steps:
  - label: "Deploy"
    commands:
      - |
        az login --service-principal \
          -u $AZURE_CLIENT_ID \
          -p $AZURE_CLIENT_SECRET \
          --tenant $AZURE_TENANT_ID
      - |
        az account set --subscription $AZURE_SUBSCRIPTION_ID
      - |
        az deployment group create \
          --resource-group $AZURE_RESOURCE_GROUP \
          --template-file main.bicep
```

## Deployment Safety Measures

### Pre-Deployment Validation

**Checklist:**

1. **Syntax Validation** - Bicep files must compile
   ```bash
   az bicep build --file main.bicep
   ```

2. **What-If Analysis** - Preview changes
   ```bash
   az deployment group what-if \
     --resource-group myRg \
     --template-file main.bicep
   ```

3. **Policy Compliance** - Check Azure Policies
   ```bash
   az policy state summarize \
     --resource-group myRg
   ```

4. **Cost Estimation** - Verify costs
   - Use Azure Pricing Calculator
   - Compare with baseline

### Post-Deployment Validation

**Health Checks:**

```bash
#!/bin/bash
# Post-deployment validation

echo "Checking resource health..."

# 1. Verify all resources deployed
az resource list --resource-group $RG_NAME --output table

# 2. Check for failed resources
az resource list \
  --resource-group $RG_NAME \
  --query "[?properties.provisioningState=='Failed']"

# 3. Run application health checks
npm run test:smoke

# 4. Verify monitoring and alerts
az monitor alert list --resource-group $RG_NAME
```

## Resource Modularization

### Output Location

**All generated Bicep artifacts must be written to `outputs/bicep-templates/`:**

```
outputs/
└── bicep-templates/
    ├── main.bicep
    ├── bicepconfig.json
    ├── modules/
    │   ├── networking.bicep
    │   ├── compute.bicep
    │   ├── storage.bicep
    │   └── security.bicep
    └── parameters/
        ├── dev.bicepparam
        ├── staging.bicepparam
        └── prod.bicepparam
```

Do **not** write output directly to the workspace root or to `bicep-templates/` — always use `outputs/bicep-templates/`.

### Module Organization Strategy

**Single Responsibility Principle:**

```bicep
// ❌ BAD - Too large, mixed concerns
// modules/everything.bicep
// Contains: networking + compute + database + storage

// ✅ GOOD - Focused modules
// modules/networking.bicep - VNets, subnets, NSGs
// modules/compute.bicep - Functions, App Service
// modules/database.bicep - Azure Database
// modules/storage.bicep - Storage accounts
// modules/security.bicep - Key Vault, RBAC
```

### Module Composition

```bicep
// main.bicep - Orchestrate modules
module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    environment: environment
    vnetCidr: vnetCidr
  }
}

module compute 'modules/compute.bicep' = {
  name: 'compute'
  params: {
    location: location
    environment: environment
    subnetId: networking.outputs.subnetId
    // Dependency on networking module
  }
}

module database 'modules/database.bicep' = {
  name: 'database'
  params: {
    location: location
    environment: environment
    vnetId: networking.outputs.vnetId
    // Dependency on networking module
  }
}
```

## Parameter Management

### Parameter File Format

**REQUIRED:** All parameter files must use the `.bicepparam` format — **do not use JSON parameter files** (`.parameters.json`).

Each `.bicepparam` file must begin with a `using` declaration referencing the parent template:

```bicepparam
using '../main.bicep'

param environment = 'dev'
param location = 'eastus'
```

Files must be named for their environment and placed in `outputs/bicep-templates/parameters/`:
- `dev.bicepparam`
- `staging.bicepparam`
- `prod.bicepparam`

### Parameter File Organization

```bicepparam
// parameters/dev.bicepparam
using './main.bicep'

// Environment settings
param environment = 'dev'
param location = 'eastus'

// Networking
param vnetCidr = '10.0.0.0/16'
param subnetCidr = '10.0.1.0/24'

// Sizing
param functionPlanSku = 'Y1'  // Consumption for dev
param databaseSku = 'Standard_B1s'  // Burstable for dev

// Features
param enableMonitoring = false
param enableDisasterRecovery = false
```

```bicepparam
// parameters/production.bicepparam
using './main.bicep'

// Environment settings
param environment = 'production'
param location = 'eastus'

// Networking
param vnetCidr = '10.0.0.0/16'
param subnetCidr = '10.0.1.0/24'

// Sizing
param functionPlanSku = 'EP2'  // Premium for production
param databaseSku = 'Standard_D4s_v3'  // Larger for production

// Features
param enableMonitoring = true
param enableDisasterRecovery = true
```

## Rollback Procedures

### Deployment Tracking

**Track all deployments:**

```bash
# List deployments for a resource group
az deployment group list --resource-group myRg \
  --query "[].{name:name, timestamp:properties.timestamp, state:properties.provisioningState}" \
  --output table

# Get deployment details
az deployment group show --name myDeployment --resource-group myRg

# Get deployment operations (what changed)
az deployment group operation list --name myDeployment --resource-group myRg
```

### Rollback Strategy

**Automatic Rollback on Failure:**

```bash
#!/bin/bash
# Deploy with automatic rollback on failure

DEPLOYMENT_NAME="deploy-$(date +%s)"
RESOURCE_GROUP=$1

az deployment group create \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters parameters/prod.bicepparam \
  --rollback-on-error

if [ $? -ne 0 ]; then
  echo "Deployment failed - automatically rolled back"
  exit 1
fi

echo "Deployment successful: $DEPLOYMENT_NAME"
```

**Manual Rollback to Specific Deployment:**

```bash
#!/bin/bash
# Manually redeploy a previous version

TARGET_DEPLOYMENT=$1
RESOURCE_GROUP=$2

# Get the template from target deployment
az deployment group show \
  --name $TARGET_DEPLOYMENT \
  --resource-group $RESOURCE_GROUP \
  --query properties.template > /tmp/rollback-template.json

# Re-deploy
az deployment group create \
  --name "rollback-$(date +%s)" \
  --resource-group $RESOURCE_GROUP \
  --template-file /tmp/rollback-template.json
```

## Conversion Report Format

**Required Sections:**

```markdown
# IaC Conversion Report

## Summary
- Templates converted: 5
- Resources migrated: 47
- Conversion status: Complete ✅

## CloudFormation to Bicep Mapping

| CloudFormation File | Bicep Modules | Resource Count | Notes |
|---|---|---|---|
| network-stack.yaml | modules/networking.bicep | 8 | VPC converted to VNet |
| compute-stack.yaml | modules/compute.bicep | 12 | Lambda → Functions |
| database-stack.yaml | modules/database.bicep | 3 | RDS → Azure Database |
| storage-stack.yaml | modules/storage.bicep | 5 | S3 → Blob Storage |
| security-stack.yaml | modules/security.bicep | 19 | IAM → RBAC |

## Parameter Mapping

### New Parameters (Azure-specific)
- `location`: Azure region for deployment
- `environment`: Deployment environment (dev/staging/prod)
- `enableZoneRedundancy`: Zone redundancy for HA

### Removed Parameters (AWS-specific)
- `AvailabilityZones`: Azure uses availability sets/zones differently
- `InstanceTypes`: Replaced with Azure SKUs

## Key Conversions

### Networking
- EC2 VPC → Virtual Network
- Subnet → Subnet
- Security Group → Network Security Group
- VPC Endpoint → Private Endpoint

### Compute
- Lambda → Azure Functions (Premium Plan)
- ECS → Container Instances (or AKS)
- EC2 Auto Scaling → Virtual Machine Scale Sets

### Database
- RDS PostgreSQL → Azure Database for PostgreSQL (Flexible Server)
- DynamoDB → Cosmos DB

### Storage
- S3 → Blob Storage
- Lifecycle Rules → Management Policy (equivalent)

## Validation Results

- ✅ Bicep validation: PASSED
- ✅ What-if analysis: PASSED
- ✅ Policy compliance: PASSED
- ✅ Resource limits: PASSED
- ✅ Cost estimation: PASSED

## Deployment Readiness

- [x] Bicep templates validated
- [x] Parameter files created for all environments
- [x] Buildkite pipeline updated
- [x] Deployment scripts created
- [x] Rollback procedures documented
- [x] Post-deployment validation defined
- [x] Team trained on deployment process

## Next Steps

1. Test deployment to development environment
2. Validate post-deployment monitoring
3. Perform smoke tests on application
4. Review cost metrics
5. Prepare for staging/production deployment
```

## Tips & Best Practices

✅ **Do:**
- Test Bicep files with `az bicep build`
- Always run what-if before deployment
- Version control parameter files separately
- Document all conversions
- Use meaningful resource naming
- Include detailed comments in Bicep
- Test rollback procedures
- Validate post-deployment

❌ **Don't:**
- Skip syntax validation
- Deploy to production without staging test
- Hardcode values in templates
- Forget to update pipelines
- Skip backup before deployment
- Deploy without monitoring setup
- Ignore what-if warnings
- Assume resource parity

## Common Conversion Issues

### Issue: CloudFormation Intrinsic Function Not Direct Equivalent

**Example:** `!Sub` with complex logic

**Solution:**
```bicep
// CloudFormation
!Sub 'arn:aws:s3:::${BucketName}/*'

// Bicep equivalent
'arn:microsoft:storage:${storageAccountName}/*'
```

### Issue: AWS-Specific Properties Have No Azure Equivalent

**Example:** EC2 AMI selection

**Solution:**
- Document in conversion report
- Make it a parameter
- Let user choose in parameter file
- Suggest Azure equivalent approach

### Issue: Circular Module Dependencies

**Solution:**
- Reorganize modules to eliminate cycles
- Use conditional resource creation
- Pass required outputs between modules
- Flatten module hierarchy if needed

---

**Last Updated:** December 2024  
**Version:** 1.0
