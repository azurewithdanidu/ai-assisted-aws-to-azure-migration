// ============================================================
// parameters/dev.bicepparam
// Development environment parameter file for the image-upload
// Azure migration. Targets australiasoutheast (ap-southeast-2
// equivalent). All SKUs sized for low cost and minimal spend.
//
// Storage: Standard_LRS (cheapest, no zone redundancy)
// Functions: Y1 Consumption (cold starts acceptable in dev)
// Log retention: 30 days (minimum)
// Daily cap: 1 GB (cost guard for dev telemetry)
// Key Vault: enabled (recommended even for dev)
// ============================================================
using '../main.bicep'

// ── Core identity ─────────────────────────────────────────────────────────────
param environment          = 'dev'
param location             = 'australiasoutheast'
param resourcePrefix       = 'img-upload'

// ── Storage ───────────────────────────────────────────────────────────────────
param storageAccountName   = 'imguploaddevase'
param storageContainerName = 'images'
param storageReplication   = 'LRS'

// ── Function App ──────────────────────────────────────────────────────────────
param functionAppName      = 'img-upload-func-dev-ase'
param appServicePlanName   = 'img-upload-plan-dev-ase'

// ── Static Web App ────────────────────────────────────────────────────────────
param staticWebAppName     = 'img-upload-swa-dev-ase'
param staticWebAppLocation = 'eastasia'

// ── Monitoring ────────────────────────────────────────────────────────────────
param logAnalyticsWorkspaceName = 'img-upload-law-dev-ase'
param applicationInsightsName  = 'img-upload-ai-dev-ase'
param logRetentionDays         = 30
param dailyCapGb               = 1

// ── Key Vault ─────────────────────────────────────────────────────────────────
param enableKeyVault       = true
param keyVaultName         = 'img-upload-kv-dev-ase'

// ── Application configuration ─────────────────────────────────────────────────
param sasExpirationSeconds = 3600
param maxUploadBytes       = 10485760

// ── CORS ──────────────────────────────────────────────────────────────────────
// Update the SWA hostname once deployed (output: staticWebAppHostname)
param corsAllowedOrigins   = [
  'http://localhost:3000'
  'http://localhost:5173'
]

// ── Tags ──────────────────────────────────────────────────────────────────────
param tags = {
  workload: 'image-upload'
  environment: 'dev'
  migrationSource: 'aws-ap-southeast-2'
  managedBy: 'bicep'
  costCentre: 'engineering'
}
