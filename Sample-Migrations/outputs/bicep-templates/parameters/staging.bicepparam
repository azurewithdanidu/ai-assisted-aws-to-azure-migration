// =============================================================================
// staging.bicepparam — Staging Environment Parameters
// Pre-production environment — mirrors prod config where practical
// Uses Standard_LRS storage, 60-day log retention, production-representative settings
//
// Deploy:
//   az deployment sub create \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters parameters/staging.bicepparam
// =============================================================================

using '../main.bicep'

param location = 'australiaeast'

param environment = 'staging'

param workloadName = 'img-upload'

// LRS for staging — upgrade to Standard_ZRS if staging is a compliance boundary
// Design doc specifies Standard_ZRS for staging; use Standard_LRS to reduce cost
// for demo staging environments that don't need zone redundancy
param storageSkuName = 'Standard_LRS'

// 60-day retention — enough to investigate issues before production release
param logRetentionDays = 60

// Match production SAS expiration
param urlExpirationSeconds = '3600'
