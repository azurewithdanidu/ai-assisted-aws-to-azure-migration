// =============================================================================
// modules/rbac.bicep
// Purpose: Assign Storage Blob Data Contributor built-in role to the Function
//   App's system-assigned Managed Identity on the Storage Account scope.
//   Replaces: AWS IAM LambdaExecutionRole inline S3 CRUD policy
//   Security: Scope limited to specific Storage Account (principle of least privilege)
//   RBAC Role ID: ba92f5b4-2d11-453d-a403-e96b0029c9fe (Storage Blob Data Contributor)
// =============================================================================

@description('Resource ID of the storage account (role assignment scope).')
param storageAccountId string

@description('Name of the storage account (required for existing resource reference).')
param storageAccountName string

@description('Principal ID of the Function App system-assigned Managed Identity.')
param principalId string

// ---------------------------------------------------------------------------
// Storage Blob Data Contributor role definition ID (built-in, subscription-invariant)
// ---------------------------------------------------------------------------
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ---------------------------------------------------------------------------
// Existing storage account reference (required for scope property)
// SKILLS.MD Pitfall 4: name/scope are resolved at deployment start;
//   use local existing reference rather than module output reference.
// ---------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// ---------------------------------------------------------------------------
// Role assignment — Storage Blob Data Contributor on Storage Account scope
// principalType: 'ServicePrincipal' avoids delay in Entra ID propagation
// ---------------------------------------------------------------------------
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, principalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Grant Function App system-assigned MI read/write/delete access to Blob Storage. Replaces AWS IAM LambdaExecutionRole S3 CRUD policy.'
  }
}

// No outputs — role assignments have no useful consumer outputs.
