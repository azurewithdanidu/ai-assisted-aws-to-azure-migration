// ── parameters/prod.bicepparam ───────────────────────────────────────────────
// Production environment parameter file for the Image Upload Service.
// Deploy to resource group: rg-imageupload-prod (australiaeast)
//
// Key differences from dev/staging:
//   - storageSkuName: Standard_ZRS (zone-redundant — HA for production)
//   - softDeleteDays: 30 (1-month retention)
//   - retentionDays: 90 (3-month log retention — compliance)
//   - allowedCorsOrigin: placeholder — replace with actual SWA prod hostname
//   - urlExpiration: 1800 (30-min SAS tokens — tighter security window)
//   - staticWebAppSku: Standard (custom domain, SLA)
//   - branch: main

using '../main.bicep'

// ── Core identity ────────────────────────────────────────────────────────────
param environment        = 'prod'
param location           = 'australiaeast'
param workload           = 'imageupload'

// ── Tags ─────────────────────────────────────────────────────────────────────
param tags = {
  environment: 'prod'
  workload:    'imageupload'
  managedBy:   'bicep'
  project:     'aws-to-azure-migration'
  costCenter:  'engineering'
}

// ── CORS ─────────────────────────────────────────────────────────────────────
// Replace this placeholder with the actual SWA prod hostname after first deploy.
// e.g. https://victorious-sea-0a1b2c3d.azurestaticapps.net
// Or use a custom domain if configured on the Standard tier SWA.
param allowedCorsOrigin  = 'https://prod-imageupload-swa-australiaeast.azurestaticapps.net'

// ── Storage ──────────────────────────────────────────────────────────────────
// Standard_ZRS: zone-redundant for production availability
param storageSkuName     = 'Standard_ZRS'
param softDeleteDays     = 30

// ── Monitoring ───────────────────────────────────────────────────────────────
param retentionDays      = 90

// ── Function App ─────────────────────────────────────────────────────────────
// Shorter SAS expiry for production (30 min vs 1 hr in dev/staging)
param urlExpiration      = 1800
// Key Vault must exist before deploying — create with:
//   az keyvault create --name kv-imageupload-prod --resource-group rg-imageupload-prod --location australiaeast --enable-purge-protection true
param keyVaultName       = 'kv-imageupload-prod'

// ── Static Web App ───────────────────────────────────────────────────────────
// Standard SKU for production: custom domain + SLA + more concurrent builds
param staticWebAppSku    = 'Standard'
param branch             = 'main'
param repositoryUrl      = ''
param appLocation        = 'source-app/app-code/build'
param outputLocation     = ''
