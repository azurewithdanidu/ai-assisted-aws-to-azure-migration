// ============================================================
// modules/static-web-app.bicep
// Creates an Azure Static Web App (Free tier) to host the
// SPA frontend. The default hostname is output for use in
// CORS configuration on the Function App and Blob Storage.
//
// AVM module used (per module-organization skill):
//   - avm/res/web/static-site:0.9.3
//
// NOTE: Static Web Apps have limited regional availability.
// The `location` parameter should be overridden via
// staticWebAppLocation in main.bicep if the primary region
// is not supported (e.g. use 'eastasia' for Asia-Pacific).
//
// Outputs: staticWebAppId, staticWebAppName, defaultHostname
// ============================================================

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Name of the Azure Static Web App resource.')
param staticWebAppName string

@description('Azure region. Must be a region that supports Static Web Apps Free tier.')
param location string

@description('SKU / tier for the Static Web App. Free for dev, Standard for staging/prod.')
@allowed(['Free', 'Standard'])
param sku string = 'Free'

@description('Resource tags.')
param tags object = {}

// ─────────────────────────────────────────────────────────────────────────────
// RESOURCES
// ─────────────────────────────────────────────────────────────────────────────

// Static Web App — Free tier SPA host
// AVM: avm/res/web/static-site:0.9.3
module staticSite 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'staticSiteAvmDeploy'
  params: {
    name: staticWebAppName
    location: location
    sku: sku
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

@description('ARM resource ID of the Static Web App.')
output staticWebAppId string = staticSite.outputs.resourceId

@description('Name of the Static Web App resource.')
output staticWebAppName string = staticSite.outputs.name

@description('Default hostname for the SPA — use this in Function App and Blob Storage CORS rules.')
output defaultHostname string = staticSite.outputs.defaultHostname
