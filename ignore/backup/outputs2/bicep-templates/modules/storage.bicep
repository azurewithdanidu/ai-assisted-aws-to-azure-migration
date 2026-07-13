// ── modules/storage.bicep ───────────────────────────────────────────────────
// Purpose: Azure Storage Account (GPv2), images blob container, CORS rules,
//          blob versioning, soft-delete, and lifecycle management policy
//          (move blobs to Cool tier after 90 days).
//
// AVM module: br/public:avm/res/storage/storage-account:0.32.0

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name, e.g. imageupload. No hyphens — used in storage account name.')
@minLength(1)
@maxLength(16)
param workload string

@description('Azure region, e.g. australiaeast.')
param location string

@description('Resource tags applied to all resources.')
param tags object

@description('Frontend origin allowed for CORS. Pass * only in dev; use SWA hostname in staging/prod.')
param allowedCorsOrigin string

@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
@description('Storage account replication SKU. Standard_LRS for dev/staging, Standard_ZRS for prod.')
param storageSkuName string = 'Standard_LRS'

@minValue(7)
@maxValue(365)
@description('Blob soft-delete retention days. 7 for dev, 14 for staging, 30 for prod.')
param softDeleteDays int = 7

// ── Variables ───────────────────────────────────────────────────────────────
var uniqueSuffix = take(uniqueString(resourceGroup().id), 8)
// Storage account names: lowercase alphanumeric, max 24 chars
// Pattern: <env><workload>stor<8-char suffix>
// Max: 4 (prod) + 11 (imageupload) + 4 (stor) + 8 = 27 → take 16 from env+workload
var namePrefix = take(toLower(replace('${environment}${workload}', '-', '')), 12)
var storageAccountName = '${namePrefix}stor${uniqueSuffix}'

// ── AVM Storage Account ─────────────────────────────────────────────────────
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storageAccountDeploy'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    skuName: storageSkuName
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    // Public network access required: SAS token generation from browser clients
    // requires the storage endpoint to be reachable.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: softDeleteDays
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: softDeleteDays
      isVersioningEnabled: true
      corsRules: [
        {
          allowedOrigins: [allowedCorsOrigin]
          allowedMethods: ['GET', 'PUT', 'POST', 'HEAD', 'DELETE']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
      containers: [
        {
          name: 'images'
          publicAccess: 'None'
          metadata: {}
        }
      ]
    }
    // ── Lifecycle management policy ─────────────────────────────────────────
    // Move block blobs in the images container to Cool tier after 90 days of
    // inactivity. This maps to the S3 lifecycle policy recommended in the
    // service-mapping.md (no lifecycle on AWS side; Azure best-practice added).
    managementPolicyRules: [
      {
        name: 'moveToCoolAfter90Days'
        enabled: true
        type: 'Lifecycle'
        definition: {
          filters: {
            blobTypes: [
              'blockBlob'
            ]
            prefixMatch: [
              'images/'
            ]
          }
          actions: {
            baseBlob: {
              tierToCool: {
                daysAfterModificationGreaterThan: 90
              }
            }
          }
        }
      }
    ]
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
@description('Storage Account resource ID.')
output resourceId string = storageAccount.outputs.resourceId

@description('Storage Account name.')
output resourceName string = storageAccount.outputs.name

@description('Primary blob service endpoint.')
output blobEndpoint string = storageAccount.outputs.primaryBlobEndpoint
