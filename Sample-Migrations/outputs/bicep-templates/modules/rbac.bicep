// =============================================================================
// rbac.bicep — RBAC Role Assignment Module
// Assigns Storage Blob Data Contributor to the Function App managed identity
// Scoped to the 'images' blob container (principle of least privilege)
// Replaces: AWS IAM LambdaExecutionRole inline S3Access policy
//   (s3:PutObject, s3:GetObject, s3:DeleteObject, s3:ListBucket)
// Design doc: Section 5.8
//
// Role: Storage Blob Data Contributor
//   ID: ba92f5b4-2d11-453d-a403-e96b0029c9fe
//   Grants: read, write, delete blobs and containers
//   Scope: images container (NOT entire storage account — least privilege)
//
// This role assignment enables DefaultAzureCredential in function_app.py to:
//   - list_blobs() on the images container
//   - generate_blob_sas() via get_user_delegation_key()
//   - delete_blob() on individual image blobs
// =============================================================================

metadata name = 'RBAC Module'
metadata description = 'Assigns Storage Blob Data Contributor to Function App managed identity on images container'

@description('Name of the images storage account (from storage module output).')
param storageAccountName string

@description('Name of the images blob container (= "images").')
param containerName string

@description('Object ID of the Function App system-assigned managed identity (from functions module output).')
param functionAppPrincipalId string

// =============================================================================
// Reference the existing images container — created by storage.bicep module
// The scope of the role assignment is the container resource, not the account
// =============================================================================
resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' existing = {
  name: '${storageAccountName}/default/${containerName}'
}

// =============================================================================
// Role Assignment: Storage Blob Data Contributor on images container
// Deterministic GUID built from resource group + principal + role definition
// to ensure idempotent deployments (same GUID on re-deploy)
// =============================================================================
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Deterministic GUID — idempotent across re-deployments
  name: guid(resourceGroup().id, functionAppPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: imagesContainer
  properties: {
    // Storage Blob Data Contributor
    // Replaces: S3Access inline policy (PutObject, GetObject, DeleteObject, ListBucket)
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the role assignment.')
output roleAssignmentId string = storageBlobDataContributorAssignment.id
