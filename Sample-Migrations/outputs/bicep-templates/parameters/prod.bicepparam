// =============================================================================
// prod.bicepparam — Production Environment Parameters
// AWS equivalent: CloudFormation Environment=prod (ap-southeast-2)
// Uses Standard_GRS storage (geo-redundant), 90-day log retention
//
// Deploy:
//   az deployment sub create \
//     --location australiaeast \
//     --template-file main.bicep \
//     --parameters parameters/prod.bicepparam
//
// Post-deployment actions (prod only):
//   1. Rotate/invalidate AWS IAM access key AKIAXZEFIIOD2OIWPRPK
//   2. Delete CloudFormation stack 'image-upload' post-cutover
//   3. Restrict Function App CORS allowed-origins to Static Web App hostname
// =============================================================================

using '../main.bicep'

param location = 'australiaeast'

param environment = 'prod'

param workloadName = 'img-upload'

// GRS — geo-redundant storage for production resilience
// Replicates data to a secondary region (australiasoutheast)
// Design doc: Standard_GRS; upgrade to Standard_RAGRS for read-access geo-redundancy
param storageSkuName = 'Standard_GRS'

// 90-day retention — meets typical compliance and audit requirements
// Key Vault soft-delete retention (computed in keyvault.bicep) also set to 90 days for prod
param logRetentionDays = 90

// Standard SAS token expiration — consider reducing to 1800 (30 min) for higher security
param urlExpirationSeconds = '3600'
