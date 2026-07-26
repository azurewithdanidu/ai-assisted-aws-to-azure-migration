"""
Bicep fixture samples for the bicep-correctness eval suite.
"""

# ---------------------------------------------------------------------------
# GOOD fixtures — should pass all applicable checks
# ---------------------------------------------------------------------------

GOOD_MAIN_BICEP = """\
// main.bicep — subscription-scoped orchestrator
// Deploy:  az deployment sub create --location australiaeast \\
//            --template-file main.bicep --parameters @parameters/dev.bicepparam

targetScope = 'subscription'

@description('Deployment location')
param location string = 'australiaeast'

@description('Resource group name')
param resourceGroupName string = 'rg-myapp-dev'

var commonTags = {
  environment: 'dev'
  project: 'myapp'
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module storageModule 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: rg
  params: {
    location: location
    tags: commonTags
  }
}

module functionModule 'modules/functions.bicep' = {
  name: 'deploy-functions'
  scope: rg
  params: {
    location: location
    tags: commonTags
  }
}
"""

GOOD_STORAGE_BICEP = """\
// modules/storage.bicep
targetScope = 'resourceGroup'

param location string
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stmyappdev001'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
"""

GOOD_PRIVATE_ENDPOINT_BICEP = """\
// modules/private-endpoint.bicep
targetScope = 'resourceGroup'

param location string
param storageAccountId string
param subnetId string
param vnetId string

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: 'pe-storage-dev'
  location: location
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-link-dev'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnetId }
  }
}
"""

# ---------------------------------------------------------------------------
# BAD fixtures — should FAIL the relevant checks (regressions from 2026-07-21)
# ---------------------------------------------------------------------------

BAD_MAIN_BICEP_RG_SCOPE = """\
// main.bicep — WRONG: resource-group scope cannot create its own resource group
// Deploy:  az deployment group create --resource-group rg-myapp-dev \\
//            --template-file main.bicep --parameters @parameters/dev.bicepparam

targetScope = 'resourceGroup'

param location string = 'australiaeast'

module storageModule 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    location: location
  }
}
"""

BAD_MAIN_BICEP_MISSING_MODULE_SCOPE = """\
// main.bicep — subscription scope declared but modules missing scope: rg
// Deploy:  az deployment sub create --location australiaeast \\
//            --template-file main.bicep --parameters @parameters/dev.bicepparam

targetScope = 'subscription'

param location string = 'australiaeast'
param resourceGroupName string = 'rg-myapp-dev'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

module storageModule 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    location: location
  }
}

module functionModule 'modules/functions.bicep' = {
  name: 'deploy-functions'
  params: {
    location: location
  }
}
"""

BAD_STORAGE_BICEP_PUBLIC_ACCESS = """\
// modules/storage.bicep — WRONG: public access enabled, shared key allowed
targetScope = 'resourceGroup'

param location string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stmyappdev001'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Enabled'
    allowSharedKeyAccess: true
  }
}
"""

# ---------------------------------------------------------------------------
# Expectation maps
# ---------------------------------------------------------------------------

BICEP_EXPECTATIONS: dict[str, bool] = {
    "GOOD_MAIN_BICEP": True,
    "GOOD_STORAGE_BICEP": True,
    "GOOD_PRIVATE_ENDPOINT_BICEP": True,
    "BAD_MAIN_BICEP_RG_SCOPE": False,
    "BAD_MAIN_BICEP_MISSING_MODULE_SCOPE": False,
    "BAD_STORAGE_BICEP_PUBLIC_ACCESS": False,
}
