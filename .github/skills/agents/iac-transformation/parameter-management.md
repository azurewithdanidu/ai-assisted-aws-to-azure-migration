---
name: parameter-management
description: Create environment-specific .bicepparam files for dev, staging, and production with correct SKUs, replication, and Key Vault references
---

# Parameter Management Skill

## Purpose

Produce environment-specific parameter files that allow the same Bicep templates to be deployed consistently across dev, staging, and prod without any manual value changes.

## When to Use

After Bicep modules are written, before any deployment validation.

## Process

1. Read `design-document.md` Section 7 (Environment Configuration table) for the per-environment parameter values.
2. Create three `.bicepparam` files:

**`outputs/bicep-templates/parameters/dev.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment = 'dev'
param location = 'australiaeast'
param workload = 'migration'
param functionPlanSku = 'Y1'
param storageReplication = 'LRS'
param databaseSku = 'Standard_B1ms'
param keyVaultSku = 'standard'
```

**`outputs/bicep-templates/parameters/staging.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment = 'staging'
param location = 'australiaeast'
param workload = 'migration'
param functionPlanSku = 'EP1'
param storageReplication = 'ZRS'
param databaseSku = 'Standard_D2s_v3'
param keyVaultSku = 'standard'
```

**`outputs/bicep-templates/parameters/prod.bicepparam`:**
```bicepparam
using '../main.bicep'

param environment = 'prod'
param location = 'australiaeast'
param workload = 'migration'
param functionPlanSku = 'EP2'
param storageReplication = 'GRS'
param databaseSku = 'Standard_D4s_v3'
param keyVaultSku = 'premium'
```

3. Verify each file resolves: `az deployment group what-if --template-file main.bicep --parameters parameters/dev.bicepparam`

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
