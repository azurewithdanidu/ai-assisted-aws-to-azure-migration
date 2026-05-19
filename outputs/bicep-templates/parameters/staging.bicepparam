// =============================================================================
// parameters/staging.bicepparam
// Environment: Staging
// Resource Group: rg-photo-gallery-staging
// Region: Australia East
// =============================================================================
using '../main.bicep'

// Naming
param environment = 'staging'
param location = 'australiaeast'

// Storage — Standard_LRS, no versioning
// Note: update corsAllowedOrigins after first SWA deployment with actual SWA hostname
param storageAccountName = 'photogallstorstagng'
param skuName = 'Standard_LRS'
param containerName = 'images'
param enableBlobVersioning = false
param corsAllowedOrigins = ['https://photo-gallery-swa-staging.azurestaticapps.net']

// Function App — CORS restricted to SWA staging hostname
// Note: update allowedCorsOrigins after first SWA deployment with actual SWA hostname
param functionAppName = 'photo-gallery-func-staging'
param allowedCorsOrigins = ['https://photo-gallery-swa-staging.azurestaticapps.net']
param urlExpiration = 3600
param imageContainerName = 'images'

// Monitoring — 60 day retention for staging
param workspaceName = 'photo-gallery-law-staging'
param appInsightsName = 'photo-gallery-ai-staging'
param retentionDays = 60

// Identity
param identityName = 'photo-gallery-mi-staging'

// Static Web App — Free tier, staging branch
param staticWebAppName = 'photo-gallery-swa-staging'
param skuNameSwa = 'Free'
param repositoryUrl = 'https://github.com/org/ai-assisted-aws-to-azure-migration'
param branch = 'staging'
