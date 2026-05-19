using '../main.bicep'

param environmentName = 'prod'
param location = 'australiaeast'
param staticWebAppLocation = 'eastasia'
param resourceNameSuffix = 'prod'
param tags = {
  workload: 'image-upload'
  env: 'prod'
  managedBy: 'bicep'
  costCenter: 'engineering'
  dataClassification: 'internal'
}
param logRetentionDays = 90
param storageSkuName = 'Standard_ZRS'
// Lock CORS to the prod SWA hostname only. Update after first SWA deploy.
param allowedCorsOrigins = [
  'https://swa-imgupload-prod.azurestaticapps.net'
]
param keyVaultSoftDeleteRetentionDays = 90
param keyVaultEnablePurgeProtection = true
param urlExpirationSeconds = 3600
