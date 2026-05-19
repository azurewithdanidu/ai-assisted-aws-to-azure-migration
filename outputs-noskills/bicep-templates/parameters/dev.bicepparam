using '../main.bicep'

param environmentName = 'dev'
param location = 'australiaeast'
param staticWebAppLocation = 'eastasia'
param resourceNameSuffix = 'dev'
param tags = {
  workload: 'image-upload'
  env: 'dev'
  managedBy: 'bicep'
  costCenter: 'engineering'
}
param logRetentionDays = 30
param storageSkuName = 'Standard_LRS'
param allowedCorsOrigins = [
  '*'
]
param keyVaultSoftDeleteRetentionDays = 7
param keyVaultEnablePurgeProtection = false
param urlExpirationSeconds = 3600
