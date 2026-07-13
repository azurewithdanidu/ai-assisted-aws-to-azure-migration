---
name: parameter-management
description: Create environment-specific .bicepparam files for dev, staging, and production — derive parameter names from deployed services, apply correct SKUs and replication by environment
---

# Parameter Management Skill

## Purpose

Produce environment-specific parameter files that allow the same Bicep templates to be deployed consistently across dev, staging, and prod without any manual value changes.

## When to Use

After Bicep modules are written, before any deployment validation.

## Universal Parameter Discovery Process

1. **Enumerate deployed modules** — Read `design-document.md` Section 5 (Bicep module list). For each module, look up which parameters it contributes using the **Service Parameter Catalog** below.
2. **Read per-environment values** — Read `design-document.md` Section 7 (Environment Configuration table). Record the target `location` and `workload` name.
3. **Assemble the parameter set** — Combine `environment`, `location`, `workload`, plus all service-specific parameters identified in step 1.
4. **Apply environment sizing rules** — Use the **Default Sizing by Environment** table to fill in SKU, replication, and tier values not explicitly specified in Section 7.
5. **Write three `.bicepparam` files** (dev, staging, prod) — one per environment.
6. **Verify each file resolves:** `az deployment group what-if --template-file main.bicep --parameters parameters/<env>.bicepparam`

### Service Parameter Catalog

Use this table to identify which parameters to include based on which modules are deployed:

| Deployed Service | Parameters to Add | Dev default | Staging default | Prod default |
|---|---|---|---|---|
| **Azure Functions** (Consumption) | `functionPlanSku` | `'Y1'` | `'Y1'` | `'Y1'` |
| **Azure Functions** (Premium) | `functionPlanSku` | `'EP1'` | `'EP1'` | `'EP2'` |
| **Container Apps** | `containerAppCpu`, `containerAppMemory` | `'0.25'`, `'0.5Gi'` | `'0.5'`, `'1.0Gi'` | `'1.0'`, `'2.0Gi'` |
| **App Service** | `appServicePlanSku` | `'B1'` | `'S2'` | `'P2v3'` |
| **Blob Storage** | `storageReplication` | `'LRS'` | `'ZRS'` | `'GRS'` |
| **PostgreSQL Flexible Server** | `databaseSku` | `'Standard_B1ms'` | `'Standard_D2s_v3'` | `'Standard_D4s_v3'` |
| **Cosmos DB** | `cosmosThroughputMode` | `'serverless'` | `'manual'` | `'autoscale'` |
| **Azure SQL** | `sqlSku` | `'Basic'` | `'S2'` | `'S4'` |
| **Azure Cache for Redis** | `redisSku` | `'Basic'` | `'Standard'` | `'Premium'` |
| **Key Vault** | `keyVaultSku` | `'standard'` | `'standard'` | `'premium'` |
| **Service Bus** | `serviceBusSku` | `'Basic'` | `'Standard'` | `'Premium'` |
| **Event Hubs** | `eventHubsSku`, `eventHubsCapacity` | `'Basic'`, `1` | `'Standard'`, `2` | `'Premium'`, `4` |
| **API Management** | `apimSku`, `apimCapacity` | `'Consumption'`, `0` | `'Developer'`, `1` | `'Standard'`, `1` |
| **Log Analytics** | `logRetentionDays` | `30` | `60` | `90` |
| **Application Insights** | (shared — no separate SKU param) | — | — | — |
| **Static Web Apps** | `staticWebAppSku` | `'Free'` | `'Standard'` | `'Standard'` |
| **VNet + Private Endpoints** | `vnetAddressPrefix` | `'10.0.0.0/16'` | `'10.1.0.0/16'` | `'10.2.0.0/16'` |

### Generic `.bicepparam` Template

Use this template structure for every environment. Populate only the parameters that match your deployed services:

