// =============================================================================
// functions.bicep — Azure Functions Module
// Deploys Consumption plan + Function App (Python 3.11, Linux)
// Replaces: 4 AWS Lambda functions (Upload, ListFiles, GetViewUrl, Delete)
// Identity: System-Assigned Managed Identity (replaces IAM LambdaExecutionRole)
// Design doc: Section 5.6
//
// CRITICAL — Reserved environment variable names (DO NOT USE):
//   CONTAINER_NAME        — reserved by Azure Functions host
//   WEBSITE_*             — reserved prefix
//   FUNCTIONS_*           — reserved prefix (except FUNCTIONS_WORKER_RUNTIME,
//                           FUNCTIONS_EXTENSION_VERSION which are intentional)
//
// App settings mapping (AWS Lambda → Azure Functions):
//   BUCKET_NAME           → BLOB_CONTAINER_NAME  (container name)
//   URL_EXPIRATION        → URL_EXPIRATION        (unchanged value: '3600')
//   N/A                   → BLOB_STORAGE_ACCOUNT_NAME  (storage account name)
//   N/A                   → AZURE_STORAGE_ACCOUNT_NAME (for DefaultAzureCredential
//                                                        BlobServiceClient URL)
// =============================================================================

metadata name = 'Functions Module'
metadata description = 'Deploys Azure Functions Consumption plan and Function App (replaces 4 AWS Lambda functions)'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

@description('Name of the images blob storage account. Set as BLOB_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_NAME.')
param imagesStorageAccountName string

@description('Name of the images blob container. Set as BLOB_CONTAINER_NAME (NOT CONTAINER_NAME — that is reserved).')
param imagesContainerName string = 'images'

@description('SAS token expiration in seconds. Mirrors AWS URL_EXPIRATION=3600. Set as URL_EXPIRATION app setting.')
param urlExpirationSeconds string = '3600'

@description('Application Insights connection string. Set as APPLICATIONINSIGHTS_CONNECTION_STRING app setting.')
param appInsightsConnectionString string

// =============================================================================
// Function App Runtime Storage Account
// Azure Functions Consumption plan requires a dedicated storage account for
// triggers, logs, state, and WebJobs SDK. Separate from the images storage account.
// Name: take 18 chars from prefix (hyphens stripped) + 'funcst' = max 24 chars
// =============================================================================
var funcStorageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 18)}funcst'

resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: funcStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
  }
  tags: {
    environment: environment
    application: 'image-upload-service'
    purpose: 'function-app-runtime-storage'
  }
}

// =============================================================================
// Consumption Plan (Dynamic Y1 SKU, Linux)
// Equivalent to AWS Lambda on-demand execution model (no always-on instances)
// =============================================================================
module functionAppPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'functionAppPlanDeploy'
  params: {
    name: '${resourceNamePrefix}-asp'
    location: location
    skuName: 'Y1'
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'lambda-consumption-model'
    }
  }
}

// =============================================================================
// Function App — replaces all 4 AWS Lambda functions in a single app
// Python 3.11 runtime exactly matches Lambda runtime python3.11
// System-Assigned Managed Identity replaces IAM LambdaExecutionRole
//
// Data plane storage access (images container) uses DefaultAzureCredential
// via Managed Identity — no storage account keys in application code.
// Runtime storage (AzureWebJobsStorage) uses connection string as required
// by Azure Functions Consumption plan trigger infrastructure.
// =============================================================================
module functionApp 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionAppDeploy'
  params: {
    name: '${resourceNamePrefix}-func'
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: functionAppPlan.outputs.resourceId
    httpsOnly: true
    // System-Assigned MI replaces AWS IAM LambdaExecutionRole
    // RBAC assignment (Storage Blob Data Contributor on images container)
    // is done separately in rbac.bicep — principle of least privilege
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: {
      // Python 3.11 — exact match to Lambda runtime python3.11
      // Azure Functions v4 supports Python 3.9, 3.10, 3.11 ONLY
      // DO NOT use Python 3.12 or 3.13 — crashes worker (0xC0000005)
      linuxFxVersion: 'Python|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      // CORS — replaces AWS API Gateway OPTIONS mock methods per route
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      // Application settings — mapped from AWS Lambda environment variables
      appSettings: [
        {
          // Azure Functions v4 runtime
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          // Python worker runtime
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          // Function App runtime infrastructure storage (triggers, logs, state)
          // Uses connection string as required by Consumption plan WebJobs SDK
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageAccount.name};AccountKey=${funcStorageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          // Application Insights telemetry — replaces CloudWatch + X-Ray
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          // Storage account name for blob operations
          // Replaces AWS Lambda BUCKET_NAME env var (storage account level)
          // Used by function code to build BlobServiceClient account URL
          name: 'BLOB_STORAGE_ACCOUNT_NAME'
          value: imagesStorageAccountName
        }
        {
          // Container name for blob operations
          // Replaces AWS Lambda BUCKET_NAME env var (container level)
          // MUST be BLOB_CONTAINER_NAME — CONTAINER_NAME is reserved by Azure Functions host
          name: 'BLOB_CONTAINER_NAME'
          value: imagesContainerName
        }
        {
          // SAS token expiration in seconds — mirrors AWS Lambda URL_EXPIRATION=3600
          // Used by upload_image() and get_view_url() functions
          name: 'URL_EXPIRATION'
          value: urlExpirationSeconds
        }
        {
          // Storage account name for DefaultAzureCredential-based BlobServiceClient
          // Used to build account URL: https://{account}.blob.core.windows.net
          // Managed Identity resolves credentials automatically in Azure
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: imagesStorageAccountName
        }
      ]
    }
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'lambda-upload-listfiles-getviewurl-delete'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Name of the Function App.')
output functionAppName string = functionApp.outputs.name

@description('Principal (Object) ID of the system-assigned managed identity — used for RBAC assignments.')
output functionAppPrincipalId string = functionApp.outputs.?systemAssignedMIPrincipalId ?? ''

@description('Default hostname of the Function App — direct HTTP trigger endpoint for all API routes.')
output functionAppHostname string = functionApp.outputs.defaultHostname

@description('Resource ID of the Function App.')
output functionAppResourceId string = functionApp.outputs.resourceId

@description('Resource ID of the App Service Plan.')
output functionAppPlanId string = functionAppPlan.outputs.resourceId

@description('Name of the Function App runtime storage account.')
output funcStorageAccountName string = funcStorageAccount.name
