// =============================================================================
// keyvault.bicep — Key Vault Module
// Deploys Azure Key Vault for storing APIM subscription key and future secrets
// AWS equivalent: AWS KMS + Secrets Manager
// Design doc: Section 5.5
//
// Security:
//   enableRbacAuthorization: true — RBAC mode (not access policies)
//   enablePurgeProtection: true   — prevents accidental/malicious key destruction
//   enableSoftDelete: true        — recoverable delete window
//   softDeleteRetentionInDays:    — 7 (dev/staging), 90 (prod) per design spec
//
// Post-deployment:
//   Store APIM subscription primary key as secret 'apim-subscription-primary-key'
//   after APIM deployment completes.
// =============================================================================

metadata name = 'Key Vault Module'
metadata description = 'Deploys Azure Key Vault (replaces AWS KMS + Secrets Manager) for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod). Controls soft-delete retention days.')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

@description('Object ID of the Function App system-assigned managed identity. Used for Key Vault Secrets User role assignment.')
param functionAppPrincipalId string = ''

// Key Vault name: 3-24 chars, alphanumeric + hyphens
// take(resourceNamePrefix, 18) ensures total with '-kv' stays within 24 chars
var keyVaultName = '${take(resourceNamePrefix, 18)}-kv'

// Soft-delete retention: 7 days for dev/staging, 90 days for prod
// Purge protection is always enabled regardless of environment
var softDeleteRetentionDays = environment == 'prod' ? 90 : 7

// =============================================================================
// Key Vault — replaces AWS KMS + Secrets Manager
// RBAC authorization mode (preferred — no access policy sprawl)
// Purge protection: always enabled (cannot be disabled once on)
// =============================================================================
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'keyVaultDeploy'
  params: {
    name: keyVaultName
    location: location
    sku: 'standard'
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionDays
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: false
    // Grant Function App managed identity read access to secrets
    // (used to retrieve APIM subscription key at runtime if needed)
    roleAssignments: functionAppPrincipalId != '' ? [
      {
        principalId: functionAppPrincipalId
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalType: 'ServicePrincipal'
      }
    ] : []
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'kms-secrets-manager'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Name of the Key Vault.')
output keyVaultName string = keyVault.outputs.name

@description('URI of the Key Vault for SDK access (e.g. for SecretClient).')
output keyVaultUri string = keyVault.outputs.uri

@description('Resource ID of the Key Vault.')
output keyVaultResourceId string = keyVault.outputs.resourceId