```bicepparam
using '../main.bicep'

// ── Core identity (always present) ─────────────────────────────────────────
param environment = '<dev|staging|prod>'
param location    = '<azure-region>'          // e.g. 'australiaeast', 'eastus', 'westeurope'
param workload    = '<workload-short-name>'   // e.g. 'orders', 'imgproc', 'portal'

// ── Compute (include only if module is deployed) ────────────────────────────
// param functionPlanSku    = '<Y1|EP1|EP2|EP3>'
// param appServicePlanSku  = '<B1|S2|P2v3>'
// param containerAppCpu    = '<0.25|0.5|1.0|2.0>'
// param containerAppMemory = '<0.5Gi|1.0Gi|2.0Gi|4.0Gi>'

// ── Storage (include only if module is deployed) ────────────────────────────
// param storageReplication = '<LRS|ZRS|GRS|GZRS>'

// ── Database (include only if module is deployed) ───────────────────────────
// param databaseSku        = '<Standard_B1ms|Standard_D2s_v3|Standard_D4s_v3>'
// param cosmosThroughputMode = '<serverless|manual|autoscale>'
// param sqlSku             = '<Basic|S2|S4>'
// param redisSku           = '<Basic|Standard|Premium>'

// ── Messaging (include only if module is deployed) ──────────────────────────
// param serviceBusSku      = '<Basic|Standard|Premium>'
// param eventHubsSku       = '<Basic|Standard|Premium>'
// param eventHubsCapacity  = <1|2|4>

// ── Security (always present if Key Vault is deployed) ──────────────────────
// param keyVaultSku        = '<standard|premium>'

// ── Observability ───────────────────────────────────────────────────────────
// param logRetentionDays   = <30|60|90>
```

### Filled Example — Three Environments (Functions + Storage + Key Vault workload)

**`dev.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment      = 'dev'
param location         = '<region>'
param workload         = '<workload>'
param functionPlanSku  = 'Y1'
param storageReplication = 'LRS'
param keyVaultSku      = 'standard'
param logRetentionDays = 30
```

**`staging.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment      = 'staging'
param location         = '<region>'
param workload         = '<workload>'
param functionPlanSku  = 'EP1'
param storageReplication = 'ZRS'
param keyVaultSku      = 'standard'
param logRetentionDays = 60
```

**`prod.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment      = 'prod'
param location         = '<region>'
param workload         = '<workload>'
param functionPlanSku  = 'EP2'
param storageReplication = 'GRS'
param keyVaultSku      = 'premium'
param logRetentionDays = 90
```

## Rules

- **Never hardcode secrets or passwords in `.bicepparam` files** — use Key Vault references or deployment-time secure parameters.
- **Always include `environment` and `location` as the first two parameters** in every `.bicepparam` file.
- **Always use LRS for dev, ZRS for staging, GRS for prod** storage replication unless `design-document.md` specifies otherwise.
- **Always use Burstable SKU for dev databases, General Purpose for prod** — never swap these.
- **Never commit `.bicepparam` files with actual secret values** — `@secure()` params must be passed at deploy time or via Key Vault.

## Output

- `outputs/bicep-templates/parameters/dev.bicepparam`
- `outputs/bicep-templates/parameters/staging.bicepparam`
- `outputs/bicep-templates/parameters/prod.bicepparam`
- Each file passes `az deployment group what-if` without errors

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/validate-bicep.ps1` | Validates all `.bicep` files and runs what-if against each `.bicepparam` environment file |

Run after generating or updating `.bicepparam` files to verify all parameter values resolve correctly:

```powershell
./.github/skills/agents/iac-transformation/scripts/validate-bicep.ps1 \
    -ResourceGroup "rg-dev-migration" -Environment dev
```

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Bicep parameter files (.bicepparam) | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameter-files |
| Bicep parameter decorators | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters#parameter-decorators |
| Secure parameters in Bicep | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-secrets |
| Azure Functions hosting plans and SKUs | https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale |
| Azure Blob Storage redundancy options | https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy |
| Azure Database for PostgreSQL SKUs | https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-compute-storage |
| Azure Cosmos DB throughput modes | https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-choose-offer |
| Azure Service Bus tiers | https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-premium-messaging |
| Azure Event Hubs pricing tiers | https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-faq#what-are-event-hubs-tiers |
| Log Analytics data retention | https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-retention-configure |
| `az deployment group what-if` | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if |

### Best Practices

- **Dev uses Consumption plan (Y1), prod uses Premium (EP2+):** Consumption plan has cold starts up to 3 seconds — Premium eliminates cold starts for latency-sensitive workloads.
- **LRS for dev, ZRS for staging, GRS for prod:** GRS replicates data to a secondary region for disaster recovery but costs ~2× LRS. ZRS provides zone-level redundancy within a single region at a moderate premium.
- **Burstable SKUs for dev databases:** `Standard_B1ms` is sufficient for development but should never be used in production — it has limited CPU credits and will throttle under sustained load.
- **Log retention: 30/60/90 day pattern** is a common regulatory baseline. Increase to 365+ days if your workload has compliance requirements (HIPAA, PCI-DSS, SOC 2).
- **Never commit actual secret values in `.bicepparam` files** — mark `@secure()` params and pass them at deploy time via `az deployment group create --parameters key=value` or reference Key Vault secrets.
