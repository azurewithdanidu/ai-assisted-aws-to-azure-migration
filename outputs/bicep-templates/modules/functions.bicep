// =============================================================================
// functions.bicep — Azure Functions Module
// Deploys Consumption plan + Function App (Python 3.11, Linux)
// Replaces: 4 AWS Lambda functions (Upload, ListFiles, GetViewUrl, Delete)
// Identity: System-assigned managed identity (replaces IAM execution role)
// Runtime storage: dedicated storage account for Function App runtime
// AVM modules: web/serverfarm:0.7.0, web/site:0.22.0
//
// Breaking-change notes:
//   serverfarm v0.7.0: skuTier removed; kind and reserved are still required for Linux plans
//   Linux plan requires: kind: 'linux', reserved: true (otherwise defaults to Windows)
//   Storage name: take(16) + 'funcstor'(8) = 24 chars max (must not exceed 24)
// =============================================================================

metadata name = 'Functions Module'
metadata description = 'Deploys Azure Functions Consumption plan and Function App (replaces 4 AWS Lambda functions)'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module.')
param resourceNamePrefix string

@description('Name of the images storage account (set as STORAGE_ACCOUNT_NAME env var).')
param imagesStorageAccountName string

@description('Name of the images blob container (set as CONTAINER_NAME env var).')
param imagesContainerName string = 'images'

@description('SAS token expiration in seconds. Mirrors AWS URL_EXPIRATION=3600.')
param urlExpirationSeconds string = '3600'

@description('Application Insights connection string for telemetry.')
param appInsightsConnectionString string

// =============================================================================
// Function App Runtime Storage Account
// Azure Functions Consumption plan requires a dedicated storage account for
// triggers, logs, and state. Separate from the images storage account.
// Name: take(16) + 'funcstor'(8) = max 24 chars — within Storage Account limit
// =============================================================================
var funcStorageAccountName = '${take(toLower(replace(resourceNamePrefix, '-', '')), 16)}funcstor'

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
// Consumption Plan (Dynamic SKU, Linux)
// Replaces AWS Lambda's on-demand execution model
// AVM serverfarm v0.7.0: skuName 'Y1' = Consumption; skuTier/reserved/kind removed
// =============================================================================
module functionAppPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'functionAppPlanDeploy'
  params: {
    name: '${resourceNamePrefix}-plan'
    location: location
    // Y1 = Consumption (Dynamic) SKU
    skuName: 'Y1'
    // Required for Linux App Service Plan
    kind: 'linux'
    reserved: true
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'lambda-consumption-model'
    }
  }
}

// =============================================================================
// Function App — replaces 4 AWS Lambda functions
// Python 3.11 runtime matches Lambda runtime exactly
// System-assigned Managed Identity replaces IAM LambdaExecutionRole
// App settings mirror Lambda environment variables (BUCKET_NAME → STORAGE_ACCOUNT_NAME etc.)
// =============================================================================
module functionApp 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionAppDeploy'
  params: {
    name: '${resourceNamePrefix}-func'
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: functionAppPlan.outputs.resourceId
    httpsOnly: true
    // System-assigned MI replaces AWS IAM LambdaExecutionRole
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: {
      // Python 3.11 runtime — matches Azure Functions v4 requirement and app code.
      // Format: PYTHON|<version> (uppercase). Empty string defaults to Python 3.6.
      linuxFxVersion: 'PYTHON|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      // CORS — replaces AWS API Gateway OPTIONS mock methods per route
      // Wildcard in dev; restrict to Static Web App hostname in production
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      // Function App application settings
      // Maps AWS Lambda environment variables to Azure equivalents
      appSettings: [
        {
          // Azure Functions runtime version
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          // Python worker runtime
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          // Function App runtime storage (WebJobs)
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageAccount.name};AccountKey=${funcStorageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          // App Insights telemetry replaces CloudWatch + X-Ray
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          // Replaces AWS Lambda BUCKET_NAME env var → storage account name
          name: 'STORAGE_ACCOUNT_NAME'
          value: imagesStorageAccountName
        }
        {
          // Container name — BLOB_CONTAINER_NAME avoids conflict with reserved CONTAINER_NAME host variable
          name: 'BLOB_CONTAINER_NAME'
          value: imagesContainerName
        }
        {
          // Replaces AWS Lambda URL_EXPIRATION env var (value in seconds)
          name: 'URL_EXPIRATION_SECONDS'
          value: urlExpirationSeconds
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

@description('Resource ID of the Function App.')
output functionAppId string = functionApp.outputs.resourceId

@description('Name of the Function App.')
output functionAppName string = functionApp.outputs.name

@description('Default hostname of the Function App — direct HTTP trigger endpoint (no APIM needed).')
output functionAppHostname string = functionApp.outputs.defaultHostname

@description('Principal ID of the system-assigned managed identity (used for RBAC assignments).')
output functionAppPrincipalId string = functionApp.outputs.?systemAssignedMIPrincipalId ?? ''

@description('Resource ID of the App Service Plan.')
output functionAppPlanId string = functionAppPlan.outputs.resourceId

@description('Connection string storage account name used by the Function App runtime.')
output funcStorageAccountName string = funcStorageAccount.name
