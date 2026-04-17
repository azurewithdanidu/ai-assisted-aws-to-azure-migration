// =============================================================================
// keyvault.bicep — Key Vault Module
// Deploys Azure Key Vault for secrets and key management
// AWS equivalent: AWS KMS + Secrets Manager
// AVM module: key-vault/vault:0.13.3
// =============================================================================

metadata name = 'Key Vault Module'
metadata description = 'Deploys Azure Key Vault (replaces AWS KMS and Secrets Manager) for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module.')
param resourceNamePrefix string

@description('Object ID of the Function App system-assigned managed identity principal.')
param functionAppPrincipalId string = ''

// Key Vault name must be globally unique, 3-24 chars, alphanumeric + hyphens
var keyVaultName = take('${resourceNamePrefix}-kv', 24)

// =============================================================================
// Key Vault — replaces AWS KMS + Secrets Manager
// RBAC-based access model (preferred over access policies)
// Soft delete and purge protection enabled for compliance
// =============================================================================
module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'kvAvmDeploy'
  params: {
    name: keyVaultName
    location: location
    sku: 'standard'
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: false
    // Grant Function App managed identity read access to secrets
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

@description('Resource ID of the Key Vault.')
output keyVaultId string = keyVault.outputs.resourceId

@description('URI of the Key Vault for SDK access.')
output keyVaultUri string = keyVault.outputs.uri

@description('Name of the Key Vault.')
output keyVaultName string = keyVault.outputs.name
