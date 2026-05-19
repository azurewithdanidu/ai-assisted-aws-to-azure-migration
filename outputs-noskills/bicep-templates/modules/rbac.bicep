// =============================================================================
// modules/rbac.bicep — Role assignments granting UAMI access to Storage + KV (§5.6)
// =============================================================================
@description('Principal ID of the User-Assigned Managed Identity.')
param principalId string

@description('Name of the storage account to grant Blob Data Contributor + Delegator on.')
param storageAccountName string

@description('Name of the Key Vault to grant Secrets User on.')
param keyVaultName string

// Built-in role definition IDs (constants — DO NOT change)
var roleStorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var roleStorageBlobDelegator       = 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
var roleKeyVaultSecretsUser        = '4633458b-17de-408a-b874-0445c86b69e6'

// Existing resource references (already deployed by storage.bicep / keyvault.bicep)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

// --- Storage Blob Data Contributor on storage account ---
resource raBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, roleStorageBlobDataContributor)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataContributor)
  }
}

// --- Storage Blob Delegator on storage account (for User Delegation Key / SAS) ---
resource raBlobDelegator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, roleStorageBlobDelegator)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDelegator)
  }
}

// --- Key Vault Secrets User on key vault ---
resource raKvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, roleKeyVaultSecretsUser)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKeyVaultSecretsUser)
  }
}

output blobContributorAssignmentId string = raBlobContributor.id
output blobDelegatorAssignmentId string = raBlobDelegator.id
output kvSecretsUserAssignmentId string = raKvSecretsUser.id
