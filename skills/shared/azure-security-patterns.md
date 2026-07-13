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

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/verify-security.ps1` | Post-deployment security verification across Storage, Key Vault, Function App, and NSG rules |

Run after every deployment to assert security baselines are met:

```powershell
./.github/skills/agents/shared/scripts/verify-security.ps1 \
    -ResourceGroup "rg-prod-migration"
```

The script auto-discovers resources and exits 1 on any FAIL, making it suitable as a CI gate.  Writes `outputs/deployment-validation/security-report.md`.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Security Benchmark | https://learn.microsoft.com/en-us/security/benchmark/azure/introduction |
| Azure Private Link / Private Endpoints | https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview |
| Private DNS zones for Private Link | https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns |
| NSG overview | https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview |
| Azure Key Vault soft-delete | https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview |
| Key Vault purge protection | https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview#purge-protection |
| Azure Policy for security | https://learn.microsoft.com/en-us/azure/governance/policy/overview |
| Microsoft Defender for Cloud | https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-cloud-introduction |
| Azure network security best practices | https://learn.microsoft.com/en-us/azure/security/fundamentals/network-best-practices |
| Storage security guide | https://learn.microsoft.com/en-us/azure/storage/blobs/security-recommendations |
| Azure Functions networking overview | https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options |
| TLS policy for App Service | https://learn.microsoft.com/en-us/azure/app-service/configure-ssl-bindings |

### Best Practices

- **Zero-trust networking:** Every PaaS data service must be private-endpoint-only. Disable public network access in Bicep — never rely on firewall rules alone.
- **Private DNS is mandatory with private endpoints:** Without registering the private DNS zone and linking it to your VNet, private endpoint hostnames resolve to public IPs and traffic exits the VNet.
- **Key Vault purge protection:** Enable on all environments, not just prod — accidental secret deletion during development causes deployment failures that can take days to recover from without purge protection.
- **NSG audit rule:** The `DenyAllInbound` rule at priority 4096 is a safety net — never delete it even when adding application-specific allow rules.
- **Azure Security Benchmark v3** maps every control to specific Bicep/policy configurations — use it as the compliance checklist for all new deployments.
