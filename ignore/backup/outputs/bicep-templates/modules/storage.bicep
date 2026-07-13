// ============================================================
// modules/storage.bicep
// Creates a StorageV2 account, configures blob service settings
// (versioning, soft delete, CORS), and provisions the private
// `images` blob container.
//
// AVM module used (per module-organization skill):
//   - avm/res/storage/storage-account:0.32.0
//
// BREAKING CHANGE in 0.32.0:
//   deleteRetentionPolicy.{enabled,days} flattened to
//   deleteRetentionPolicyEnabled + deleteRetentionPolicyDays
//
// Outputs: storageAccountId, storageAccountName,
//          blobEndpoint, imagesContainerName
// ============================================================

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Storage account name — lowercase alphanumeric only, 3-24 characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('Name of the private blob container for image payloads.')
param containerName string = 'images'

@description('Storage replication SKU. Use LRS for dev, ZRS for staging, GRS for prod.')
@allowed(['LRS', 'ZRS', 'GRS', 'GZRS', 'RA-GRS', 'RA-GZRS'])
param storageReplication string = 'LRS'

@description('CORS allowed origins for the blob service (browser upload/download).')
param corsAllowedOrigins array = []

@description('Resource tags.')
param tags object = {}

var storageSkuName = storageReplication == 'LRS'
  ? 'Standard_LRS'
  : storageReplication == 'ZRS'
    ? 'Standard_ZRS'
    : storageReplication == 'GRS'
      ? 'Standard_GRS'
      : storageReplication == 'GZRS'
        ? 'Standard_GZRS'
        : storageReplication == 'RA-GRS'
          ? 'Standard_RAGRS'
          : 'Standard_RAGZRS'

// ─────────────────────────────────────────────────────────────────────────────
// RESOURCES
// ─────────────────────────────────────────────────────────────────────────────

// StorageV2 account with blob service configuration
// AVM: avm/res/storage/storage-account:0.32.0
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storageAccountAvmDeploy'
  params: {
    name: storageAccountName
    location: location
    skuName: storageSkuName
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    blobServices: {
      // Blob versioning — required to preserve version history of uploaded images
      isVersioningEnabled: true
      // Soft delete retention — 7 days per design-document.md §5.5
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      // Container-level soft delete
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      // CORS rules for browser direct upload/download
      corsRules: empty(corsAllowedOrigins)
        ? []
        : [
            {
              allowedOrigins: corsAllowedOrigins
              allowedMethods: [
                'GET'
                'PUT'
                'DELETE'
                'HEAD'
                'OPTIONS'
              ]
              allowedHeaders: [
                '*'
              ]
              exposedHeaders: [
                'ETag'
                'x-ms-request-id'
                'x-ms-version'
                'Content-Type'
              ]
              maxAgeInSeconds: 600
            }
          ]
      // Private images container (access type None — no anonymous read)
      containers: [
        {
          name: containerName
          publicAccess: 'None'
        }
      ]
    }
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

@description('ARM resource ID of the storage account.')
output storageAccountId string = storageAccount.outputs.resourceId

@description('Name of the storage account.')
output storageAccountName string = storageAccount.outputs.name

@description('Primary blob service endpoint URL.')
output blobEndpoint string = 'https://${storageAccount.outputs.name}.blob.${environment().suffixes.storage}'

@description('Name of the private images blob container.')
output imagesContainerName string = containerName
