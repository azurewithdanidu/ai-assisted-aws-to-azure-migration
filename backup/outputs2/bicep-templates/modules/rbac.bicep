// ── modules/rbac.bicep ──────────────────────────────────────────────────────
// Purpose: Assigns Storage Blob Data Contributor to the Function App's
//          system-assigned managed identity, scoped to the Storage Account.
//
// Uses native Microsoft.Authorization/roleAssignments — the AVM pattern module
// ptn/authorization/role-assignment only supports managementGroup scope and
// cannot be used for resource-level or resource-group-level assignments.
//
// Role: Storage Blob Data Contributor
//   GUID: ba92f5b4-2d11-453d-a403-e96b0029c9fe

@description('Storage Account resource ID — role assignment is scoped to this resource.')
param storageAccountId string

@description('Principal ID of the Function App system-assigned managed identity.')
param functionAppPrincipalId string

@description('Azure region for deployment metadata (unused; kept for API compatibility).')
#disable-next-line no-unused-params
param location string = resourceGroup().location

// ── Variables ───────────────────────────────────────────────────────────────
// Storage Blob Data Contributor built-in role
var storageBlobDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

// Parse storage account name from its resource ID
// Format: /subscriptions/{subId}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}
var storageAccountName = last(split(storageAccountId, '/'))

// Deterministic GUID ensures idempotent deployments
var roleAssignmentName = guid(storageAccountId, functionAppPrincipalId, storageBlobDataContributorRoleId)

// ── Existing storage account reference (used as scope) ──────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// ── Native role assignment scoped to the Storage Account ────────────────────
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Storage Blob Data Contributor — Function App managed identity'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
@description('Role assignment resource ID.')
output roleAssignmentId string = storageBlobDataContributorAssignment.id
