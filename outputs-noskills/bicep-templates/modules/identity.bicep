// =============================================================================
// modules/identity.bicep — User-Assigned Managed Identity (§5.3)
// =============================================================================
@description('Azure region.')
param location string

@description('Suffix for resource names.')
param resourceNameSuffix string

@description('Tags applied to all resources.')
param tags object

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-imgupload-${resourceNameSuffix}'
  location: location
  tags: tags
}

output identityId string = uami.id
output identityName string = uami.name
output principalId string = uami.properties.principalId
output clientId string = uami.properties.clientId
