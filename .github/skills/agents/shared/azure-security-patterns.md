---
name: azure-security-patterns
description: Zero-trust security defaults for every Azure resource — private networking, least-privilege access, encryption, and NSG rules
---

# Azure Security Patterns Skill

## Purpose

Apply consistent zero-trust security defaults to every Azure resource deployed in this migration. Every PaaS service must be private-network-only, encrypted, and accessed only via managed identity.

## When to Use

- When writing or reviewing any Bicep module that deploys a PaaS service
- During pre-deployment validation checks
- When verifying security compliance post-deployment

## Process

1. **Disable public network access** on all data services and set up private endpoints:
   ```bicep
   resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
     properties: {
       publicNetworkAccess: 'Disabled'
       allowBlobPublicAccess: false
       minimumTlsVersion: 'TLS1_2'
     }
   }

   resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
     name: '${storageAccountName}-pe'
     location: location
     properties: {
       subnet: { id: dataSubnetId }
       privateLinkServiceConnections: [{
         name: storageAccountName
         properties: {
           privateLinkServiceId: storageAccount.id
           groupIds: ['blob']
         }
       }]
     }
   }
   ```

2. **Register private DNS zones** — without this, the private endpoint is unreachable:
   ```bicep
   resource blobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
     name: 'privatelink.blob.core.windows.net'
     location: 'global'
   }

   resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
     parent: blobDnsZone
     name: 'link-${vnetName}'
     location: 'global'
     properties: {
       virtualNetwork: { id: vnetId }
       registrationEnabled: false
     }
   }
   ```

3. **Apply NSGs to every subnet** with least-privilege rules — deny all inbound by default:
   ```bicep
   resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
     properties: {
       securityRules: [
         {
           name: 'AllowHttpsInbound'
           properties: {
             protocol: 'Tcp'
             sourcePortRange: '*'
             destinationPortRange: '443'
             sourceAddressPrefix: 'Internet'
             destinationAddressPrefix: '*'
             access: 'Allow'
             priority: 100
             direction: 'Inbound'
           }
         }
         {
           name: 'DenyAllInbound'
           properties: {
             protocol: '*'
             sourcePortRange: '*'
             destinationPortRange: '*'
             sourceAddressPrefix: '*'
             destinationAddressPrefix: '*'
             access: 'Deny'
             priority: 4096
             direction: 'Inbound'
           }
         }
       ]
     }
   }
   ```

4. **Configure Key Vault hardening:**
   ```bicep
   resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
     properties: {
       enableSoftDelete: true
       softDeleteRetentionInDays: 90
       enablePurgeProtection: true
       publicNetworkAccess: 'Disabled'
       enableRbacAuthorization: true
     }
   }
   ```

5. **Enforce HTTPS and TLS 1.2+ on Function Apps and App Service:**
   ```bicep
   resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
     properties: {
       httpsOnly: true
       siteConfig: {
         minTlsVersion: '1.2'
         ftpsState: 'Disabled'
       }
     }
   }
   ```

## Private DNS Zone Names by Service

| Service | Private DNS Zone Name | Group ID |
|---|---|---|
| Blob Storage | `privatelink.blob.core.windows.net` | `blob` |
| Key Vault | `privatelink.vaultcore.azure.net` | `vault` |
| Service Bus | `privatelink.servicebus.windows.net` | `namespace` |
| PostgreSQL Flexible | `<server>.private.postgres.database.azure.com` | `postgresqlServer` |
| Cosmos DB | `privatelink.documents.azure.com` | `Sql` |
| Container Registry | `privatelink.azurecr.io` | `registry` |
| Azure Functions | `privatelink.azurewebsites.net` | `sites` |

## Rules

- **Never deploy a storage account with `allowBlobPublicAccess: true`.**
- **Never create a subnet without an associated NSG.**
- **Never create a Key Vault with `softDeleteRetentionInDays` < 7.** Default to 90 for prod.
- **Never skip DNS zone registration for private endpoints** — the resource will be unreachable without it.
- **Never use `enablePurgeProtection: false` on a production Key Vault.**
- **Always set `httpsOnly: true`** on every Function App and App Service.
- **Always set `minimumTlsVersion: 'TLS1_2'`** on Storage Accounts.

## Output

- Every Bicep module with a data service includes a private endpoint and DNS zone registration
- Every subnet has an NSG with deny-all-inbound as the lowest-priority rule
- Key Vault has soft delete + purge protection + RBAC authorization enabled
- Pre-deployment security checklist passes with no blocking findings
