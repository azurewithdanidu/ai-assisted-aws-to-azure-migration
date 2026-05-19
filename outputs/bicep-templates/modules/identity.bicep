// =============================================================================
// modules/identity.bicep
// Purpose: User-assigned Managed Identity (optional / future use).
//   For this workload, the system-assigned MI on the Function App is used.
//   This module is provided as a placeholder for future multi-resource identity
//   sharing scenarios. The system-assigned MI is created inline in functionApp.bicep.
// AVM module: br/public:avm/res/managed-identity/user-assigned-identity:0.4.3
//   Selected per SKILLS.MD §Step 3 — Security & Identity (IAM Role → Managed Identity)
// =============================================================================

@description('Azure region for deployment.')
param location string

@description('Name of the user-assigned managed identity.')
param identityName string

// ---------------------------------------------------------------------------
// AVM User-Assigned Managed Identity module
// ---------------------------------------------------------------------------
module userAssignedIdentityAvmDeploy 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.3' = {
  name: 'userAssignedIdentityAvmDeploy'
  params: {
    name: identityName
    location: location
  }
}

// ---------------------------------------------------------------------------
// Outputs (forwarded to rbac.bicep if user-assigned MI is used instead of system-assigned)
// ---------------------------------------------------------------------------

@description('Principal ID (object ID) of the user-assigned managed identity.')
output principalId string = userAssignedIdentityAvmDeploy.outputs.principalId

@description('Client ID (application ID) of the user-assigned managed identity.')
output clientId string = userAssignedIdentityAvmDeploy.outputs.clientId

@description('Resource ID of the user-assigned managed identity.')
output resourceId string = userAssignedIdentityAvmDeploy.outputs.resourceId
