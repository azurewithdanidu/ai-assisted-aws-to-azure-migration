// =============================================================================
// main.bicep — Image Upload Service — Azure IaC Entry Point
// Subscription-scoped orchestration: creates resource group + deploys all modules
// Converted from: AWS CloudFormation image-upload stack (ap-southeast-2)
// Target region: australiaeast (Sydney — same geographic zone)
//
// Deploy command:
//   az deployment sub create \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters parameters/dev.bicepparam
//
// Architecture (AWS → Azure):
//   API Gateway REST (AWS_IAM) → Azure Functions HTTP Triggers (direct, CORS via siteConfig)
//   Lambda × 4 (python3.11)   → Azure Functions (Consumption Y1, Python 3.11)
//   S3 image bucket            → Azure Blob Storage (Standard LRS, images container)
//   S3 website bucket          → Azure Static Web Apps (Free)
//   IAM Role (S3Access policy) → System-Assigned Managed Identity + RBAC
//   Secrets Manager / KMS      → Azure Key Vault (Standard, RBAC mode)
//   CloudWatch + X-Ray         → Log Analytics Workspace + Application Insights
//
// Deployment order (dependency-driven):
//   1. monitoring              (all others depend on App Insights connection string)
//   2. storage + staticWebApp  (parallel — no inter-dependency)
//   3. functions               (depends on storage.storageAccountName + monitoring.connectionString)
//   4. keyVault                (depends on functions.functionAppPrincipalId for KV Secrets User)
//   5. rbac                    (depends on functions.principalId + storage.containerName)
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// Parameters
// =============================================================================

@description('Azure region for all resources. Default: australiaeast (mirrors ap-southeast-2 geo).')
param location string = 'australiaeast'

@description('Environment name. Controls resource sizing, replication, and naming.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Workload name — used to build all resource names (e.g. img-upload → img-upload-dev-*).')
param workloadName string = 'img-upload'

@description('Storage account replication SKU. Dev: Standard_LRS, staging: Standard_ZRS, prod: Standard_GRS.')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageSkuName string = 'Standard_LRS'

@description('Log Analytics retention in days. Dev: 30, staging: 60, prod: 90.')
@minValue(7)
@maxValue(730)
param logRetentionDays int = 30

@description('SAS token expiration in seconds. Mirrors AWS Lambda URL_EXPIRATION=3600.')
param urlExpirationSeconds string = '3600'

// =============================================================================
// Variables
// =============================================================================

// Consistent resource name prefix: '<workload>-<environment>'
// Applied to all resource names across all modules
var resourceNamePrefix = '${workloadName}-${environment}'

// Resource group name — created at subscription scope
var resourceGroupName = '${resourceNamePrefix}-rg'

// =============================================================================
// Resource Group — created at subscription scope
// All module resources deploy into this resource group
// =============================================================================
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: {
    environment: environment
    application: 'image-upload-service'
    'source-aws-stack': 'image-upload (ap-southeast-2)'
  }
}

// =============================================================================
// Module 1: Monitoring (must deploy first — others depend on App Insights ID/key)
// Replaces: Amazon CloudWatch Logs + CloudWatch Metrics + X-Ray
// =============================================================================
module monitoring 'modules/monitoring.bicep' = {
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
// Module 2a: Blob Storage (parallel with staticWebApp after monitoring)
// Replaces: AWS S3 ImageBucket (private, versioned, CORS-enabled)
// =============================================================================
module storage 'modules/storage.bicep' = {
  name: 'storageDeploy'
  scope: rg
  dependsOn: [monitoring]
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
    skuName: storageSkuName
  }
}

// =============================================================================
// Module 2b: Static Web Apps (parallel with storage after monitoring)
// Replaces: AWS S3 WebsiteBucket (public static website, index: app.html)
// =============================================================================
module staticWebApp 'modules/staticweb.bicep' = {
  name: 'staticWebAppDeploy'
  scope: rg
  dependsOn: [monitoring]
  params: {
    location: location
    environment: environment
    resourceNamePrefix: resourceNamePrefix
  }
}

// =============================================================================
// Module 3: Azure Functions (depends on storage account name + App Insights)
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
// Module 4: Key Vault (depends on functions for principalId)
// Replaces: AWS KMS + Secrets Manager
// softDeleteRetentionInDays: 7 (dev/staging), 90 (prod) — computed inside module
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
// Module 5: RBAC — Storage Blob Data Contributor on images container
// Replaces: AWS Lambda IAM Role inline S3Access policy
// Scoped to container (principle of least privilege — not entire storage account)
// Role: ba92f5b4-2d11-453d-a403-e96b0029c9fe (Storage Blob Data Contributor)
// =============================================================================
module rbac 'modules/rbac.bicep' = {
  name: 'rbacDeploy'
  scope: rg
  params: {
    storageAccountName: storage.outputs.storageAccountName
    containerName: storage.outputs.containerName
    functionAppPrincipalId: functions.outputs.functionAppPrincipalId
  }
}

// =============================================================================
// Outputs — key values for application configuration and CI/CD
// =============================================================================

@description('Function App HTTPS URL — direct HTTP trigger endpoint for all API routes.')
output functionAppUrl string = 'https://${functions.outputs.functionAppHostname}'

@description('Static Web App HTTPS URL — frontend SPA endpoint.')
output staticWebAppUrl string = staticWebApp.outputs.staticWebAppUrl

@description('Images storage account name — used in BLOB_STORAGE_ACCOUNT_NAME and AZURE_STORAGE_ACCOUNT_NAME settings.')
output storageAccountName string = storage.outputs.storageAccountName

@description('Key Vault URI — for storing application secrets post-deployment.')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Resource group name created by this deployment.')
output resourceGroupName string = rg.name
