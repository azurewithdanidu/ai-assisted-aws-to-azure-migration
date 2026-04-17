// =============================================================================
// main.bicep — Image Upload Service — Azure IaC Entry Point
// Converted from: AWS CloudFormation image-upload stack (ap-southeast-2)
// Target region: australiaeast (Sydney — same geographic zone)
//
// Architecture:
//   Azure Static Web Apps → Azure Functions HTTP Triggers (Consumption, Python 3.11) → Azure Blob Storage
//   No APIM — Functions HTTP triggers are the direct equivalent of API Gateway + Lambda proxy
//   Identity: System-Assigned Managed Identity + RBAC (Storage Blob Data Contributor)
//   Observability: Log Analytics Workspace + Application Insights
//   Security: Azure Key Vault (Standard, soft-delete, purge-protected)
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// Parameters
// =============================================================================

@description('Azure region for all resources. Default: australiaeast (mirrors ap-southeast-2 geo).')
param location string = 'eastus2'

@description('Environment name. Controls sizing, replication, and naming.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Workload name — used to build all resource names.')
param workloadName string = 'img-upload'

@description('Storage account replication SKU. Use Standard_ZRS for production.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageSkuName string = 'Standard_LRS'

@description('Log retention in days. 30 for dev/staging, 90+ recommended for prod.')
@minValue(7)
@maxValue(730)
param logRetentionDays int = 30

@description('SAS token expiration in seconds. Mirrors AWS URL_EXPIRATION=3600.')
param urlExpirationSeconds string = '3600'

@description('Resource group name. Defaults to <workload>-<environment>-rg.')
param resourceGroupName string = ''

// =============================================================================
// Variables
// =============================================================================

// Consistent resource name prefix: '<workload>-<environment>'
// Matches naming convention across all module deployments
var resourceNamePrefix = '${workloadName}-${environment}'

// Resource group name — defaults to '<workload>-<environment>-rg' if not explicitly provided
var resolvedResourceGroupName = empty(resourceGroupName) ? '${resourceNamePrefix}-rg' : resourceGroupName

// Images storage account name — same formula as storage.bicep, passed to the RBAC module
// so the existing container reference can be resolved without depending on module outputs
var imagesStorageAccountNameLocal = take(toLower(replace('${resourceNamePrefix}store', '-', '')), 24)

// =============================================================================
// Resource Group — created at subscription scope
// Replaces: CloudFormation stack-level resource group equivalent
// =============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resolvedResourceGroupName
  location: location
  tags: {
    environment: environment
    application: 'image-upload-service'
    'aws-equivalent': 'cloudformation-stack'
  }
}

// =============================================================================
// Module: Monitoring (must deploy first — others depend on App Insights ID/key)
// Replaces: Amazon CloudWatch Logs + CloudWatch Metrics + X-Ray
// =============================================================================
module monitoring './modules/monitoring.bicep' = {
  name: 'monitoringDeploy'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    logRetentionDays: logRetentionDays
  }
}

// =============================================================================
// Module: Blob Storage (parallel with staticweb after monitoring)
// Replaces: AWS S3 ImageBucket (private, versioned, CORS-enabled)
// =============================================================================
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    skuName: storageSkuName
  }
}

// =============================================================================
// Module: Static Web Apps (parallel with storage after monitoring)
// Replaces: AWS S3 WebsiteBucket (static website hosting)
// =============================================================================
module staticWebApp 'modules/staticweb.bicep' = {
  name: 'staticWebAppDeploy'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
  }
}

// =============================================================================
// Module: Azure Functions (depends on storage account name + App Insights)
// Replaces: 4 AWS Lambda functions (Upload, ListFiles, GetViewUrl, Delete)
// =============================================================================
module functions 'modules/functions.bicep' = {
  name: 'functionsDeploy'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    imagesStorageAccountName: storage.outputs.storageAccountName
    imagesContainerName: storage.outputs.containerName
    urlExpirationSeconds: urlExpirationSeconds
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

// =============================================================================
// Module: RBAC — Storage Blob Data Contributor on images container
// Replaces: AWS Lambda IAM Role inline S3Access policy
// Runs inside the resource group scope via a dedicated module (required at subscription scope)
// =============================================================================
module rbac 'modules/rbac.bicep' = {
  name: 'rbacDeploy'
  scope: rg
  params: {
    imagesStorageAccountName: imagesStorageAccountNameLocal
    resourceNamePrefix: resourceNamePrefix
    functionAppPrincipalId: functions.outputs.functionAppPrincipalId
  }
}

// =============================================================================
// Module: Key Vault (depends on function app principal ID)
// Replaces: AWS KMS + Secrets Manager
// =============================================================================
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  scope: rg
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    functionAppPrincipalId: functions.outputs.functionAppPrincipalId
  }
}

// =============================================================================
// Outputs — key values for application configuration and CI/CD
// =============================================================================

@description('Function App API base URL — direct HTTP trigger endpoint (replaces AWS API Gateway + Lambda).')
output apiBaseUrl string = 'https://${functions.outputs.functionAppHostname}/api'

@description('Static Web App URL — replaces AWS S3 website endpoint (HTTPS only).')
output staticWebAppUrl string = staticWebApp.outputs.staticWebAppUrl

@description('Function App hostname — for health checks and backend config.')
output functionAppHostname string = functions.outputs.functionAppHostname

@description('Storage account name — set as STORAGE_ACCOUNT_NAME in Function App config.')
output storageAccountName string = storage.outputs.storageAccountName

@description('Blob storage primary endpoint.')
output blobEndpoint string = storage.outputs.blobEndpoint

@description('Key Vault URI — for storing and retrieving secrets.')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Log Analytics Workspace resource ID.')
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId

@description('Application Insights resource ID.')
output appInsightsId string = monitoring.outputs.appInsightsId

@description('Resource group name where all resources are deployed.')
output resourceGroupName string = rg.name
