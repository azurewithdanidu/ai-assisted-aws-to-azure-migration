// =============================================================================
// parameters/dev.bicepparam
// Environment: Development
// Resource Group: rg-photo-gallery-dev
// Region: Australia East
// =============================================================================
using '../main.bicep'

// Naming
param environment = 'dev'
param location = 'australiaeast'

// Storage — Standard_LRS, no versioning, open CORS for dev
param storageAccountName = 'photogallstordev'
param skuName = 'Standard_LRS'
param containerName = 'images'
param enableBlobVersioning = false
param corsAllowedOrigins = ['*']

// Function App — open CORS for dev
param functionAppName = 'photo-gallery-func-dev'
param allowedCorsOrigins = ['*']
param urlExpiration = 3600
param imageContainerName = 'images'

// Monitoring — 30 day retention for dev
param workspaceName = 'photo-gallery-law-dev'
param appInsightsName = 'photo-gallery-ai-dev'
param retentionDays = 30

// Identity
param identityName = 'photo-gallery-mi-dev'

// Static Web App — Free tier, dev branch
param staticWebAppName = 'photo-gallery-swa-dev'
param skuNameSwa = 'Free'
param repositoryUrl = 'https://github.com/org/ai-assisted-aws-to-azure-migration'
param branch = 'dev'
