// =============================================================================
// modules/functionApp.bicep — Linux Consumption Function App, Python 3.11 (§5.7)
// =============================================================================
@description('Azure region.')
param location string

@description('Suffix for resource names.')
param resourceNameSuffix string

@description('Tags applied to all resources.')
param tags object

@description('Name of the AzureWebJobsStorage backing storage account.')
param storageAccountName string

@description('Resource ID of the User-Assigned Managed Identity.')
param userAssignedIdentityId string

@description('Client ID of the User-Assigned Managed Identity.')
param userAssignedIdentityClientId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Python runtime version.')
param pythonVersion string = '3.11'

@description('Blob container that stores uploaded images.')
param imagesContainerName string = 'images'

@description('SAS expiration in seconds.')
param urlExpirationSeconds int = 3600

@description('CORS origins allowed by the Function App. dev = ["*"], prod = SWA hostname.')
param allowedCorsOrigins array = []

var planName = 'plan-imgupload-${resourceNameSuffix}'
var functionAppName = 'func-imgupload-${resourceNameSuffix}'

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    keyVaultReferenceIdentity: userAssignedIdentityId
    siteConfig: {
      linuxFxVersion: 'Python|${pythonVersion}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
      http20Enabled: true
      cors: {
        allowedOrigins: empty(allowedCorsOrigins) ? [
          '*'
        ] : allowedCorsOrigins
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: userAssignedIdentityClientId
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'IMAGES_CONTAINER_NAME'
          value: imagesContainerName
        }
        {
          name: 'URL_EXPIRATION_SECONDS'
          value: string(urlExpirationSeconds)
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output functionAppPrincipalId string = userAssignedIdentityClientId
output functionAppResourceId string = functionApp.id
