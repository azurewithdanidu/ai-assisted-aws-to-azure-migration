// ── deploy/dev.bicepparam ────────────────────────────────────────────────────
// Dev parameters for the deployment wrapper (SWA location override).
// Mirrors outputs/bicep-templates/parameters/dev.bicepparam exactly.

using './main-deploy.bicep'

param environment        = 'dev'
param location           = 'australiaeast'
param workload           = 'imageupload'

param tags = {
  environment: 'dev'
  workload:    'imageupload'
  managedBy:   'bicep'
  project:     'aws-to-azure-migration'
}

param allowedCorsOrigin  = '*'
param storageSkuName     = 'Standard_LRS'
param softDeleteDays     = 7
param retentionDays      = 30
param urlExpiration      = 3600
param keyVaultName       = 'kv-imageupload-dev'
