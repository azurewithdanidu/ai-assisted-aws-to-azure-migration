// ── parameters/staging.bicepparam ───────────────────────────────────────────
// Staging environment parameter file for the Image Upload Service.
// Deploy to resource group: rg-imageupload-staging (australiaeast)
//
// Key differences from dev:
//   - storageSkuName: Standard_LRS (same as dev — staging mirrors dev cost)
//   - softDeleteDays: 14 (2-week retention for staging testing)
//   - retentionDays: 60 (2-month log retention)
//   - allowedCorsOrigin: placeholder — replace with actual SWA staging hostname
//     after first deploy: az deployment group show ... | jq '.properties.outputs.staticWebAppHostname.value'
//   - urlExpiration: 3600 (1 hour)
//   - staticWebAppSku: Free
//   - branch: staging

using '../main.bicep'

// ── Core identity ────────────────────────────────────────────────────────────
param environment        = 'staging'
param location           = 'australiaeast'
param workload           = 'imageupload'

// ── Tags ─────────────────────────────────────────────────────────────────────
param tags = {
  environment: 'staging'
  workload:    'imageupload'
  managedBy:   'bicep'
  project:     'aws-to-azure-migration'
}

// ── CORS ─────────────────────────────────────────────────────────────────────
// Replace this placeholder with the actual SWA staging hostname after first deploy.
// e.g. https://lemon-rock-0a1b2c3d.azurestaticapps.net
param allowedCorsOrigin  = 'https://staging-imageupload-swa-australiaeast.azurestaticapps.net'

// ── Storage ──────────────────────────────────────────────────────────────────
param storageSkuName     = 'Standard_LRS'
param softDeleteDays     = 14

// ── Monitoring ───────────────────────────────────────────────────────────────
param retentionDays      = 60

// ── Function App ─────────────────────────────────────────────────────────────
param urlExpiration      = 3600
// Key Vault must exist before deploying — create with:
//   az keyvault create --name kv-imageupload-staging --resource-group rg-imageupload-staging --location australiaeast
param keyVaultName       = 'kv-imageupload-staging'

// ── Static Web App ───────────────────────────────────────────────────────────
param staticWebAppSku    = 'Free'
param branch             = 'staging'
param repositoryUrl      = ''
param appLocation        = 'source-app/app-code/build'
param outputLocation     = ''
