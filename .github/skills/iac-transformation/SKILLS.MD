---
name: avm-bicep
description: >
  Azure Verified Modules (AVM) selection and usage skill for Bicep IaC generation.
  Given an AWS service to migrate or an Azure resource to provision, this skill tells
  the agent WHICH AVM module to use, HOW to reference it, HOW to resolve the correct
  version, and WHAT pitfalls to avoid. Use this skill as the primary decision guide
  whenever writing Bicep templates in this project.
---

# AVM Bicep Skill

## What Is AVM

Azure Verified Modules (AVM) are Microsoft-owned, tested, and versioned Bicep modules published to the Microsoft Container Registry (MCR). Using AVM avoids writing raw resource declarations for common Azure services — modules encapsulate best-practice defaults, RBAC wiring, diagnostics, and private-endpoint support.

Registry: `mcr.microsoft.com/bicep/avm/...`
Index:    https://azure.github.io/Azure-Verified-Modules/indexes/bicep/
Source:   https://github.com/Azure/bicep-registry-modules

Module types:
- **res/** — Single resource module (one Azure resource type)
- **ptn/** — Pattern module (multi-resource opinionated deployment)
- **utl/** — Utility module (helpers, not deployable resources)

---

## Step 1 — Configure bicepconfig.json (Mandatory First Step)

Every project that uses AVM modules MUST have this file at the Bicep root:

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
- Correct resolution: `mcr.microsoft.com/bicep/avm/res/storage/storage-account:0.32.0`
- Wrong resolution: `mcr.microsoft.com/bicep/public/avm/res/...` (does not exist — causes "artifact does not exist in registry" on every module)

Reference syntax in Bicep:
```bicep
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = { ... }
```

---

## Step 2 — Module Selection Decision Tree

### How to Pick the Right Module

```
Is there an AVM ptn/ (pattern) module that covers the full scenario?
  YES → Use ptn/ module (preferred — includes networking, RBAC, monitoring wiring)
  NO  → Is there an AVM res/ (resource) module for the Azure service?
          YES → Use res/ module
          NO  → Write raw Bicep resource declaration
```

Pattern modules to prefer over resource modules when applicable:
- Multi-spoke hub networking → `ptn/network/hub-networking`
- AKS full cluster → `ptn/azd/aks`
- Container Apps full stack → `ptn/azd/container-apps-stack`
- Private DNS zones for Private Link → `ptn/network/private-link-private-dns-zones`
- RBAC role assignment (cross-scope) → `ptn/authorization/role-assignment`
- AI Foundry stack → `ptn/ai-ml/ai-foundry`

---

## Step 3 — AWS → Azure → AVM Module Mapping

### Compute

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| Lambda (event-driven) | Azure Functions | `res/web/site` + `res/web/serverfarm` | kind='functionapp' or 'functionapp,linux' |
| Lambda (container) | Azure Container Apps Job | `res/app/job` | Preferred for containerised functions |
| ECS Fargate | Azure Container Apps | `res/app/container-app` + `res/app/managed-environment` | Or use `ptn/azd/container-apps-stack` |
| ECS EC2 | AKS + node pools | `res/container-service/managed-cluster` | Or `ptn/azd/aks` |
| EKS | AKS | `res/container-service/managed-cluster` | Or `ptn/azd/aks` |
| EC2 | Azure Virtual Machine | `res/compute/virtual-machine` | |
| Auto Scaling Group | VMSS | `res/compute/virtual-machine-scale-set` | |
| Elastic Beanstalk | App Service | `res/web/site` + `res/web/serverfarm` | kind='app' |
| App Runner | Container Apps | `res/app/container-app` | |
| Batch | Azure Batch | `res/batch/batch-account` | |

### Networking

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| VPC | Virtual Network | `res/network/virtual-network` | |
| Security Group | Network Security Group | `res/network/network-security-group` | |
| ALB / NLB | Application Gateway / Load Balancer | `res/network/application-gateway` or `res/network/load-balancer` | ALB→AppGW, NLB→LB |
| Route 53 (public) | Azure DNS Zone | `res/network/dns-zone` | |
| Route 53 (private) | Private DNS Zone | `res/network/private-dns-zone` | |
| VPC Endpoint | Private Endpoint | `res/network/private-endpoint` | |
| NAT Gateway | NAT Gateway | `res/network/nat-gateway` | |
| Internet Gateway | (implicit in VNet) | None — VNet has outbound by default | |
| VPC Peering | VNet Peering | `res/network/virtual-network-peering` | Child of VNet module |
| Transit Gateway | Virtual WAN | `ptn/network/virtual-wan` or `res/network/virtual-wan-hub` | |
| Direct Connect | ExpressRoute | `res/network/express-route-circuit` + `res/network/express-route-gateway` | |
| VPN Gateway | VPN Gateway | `res/network/virtual-network-gateway` | |
| CloudFront | Azure Front Door / CDN | `res/cdn/profile` | |
| WAF (Regional) | App Gateway WAF | `res/network/application-gateway-web-application-firewall-policy` | |
| AWS Firewall | Azure Firewall | `res/network/azure-firewall` | |
| Bastion | Azure Bastion | `res/network/bastion-host` | |
| Private Link DNS (all zones) | Private Link Private DNS Zones | `ptn/network/private-link-private-dns-zones` | Use ptn/ — covers all 200+ zones |

### Storage

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| S3 | Azure Blob Storage | `res/storage/storage-account` | kind='StorageV2' |
| S3 Static Website | Static Web App | `res/web/static-site` | |
| EFS | Azure Files (in Storage Account) | `res/storage/storage-account` | fileServices enabled |
| FSx | NetApp Files | `res/net-app/net-app-account` | |
| EBS | Managed Disk | `res/compute/disk` | Usually inline with VM module |
| Glacier | Archive tier (Storage lifecycle) | `res/storage/storage-account` | managementPolicies |

### Database

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| RDS PostgreSQL | Azure Database for PostgreSQL Flexible | `res/db-for-postgre-sql/flexible-server` | |
| RDS MySQL | Azure Database for MySQL Flexible | `res/db-for-my-sql/flexible-server` | |
| RDS SQL Server | Azure SQL Database / Managed Instance | `res/sql/server` | |
| Aurora PostgreSQL | Azure Database for PostgreSQL Flexible | `res/db-for-postgre-sql/flexible-server` | HA mode |
| Aurora MySQL | Azure Database for MySQL Flexible | `res/db-for-my-sql/flexible-server` | HA mode |
| DynamoDB | CosmosDB | `res/document-db/database-account` | NoSQL API |
| DocumentDB | CosmosDB MongoDB API | `res/document-db/mongo-cluster` | |
| ElastiCache Redis | Azure Cache for Redis | `res/cache/redis` | |
| ElastiCache Redis Enterprise | Azure Cache for Redis Enterprise | `res/cache/redis-enterprise` | |
| Redshift | Synapse Analytics | `res/synapse/workspace` | |
| Keyspaces | CosmosDB Cassandra API | `res/document-db/database-account` | Cassandra API |

### Messaging & Events

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| SQS | Azure Service Bus (queue) | `res/service-bus/namespace` | Standard or Premium tier |
| SNS | Azure Service Bus (topic) or Event Grid | `res/service-bus/namespace` or `res/event-grid/topic` | |
| EventBridge | Azure Event Grid | `res/event-grid/namespace` or `res/event-grid/topic` | |
| Kinesis Data Streams | Azure Event Hubs | `res/event-hub/namespace` | |
| Kinesis Firehose | Azure Event Hubs + Stream Analytics | `res/event-hub/namespace` | |
| MSK (Kafka) | Azure Event Hubs (Kafka endpoint) | `res/event-hub/namespace` | Enable Kafka |
| MQ (RabbitMQ) | Azure Service Bus Premium | `res/service-bus/namespace` | Premium tier supports AMQP |
| Step Functions | Logic Apps or Durable Functions | `res/logic/workflow` | |

### Security & Identity

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| IAM Role (service) | Managed Identity | `res/managed-identity/user-assigned-identity` | Or system-assigned (inline) |
| IAM Role (user) | Azure RBAC role assignment | `ptn/authorization/role-assignment` | |
| IAM Policy | Azure Policy or RBAC | `res/authorization/policy-assignment` | |
| Secrets Manager | Azure Key Vault | `res/key-vault/vault` | Secrets + Certs + Keys |
| KMS | Azure Key Vault (keys) | `res/key-vault/vault` | CMK scenarios |
| SSM Parameter Store | App Configuration or Key Vault | `res/app-configuration/configuration-store` | |
| Cognito | Azure AD B2C / Entra External ID | No AVM module — use Entra portal | |
| WAF (CloudFront) | Azure Front Door WAF | `res/network/front-door-web-application-firewall-policy` | |

### Monitoring & Observability

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| CloudWatch Logs | Log Analytics Workspace | `res/operational-insights/workspace` | |
| CloudWatch Metrics | Azure Monitor (built-in) | `res/insights/metric-alert` | |
| CloudWatch Alarms | Azure Monitor Alerts | `res/insights/metric-alert` or `res/insights/scheduled-query-rule` | |
| X-Ray | Application Insights | `res/insights/component` | |
| CloudTrail | Azure Monitor Activity Log | `res/insights/diagnostic-setting` | |
| CloudWatch Dashboard | Azure Dashboard | `res/portal/dashboard` | |

### CI/CD & DevOps

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| CodePipeline / CodeBuild | GitHub Actions / Azure DevOps | No AVM — configure pipelines directly | |
| ECR | Azure Container Registry | `res/container-registry/registry` | |
| Systems Manager | Azure Arc / VM extensions | `res/hybrid-compute/machine` | |

### AI / ML

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| SageMaker | Azure Machine Learning | `res/machine-learning-services/workspace` | Or `ptn/ai-ml/ai-foundry` |
| Bedrock | Azure OpenAI (Cognitive Services) | `res/cognitive-services/account` | kind='OpenAI' |
| Comprehend / Rekognition | Cognitive Services | `res/cognitive-services/account` | |
| Lex | Azure Bot Service | `res/cognitive-services/account` | |

### Data & Analytics

| AWS Service | Azure Equivalent | AVM Module | Notes |
|---|---|---|---|
| Glue | Azure Data Factory | `res/data-factory/factory` | |
| Athena | Synapse Serverless SQL | `res/synapse/workspace` | |
| EMR | HDInsight or Synapse Spark | `res/synapse/workspace` | |
| OpenSearch / Elasticsearch | Azure Cognitive Search | `res/search/search-service` | |
| IoT Core | Azure IoT Hub | `res/devices/iot-hub` | |

---

## Step 4 — Resolve Module Version

**NEVER hardcode a version without verifying it exists.** Always resolve from the official CHANGELOG:

```
CHANGELOG URL pattern:
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/<provider>/<module>/CHANGELOG.md

Examples:
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/storage/storage-account/CHANGELOG.md
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/web/site/CHANGELOG.md
https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/network/virtual-network/CHANGELOG.md
```

Use the script at `scripts/resolve-avm-version.sh` to automate this:

```bash
./scripts/resolve-avm-version.sh storage/storage-account
# Returns: 0.32.0
```

### Confirmed Working Versions (as of May 2026)

| Module | Version |
|---|---|
| `avm/res/operational-insights/workspace` | `0.15.0` |
| `avm/res/insights/component` | `0.7.1` |
| `avm/res/web/serverfarm` | `0.7.0` |
| `avm/res/web/site` | `0.22.0` |
| `avm/res/key-vault/vault` | `0.13.3` |
| `avm/res/web/static-site` | `0.9.3` |
| `avm/res/storage/storage-account` | `0.32.0` |

> Always run `./scripts/resolve-avm-version.sh` to get the latest — the table above is a starting point, not a guarantee.

---

## Step 5 — Write the Module Declaration

### Standard Pattern

```bicep
// Reference format: br/public:avm/<type>/<provider>/<module>:<version>
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storageAccountAvmDeploy'   // ← suffix 'Avm' to avoid duplicate deployment name errors
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
  }
}
```

### Critical Naming Rule

Every module `name:` property is an ARM nested deployment ID. If the name in `main.bicep` (outer) matches the name used inside a child module file (inner), ARM throws:

```
Duplicate parent and nested deployment ID '.../<name>' found in deployment.
```

**Convention:** Append `Avm` to all inner AVM module `name:` values:
- Outer module in `main.bicep`: `name: 'storageAccountDeploy'`
- Inner AVM call inside `modules/storage.bicep`: `name: 'storageAccountAvmDeploy'`

---

## Step 6 — Restore and Validate

After writing any Bicep file that references AVM modules:

```bash
# Pull modules into local .bicep/modules cache
az bicep restore --file main.bicep --force

# Validate compilation — must exit 0 with no errors
az bicep build --file main.bicep
```

Use `scripts/validate-avm-modules.sh` to validate all Bicep files in the project at once.

---

## Common Pitfalls and How to Avoid Them

### 1. App Service Plan OS Must Match Runtime

For Linux runtimes (Python, Node on Linux, containers):

```bicep
module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'appPlanAvmDeploy'
  params: {
    name: planName
    skuName: 'Y1'         // Consumption
    kind: 'linux'         // REQUIRED for Linux
    reserved: true        // REQUIRED for Linux
  }
}
```

Omitting `kind: 'linux'` and `reserved: true` silently creates a Windows plan — the Function App deploys but fails at runtime.

### 2. linuxFxVersion Must Be Explicit

```bicep
// ✅ CORRECT
siteConfig: {
  linuxFxVersion: 'PYTHON|3.11'   // uppercase, pipe-separated
  appSettings: [
    { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
  ]
}

// ❌ WRONG — Azure defaults to oldest registered runtime (Python 3.6)
siteConfig: {
  linuxFxVersion: ''
}
```

Azure Functions v4 supports Python 3.9, 3.10, 3.11 only. Use `PYTHON|3.11` unless source code specifies otherwise.

### 3. Storage Account Name Length

Names must be 1–24 characters, lowercase, alphanumeric only (no hyphens):

```bicep
// ✅ CORRECT — take(16) + 8 suffix = 24 chars max
var storageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}funcstor'

// ❌ WRONG — take(17) + 8 = 25 chars (exceeds 24-char max)
var storageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 17)}funcstor'
```

### 4. RoleAssignment Name and Scope Cannot Use Module Outputs

ARM resolves `name` and `scope` at deployment start — module outputs are not available yet:

```bicep
// ❌ BAD — scope/name from module output, ARM cannot resolve at deploy start
resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageModule.outputs.storageAccountName, ...)
  scope: storageModule.outputs.containerRef
}

// ✅ GOOD — compute locally using the same formula as the module
var storageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}store'
resource containerRef 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${storageAccountName}/default/images'
}
resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-data-contributor')
  scope: containerRef
}
```

### 5. Subscription-Scope Deployments

When `targetScope = 'subscription'`, every module must have `scope: rg`:

```bicep
targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module networking 'modules/networking.bicep' = {
  name: 'networkingDeploy'
  scope: rg           // ← required
  params: { ... }
}
```

Any `existing` resource that targets a resource-group-scoped resource must also go into a dedicated module called with `scope: rg`.

### 6. AVM Schema Breaking Changes

Always read the CHANGELOG before bumping a module version. Known breaking changes:

| Module | Version | Change |
|---|---|---|
| `avm/res/web/serverfarm` | `0.7.0` | `skuTier` removed. `kind` and `reserved` still required for Linux plans |
| `avm/res/storage/storage-account` | `0.32.0` | `blobServices.deleteRetentionPolicy.{enabled,days}` flattened to `blobServices.deleteRetentionPolicyEnabled` and `blobServices.deleteRetentionPolicyDays` |

### 7. Do Not Set experimentalFeaturesEnabled

Removing this from `bicepconfig.json` eliminates build warnings:

```json
// ❌ Causes warnings
{
  "experimentalFeaturesEnabled": { "extensibility": true }
}

// ✅ Remove the section entirely if not required
```

---

## Pattern Modules — When to Use

Use `ptn/` modules when the scenario requires multi-resource orchestration:

### Hub-and-Spoke Networking

```bicep
module hubNetworking 'br/public:avm/ptn/network/hub-networking:<version>' = {
  name: 'hubNetworkingAvmDeploy'
  params: {
    hubVirtualNetworkResourceGroupName: rg.name
    hubVirtualNetworkName: 'vnet-hub'
    hubVirtualNetworkLocation: location
    hubVirtualNetworkAddressPrefixes: ['10.0.0.0/16']
  }
}
```

### Private Link DNS Zones (covers all 200+ Azure service private DNS zones)

```bicep
module privateDnsZones 'br/public:avm/ptn/network/private-link-private-dns-zones:<version>' = {
  name: 'privateDnsZonesAvmDeploy'
  params: {
    virtualNetworkResourceId: vnet.outputs.resourceId
  }
}
```

### AKS Full Cluster

```bicep
module aks 'br/public:avm/ptn/azd/aks:<version>' = {
  name: 'aksAvmDeploy'
  params: {
    name: 'aks-${resourceNamePrefix}'
    location: location
    principalId: identity.outputs.principalId
  }
}
```

### Container Apps Stack

```bicep
module containerAppsStack 'br/public:avm/ptn/azd/container-apps-stack:<version>' = {
  name: 'containerAppsStackAvmDeploy'
  params: {
    containerAppsEnvironmentName: 'cae-${resourceNamePrefix}'
    location: location
  }
}
```

---

## Full AVM Module Quick Reference

### Resource Modules (res/)

| Category | Module ID |
|---|---|
| AAD | `avm/res/aad/domain-service` |
| API Management | `avm/res/api-management/service` |
| App Config | `avm/res/app-configuration/configuration-store` |
| Container App | `avm/res/app/container-app` |
| Container App Job | `avm/res/app/job` |
| Container Apps Env | `avm/res/app/managed-environment` |
| Automation | `avm/res/automation/automation-account` |
| Batch | `avm/res/batch/batch-account` |
| Redis | `avm/res/cache/redis` |
| Redis Enterprise | `avm/res/cache/redis-enterprise` |
| CDN Profile | `avm/res/cdn/profile` |
| Cognitive Services | `avm/res/cognitive-services/account` |
| Disk | `avm/res/compute/disk` |
| VM Gallery | `avm/res/compute/gallery` |
| Virtual Machine | `avm/res/compute/virtual-machine` |
| VMSS | `avm/res/compute/virtual-machine-scale-set` |
| ACR | `avm/res/container-registry/registry` |
| AKS | `avm/res/container-service/managed-cluster` |
| Data Factory | `avm/res/data-factory/factory` |
| Backup Vault | `avm/res/data-protection/backup-vault` |
| Databricks | `avm/res/databricks/workspace` |
| PostgreSQL Flexible | `avm/res/db-for-postgre-sql/flexible-server` |
| MySQL Flexible | `avm/res/db-for-my-sql/flexible-server` |
| IoT Hub | `avm/res/devices/iot-hub` |
| CosmosDB | `avm/res/document-db/database-account` |
| CosmosDB Mongo | `avm/res/document-db/mongo-cluster` |
| Event Grid Domain | `avm/res/event-grid/domain` |
| Event Grid NS | `avm/res/event-grid/namespace` |
| Event Grid Topic | `avm/res/event-grid/topic` |
| Event Hub NS | `avm/res/event-hub/namespace` |
| App Gateway | `avm/res/network/application-gateway` |
| App Gateway WAF | `avm/res/network/application-gateway-web-application-firewall-policy` |
| Azure Firewall | `avm/res/network/azure-firewall` |
| Bastion | `avm/res/network/bastion-host` |
| DDoS Plan | `avm/res/network/ddos-protection-plan` |
| DNS Resolver | `avm/res/network/dns-resolver` |
| DNS Zone | `avm/res/network/dns-zone` |
| ExpressRoute Circuit | `avm/res/network/express-route-circuit` |
| ExpressRoute GW | `avm/res/network/express-route-gateway` |
| Firewall Policy | `avm/res/network/firewall-policy` |
| Front Door WAF | `avm/res/network/front-door-web-application-firewall-policy` |
| Load Balancer | `avm/res/network/load-balancer` |
| NAT Gateway | `avm/res/network/nat-gateway` |
| NIC | `avm/res/network/network-interface` |
| NSG | `avm/res/network/network-security-group` |
| Network Watcher | `avm/res/network/network-watcher` |
| Private DNS Zone | `avm/res/network/private-dns-zone` |
| Private Endpoint | `avm/res/network/private-endpoint` |
| Public IP | `avm/res/network/public-ip-address` |
| Route Table | `avm/res/network/route-table` |
| Traffic Manager | `avm/res/network/traffic-manager-profile` |
| VNet | `avm/res/network/virtual-network` |
| VNet Gateway | `avm/res/network/virtual-network-gateway` |
| VNet Peering | `avm/res/network/virtual-network-peering` |
| Virtual WAN Hub | `avm/res/network/virtual-wan-hub` |
| Log Analytics | `avm/res/operational-insights/workspace` |
| Action Group | `avm/res/insights/action-group` |
| App Insights | `avm/res/insights/component` |
| Data Collection Rule | `avm/res/insights/data-collection-rule` |
| Diagnostic Setting | `avm/res/insights/diagnostic-setting` |
| Metric Alert | `avm/res/insights/metric-alert` |
| Scheduled Query Rule | `avm/res/insights/scheduled-query-rule` |
| Key Vault | `avm/res/key-vault/vault` |
| ML Workspace | `avm/res/machine-learning-services/workspace` |
| Managed Identity | `avm/res/managed-identity/user-assigned-identity` |
| NetApp | `avm/res/net-app/net-app-account` |
| Recovery Services | `avm/res/recovery-services/vault` |
| Resource Group | `avm/res/resources/resource-group` |
| Cognitive Search | `avm/res/search/search-service` |
| Service Bus NS | `avm/res/service-bus/namespace` |
| Service Fabric | `avm/res/service-fabric/cluster` |
| SignalR / Web PubSub | `avm/res/signal-r-service/web-pubsub` |
| SQL Server | `avm/res/sql/server` |
| Storage Account | `avm/res/storage/storage-account` |
| Synapse | `avm/res/synapse/workspace` |
| App Service Plan | `avm/res/web/serverfarm` |
| App Service / Function App | `avm/res/web/site` |
| Static Web App | `avm/res/web/static-site` |
| Policy Assignment | `avm/res/authorization/policy-assignment` |
| Role Assignment | `avm/res/authorization/role-assignment` |

### Pattern Modules (ptn/)

| Scenario | Module ID |
|---|---|
| ACA Landing Zone | `avm/ptn/aca-lza/hosting-environment` |
| AI Foundry | `avm/ptn/ai-ml/ai-foundry` |
| AI Platform Baseline | `avm/ptn/ai-platform/baseline` |
| App Service LZA | `avm/ptn/app-service-lza/hosting-environment` |
| Container Job Toolkit | `avm/ptn/app/container-job-toolkit` |
| PIM Role Assignment | `avm/ptn/authorization/pim-role-assignment` |
| Policy Assignment | `avm/ptn/authorization/policy-assignment` |
| Cross-scope Role Assignment | `avm/ptn/authorization/role-assignment` |
| ACR + Container App | `avm/ptn/azd/acr-container-app` |
| AKS (azd) | `avm/ptn/azd/aks` |
| APIM + API | `avm/ptn/azd/apim-api` |
| Container App Upsert | `avm/ptn/azd/container-app-upsert` |
| Container Apps Stack | `avm/ptn/azd/container-apps-stack` |
| Monitoring Dashboard | `avm/ptn/azd/insights-dashboard` |
| Monitoring Stack | `avm/ptn/azd/monitoring` |
| Private Analytical Workspace | `avm/ptn/data/private-analytical-workspace` |
| Import Image to ACR | `avm/ptn/deployment-script/import-image-to-acr` |
| CI/CD Agents & Runners | `avm/ptn/dev-ops/cicd-agents-and-runners` |
| FinOps Hub | `avm/ptn/finops-toolkit/finops-hub` |
| Landing Zone (sub vending) | `avm/ptn/lz/sub-vending` |
| Hub Networking | `avm/ptn/network/hub-networking` |
| Private Link DNS Zones | `avm/ptn/network/private-link-private-dns-zones` |
| Virtual WAN | `avm/ptn/network/virtual-wan` |
| Remediation | `avm/ptn/policy-insights/remediation` |
| Security Center | `avm/ptn/security/security-center` |
| Service Health Alerts | `avm/ptn/subscription/service-health-alerts` |
| Azure Image Builder | `avm/ptn/virtual-machine-images/azure-image-builder` |

---

## Output Checklist

Before committing any Bicep using AVM modules, verify:

- [ ] `bicepconfig.json` exists with `modulePath: "bicep"` (not `"bicep/public"`)
- [ ] All module versions verified via CHANGELOG or `resolve-avm-version.sh`
- [ ] `az bicep restore --file main.bicep --force` ran without errors
- [ ] `az bicep build --file main.bicep` exits 0 with no errors or warnings
- [ ] Inner AVM module `name:` values suffixed with `Avm` to prevent duplicate deployment names
- [ ] Linux App Service Plans have `kind: 'linux'` and `reserved: true`
- [ ] `linuxFxVersion` explicitly set for all Linux Function Apps
- [ ] Storage account names ≤ 24 characters, no hyphens
- [ ] Role assignments use locally-computed names and scopes (not module outputs)
- [ ] Subscription-scope templates add `scope: rg` to every module call
