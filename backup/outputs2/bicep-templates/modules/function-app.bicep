// ── modules/function-app.bicep ──────────────────────────────────────────────
// Purpose: Consumption plan (Y1/Linux), Azure Function App (Python 3.11, v2
//          model), system-assigned managed identity, Key Vault references,
//          Application Insights integration.
//
// AVM modules:
//   br/public:avm/res/web/serverfarm:0.7.0    (hosting plan)
//   br/public:avm/res/web/site:0.22.0          (function app)

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name, e.g. imageupload.')
param workload string

@description('Azure region, e.g. australiaeast.')
param location string

@description('Resource tags applied to all resources.')
param tags object

@description('Storage Account name (from storage module output). Used for AzureWebJobsStorage managed identity auth.')
param storageAccountName string

@description('Storage Account resource ID (from storage module output).')
param storageAccountId string

@description('Application Insights connection string (from monitoring module output).')
param appInsightsConnectionString string

@description('Key Vault name. A new Key Vault is created with this name if it does not exist.')
param keyVaultName string

@description('Object ID of the deploying principal — granted Key Vault Secrets Officer during deployment.')
param deployerObjectId string = ''

@minValue(300)
@maxValue(86400)
@description('SAS token expiry in seconds. 3600 (1 hr) for dev/staging, 1800 (30 min) for prod.')
param urlExpiration int = 3600

@description('Frontend origin allowed for CORS. Pass * only in dev; use SWA hostname in staging/prod.')
param allowedCorsOrigin string

// ── Variables ───────────────────────────────────────────────────────────────
var functionAppName = '${environment}-${workload}-func-${location}'
var hostingPlanName = '${environment}-${workload}-plan-${location}'
// Azure Storage container name for images
var containerName = 'images'

// ── Key Vault (with purge protection) ───────────────────────────────────────
// Stores STORAGE_ACCOUNT_NAME secret for Key Vault references in app settings.
// enablePurgeProtection + enableSoftDelete required by security checklist §7.4.
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'keyVaultDeploy'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    // Grant the Function App managed identity Secrets User access
    // (principalId is wired after functionApp deployment via main.bicep post-deploy step)
    roleAssignments: empty(deployerObjectId) ? [] : [
      {
        principalId: deployerObjectId
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'ServicePrincipal'
      }
    ]
    secrets: [
      {
        name: 'storage-account-name'
        value: storageAccountName
      }
    ]
  }
}

// ── AVM App Service Plan (Consumption / Y1 / Linux) ─────────────────────────
// IMPORTANT: kind='linux' and reserved=true are required for Linux Consumption plan.
// Omitting them silently creates a Windows plan that fails at Python runtime.
module hostingPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'hostingPlanDeploy'
  params: {
    name: hostingPlanName
    location: location
    tags: tags
    skuName: 'Y1'
    skuCapacity: 0
    kind: 'linux'
    reserved: true
  }
}

// ── AVM Function App ─────────────────────────────────────────────────────────
module functionApp 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionAppDeploy'
  params: {
    name: functionAppName
    location: location
    tags: tags
    kind: 'functionapp,linux'
    serverFarmResourceId: hostingPlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    httpsOnly: true
    siteConfig: {
      // REQUIRED for Python 3.11 on Linux — uppercased, pipe-separated
      linuxFxVersion: 'PYTHON|3.11'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          // Managed identity auth for AzureWebJobsStorage — no connection string
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          // Key Vault reference — storage account name stored as secret
          name: 'STORAGE_ACCOUNT_NAME'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=storage-account-name)'
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: containerName
        }
        {
          name: 'URL_EXPIRATION'
          value: string(urlExpiration)
        }
        {
          name: 'ALLOWED_CORS_ORIGIN'
          value: allowedCorsOrigin
        }
        {
          // Required for storage account resource ID lookup (SAS generation)
          name: 'STORAGE_ACCOUNT_RESOURCE_ID'
          value: storageAccountId
        }
      ]
      cors: {
        allowedOrigins: [
          allowedCorsOrigin
        ]
        supportCredentials: false
      }
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
@description('Function App resource ID.')
output resourceId string = functionApp.outputs.resourceId

@description('Function App name.')
output resourceName string = functionApp.outputs.name

@description('System-assigned managed identity principal ID.')
// systemAssigned: true is always set above — non-null assertion is safe.
output principalId string = functionApp.outputs.systemAssignedMIPrincipalId!

@description('Function App default hostname (e.g. func.azurewebsites.net).')
output defaultHostname string = functionApp.outputs.defaultHostname
