// =============================================================================
// modules/keyvault.bicep — Key Vault (Standard, RBAC) (§5.4)
// =============================================================================
@description('Azure region.')
param location string

@description('Suffix for resource names.')
param resourceNameSuffix string

@description('Tags applied to all resources.')
param tags object

@description('Entra tenant ID.')
param tenantId string = subscription().tenantId

@description('Use RBAC authorization (true) vs access policies (false).')
param enableRbacAuthorization bool = true

@description('Soft-delete retention in days (7-90).')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 7

@description('Enable purge protection (recommended for prod).')
param enablePurgeProtection bool = false

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: 'kv-imgupload-${resourceNameSuffix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: enableRbacAuthorization
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
