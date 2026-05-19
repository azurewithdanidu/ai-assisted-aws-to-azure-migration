// =============================================================================
// parameters/prod.bicepparam
// Environment: Production
// Resource Group: rg-photo-gallery-prod
// Region: Australia East
// =============================================================================
using '../main.bicep'

// Naming
param environment = 'prod'
param location = 'australiaeast'

// Storage — Standard_GRS for geo-redundancy, blob versioning enabled
// Note: update corsAllowedOrigins after first SWA deployment with actual prod SWA hostname
param storageAccountName = 'photogallstoreprod'
param skuName = 'Standard_GRS'
param containerName = 'images'
param enableBlobVersioning = true
param corsAllowedOrigins = ['https://photo-gallery-swa-prod.azurestaticapps.net']

// Function App — CORS restricted to SWA prod hostname
// Note: update allowedCorsOrigins after first SWA deployment with actual prod SWA hostname
param functionAppName = 'photo-gallery-func-prod'
param allowedCorsOrigins = ['https://photo-gallery-swa-prod.azurestaticapps.net']
param urlExpiration = 3600
param imageContainerName = 'images'

// Monitoring — 90 day retention for prod
param workspaceName = 'photo-gallery-law-prod'
param appInsightsName = 'photo-gallery-ai-prod'
param retentionDays = 90

// Identity
param identityName = 'photo-gallery-mi-prod'

// Static Web App — Free tier, main branch
// Upgrade to Standard SKU if Entra ID / social auth is required post-migration
param staticWebAppName = 'photo-gallery-swa-prod'
param skuNameSwa = 'Free'
param repositoryUrl = 'https://github.com/org/ai-assisted-aws-to-azure-migration'
param branch = 'main'
