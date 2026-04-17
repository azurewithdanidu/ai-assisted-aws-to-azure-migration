// =============================================================================
// storage.bicep — Blob Storage Module
// Deploys Azure Blob Storage replacing AWS S3 ImageBucket
// Mirrors: versioning, CORS (all methods, * origins, 3000s), private access
// Adds: lifecycle management (Hot→Cool 90d, Cool→Archive 365d), soft-delete 7d
// AVM module: storage/storage-account:0.32.0
//
// Breaking-change note (v0.32.0): retention policy props are flat:
//   deleteRetentionPolicyEnabled + deleteRetentionPolicyDays
//   containerDeleteRetentionPolicyEnabled + containerDeleteRetentionPolicyDays
// =============================================================================

metadata name = 'Storage Module'
metadata description = 'Deploys Azure Blob Storage (replaces AWS S3 ImageBucket) for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module.')
param resourceNamePrefix string

@description('Storage account replication SKU. Use Standard_LRS for dev/staging, Standard_ZRS for prod.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param skuName string = 'Standard_LRS'

// Storage account name must be globally unique, 3-24 chars, lowercase alphanumeric only
// Strip hyphens and prefix to fit within 24 chars
var rawStorageName = replace('${resourceNamePrefix}store', '-', '')
var storageAccountName = take(toLower(rawStorageName), 24)

// =============================================================================
// Storage Account — replaces AWS S3 ImageBucket
// CORS mirrors CloudFormation: GET/PUT/POST/HEAD/DELETE, * origins, 3000s
// Versioning enabled (matches S3 VersioningConfiguration: Enabled)
// Public blob access blocked (matches S3 PublicAccessBlockConfiguration)
// =============================================================================
module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storageAccountDeploy'
  params: {
    name: storageAccountName
    location: location
    skuName: skuName
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
    blobServices: {
      // Mirror S3 VersioningConfiguration: Enabled
      isVersioningEnabled: true
      // Soft-delete for blobs — 7 days (flattened props in AVM storage-account v0.32.0)
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      // Soft-delete for containers — 7 days
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      // CORS mirrors CloudFormation CorsRules exactly
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'PUT', 'POST', 'HEAD', 'DELETE']
          allowedHeaders: ['*']
          exposedHeaders: ['ETag', 'Content-Type']
          maxAgeInSeconds: 3000
        }
      ]
      // Images container — private, replaces S3 ImageBucket default container
      containers: [
        {
          name: 'images'
          publicAccess: 'None'
        }
      ]
    }
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 's3-image-bucket'
    }
  }
}

// =============================================================================
// Lifecycle Policy — native resource (lifecycle rules added as Azure best practice)
// Hot → Cool after 90 days, Cool → Archive after 365 days
// Versioned blobs: archive old versions after 90 days, delete after 2 years
// =============================================================================
resource storageManagementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  name: '${storageAccountName}/default'
  dependsOn: [storageAccount]
  properties: {
    policy: {
      rules: [
        {
          name: 'lifecycle-tiering'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 90
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 365
                }
              }
              version: {
                tierToCool: {
                  daysAfterCreationGreaterThan: 90
                }
                delete: {
                  daysAfterCreationGreaterThan: 730
                }
              }
            }
          }
        }
      ]
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Name of the storage account (used as env var STORAGE_ACCOUNT_NAME in Function App).')
output storageAccountName string = storageAccount.outputs.name

@description('Resource ID of the storage account.')
output storageAccountId string = storageAccount.outputs.resourceId

@description('Primary blob service endpoint URI.')
output blobEndpoint string = storageAccount.outputs.primaryBlobEndpoint

@description('Name of the images container (used as env var CONTAINER_NAME in Function App).')
output containerName string = 'images'
