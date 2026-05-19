// =============================================================================
// main.bicep — Root orchestration template
// Project: Image Upload Photo Gallery — AWS → Azure Migration
// Target Region: Australia East (australiaeast)
// Environments: dev | staging | prod (see parameters/ directory)
//
// Module deployment order (implicit dependencies via outputs):
//   1. monitoring   — App Insights + Log Analytics (no dependencies)
//   2. storage      — Storage Account + images container (no dependencies)
//   3. identity     — User-assigned MI placeholder (no dependencies, optional)
//   4. functionApp  — Depends on: monitoring (connectionString), storage (name/id/connstr)
//   5. rbac         — Depends on: storage (id/name), functionApp (principalId)
//   6. staticWebApp — Independent; defaultHostname used in CORS after first deploy
//
// AVM modules used (all via br/public:avm/... — no local module files):
//   res/storage/storage-account:0.32.0          — Storage Account
//   res/managed-identity/user-assigned-identity:0.4.3 — User-assigned MI
//   res/web/serverfarm:0.7.0                    — App Service Plan (inside functionApp.bicep)
//   res/web/site:0.22.0                         — Function App (inside functionApp.bicep)
//   res/operational-insights/workspace:0.15.0   — Log Analytics (inside monitoring.bicep)
//   res/insights/component:0.7.1                — App Insights (inside monitoring.bicep)
//   res/web/static-site:0.9.3                   — Static Web App
//
// Bicep restore command before build:
//   az bicep restore --file main.bicep --force
//   az bicep build  --file main.bicep
// =============================================================================

// ---------------------------------------------------------------------------
// Parameters — Naming
// ---------------------------------------------------------------------------

@description('Short environment label used in resource naming (dev | staging | prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources.')
param location string = 'australiaeast'

// ---------------------------------------------------------------------------
// Parameters — Storage
// ---------------------------------------------------------------------------

@description('Globally unique storage account name (3–24 lowercase alphanumeric, no hyphens).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Storage SKU. Standard_LRS for dev/staging; Standard_GRS for prod.')
@allowed(['Standard_LRS', 'Standard_GRS'])
param skuName string = 'Standard_LRS'

@description('Blob container name for images.')
param containerName string = 'images'

@description('CORS allowed origins for Blob Storage. Use [\'*\'] for dev.')
param corsAllowedOrigins array = ['*']

@description('Enable blob versioning. false for dev/staging, true for prod.')
param enableBlobVersioning bool = false

// ---------------------------------------------------------------------------
// Parameters — Function App
// ---------------------------------------------------------------------------

@description('Globally unique Function App name.')
param functionAppName string

@description('CORS allowed origins for Function App HTTP triggers.')
param allowedCorsOrigins array = ['*']

@description('SAS token lifetime in seconds.')
@minValue(300)
@maxValue(86400)
param urlExpiration int = 3600

@description('Blob container name passed to Function App as BLOB_CONTAINER_NAME env var.')
param imageContainerName string = 'images'

// ---------------------------------------------------------------------------
// Parameters — Monitoring
// ---------------------------------------------------------------------------

@description('Log Analytics Workspace name.')
param workspaceName string = 'photo-gallery-law-${environment}'

@description('Application Insights resource name.')
param appInsightsName string = 'photo-gallery-ai-${environment}'

@description('Log retention in days. dev=30, staging=60, prod=90.')
@minValue(30)
@maxValue(730)
param retentionDays int = 30

// ---------------------------------------------------------------------------
// Parameters — Identity (optional user-assigned MI)
// ---------------------------------------------------------------------------

@description('User-assigned Managed Identity name (optional placeholder for future multi-resource sharing).')
param identityName string = 'photo-gallery-mi-${environment}'

// ---------------------------------------------------------------------------
// Parameters — Static Web App
// ---------------------------------------------------------------------------

@description('Static Web App resource name.')
param staticWebAppName string

