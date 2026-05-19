// =============================================================================
// modules/functionApp.bicep
// Purpose: Deploy Consumption-plan Azure Function App (Python 3.11 v2)
//   + App Service Plan (Y1 Consumption) for the photo-gallery workload.
//   Replaces: 4× AWS Lambda functions + Amazon API Gateway
// AVM modules:
//   br/public:avm/res/web/serverfarm:0.7.0   — App Service Plan (Y1 Linux)
//   br/public:avm/res/web/site:0.22.0        — Function App (functionapp,linux)
//   Selected per SKILLS.MD §Step 3 — Compute (Lambda → Azure Functions)
// =============================================================================

@description('Globally unique Function App name.')
param functionAppName string

@description('Azure region for deployment.')
param location string

@description('Storage account name used for Function App runtime (AzureWebJobsStorage).')
param storageAccountName string

@description('Resource ID of the storage account (for dependency tracking).')
param storageAccountId string

@description('Storage account connection string for AzureWebJobsStorage. Use MI-based config in prod.')
@secure()
param storageConnectionString string

@description('Application Insights connection string for telemetry.')
@secure()
param appInsightsConnectionString string

@description('Blob container name for images (passed as BLOB_CONTAINER_NAME env var).')
param imageContainerName string = 'images'

@description('SAS token lifetime in seconds (300–86400).')
@minValue(300)
@maxValue(86400)
param urlExpiration int = 3600

@description('CORS allowed origins for HTTP triggers. Use [\'*\'] for dev.')
param allowedCorsOrigins array = ['*']

@description('Consumption plan SKU. Must be Y1.')
@allowed(['Y1'])
param functionAppSkuName string = 'Y1'

// ---------------------------------------------------------------------------
// App Service Plan — Consumption Y1, Linux
// SKILLS.MD Pitfall 1: kind='linux' and reserved=true are REQUIRED for Linux
// skuTier removed in 0.7.0 — do not include
// ---------------------------------------------------------------------------
module appServicePlanAvmDeploy 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'appServicePlanAvmDeploy'
  params: {
    name: '${functionAppName}-plan'
    location: location
    skuName: functionAppSkuName
    kind: 'linux'
    reserved: true
  }
}

// ---------------------------------------------------------------------------
// Function App — functionapp,linux, Python 3.11, System-assigned MI
// SKILLS.MD Pitfall 2: linuxFxVersion must be 'PYTHON|3.11' (uppercase, pipe-separated)
// ---------------------------------------------------------------------------
module functionAppAvmDeploy 'br/public:avm/res/web/site:0.22.0' = {
  name: 'functionAppAvmDeploy'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: appServicePlanAvmDeploy.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      systemAssigned: true
    }
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      cors: {
        allowedOrigins: allowedCorsOrigins
        supportCredentials: false
      }
    }
    appSettingsKeyValuePairs: {
      // Function runtime settings
      AzureWebJobsStorage: storageConnectionString
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'python'
      // Application Insights telemetry
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
      ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
      // Photo gallery application settings
      STORAGE_ACCOUNT_NAME: storageAccountName
      BLOB_CONTAINER_NAME: imageContainerName
      URL_EXPIRATION: string(urlExpiration)
    }
  }
  dependsOn: [
    appServicePlanAvmDeploy
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Function App.')
output functionAppId string = functionAppAvmDeploy.outputs.resourceId

@description('Name of the Function App.')
output functionAppName string = functionAppAvmDeploy.outputs.name

@description('Default hostname of the Function App (e.g., photo-gallery-func.azurewebsites.net).')
output functionAppHostname string = functionAppAvmDeploy.outputs.defaultHostname

@description('System-assigned Managed Identity principal ID. Passed to rbac.bicep for Storage Blob Data Contributor assignment.')
output principalId string = functionAppAvmDeploy.outputs.systemAssignedMIPrincipalId

// Note: functionAppDefaultKey is a runtime value. Obtain post-deployment via:
//   az functionapp keys list --name <functionAppName> --resource-group <rg> --query defaultFunctionKey -o tsv
