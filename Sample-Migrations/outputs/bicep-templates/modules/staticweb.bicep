// =============================================================================
// staticweb.bicep — Static Web Apps Module
// Deploys Azure Static Web Apps (Free tier)
// Replaces: AWS S3 WebsiteBucket (public, index: app.html)
// Design doc: Section 5.4
//
// Notes:
//   - HTTPS enforced automatically (improvement over plain HTTP S3 website)
//   - Deploy app.html via SWA CLI or GitHub Actions post-provisioning
//   - Add staticwebapp.config.json with route "/" → "/app.html" to serve SPA root
//   - SWA region availability: australiaeast is supported; if deployment fails,
//     set location to 'eastasia' or 'eastus2'
// =============================================================================

metadata name = 'Static Web Apps Module'
metadata description = 'Deploys Azure Static Web Apps Free tier (replaces AWS S3 static website hosting)'

@description('Azure region for all resources. SWA has limited region coverage — australiaeast is supported.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

// =============================================================================
// Static Web App — replaces AWS S3 WebsiteBucket + static website hosting
// Free tier: CDN, SSL, custom domain, 100 GB bandwidth/month
// All environments use Free tier for this image upload workload
// =============================================================================
module staticWebApp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'staticWebAppDeploy'
  params: {
    name: '${resourceNamePrefix}-swa'
    location: location
    sku: 'Free'
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 's3-websitebucket-static-hosting'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Full HTTPS URL of the Static Web App.')
output staticWebAppUrl string = 'https://${staticWebApp.outputs.defaultHostname}'

@description('Default hostname (without https:// prefix) — use for APIM CORS allowed-origins in prod.')
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname

@description('Resource ID of the Static Web App.')
output staticWebAppId string = staticWebApp.outputs.resourceId

@description('Name of the Static Web App resource.')
output staticWebAppName string = staticWebApp.outputs.name