@description('SWA SKU: Free for all envs; upgrade to Standard only if Entra auth is required.')
@allowed(['Free', 'Standard'])
param skuNameSwa string = 'Free'

@description('GitHub repository URL for Static Web App CI/CD integration.')
param repositoryUrl string = 'https://github.com/org/ai-assisted-aws-to-azure-migration'

@description('Git branch to deploy from. dev → dev env, staging → staging env, main → prod env.')
param branch string = 'main'

// ---------------------------------------------------------------------------
// Module 1 — Monitoring (no dependencies)
// ---------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoringDeploy'
  params: {
    workspaceName: workspaceName
    appInsightsName: appInsightsName
    location: location
    retentionDays: retentionDays
  }
}

// ---------------------------------------------------------------------------
// Module 2 — Storage Account + images container (no dependencies)
// ---------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: skuName
    containerName: containerName
    corsAllowedOrigins: corsAllowedOrigins
    enableBlobVersioning: enableBlobVersioning
  }
}

// ---------------------------------------------------------------------------
// Module 3 — Identity: User-assigned MI placeholder (no dependencies)
// Note: system-assigned MI is created inline in functionApp.bicep and is the
//       primary identity used for Storage Blob Data Contributor RBAC assignment.
// ---------------------------------------------------------------------------
module identity 'modules/identity.bicep' = {
  name: 'identityDeploy'
  params: {
    location: location
    identityName: identityName
  }
}

// ---------------------------------------------------------------------------
// Module 4 — Function App (depends on monitoring + storage)
// ---------------------------------------------------------------------------
module functionApp 'modules/functionApp.bicep' = {
  name: 'functionAppDeploy'
  params: {
    functionAppName: functionAppName
    location: location
    storageAccountName: storage.outputs.storageAccountName
    storageAccountId: storage.outputs.storageAccountId
    storageConnectionString: storage.outputs.storageConnectionString
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageContainerName: imageContainerName
    urlExpiration: urlExpiration
    allowedCorsOrigins: allowedCorsOrigins
  }
}

// ---------------------------------------------------------------------------
// Module 5 — RBAC: Storage Blob Data Contributor on Storage Account scope
//   (depends on storage + functionApp for principalId of system-assigned MI)
// ---------------------------------------------------------------------------
module rbac 'modules/rbac.bicep' = {
  name: 'rbacDeploy'
  params: {
    storageAccountId: storage.outputs.storageAccountId
    storageAccountName: storage.outputs.storageAccountName
    principalId: functionApp.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// Module 6 — Static Web App (independent; CORS for functionApp/storage uses
//   its defaultHostname but that is passed as a parameter in staging/prod)
// ---------------------------------------------------------------------------
module staticWebApp 'modules/staticWebApp.bicep' = {
  name: 'staticWebAppDeploy'
  params: {
    staticWebAppName: staticWebAppName
    location: location
    skuName: skuNameSwa
    repositoryUrl: repositoryUrl
    branch: branch
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Storage Account resource ID.')
output storageAccountId string = storage.outputs.storageAccountId

@description('Storage Account name.')
output storageAccountName string = storage.outputs.storageAccountName

@description('Primary Blob endpoint URL.')
output blobEndpoint string = storage.outputs.blobEndpoint

@description('Function App resource ID.')
output functionAppId string = functionApp.outputs.functionAppId

@description('Function App name.')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App default hostname (used as API base URL in SPA config).')
output functionAppHostname string = functionApp.outputs.functionAppHostname

@description('Application Insights connection string.')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

@description('Log Analytics Workspace resource ID.')
output workspaceId string = monitoring.outputs.workspaceId

@description('Static Web App default hostname (e.g., *.azurestaticapps.net). Update corsAllowedOrigins in staging/prod after first SWA deployment.')
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname

@description('User-assigned Managed Identity resource ID (optional, for future use).')
output identityResourceId string = identity.outputs.resourceId
