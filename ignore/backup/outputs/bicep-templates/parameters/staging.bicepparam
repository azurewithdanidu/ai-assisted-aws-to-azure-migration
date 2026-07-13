// ============================================================
// parameters/staging.bicepparam
// Staging environment parameter file for the image-upload
// Azure migration. Increased redundancy and retention vs dev.
//
// Storage: Standard_ZRS (zone-redundant within region)
// Functions: Y1 Consumption (can upgrade to EP1 if needed)
// Log retention: 60 days
// Daily cap: 5 GB (staging ingests more than dev)
// Key Vault: enabled
// ============================================================
using '../main.bicep'

// ── Core identity ─────────────────────────────────────────────────────────────
param environment          = 'staging'
param location             = 'australiasoutheast'
param resourcePrefix       = 'img-upload'

// ── Storage ───────────────────────────────────────────────────────────────────
param storageAccountName   = 'imguploadstgase'
param storageContainerName = 'images'
param storageReplication   = 'ZRS'

// ── Function App ──────────────────────────────────────────────────────────────
param functionAppName      = 'img-upload-func-stg-ase'
param appServicePlanName   = 'img-upload-plan-stg-ase'

// ── Static Web App ────────────────────────────────────────────────────────────
param staticWebAppName     = 'img-upload-swa-stg-ase'
param staticWebAppLocation = 'eastasia'

// ── Monitoring ────────────────────────────────────────────────────────────────
param logAnalyticsWorkspaceName = 'img-upload-law-stg-ase'
param applicationInsightsName  = 'img-upload-ai-stg-ase'
param logRetentionDays         = 60
param dailyCapGb               = 5

// ── Key Vault ─────────────────────────────────────────────────────────────────
param enableKeyVault       = true
param keyVaultName         = 'img-upload-kv-stg-ase'

// ── Application configuration ─────────────────────────────────────────────────
param sasExpirationSeconds = 3600
param maxUploadBytes       = 10485760

// ── CORS ──────────────────────────────────────────────────────────────────────
// Update the SWA hostname once deployed (output: staticWebAppHostname)
param corsAllowedOrigins   = [
  'https://img-upload-swa-stg-ase.azurestaticapps.net'
]

// ── Tags ──────────────────────────────────────────────────────────────────────
param tags = {
  workload: 'image-upload'
  environment: 'staging'
  migrationSource: 'aws-ap-southeast-2'
  managedBy: 'bicep'
  costCentre: 'engineering'
}
