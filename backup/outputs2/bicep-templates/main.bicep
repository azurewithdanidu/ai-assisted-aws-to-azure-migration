// ── main.bicep ───────────────────────────────────────────────────────────────
// Purpose: Orchestrator — declares all top-level parameters, calls all five
//          modules, and wires outputs between modules.
//
// Deployment order (respects dependencies):
//   1. monitoring   — no dependencies
//   2. storage      — no dependencies  (parallel with monitoring)
//   3. staticWebApp — no dependencies  (parallel with monitoring, storage)
//   4. functionApp  — depends on monitoring.connectionString, storage.resourceName, storage.resourceId
//   5. rbac         — depends on storage.resourceId, functionApp.principalId
//
// Target region: australiaeast
// Workload:      imageupload (Image Upload Service)

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name — used in resource naming. No hyphens.')
@minLength(1)
@maxLength(16)
param workload string = 'imageupload'

@description('Azure region. Defaults to australiaeast.')
param location string = 'australiaeast'

@description('Resource tags applied to all resources.')
param tags object = {
  environment: environment
  workload: workload
  managedBy: 'bicep'
  project: 'aws-to-azure-migration'
}

@description('Frontend SWA origin allowed for CORS. Use * only in dev.')
param allowedCorsOrigin string = '*'

@description('GitHub repository URL for Static Web Apps CI/CD.')
param repositoryUrl string = ''

@description('Git branch to deploy to Static Web Apps.')
param branch string = 'main'

@description('Relative path to app source within the repository.')
param appLocation string = 'source-app/app-code/build'

@description('Build output folder for Static Web Apps.')
param outputLocation string = ''

@allowed(['Free', 'Standard'])
@description('Static Web Apps SKU tier.')
param staticWebAppSku string = 'Free'

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
// Deploys: Log Analytics Workspace + Application Insights
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoringDeploy'
  params: {
    environment: environment
    workload: workload
    location: location
    tags: tags
    retentionDays: retentionDays
  }
}

// ── Module: Storage ──────────────────────────────────────────────────────────
// Deploys: Storage Account (GPv2) + images container + CORS + versioning + soft-delete
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
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

// ── Module: Static Web App ───────────────────────────────────────────────────
// Deploys: Azure Static Web Apps (Free/Standard tier) — hosts app.html frontend
module staticWebApp 'modules/static-web-app.bicep' = {
  name: 'staticWebAppDeploy'
  params: {
    environment: environment
    workload: workload
    location: location
    tags: tags
    repositoryUrl: repositoryUrl
    branch: branch
    appLocation: appLocation
    outputLocation: outputLocation
    staticWebAppSku: staticWebAppSku
  }
}

// ── Module: Function App ─────────────────────────────────────────────────────
// Deploys: Consumption plan + Function App (Python 3.11) + managed identity
// Depends on: monitoring (connectionString), storage (resourceName, resourceId)
module functionApp 'modules/function-app.bicep' = {
  name: 'functionAppDeploy'
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
// Deploys: Storage Blob Data Contributor role assignment for Function App MI
// Depends on: storage (resourceId), functionApp (principalId)
module rbac 'modules/rbac.bicep' = {
  name: 'rbacDeploy'
  params: {
    storageAccountId: storage.outputs.resourceId
    functionAppPrincipalId: functionApp.outputs.principalId
    location: location
  }
}

// ── Root Outputs ─────────────────────────────────────────────────────────────
@description('Function App default hostname.')
output functionAppHostname string = functionApp.outputs.defaultHostname

@description('Function App resource name.')
output functionAppName string = functionApp.outputs.resourceName

@description('Function App managed identity principal ID.')
output functionAppPrincipalId string = functionApp.outputs.principalId

@description('Storage Account name.')
output storageAccountName string = storage.outputs.resourceName

@description('Storage Account resource ID.')
output storageAccountId string = storage.outputs.resourceId

@description('Storage Account primary blob endpoint.')
output blobEndpoint string = storage.outputs.blobEndpoint

@description('Static Web App default hostname.')
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname

@description('Static Web App resource name.')
output staticWebAppName string = staticWebApp.outputs.resourceName

@secure()
@description('Static Web App deployment token (for CI/CD).')
output staticWebAppDeploymentToken string = staticWebApp.outputs.deploymentToken

@description('Application Insights connection string.')
output appInsightsConnectionString string = monitoring.outputs.connectionString

@description('Application Insights resource name.')
output appInsightsName string = monitoring.outputs.resourceName

@description('Log Analytics Workspace resource ID.')
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId

@description('Role assignment resource ID.')
output rbacRoleAssignmentId string = rbac.outputs.roleAssignmentId
