// =============================================================================
// dev.bicepparam — Development Environment Parameters
// AWS equivalent: CloudFormation Environment=dev (ap-southeast-2)
// Uses Standard_LRS storage (single region), 30-day log retention, lowest cost
//
// Deploy:
//   az deployment sub create \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters parameters/dev.bicepparam
// =============================================================================

using '../main.bicep'

// Deployment region — australiaeast mirrors ap-southeast-2 geographic zone
param location = 'australiaeast'

param environment = 'dev'

param workloadName = 'img-upload'

// LRS — single datacenter replication, lowest cost for dev/test
param storageSkuName = 'Standard_LRS'

// 30-day retention — minimum recommended for dev debugging
param logRetentionDays = 30

// SAS token expiration — mirrors AWS Lambda URL_EXPIRATION=3600
param urlExpirationSeconds = '3600'
