// =============================================================================
// modules/staticWebApp.bicep — Azure Static Web App, Free SKU (§5.8)
// =============================================================================
@description('Region for the Static Web App. Free SKU is region-constrained; eastasia recommended for AU.')
param location string = 'eastasia'

@description('Suffix for resource names.')
param resourceNameSuffix string

@description('Tags applied to all resources.')
param tags object

@description('Function App default hostname — used to wire SPA → API base URL via app settings.')
param apiBaseUrl string

@description('Optional source repository URL. Leave empty to deploy via SWA CLI / GH Actions token.')
param repositoryUrl string = ''

@description('Optional branch (only used when repositoryUrl is set).')
param branch string = 'main'

var staticWebAppName = 'swa-imgupload-${resourceNameSuffix}'

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    provider: empty(repositoryUrl) ? 'None' : 'GitHub'
    repositoryUrl: empty(repositoryUrl) ? null : repositoryUrl
    branch: empty(repositoryUrl) ? null : branch
    buildProperties: {
      appLocation: '/'
      outputLocation: ''
    }
  }
}

// Surface the API base URL to the SPA at runtime via SWA app settings.
resource swaAppSettings 'Microsoft.Web/staticSites/config@2023-12-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    API_BASE_URL: 'https://${apiBaseUrl}/api'
  }
}

output staticWebAppName string = staticWebApp.name
output defaultHostname string = staticWebApp.properties.defaultHostname
output staticWebAppId string = staticWebApp.id
