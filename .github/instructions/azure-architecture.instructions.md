---
name: azure-architect-instructions
description: Custom instructions for Azure Architect Agent
applyTo: azure-architect
---

# Azure Architect Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All inputs come from `outputs/aws-migration-artifacts/` and outputs go to `outputs/azure-architecture-output/`.

## Bicep Best Practices

### Symbolic Naming

Use descriptive, meaningful names that indicate purpose:

```bicep
// Good
var functionAppName = '${environment}-${workload}-func-${location}'
var storageAccountName = '${environment}${workload}stor${uniqueSuffix}'

// Avoid
var func1 = '${env}func'
var stor = 'storage'
```

### Parameter Naming

```bicep
@minLength(3)
@maxLength(24)
@description('Name of the storage account')
param storageAccountName string

@allowed(['eastus', 'westus', 'eastus2'])
@description('Azure region for resources')
param location string = 'eastus'

@minValue(1)
@maxValue(10)
@description('Number of instances to deploy')
param instanceCount int = 1
```

### Decorators

Always include decorators for validation:

```bicep
@minLength(3)          // Minimum string length
@maxLength(24)         // Maximum string length
@allowed(['value1', 'value2'])  // Specific allowed values
@minValue(1)           // Minimum numeric value
@maxValue(100)         // Maximum numeric value
@metadata({
  description: 'Purpose of parameter'
})
param paramName type
```

### Module Organization

Create reusable, focused modules:

```bicep
// modules/database.bicep
param location string
param environment string
param sqlAdminPassword string @secure()

resource sqlServer 'Microsoft.Sql/servers@2023-02-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: sqlAdminPassword
  }
}

output serverId string = sqlServer.id
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
```

### Output Standards

```bicep
// In modules, output important resource properties
output resourceId string = resource.id
output resourceName string = resource.name
output principalId string = systemIdentity.principalId
output endpoint string = resource.properties.endpoint
```

## Security Requirements

### Private Endpoints

All PaaS services must use private endpoints:

```bicep
// ❌ DON'T - Public endpoint
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    publicNetworkAccess: 'Enabled'  // BAD
  }
}

// ✅ DO - Private endpoint
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    publicNetworkAccess: 'Disabled'  // GOOD
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${storageAccountName}-pe'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: storageAccountName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}
```

### Managed Identity

Use Managed Identity instead of access keys:

```bicep
// ✅ DO - Use Managed Identity
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
  }
}

// Grant permissions via RBAC
resource functionAppBlobAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(resourceGroup().id, functionApp.id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
```

### Key Vault

Store all secrets in Key Vault:

```bicep
// Store connection strings
resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  name: '${keyVault.name}/DbConnectionString'
  properties: {
    value: 'Server=${postgresqlServer.properties.fullyQualifiedDomainName};Database=mydb;Port=5432;'
  }
}

// Reference from Key Vault in app settings
resource functionAppSettings 'Microsoft.Web/sites/config@2023-01-01' = {
  name: '${functionApp.name}/appsettings'
  properties: {
    'DbConnectionString': '@Microsoft.KeyVault(SecretUri=https://${keyVault.name}.vault.azure.net/secrets/DbConnectionString/)'
  }
}
```

### Network Security Groups

Implement principle of least privilege:

```bicep
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
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

## Cost Optimization Guidelines

### Compute

**Azure Functions:**
- Use **Consumption Plan** for sporadic, short-duration workloads
- Use **Premium Plan** for sustained workloads or VNet integration
- Use **Dedicated App Service Plan** for CPU-intensive workloads

**AKS:**
- Use **Standard** SKU for production
- Use **Spot nodes** for non-critical, batch workloads (70% savings)
- Use **Reserved Instances** for baseline node capacity
- Scale down non-production clusters during off-hours

### Storage

**Blob Storage:**
- Use **Hot tier** for frequently accessed data
- Use **Cool tier** for infrequent access (after 30 days)
- Use **Archive tier** for long-term retention (after 90 days)
- Implement lifecycle policies automatically

**Database:**
- Use **Burstable SKU** (B-series) for development and testing
- Use **General Purpose SKU** (GP) for production baseline
- Use **Reserved Capacity** (1-year) for predictable workloads (30-40% savings)

### Networking

**Data Transfer:**
- Keep resources in same region to avoid data transfer charges
- Use service endpoints to avoid going through public internet
- Use private endpoints to keep traffic private

### Example Cost Optimization

```bicep
param environment string
param skipMinorServices bool = (environment == 'dev')

// Only deploy monitoring in production/staging
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (environment != 'dev') {
  name: 'monitoring-${functionApp.name}'
  scope: functionApp
  properties: {
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: (environment == 'prod') ? 30 : 7
        }
      }
    ]
  }
}

