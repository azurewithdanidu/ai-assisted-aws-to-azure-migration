// ============================================================
// modules/function-app.bicep
// Creates:
//   - Consumption Y1 App Service Plan (Linux)
//   - Azure Function App (Python 3.11, system-assigned MI)
//   - Azure Key Vault (when enableKeyVault = true)
//
// AVM modules used (per module-organization skill):
//   - avm/res/web/serverfarm:0.7.0   — App Service Plan
//   - avm/res/web/site:0.22.0        — Function App
//   - avm/res/key-vault/vault:0.13.3 — Key Vault (conditional)
//
// BREAKING CHANGES applied:
//   serverfarm 0.7.0: skuTier removed — use skuName only
//   serverfarm 0.7.0: kind:'linux' + reserved:true required for Linux
//   site 0.22.0: linuxFxVersion must be 'PYTHON|3.11'
//
// Auth note: App Service Authentication (EasyAuth v2) for
// Microsoft Entra ID requires the Entra app registration
// client ID, which is created after deployment. Configure
// authSettingV2 as a post-deployment step once the client ID
// is known.
//
// Outputs: functionAppId, functionAppName, functionHostname,
//          principalId, keyVaultUri, keyVaultResourceId
// ============================================================

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Name of the App Service Plan (Consumption Y1).')
param appServicePlanName string

@description('Name of the Azure Function App.')
param functionAppName string

@description('Azure region.')
param location string

@description('Name of the storage account for function runtime and image storage.')
param storageAccountName string

@description('Primary blob endpoint of the storage account.')
param blobEndpoint string

@description('ARM resource ID of the storage account.')
param storageAccountResourceId string

@description('Application Insights connection string (from monitoring module).')
param appInsightsConnectionString string

@description('SAS token expiry in seconds — replaces AWS URL_EXPIRATION.')
param sasExpirationSeconds int = 3600

@description('Maximum upload size in bytes (default 10 MB).')
param maxUploadBytes int = 10485760

@description('Name of the images blob container.')
param imagesContainerName string = 'images'

@description('CORS allowed origins for the Function App.')
param corsAllowedOrigins array = []

@description('Enable Azure Key Vault for runtime secret references.')
param enableKeyVault bool = true

@description('Name of the Key Vault. Used when enableKeyVault = true.')
param keyVaultName string = ''

@description('Resource tags.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────────────

var effectiveKeyVaultName = empty(keyVaultName) ? 'kv-${take(functionAppName, 14)}' : keyVaultName

// ─────────────────────────────────────────────────────────────────────────────
// RESOURCES
// ─────────────────────────────────────────────────────────────────────────────

// App Service Plan — Consumption Y1, Linux
// AVM: avm/res/web/serverfarm:0.7.0
// IMPORTANT: kind:'linux' and reserved:true are REQUIRED for Linux — omitting
// them silently creates a Windows plan causing Python runtime failures.
module appPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'appPlanAvmDeploy'
  params: {
    name: appServicePlanName
    location: location
    skuName: 'Y1'
    kind: 'linux'
    reserved: true
    tags: tags
  }
}

// Key Vault — optional, for secure secret references
// AVM: avm/res/key-vault/vault:0.13.3
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = if (enableKeyVault) {
  name: 'keyVaultAvmDeploy'
  params: {
    name: effectiveKeyVaultName
    location: location
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: false
    softDeleteRetentionInDays: 7
    tags: tags
  }
}

// Function App — Linux, Python 3.11, system-assigned managed identity
// AVM: avm/res/web/site:0.22.0
// App settings use managed identity for storage access (no connection strings).
// AzureWebJobsStorage is configured via __accountName + __credential pattern
// to avoid storing storage keys.
module functionAppSite 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionAppSiteAvmDeploy'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: appPlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: {
      // REQUIRED: uppercase 'PYTHON|3.11' — lowercase or blank causes Python 3.6 default
      linuxFxVersion: 'PYTHON|3.11'
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.2'
      cors: {
        allowedOrigins: union(
          corsAllowedOrigins,
          ['https://functions.azure.com', 'https://functions-staging.azure.com']
        )
        supportCredentials: false
      }
    }
    configs: [
      {
        name: 'appsettings'
        properties: {
          // Azure Functions runtime
          FUNCTIONS_WORKER_RUNTIME: 'python'
          FUNCTIONS_EXTENSION_VERSION: '~4'
          WEBSITE_RUN_FROM_PACKAGE: '1'

          // Storage — uses managed identity, no connection string stored
          AzureWebJobsStorage__accountName: storageAccountName
          AzureWebJobsStorage__credential: 'managedidentity'

          // Application configuration — maps from AWS Lambda env vars
          SAS_EXPIRATION_SECONDS: string(sasExpirationSeconds)
          MAX_UPLOAD_BYTES: string(maxUploadBytes)
          IMAGES_CONTAINER_NAME: imagesContainerName
          AZURE_STORAGE_ACCOUNT_NAME: storageAccountName
          AZURE_STORAGE_BLOB_ENDPOINT: blobEndpoint

          // Telemetry
          APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
          ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
        }
        storageAccountResourceId: storageAccountResourceId
        storageAccountUseIdentityAuthentication: true
      }
    ]
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

@description('ARM resource ID of the Function App.')
output functionAppId string = functionAppSite.outputs.resourceId

@description('Name of the Function App.')
output functionAppName string = functionAppSite.outputs.name

@description('Default hostname of the Function App (without https://).')
output functionHostname string = functionAppSite.outputs.defaultHostname

@description('System-assigned managed identity principal ID for RBAC assignments.')
output principalId string = functionAppSite.outputs.?systemAssignedMIPrincipalId ?? ''

@description('URI of the Key Vault. Empty string when enableKeyVault = false.')
output keyVaultUri string = enableKeyVault ? 'https://${effectiveKeyVaultName}.${environment().suffixes.keyvaultDns}' : ''

@description('ARM resource ID of the Key Vault. Empty string when enableKeyVault = false.')
output keyVaultResourceId string = enableKeyVault ? resourceId('Microsoft.KeyVault/vaults', effectiveKeyVaultName) : ''
