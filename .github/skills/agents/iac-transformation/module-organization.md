---
name: module-organization
description: Decide what belongs in root main.bicep vs child modules, module boundaries, dependency ordering, and how to avoid circular dependencies
---

# Module Organization Skill

## Purpose

Structure Bicep templates into focused, reusable modules with clear boundaries so the deployment is maintainable, testable, and free of circular dependencies.

## When to Use

Before writing any Bicep file — this skill defines the file structure that all other Bicep work follows.

## Process

1. Read `outputs/azure-architecture-output/design-document.md` Section 5 for the full module list.
2. Create one module per logical resource group:

   | Module file | Responsibility |
   |---|---|
   | `modules/networking.bicep` | VNet, subnets, NSGs, private DNS zones |
   | `modules/storage.bicep` | Storage accounts, private endpoints for storage |
   | `modules/security.bicep` | Key Vault, private endpoints for KV, RBAC |
   | `modules/compute.bicep` | Function App, App Service Plan, App Insights |
   | `modules/messaging.bicep` | Service Bus namespace and queues (if used) |
   | `modules/monitoring.bicep` | Log Analytics workspace, diagnostic settings |

3. Root `main.bicep` structure — only parameters, module calls, and outputs:

```bicep
// main.bicep — orchestrates modules only, no direct resources
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

4. Dependency order (deploy in this sequence):
   1. `networking` — no deps
   2. `security` — depends on networking (subnet IDs)
   3. `storage` — depends on networking (subnet IDs)
   4. `monitoring` — no deps
   5. `compute` — depends on security, storage, monitoring
   6. `messaging` — depends on networking

## Rules

- **Never put resources directly in `main.bicep`** — use modules.
- **Never create circular module dependencies** — if A needs B and B needs A, extract the shared resource into a third module.
- **Never create a module that exceeds ~150 lines** — split it.
- **Always output `resourceId`, `resourceName`, and `principalId`** (where applicable) from every module.
- **Use output references (not `dependsOn`)** wherever possible — output references are self-documenting dependencies.
- **Use `dependsOn` explicitly** only when the dependency exists but is not expressed through an output reference.

## Output

- `outputs/bicep-templates/main.bicep` — contains only parameters, module declarations, and outputs
- `outputs/bicep-templates/modules/*.bicep` — one file per logical resource group, each under ~150 lines
- `az bicep build --file outputs/bicep-templates/main.bicep` exits with code 0
