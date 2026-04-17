// =============================================================================
// rbac.bicep — Role Assignment Module
// Deploys two roles for the Function App managed identity:
//   1. Storage Blob Data Contributor — on the images container (read/write/delete blobs)
//   2. Storage Blob Delegator        — on the storage account (required for get_user_delegation_key)
// Runs at resourceGroup scope (called from subscription-scope main.bicep with scope: rg)
// Replaces: AWS Lambda IAM Role inline S3Access policy
//
// NOTE: get_user_delegation_key (used to mint SAS tokens via Managed Identity) requires
// Storage Blob Delegator at the storage account scope — Data Contributor alone is insufficient.
// =============================================================================

metadata name = 'RBAC Module'
metadata description = 'Assigns Storage Blob Data Contributor (container) + Storage Blob Delegator (account) to the Function App managed identity'

@description('Storage account name that holds the images container.')
param imagesStorageAccountName string

@description('Resource name prefix (used to build a stable role assignment GUID).')
param resourceNamePrefix string

@description('Principal ID of the Function App system-assigned managed identity.')
param functionAppPrincipalId string

// Existing storage account — needed for Storage Blob Delegator scope
resource imagesStorageAccountRef 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: imagesStorageAccountName
}

// Existing images container — needed for Storage Blob Data Contributor scope
resource imagesContainerRef 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${imagesStorageAccountName}/default/images'
}

// Role 1: Storage Blob Data Contributor on images container
// Grants read/write/delete on blobs — matches S3 PutObject/GetObject/DeleteObject/ListBucket
resource funcStorageDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-data-contributor')
  scope: imagesContainerRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Role 2: Storage Blob Delegator on storage account
// Required for get_user_delegation_key() — used to generate user-delegation SAS tokens
// Must be scoped at storage account level (container scope is insufficient)
resource funcStorageDelegatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-delegator')
  scope: imagesStorageAccountRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
