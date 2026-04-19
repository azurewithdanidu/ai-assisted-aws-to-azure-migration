// =============================================================================
// storage.bicep — Blob Storage Module
// Deploys Azure Storage Account and 'images' blob container
// Replaces: AWS S3 ImageBucket (private, versioned, CORS-enabled)
// Design doc: Section 5.3
//
// Security:
//   allowBlobPublicAccess: false   — all access via SAS tokens only
//   minimumTlsVersion: TLS1_2      — no legacy TLS
//   supportsHttpsTrafficOnly: true  — no plain HTTP
//   Container publicAccess: None   — private, no anonymous read
// =============================================================================

metadata name = 'Storage Module'
metadata description = 'Deploys Azure Blob Storage (replaces AWS S3 ImageBucket) for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

@description('Storage account replication SKU. Dev: Standard_LRS, staging: Standard_ZRS, prod: Standard_GRS.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param skuName string = 'Standard_LRS'

// Storage account name: max 24 chars, lowercase alphanumeric only, globally unique
// Strip hyphens from prefix then append 'store' and take first 24 chars
var rawStorageName = replace('${resourceNamePrefix}store', '-', '')
var storageAccountName = take(toLower(rawStorageName), 24)

// =============================================================================
// Storage Account — replaces AWS S3 ImageBucket
// Versioning enabled (mirrors S3 VersioningConfiguration: Enabled)
// CORS mirrors AWS CloudFormation CorsRule: all origins, all methods including OPTIONS
// Public blob access blocked (mirrors S3 PublicAccessBlockConfiguration: all true)
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
      // Mirrors S3 VersioningConfiguration: Enabled
      isVersioningEnabled: true
      // Soft-delete for blobs — 7 days
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      // Soft-delete for containers — 7 days
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      // CORS mirrors AWS CloudFormation CorsRule:
      //   AllowedOrigins: ['*'], AllowedMethods: [GET,PUT,POST,HEAD,DELETE,OPTIONS]
      //   AllowedHeaders: ['*'], ExposedHeaders: ['*'], MaxAge: 3000
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'PUT', 'POST', 'HEAD', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['ETag', 'Content-Type']
          maxAgeInSeconds: 3000
        }
      ]
      // Images container — private, replaces S3 ImageBucket
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
      'aws-equivalent': 's3-image-upload-imagebucket'
    }
  }
}

// =============================================================================
// Lifecycle Policy — hot → cool after 90 days, cool → archive after 365 days
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

@description('Name of the storage account (used as BLOB_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_NAME app settings).')
output storageAccountName string = storageAccount.outputs.name

@description('Resource ID of the storage account.')
output storageAccountResourceId string = storageAccount.outputs.resourceId

@description('Primary blob endpoint URI.')
output blobEndpoint string = storageAccount.outputs.primaryBlobEndpoint

@description('Name of the images container (used as BLOB_CONTAINER_NAME app setting).')
output containerName string = 'images'
