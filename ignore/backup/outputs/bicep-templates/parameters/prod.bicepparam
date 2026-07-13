// ============================================================
// parameters/prod.bicepparam
// Production environment parameter file for the image-upload
// Azure migration. Maximum redundancy, retention, and security.
//
// Storage: Standard_GRS (geo-redundant for disaster recovery)
// Functions: Y1 Consumption (upgrade to EP1/EP2 if cold-start
//            latency becomes unacceptable — see parameter-
//            management skill best practices)
// Log retention: 90 days (regulatory baseline)
// Daily cap: 10 GB
// Key Vault: enabled, soft delete retention 30 days
// ============================================================
using '../main.bicep'

// ── Core identity ─────────────────────────────────────────────────────────────
param environment          = 'prod'
param location             = 'australiasoutheast'
param resourcePrefix       = 'img-upload'

// ── Storage ───────────────────────────────────────────────────────────────────
param storageAccountName   = 'imguploadprdase'
param storageContainerName = 'images'
param storageReplication   = 'GRS'

// ── Function App ──────────────────────────────────────────────────────────────
param functionAppName      = 'img-upload-func-prd-ase'
param appServicePlanName   = 'img-upload-plan-prd-ase'

// ── Static Web App ────────────────────────────────────────────────────────────
param staticWebAppName     = 'img-upload-swa-prd-ase'
param staticWebAppLocation = 'eastasia'

// ── Monitoring ────────────────────────────────────────────────────────────────
param logAnalyticsWorkspaceName = 'img-upload-law-prd-ase'
param applicationInsightsName  = 'img-upload-ai-prd-ase'
param logRetentionDays         = 90
param dailyCapGb               = 10

// ── Key Vault ─────────────────────────────────────────────────────────────────
param enableKeyVault       = true
param keyVaultName         = 'img-upload-kv-prd-ase'

// ── Application configuration ─────────────────────────────────────────────────
param sasExpirationSeconds = 3600
param maxUploadBytes       = 10485760

// ── CORS ──────────────────────────────────────────────────────────────────────
// Replace the placeholder with the actual production SWA hostname
// and any custom domain once configured.
param corsAllowedOrigins   = [
  'https://img-upload-swa-prd-ase.azurestaticapps.net'
]

// ── Tags ──────────────────────────────────────────────────────────────────────
param tags = {
  workload: 'image-upload'
  environment: 'prod'
  migrationSource: 'aws-ap-southeast-2'
  managedBy: 'bicep'
  costCentre: 'engineering'
}