// Use cheaper SKU in dev
var functionPlanSkuName = (environment == 'prod') ? 'EP2' : 'Y1'
var storageAccountTier = (environment == 'prod') ? 'Premium' : 'Standard'
```

## Well-Architected Framework Application

### Reliability

- [ ] Use Availability Zones for production deployments
- [ ] Implement auto-scaling based on metrics
- [ ] Configure health probes and monitoring
- [ ] Plan for disaster recovery and business continuity
- [ ] Implement database backups and geo-redundancy

### Security

- [ ] Use Managed Identity for all service-to-service authentication
- [ ] Implement private endpoints for PaaS services
- [ ] Store secrets in Key Vault
- [ ] Enable encryption for data at rest and in transit
- [ ] Implement Network Security Groups with least privilege
- [ ] Use Azure Policy for compliance enforcement

### Cost Optimization

- [ ] Choose appropriate SKUs and pricing tiers
- [ ] Implement auto-scaling to match demand
- [ ] Use reserved instances for predictable workloads
- [ ] Archive unused data to cooler storage tiers
- [ ] Monitor and optimize resource usage
- [ ] Use spot instances for non-critical workloads

### Operational Excellence

- [ ] Implement comprehensive monitoring and alerting
- [ ] Use Infrastructure as Code for all deployments
- [ ] Document architecture and operational procedures
- [ ] Implement CI/CD pipelines
- [ ] Plan for regular maintenance and updates
- [ ] Implement logging for audit and troubleshooting

### Performance Efficiency

- [ ] Choose appropriate service tiers
- [ ] Implement caching strategies (Redis, CDN)
- [ ] Optimize database queries and indexing
- [ ] Use CDN for static content
- [ ] Implement proper database scaling

## Template Validation Checklist

Before finalizing templates, verify:

### Structure
- [ ] All parameters have description and constraints
- [ ] All variables are defined clearly
- [ ] All modules are reusable and focused
- [ ] All outputs are defined for resource references
- [ ] Parameter files provided for each environment

### Security
- [ ] No hardcoded passwords or secrets
- [ ] All PaaS services use private endpoints
- [ ] Managed Identity used for authentication
- [ ] RBAC roles follow least privilege
- [ ] Key Vault configured for secrets
- [ ] NSGs configured correctly

### Best Practices
- [ ] Bicep syntax is valid (az bicep validate)
- [ ] Naming conventions are consistent
- [ ] Decorators used for validation
- [ ] Modules are documented
- [ ] Outputs are properly defined
- [ ] Tags included for cost allocation

### Cost
- [ ] SKUs are appropriate for workload
- [ ] Scaling is configured
- [ ] Storage tiering is implemented
- [ ] Data transfer minimized
- [ ] Monitoring is optimized

### Deployability
- [ ] Templates test with what-if (az deployment group what-if)
- [ ] Parameters work for all environments
- [ ] Resource dependencies are correct
- [ ] No circular dependencies
- [ ] Sufficient permissions for deployment

## Service-Specific Guidance

### Azure Functions Migration

**From Lambda to Functions:**

| Aspect | Lambda | Azure Functions |
|---|---|---|
| Invocation | Event + context | Trigger + binding |
| Response | Return value | HttpResponse or queue message |
| Environment Vars | process.env | CloudConfiguration.GetAppSetting() |
| Timeout | 15 mins max | Depends on plan (Consumption: 10 mins, Premium: unlimited) |
| Execution Context | Cold/warm start | Cold/warm start |
| Networking | Configure in function config | Configure in Function Plan VNet integration |

### RDS to Azure Database Migration

**Connection String Changes:**

```
// AWS RDS PostgreSQL
server=mydb.c9akciq32.us-east-1.rds.amazonaws.com;userid=postgres;password=...

// Azure Database for PostgreSQL
Server=myserver.postgres.database.azure.com;UserId=pgadmin@myserver;Password=...;Database=mydb
```

### EKS to AKS Migration

**Key Differences:**

| Aspect | EKS | AKS |
|---|---|---|
| Networking | VPC + Security Groups | VNet + NSGs |
| Storage | EBS + EFS | Managed Disks + Azure Files |
| Registry | ECR | ACR (Azure Container Registry) |
| Monitoring | CloudWatch | Azure Monitor + Container Insights |
| Ingress | ALB/NLB | Application Gateway |
| RBAC | IAM roles | Azure AD + RBAC |

## Common Issues & Resolution

### Issue: Template Deployment Fails with Permission Error

**Resolution:**
- Verify deployment principal has sufficient permissions
- Check role assignments on resource group
- Verify Key Vault access policies if using secrets

### Issue: VNet Integration Fails for Functions

**Resolution:**
- Use Premium or Dedicated plan (Consumption doesn't support VNet integration)
- Ensure subnet exists and is available
- Check NSG rules allow outbound HTTPS traffic
- Verify no IP space conflicts

### Issue: Cost Estimates Don't Match Azure Pricing

**Resolution:**
- Verify SKU and pricing tier are correct
- Include compute, storage, data transfer, and managed service costs
- Account for tax and region-specific pricing differences
- Check for additional charges (backup, disaster recovery, premium features)

## Output Format Standards

### Bicep Files

```bicep
// File header
@description('Module for [purpose]')

// Parameters section
@minLength(3)
@maxLength(24)
param parameterName string

// Variables section
var resourceName = '${environment}-resource'

// Resources section
resource resource1 'Microsoft.Service/type@apiVersion' = {
  name: resourceName
  location: location
  properties: {
    // properties
  }
}

// Outputs section
@description('ID of created resource')
output resourceId string = resource1.id
```

### Parameter Files

```bicepparam
using './main.bicep'

param environment = 'production'
param location = 'eastus'
param vmSize = 'Standard_D4s_v3'
```

## Tips & Best Practices

✅ **Do:**
- Test templates with what-if validation
- Use consistent naming conventions
- Document all parameters
- Apply security best practices
- Consider disaster recovery
- Review cost implications
- Use Availability Zones for production

❌ **Don't:**
- Hardcode values (use parameters)
- Use public endpoints for data services
- Store secrets in templates
- Create overly large modules
- Skip security best practices
- Ignore cost implications
- Deploy resources to wrong regions

---

**Last Updated:** December 2024  
**Version:** 1.0
