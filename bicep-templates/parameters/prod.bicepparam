// =============================================================================
// prod.bicepparam — Production Environment Parameters
// Equivalent to AWS CloudFormation Environment=prod
// Uses ZRS storage (zone-redundant), 90-day log retention, stricter settings
// =============================================================================

using '../main.bicep'

param location = 'australiaeast'

param environment = 'prod'

param workloadName = 'img-upload'

// ZRS — zone-redundant storage for production resilience
// Provides 99.9999999999% (12 9s) durability across availability zones
param storageSkuName = 'Standard_ZRS'

// 90-day retention — meets typical compliance and audit requirements
param logRetentionDays = 90

// Standard SAS token expiration — reduce to 1800 (30 min) for higher security
param urlExpirationSeconds = '3600'
