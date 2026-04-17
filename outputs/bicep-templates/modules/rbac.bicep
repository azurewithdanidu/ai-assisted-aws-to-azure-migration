// =============================================================================
// rbac.bicep — Role Assignment Module
// Deploys Storage Blob Data Contributor on the images container for the Function App
// Runs at resourceGroup scope (called from subscription-scope main.bicep with scope: rg)
// Replaces: AWS Lambda IAM Role inline S3Access policy
// =============================================================================

metadata name = 'RBAC Module'
metadata description = 'Assigns Storage Blob Data Contributor to the Function App managed identity on the images container'

@description('Storage account name that holds the images container.')
param imagesStorageAccountName string

@description('Resource name prefix (used to build a stable role assignment GUID).')
param resourceNamePrefix string

@description('Principal ID of the Function App system-assigned managed identity.')
param functionAppPrincipalId string

// Existing images container — resolved within the resourceGroup scope of this module
resource imagesContainerRef 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${imagesStorageAccountName}/default/images'
}

// Storage Blob Data Contributor on images container only
// Matches S3 PutObject/GetObject/DeleteObject/ListBucket permissions on ImageBucket
resource funcStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resourceNamePrefix, 'storage-blob-data-contributor')
  scope: imagesContainerRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
