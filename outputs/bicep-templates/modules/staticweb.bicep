// =============================================================================
// staticweb.bicep — Static Web Apps Module
// Deploys Azure Static Web Apps replacing AWS S3 static website hosting
// Adds: built-in CDN, HTTPS enforcement, auto-managed SSL certificate
// AWS equivalent: S3 WebsiteBucket (app.html index, error.html error doc)
// AVM module: web/static-site:0.9.3
// =============================================================================

metadata name = 'Static Web Apps Module'
metadata description = 'Deploys Azure Static Web Apps (replaces AWS S3 WebsiteBucket static hosting) for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module.')
param resourceNamePrefix string

// =============================================================================
// Static Web App — replaces AWS S3 WebsiteBucket + static website hosting
// Free tier includes: CDN, SSL, custom domain support, 100GB bandwidth/month
// Index: app.html, Error: error.html — mirrors CloudFormation WebsiteConfiguration
// HTTPS only enforced (improvement over HTTP-accessible S3 website)
// =============================================================================
module staticWebApp 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'swaAvmDeploy'
  params: {
    name: '${resourceNamePrefix}-swa'
    location: location
    sku: 'Free'
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 's3-static-website'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Default hostname of the Static Web App (HTTPS).')
output staticWebAppUrl string = 'https://${staticWebApp.outputs.defaultHostname}'

@description('Default hostname (without https prefix).')
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname

@description('Resource ID of the Static Web App.')
output staticWebAppId string = staticWebApp.outputs.resourceId

@description('Name of the Static Web App.')
output staticWebAppName string = staticWebApp.outputs.name
