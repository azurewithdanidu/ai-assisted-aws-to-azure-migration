---
name: bicep-generation
description: Write secure, modular, deployable Bicep IaC — naming conventions, decorators, module structure, outputs, and validation steps
---

# Bicep Generation Skill

## Purpose

Produce valid, secure, and maintainable Azure Bicep templates that follow Azure best practices, pass `az bicep build` without errors, and can be deployed safely across dev/staging/prod environments.

## When to Use

- When specifying Bicep module structure in `design-document.md` Section 5 (azure-architect)
- When implementing Bicep files from the design document (iac-transformation)
- When reviewing or modifying any existing `.bicep` or `.bicepparam` file

## Process

1. **Naming:** Use `'${environment}-${workload}-<type>-${location}'` for most resources. For storage accounts (24-char limit, no hyphens): `'${environment}${workload}stor${uniqueSuffix}'`. Use `uniqueString(resourceGroup().id)` for the suffix.

2. **Parameters:** Decorate every parameter:
   ```bicep
   @minLength(3)
   @maxLength(24)
   @description('Name of the storage account. Must be globally unique.')
   param storageAccountName string

   @allowed(['dev', 'staging', 'prod'])
   @description('Deployment environment.')
   param environment string

   @minValue(1)
   @maxValue(10)
   @description('Number of instances.')
   param instanceCount int = 1
   ```

3. **Variables:** Compute derived names in variables — never inline:
   ```bicep
   var uniqueSuffix = uniqueString(resourceGroup().id)
   var functionAppName = '${environment}-${workload}-func-${location}'
   var storageAccountName = toLower('${environment}${workload}stor${uniqueSuffix}')
   ```

4. **Modules:** Each module has one responsibility (networking, storage, compute, security, monitoring). Keep modules under ~150 lines. Root `main.bicep` only declares parameters and module calls — no direct resources.

5. **Outputs:** Every module must output:
   - `resourceId` — the full resource ID
   - `resourceName` — the resource name
   - `principalId` — if the resource has a managed identity
   - `endpoint` or `fqdn` — for services accessed over the network

6. **Tags:** Apply a `tags` object to every resource:
   ```bicep
   param tags object = {
     environment: environment
     workload: workload
     managedBy: 'bicep'
   }
   ```

7. **Validate before declaring done:**
   ```bash
   az bicep build --file main.bicep
   az deployment group what-if \
     --resource-group <rg> \
     --template-file main.bicep \
     --parameters @parameters/dev.bicepparam
   ```

## Rules

- **Never hardcode secrets, passwords, or connection strings.** Use `@secure()` for sensitive parameters; reference Key Vault secrets via `@Microsoft.KeyVault(SecretUri=...)`.
- **Never set `publicNetworkAccess: 'Enabled'` on data services** (Storage, Key Vault, Service Bus, databases). Always `'Disabled'` with a private endpoint.
- **Never use access keys for service-to-service auth.** Always Managed Identity + RBAC role assignments (see `azure-auth-patterns` skill).
- **Always pin API versions** — never use `@latest` or omit the version. Example: `'Microsoft.Storage/storageAccounts@2023-01-01'`.
- **Never create a module that exceeds ~150 lines** — split it if it grows beyond that.
- **Always run `az bicep build`** before declaring any Bicep file complete. A file that does not build is not done.

## Output

- Valid `.bicep` files under `outputs/bicep-templates/` with zero build errors
- `.bicepparam` files under `outputs/bicep-templates/parameters/` for each environment (dev, staging, prod)
- `az bicep build` exits with code 0 for every file
- `az deployment group what-if` produces no blocking errors
