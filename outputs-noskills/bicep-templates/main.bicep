// =============================================================================
// main.bicep — Subscription-scope orchestrator for image-upload workload
// Source design: outputs/azure-architecture-output/design-document.md §5.1
// =============================================================================
targetScope = 'subscription'

@description('Environment name. Drives naming + per-env settings.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentName string

@description('Primary Azure region for all resources except SWA.')
param location string = 'australiaeast'

@description('Region for Static Web App (Free SKU). Defaults to eastasia for AU proximity.')
param staticWebAppLocation string = 'eastasia'

@description('Suffix appended to resource names. Defaults to environmentName.')
param resourceNameSuffix string = environmentName

@description('Resource tags applied to RG + all child resources.')
param tags object = {
  workload: 'image-upload'
  env: environmentName
  managedBy: 'bicep'
}

@description('Log Analytics retention (days). prod=90, dev/staging=30.')
param logRetentionDays int = environmentName == 'prod' ? 90 : 30

@description('Storage SKU. prod=ZRS, dev/staging=LRS.')
param storageSkuName string = environmentName == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'

@description('CORS origins allowed by Storage + Function App. prod=SWA hostname only, dev/staging=*.')
param allowedCorsOrigins array = environmentName == 'dev' ? [
  '*'
] : []

@description('Key Vault soft-delete retention. prod=90, dev/staging=7.')
param keyVaultSoftDeleteRetentionDays int = environmentName == 'prod' ? 90 : 7

@description('Enable Key Vault purge protection (prod only).')
param keyVaultEnablePurgeProtection bool = environmentName == 'prod'

@description('SAS / presigned URL expiration (seconds). Mirrors AWS URL_EXPIRATION.')
param urlExpirationSeconds int = 3600

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-imgupload-${resourceNameSuffix}'
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Modules (ordered per §5.1)
// monitoring → identity → keyvault → storage → rbac → functionApp → staticWebApp
// ---------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring-deploy'
  params: {
    location: location
    resourceNameSuffix: resourceNameSuffix
    tags: tags
    logRetentionDays: logRetentionDays
  }
}

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity-deploy'
  params: {
    location: location
    resourceNameSuffix: resourceNameSuffix
    tags: tags
  }
}

module keyvault 'modules/keyvault.bicep' = {
  scope: rg
  name: 'keyvault-deploy'
  params: {
    location: location
    resourceNameSuffix: resourceNameSuffix
    tags: tags
    softDeleteRetentionInDays: keyVaultSoftDeleteRetentionDays
    enablePurgeProtection: keyVaultEnablePurgeProtection
  }
}

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage-deploy'
  params: {
    location: location
    resourceNameSuffix: resourceNameSuffix
    tags: tags
    allowedCorsOrigins: allowedCorsOrigins
    skuName: storageSkuName
  }
}

module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac-deploy'
  params: {
    principalId: identity.outputs.principalId
    storageAccountName: storage.outputs.storageAccountName
    keyVaultName: keyvault.outputs.keyVaultName
  }
}

module functionApp 'modules/functionApp.bicep' = {
  scope: rg
  name: 'functionApp-deploy'
  params: {
    location: location
    resourceNameSuffix: resourceNameSuffix
    tags: tags
    storageAccountName: storage.outputs.storageAccountName
    userAssignedIdentityId: identity.outputs.identityId
    userAssignedIdentityClientId: identity.outputs.clientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imagesContainerName: storage.outputs.imagesContainerName
    urlExpirationSeconds: urlExpirationSeconds
    allowedCorsOrigins: allowedCorsOrigins
  }
  dependsOn: [
    rbac
  ]
}

module staticWebApp 'modules/staticWebApp.bicep' = {
  scope: rg
  name: 'staticWebApp-deploy'
  params: {
    location: staticWebAppLocation
    resourceNameSuffix: resourceNameSuffix
    tags: tags
    apiBaseUrl: functionApp.outputs.functionAppDefaultHostName
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output resourceGroupName string = rg.name
output functionAppName string = functionApp.outputs.functionAppName
output storageAccountName string = storage.outputs.storageAccountName
output staticWebAppName string = staticWebApp.outputs.staticWebAppName
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname
output managedIdentityClientId string = identity.outputs.clientId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
