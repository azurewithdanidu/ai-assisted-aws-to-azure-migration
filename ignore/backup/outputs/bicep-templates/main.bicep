// ============================================================
// main.bicep — Image Upload Service — Azure Migration
// Root orchestration file: parameters, module calls, outputs.
// No resources declared directly here — all resources are in
// child modules referenced via br/public:avm/... paths.
//
// Deployment dependency order (per design-document.md §5.6):
//   1. monitoring  2. storage  3. function-app  4. rbac  5. static-web-app
// ============================================================

// ── Core identity ────────────────────────────────────────────────────────────

@description('Deployment environment name. Controls SKU, replication, and retention sizing.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources. Maps from AWS ap-southeast-2.')
param location string = 'australiasoutheast'

@description('Short workload identifier used in resource names.')
param resourcePrefix string = 'img-upload'

// ── Storage ──────────────────────────────────────────────────────────────────

@description('Storage account name (lowercase alphanumeric, 3-24 chars).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Name of the private blob container for image payloads.')
param storageContainerName string = 'images'

@description('Storage replication SKU. LRS for dev, ZRS for staging, GRS for prod.')
@allowed(['LRS', 'ZRS', 'GRS', 'GZRS', 'RA-GRS', 'RA-GZRS'])
param storageReplication string = 'LRS'

// ── Function App ─────────────────────────────────────────────────────────────

@description('Name of the Azure Function App.')
param functionAppName string

@description('Name of the App Service Plan (Consumption Y1).')
param appServicePlanName string

// ── Static Web App ───────────────────────────────────────────────────────────

@description('Name of the Azure Static Web App hosting the SPA frontend.')
param staticWebAppName string

@description('Location for the Static Web App. Overridable because SWA has limited region availability.')
param staticWebAppLocation string = 'eastasia'

// ── Monitoring ───────────────────────────────────────────────────────────────

@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Name of the Application Insights component.')
param applicationInsightsName string

@description('Log Analytics data retention in days. 30 for dev, 60 for staging, 90 for prod.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Daily data ingestion cap in GB for Application Insights / Log Analytics (dev cost guard).')
param dailyCapGb int = 1

// ── Key Vault ─────────────────────────────────────────────────────────────────

@description('Name of the Azure Key Vault. Used when enableKeyVault = true.')
param keyVaultName string = 'img-upload-kv-${environment}'

@description('Enable Key Vault for runtime secret references.')
param enableKeyVault bool = true

// ── Application configuration ─────────────────────────────────────────────────

@description('SAS token expiry in seconds. Replaces AWS URL_EXPIRATION env var.')
param sasExpirationSeconds int = 3600

@description('Maximum upload size in bytes (default 10 MB).')
param maxUploadBytes int = 10485760

@description('CORS allowed origins for Blob Storage and Function App.')
param corsAllowedOrigins array = []

// ── Tagging ───────────────────────────────────────────────────────────────────

@description('Resource tags applied to all deployed resources.')
param tags object = {
  workload: resourcePrefix
  environment: environment
  migrationSource: 'aws-ap-southeast-2'
  managedBy: 'bicep'
}

// ─────────────────────────────────────────────────────────────────────────────
// MODULE CALLS  (dependency order: monitoring → storage → functionApp → rbac → swa)
// ─────────────────────────────────────────────────────────────────────────────

// 1. Monitoring — no external dependencies
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoringDeploy'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    appInsightsName: applicationInsightsName
    location: location
    logRetentionDays: logRetentionDays
    dailyCapGb: dailyCapGb
    tags: tags
  }
}

// 2. Storage — no external dependencies
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  params: {
    storageAccountName: storageAccountName
    location: location
    containerName: storageContainerName
    storageReplication: storageReplication
    corsAllowedOrigins: corsAllowedOrigins
    tags: tags
  }
}

// 3. Function App — depends on monitoring (App Insights conn string) and storage (account name)
module functionApp 'modules/function-app.bicep' = {
  name: 'functionAppDeploy'
  params: {
    appServicePlanName: appServicePlanName
    functionAppName: functionAppName
    location: location
    storageAccountName: storage.outputs.storageAccountName
    blobEndpoint: storage.outputs.blobEndpoint
    storageAccountResourceId: storage.outputs.storageAccountId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    sasExpirationSeconds: sasExpirationSeconds
    maxUploadBytes: maxUploadBytes
    imagesContainerName: storageContainerName
    corsAllowedOrigins: corsAllowedOrigins
    enableKeyVault: enableKeyVault
    keyVaultName: keyVaultName
    tags: tags
  }
}

// 4. RBAC — depends on functionApp (principalId) and storage (resourceId)
module rbac 'modules/rbac.bicep' = {
  name: 'rbacDeploy'
  params: {
    principalId: functionApp.outputs.principalId
    storageAccountResourceId: storage.outputs.storageAccountId
    enableKeyVault: enableKeyVault
    keyVaultResourceId: functionApp.outputs.keyVaultResourceId
  }
}

// 5. Static Web App — no external dependencies
module staticWebApp 'modules/static-web-app.bicep' = {
  name: 'staticWebAppDeploy'
  params: {
    staticWebAppName: staticWebAppName
    location: staticWebAppLocation
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

// Monitoring
output workspaceId string = monitoring.outputs.workspaceId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output appInsightsInstrumentationKey string = monitoring.outputs.appInsightsInstrumentationKey

// Storage
output storageAccountId string = storage.outputs.storageAccountId
output storageAccountNameOut string = storage.outputs.storageAccountName
output blobEndpoint string = storage.outputs.blobEndpoint
output imagesContainerName string = storage.outputs.imagesContainerName

// Function App
output functionAppId string = functionApp.outputs.functionAppId
output functionAppNameOut string = functionApp.outputs.functionAppName
output functionHostname string = functionApp.outputs.functionHostname
output functionPrincipalId string = functionApp.outputs.principalId
output keyVaultUri string = functionApp.outputs.keyVaultUri

// Static Web App
output staticWebAppId string = staticWebApp.outputs.staticWebAppId
output staticWebAppNameOut string = staticWebApp.outputs.staticWebAppName
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname
