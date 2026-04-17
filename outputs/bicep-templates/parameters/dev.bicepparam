// =============================================================================
// dev.bicepparam — Development Environment Parameters
// Equivalent to AWS CloudFormation Environment=dev
// Uses LRS storage (single replica), 30-day log retention, minimal cost
// =============================================================================

using '../main.bicep'

// Deployment region — eastus2 mirrors ap-southeast-2 geographic zone
param location = 'eastus2'

param environment = 'dev'

param workloadName = 'img-upload'

// LRS — single datacenter replication, lowest cost for dev
param storageSkuName = 'Standard_LRS'

// 30-day retention — minimum recommended for dev debugging
param logRetentionDays = 30

// SAS token expiration — mirrors AWS Lambda URL_EXPIRATION=3600
param urlExpirationSeconds = '3600'
