using '../main.bicep'

param environmentName = 'staging'
param location = 'australiaeast'
param staticWebAppLocation = 'eastasia'
param resourceNameSuffix = 'staging'
param tags = {
  workload: 'image-upload'
  env: 'staging'
  managedBy: 'bicep'
  costCenter: 'engineering'
}
param logRetentionDays = 30
param storageSkuName = 'Standard_LRS'
// Tighten in staging: replace with the staging SWA hostname after first deploy.
param allowedCorsOrigins = [
  '*'
]
param keyVaultSoftDeleteRetentionDays = 7
param keyVaultEnablePurgeProtection = false
param urlExpirationSeconds = 3600
