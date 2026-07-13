// ── parameters/dev.bicepparam ────────────────────────────────────────────────
// Development environment parameter file for the Image Upload Service.
// Deploy to resource group: rg-imageupload-dev (australiaeast)
//
// Key differences from staging/prod:
//   - storageSkuName: Standard_LRS (single zone — cost optimised)
//   - softDeleteDays: 7 (minimum retention)
//   - retentionDays: 30 (minimum log retention)
//   - allowedCorsOrigin: * (permissive — any origin allowed)
//   - urlExpiration: 3600 (1 hour SAS tokens)
//   - staticWebAppSku: Free
//   - branch: dev

using '../main.bicep'

// ── Core identity ────────────────────────────────────────────────────────────
param environment        = 'dev'
param location           = 'australiaeast'
param workload           = 'imageupload'

// ── Tags ─────────────────────────────────────────────────────────────────────
param tags = {
  environment: 'dev'
  workload:    'imageupload'
  managedBy:   'bicep'
  project:     'aws-to-azure-migration'
}

// ── CORS ─────────────────────────────────────────────────────────────────────
// Dev: permissive — allow all origins for local development
param allowedCorsOrigin  = '*'

// ── Storage ──────────────────────────────────────────────────────────────────
param storageSkuName     = 'Standard_LRS'
param softDeleteDays     = 7

// ── Monitoring ───────────────────────────────────────────────────────────────
param retentionDays      = 30

// ── Function App ─────────────────────────────────────────────────────────────
param urlExpiration      = 3600
// Key Vault must exist before deploying — create with:
//   az keyvault create --name kv-imageupload-dev --resource-group rg-imageupload-dev --location australiaeast
param keyVaultName       = 'kv-imageupload-dev'

// ── Static Web App ───────────────────────────────────────────────────────────
param staticWebAppSku    = 'Free'
param branch             = 'dev'
param repositoryUrl      = ''
param appLocation        = 'source-app/app-code/build'
param outputLocation     = ''
