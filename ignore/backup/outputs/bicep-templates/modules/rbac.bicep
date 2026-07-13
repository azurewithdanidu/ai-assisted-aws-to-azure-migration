// ============================================================
// modules/rbac.bicep
// Creates role assignments for the Function App's system-assigned
// managed identity:
//
//   1. Storage Blob Data Contributor on the storage account
//      Role def ID: ba92f5b4-2d11-453d-a403-e96b0029c9fe
//      Allows: list blobs, read/write blobs, generate user
//              delegation keys for SAS token creation.
//
//   2. Key Vault Secrets User on the Key Vault (when enabled)
//      Role def ID: 4633458b-17de-408a-b874-0445c86b69e6
//      Allows: read Key Vault secrets for Key Vault references
//              in app settings.
//
// NOTE on raw resource declarations:
//   Microsoft.Authorization/roleAssignments are a built-in ARM
//   resource type. The AVM ptn/authorization/role-assignment
//   pattern module is designed for subscription-scope cross-
//   resource deployments and does not support scoping to a
//   specific storage account resource. Raw resource declarations
//   are used here per the module-organization skill rule:
//   "no raw resource declarations unless no AVM module exists
//   for the specific use case."
//
// Outputs: storageBlobDataContributorAssignmentId,
//          keyVaultSecretsUserAssignmentId
// ============================================================

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Object (principal) ID of the Function App system-assigned managed identity.')
param principalId string

@description('ARM resource ID of the storage account to scope the role assignment to.')
param storageAccountResourceId string

@description('When true, also create the Key Vault Secrets User role assignment.')
param enableKeyVault bool = false

@description('ARM resource ID of the Key Vault. Required when enableKeyVault = true.')
param keyVaultResourceId string = ''

// ── Variables ─────────────────────────────────────────────────────────────────

// Built-in role definition IDs (stable across all Azure tenants)
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var keyVaultSecretsUserRoleId        = '4633458b-17de-408a-b874-0445c86b69e6'

// ─────────────────────────────────────────────────────────────────────────────
// RESOURCES
// ─────────────────────────────────────────────────────────────────────────────

// Existing storage account reference for scope resolution
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: last(split(storageAccountResourceId, '/'))
}

// Role Assignment 1: Storage Blob Data Contributor
// Grants the Function App MI the ability to read/write blobs and generate
// user delegation keys (required for SAS URL generation).
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountResourceId, principalId, storageBlobDataContributorRoleId)
  scope: storageAccountRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Function App managed identity — Storage Blob Data Contributor for image upload service'
  }
}

// Existing Key Vault reference for scope resolution (conditional)
resource keyVaultRef 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (enableKeyVault && !empty(keyVaultResourceId)) {
  name: last(split(keyVaultResourceId, '/'))
}

// Role Assignment 2: Key Vault Secrets User (conditional)
// Grants the Function App MI read access to Key Vault secrets
// used as Key Vault references in app settings.
resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault && !empty(keyVaultResourceId)) {
  name: guid(keyVaultResourceId, principalId, keyVaultSecretsUserRoleId)
  scope: keyVaultRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Function App managed identity — Key Vault Secrets User for runtime secret references'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

@description('Resource ID of the Storage Blob Data Contributor role assignment.')
output storageBlobDataContributorAssignmentId string = storageBlobDataContributorAssignment.id

@description('Resource ID of the Key Vault Secrets User role assignment. Empty when Key Vault is disabled.')
output keyVaultSecretsUserAssignmentId string = (enableKeyVault && !empty(keyVaultResourceId)) ? keyVaultSecretsUserAssignment.id : ''
