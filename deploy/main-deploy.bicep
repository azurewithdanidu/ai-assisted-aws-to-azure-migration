// ── deploy/main-deploy.bicep ─────────────────────────────────────────────────
// Deployment wrapper for main.bicep that overrides Static Web App location to
// 'eastasia' — Azure Static Web Apps (Microsoft.Web/staticSites) is NOT
// available in australiaeast.  All other resources use the provided location.
//
// Available SWA regions: centralus, eastus2, westus2, westeurope, eastasia
// Reference: outputs/bicep-templates/main.bicep (unmodified)

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name. No hyphens.')
@minLength(1)
@maxLength(16)
param workload string = 'imageupload'

@description('Azure region for all resources except Static Web App.')
param location string = 'australiaeast'

@description('Resource tags applied to all resources.')
param tags object = {
  environment: environment
  workload: workload
  managedBy: 'bicep'
  project: 'aws-to-azure-migration'
}

@description('Frontend SWA origin allowed for CORS.')
param allowedCorsOrigin string = '*'

@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
@description('Storage account replication SKU.')
param storageSkuName string = 'Standard_LRS'

@minValue(7)
@maxValue(365)
@description('Blob soft-delete retention days.')
param softDeleteDays int = 7

@minValue(30)
@maxValue(730)
@description('Log Analytics retention days.')
param retentionDays int = 30

@minValue(300)
@maxValue(86400)
@description('SAS token expiry in seconds.')
param urlExpiration int = 3600

@description('Key Vault name for Key Vault references in Function App config.')
param keyVaultName string

// ── Module: Monitoring ───────────────────────────────────────────────────────
module monitoring '../outputs/bicep-templates/modules/monitoring.bicep' = {
  name: 'monitoringDeployFixed'
  params: {
    environment: environment
    workload: workload
    location: location
    tags: tags
    retentionDays: retentionDays
  }
}

// ── Module: Storage ──────────────────────────────────────────────────────────
module storage '../outputs/bicep-templates/modules/storage.bicep' = {
  name: 'storageDeployFixed'
  params: {
    environment: environment
    workload: workload
    location: location
    tags: tags
    allowedCorsOrigin: allowedCorsOrigin
    storageSkuName: storageSkuName
    softDeleteDays: softDeleteDays
  }
}

// NOTE: Static Web App is deployed separately via az staticwebapp create
// because Microsoft.Web/staticSites is not available in australiaeast, and
// the AVM module requires a non-empty repositoryUrl for free-standing mode.
// See Step 6 in deployment instructions.

// ── Module: Function App ─────────────────────────────────────────────────────
module functionApp '../outputs/bicep-templates/modules/function-app.bicep' = {
  name: 'funcAppDeployFixed'
  params: {
    environment: environment
    workload: workload
    location: location
    tags: tags
    storageAccountName: storage.outputs.resourceName
    storageAccountId: storage.outputs.resourceId
    appInsightsConnectionString: monitoring.outputs.connectionString
    keyVaultName: keyVaultName
    urlExpiration: urlExpiration
    allowedCorsOrigin: allowedCorsOrigin
  }
}

// ── Module: RBAC ─────────────────────────────────────────────────────────────
module rbac '../outputs/bicep-templates/modules/rbac.bicep' = {
  name: 'rbacDeployFixed'
  params: {
    storageAccountId: storage.outputs.resourceId
    functionAppPrincipalId: functionApp.outputs.principalId
    location: location
  }
}

// ── Root Outputs ─────────────────────────────────────────────────────────────
output functionAppHostname string = functionApp.outputs.defaultHostname
output functionAppName string = functionApp.outputs.resourceName
output functionAppPrincipalId string = functionApp.outputs.principalId
output storageAccountName string = storage.outputs.resourceName
output storageAccountId string = storage.outputs.resourceId
output blobEndpoint string = storage.outputs.blobEndpoint
output appInsightsConnectionString string = monitoring.outputs.connectionString
output appInsightsName string = monitoring.outputs.resourceName
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output rbacRoleAssignmentId string = rbac.outputs.roleAssignmentId
