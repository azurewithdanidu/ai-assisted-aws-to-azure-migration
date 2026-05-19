// =============================================================================
// modules/storage.bicep
// Purpose: Deploy Azure Storage Account + images blob container + CORS + lifecycle
// AWS equivalent: S3 image bucket (image-upload-imagebucket-t8isnbr8sswv)
// AVM module: br/public:avm/res/storage/storage-account:0.32.0
//   Selected per SKILLS.MD §Step 3 — Storage (S3 → Azure Blob Storage)
// =============================================================================

@description('Globally unique storage account name (3–24 lowercase alphanumeric).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for deployment.')
param location string

@description('Storage SKU. Use Standard_LRS for dev/staging, Standard_GRS for prod.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
])
param skuName string = 'Standard_LRS'

@description('Blob container name for images.')
param containerName string = 'images'

@description('CORS allowed origins. Use [\'*\'] for dev, SWA URL for prod.')
param corsAllowedOrigins array = ['*']

@description('Enable blob versioning. false for dev/staging, true for prod.')
param enableBlobVersioning bool = false

// ---------------------------------------------------------------------------
// AVM Storage Account module
// ---------------------------------------------------------------------------
module storageAccountAvmDeploy 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storageAccountAvmDeploy'
  params: {
    name: storageAccountName
    location: location
    skuName: skuName
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    blobServices: {
      isVersioningEnabled: enableBlobVersioning
      // Soft delete retained for 7 days (security baseline requirement)
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      corsRules: [
        {
          allowedOrigins: corsAllowedOrigins
          allowedMethods: [
            'DELETE'
            'GET'
            'HEAD'
            'MERGE'
            'OPTIONS'
            'POST'
            'PUT'
            'PATCH'
          ]
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 86400
        }
      ]
      containers: [
        {
          name: containerName
          publicAccess: 'None'
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the storage account.')
output storageAccountId string = storageAccountAvmDeploy.outputs.resourceId

@description('Name of the storage account.')
output storageAccountName string = storageAccountAvmDeploy.outputs.name

@description('Primary blob service endpoint URL.')
output blobEndpoint string = storageAccountAvmDeploy.outputs.primaryBlobEndpoint

@description('Storage account connection string. Used for Function App runtime storage in dev/staging only. In prod, use Managed Identity (DefaultAzureCredential).')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountAvmDeploy.outputs.name};AccountKey=${listKeys(storageAccountAvmDeploy.outputs.resourceId, '2023-01-01').keys[0].value};EndpointSuffix=core.windows.net'
