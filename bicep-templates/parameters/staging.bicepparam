// =============================================================================
// staging.bicepparam — Staging Environment Parameters
// Pre-production environment — mirrors prod config where practical
// Uses LRS storage, 60-day log retention, production-representative settings
// =============================================================================

using '../main.bicep'

param location = 'australiaeast'

param environment = 'staging'

param workloadName = 'img-upload'

// LRS in staging — use ZRS in prod. Upgrade if staging is a compliance requirement.
param storageSkuName = 'Standard_LRS'

// 60-day retention — enough to investigate issues before prod release
param logRetentionDays = 60

// Match production SAS expiration
param urlExpirationSeconds = '3600'
