// =============================================================================
// modules/staticWebApp.bicep
// Purpose: Deploy Azure Static Web Apps (Free tier) for the photo gallery SPA.
//   Replaces: S3 static website bucket (image-upload-websitebucket-vd866vxtcs1z)
//   Provides built-in global CDN, custom domain support, 100 GB/month bandwidth.
//   app.html (AWS) → index.html (Azure) rename required.
// AVM module: br/public:avm/res/web/static-site:0.9.3
//   Selected per SKILLS.MD §Step 3 — Storage (S3 Static Website → Static Web App)
// =============================================================================

@description('Globally unique Static Web App resource name.')
param staticWebAppName string

@description('Azure region for deployment. Must support SWA Free tier (australiaeast is supported).')
param location string = 'australiaeast'

@description('SWA SKU. Free for all environments; upgrade to Standard only if Entra auth is required.')
@allowed([
  'Free'
  'Standard'
])
param skuName string = 'Free'

@description('GitHub repository URL for CI/CD integration (e.g., https://github.com/org/repo).')
param repositoryUrl string

@description('Branch to deploy from. dev for dev, staging for staging, main for prod.')
param branch string = 'main'

// ---------------------------------------------------------------------------
// AVM Static Web App module
// SWA Free tier: no private endpoints, built-in CDN, 100 GB/month bandwidth
// ---------------------------------------------------------------------------
module staticWebAppAvmDeploy 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'staticWebAppAvmDeploy'
  params: {
    name: staticWebAppName
    location: location
    sku: skuName
    repositoryUrl: repositoryUrl
    branch: branch
    buildProperties: {
      appLocation: '/'
      apiLocation: ''
      outputLocation: ''
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Static Web App.')
output staticWebAppId string = staticWebAppAvmDeploy.outputs.resourceId

@description('Default hostname of the Static Web App (e.g., *.azurestaticapps.net). Use this in CORS config of Function App and Storage in prod.')
output defaultHostname string = staticWebAppAvmDeploy.outputs.defaultHostname

@description('Deployment token for GitHub Actions secret STATIC_WEB_APP_TOKEN.')
@secure()
output deploymentToken string = staticWebAppAvmDeploy.outputs.apiKey
