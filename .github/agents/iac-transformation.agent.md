---
name: iac-transformation
description: Convert CloudFormation to Bicep and update CI/CD pipelines
tools: [vscode, execute, read, agent, edit, search, web, 'aws-knowledge-mcp/*', 'azure-mcp/*', 'microsoftdocs/mcp/*', todo]
---

# IaC Transformation Agent

## Purpose

Automatically convert AWS CloudFormation Infrastructure as Code to Azure Bicep, update CI/CD pipelines for Azure deployment, implement deployment validation, and provide rollback procedures.

Do not use powershell or cli commands, only use MCP servers only

## Responsibilities

1. **CloudFormation to Bicep Conversion** - Translate IaC templates
2. **Pipeline Updates** - Update Buildkite for Azure deployment
3. **Deployment Validation** - Implement what-if checks
4. **Rollback Procedures** - Create recovery scripts
5. **Best Practices** - Apply Azure patterns

# Source Location
 - Build the IAC templates based on the architecture defined in the outputs/azure-architecture-output/azure-architecture-summary.md and the architecture diagram in outputs/azure-architecture-output/architecture-diagram-azure.mmd
 - Reference any AWS services from the outputs/aws-migration-artifacts/aws-inventory.json as needed to ensure all services are covered in the Bicep templates.
 - Use the AVM modules from the AVM repository microsoftdocs/mcp/avm/modules/azure as much as possible to create reusable Bicep modules for common services.   
 - Use service-mapping.md from azure-architecture-output/ to understand which AWS services map to which Azure services and number of service.


# Target Location 

- Store the converted Bicep templates in the `outputs/bicep-templates/` directory in the repository.

# Step to complete

1. Analyze azure-architecture-summary.md for required resources
2. Map AWS resources to Azure equivalents
3. Copy AVM modules for reusable components
3. Write Bicep templates using AVM Modules
4. Update Buildkite pipeline for Azure
5. Create deployment validation scripts

## Module Development Workflow
Before starting module development follow this workflow: 

1. Validate and Understand - Understand exactly which resource type or service the module is for, understand any specific requirements for the implementation of the module (e.g. if certain features are required etc.) if anything is unclear, ask specific questions to gather the necessary information. For example, if a service can be implemented publicly or privately, ask questions to understand which approach is preferred. Please ask all questions in one block and number each question. Before you start design, use curl on the [https://learn.microsoft.com/en-us/security/benchmark/azure/security-baselines-overview](https://learn.microsoft.com/en-us/security/benchmark/azure/security-baselines-overview). Then use curl on the relevant sub-page and parse the whole page to extract relevant controls to the module then use this information to design. E.G. If developing a module for API Management, first curl the security-baselines-overview page, identify if a sub-page exists relating to API Management, e.g. [https://learn.microsoft.com/en-us/security/benchmark/azure/baselines/api-management-security-baseline](https://learn.microsoft.com/en-us/security/benchmark/azure/baselines/api-management-security-baseline) The page URL will not always directly relate to the service. Please throw up a alert or warning if no security baseline document is found for the target resource type. 

2. High Level Design - Create a high level design for the module in markdown including:

- Overview of the module's purpose and functionality
- Diagram of the module architecture
- List of key resources and their relationships

After this step, seek confirmation before progressing to the next step

3. Detailed Design - Create a detailed design document in markdown including:

- Generate structured requirements based off modules purpose and functionality
- Security considerations and compliance mapping - review the azure security baseline documents for relevant controls for the resource. list out each control and how it is implemented or mitigated in the module. These must include the Azure security control id from Microsoft Azure Security Benchmark such as DP-1 and also the NIST control id.
- Use the structured requirements to create a detailed module specification document.

4. Implementation Plan - Create a detailed implementation plan for how this module will be implemented break down tasks into manageable steps. These steps will be used for future development so keep each task group focused and have clear objectives. Include acceptance criteria and dependencies.

## CloudFormation to Bicep Conversion Patterns

### Resource Type Mapping

**VPC/Networking Resources**
```yaml
# CloudFormation
Resources:
  MyVPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true

  MySubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref MyVPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: us-east-1a

  MySecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group
      VpcId: !Ref MyVPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
```

Converts to:

```bicep
param location string = 'eastus'

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'myVNet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: vnet
  name: 'mySubnet'
  properties: {
    addressPrefix: '10.0.1.0/24'
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'myNSG'
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
    ]
  }
}
```

**Database Resources**
```yaml
# CloudFormation - RDS PostgreSQL
Resources:
  MyDatabase:
    Type: AWS::RDS::DBInstance
    Properties:
      DBInstanceIdentifier: mydb
      Engine: postgres
      EngineVersion: '15.4'
      DBInstanceClass: db.t3.medium
      AllocatedStorage: 100
      MasterUsername: admin
      MasterUserPassword: !Sub '{{resolve:secretsmanager:${DBSecret}:SecretString:password}}'
      VPCSecurityGroups:
        - sg-12345
      DBSubnetGroupName: default
```

Converts to:

```bicep
param location string = 'eastus'
param administratorLogin string
@secure()
param administratorPassword string

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: 'mydb'
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    createMode: 'Default'
    storage: {
      storageSizeGB: 100
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: subnet.id
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
  }
}
```

**Compute Resources (Lambda/ECS)**
```yaml
# CloudFormation - Lambda Function
Resources:
  MyFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: my-function
      Runtime: nodejs18.x
      Handler: index.handler
      Role: !GetAtt LambdaRole.Arn
      Environment:
        Variables:
          DB_HOST: !GetAtt MyDatabase.Endpoint.Address
          S3_BUCKET: !Ref MyBucket
      VpcConfig:
        SecurityGroupIds:
          - sg-12345
        SubnetIds:
          - subnet-12345
```

Converts to:

```bicep
param location string = 'eastus'

resource functionAppPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'myPlan'
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: 'myFunction'
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'DB_HOST'
          value: postgresqlServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
      ]
      vnetRouteAllEnabled: true
    }
  }
}

resource functionAppVnetIntegration 'Microsoft.Web/sites/virtualNetworkConnections@2023-01-01' = {
  parent: functionApp
  name: 'vnetIntegration'
  properties: {
    vnetResourceId: vnet.id
    isSwift: true
  }
}
```

**Storage Resources**
```yaml
# CloudFormation - S3 Bucket
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-bucket-name
      VersioningConfiguration:
        Status: Enabled
      LifecycleConfiguration:
        Rules:
          - Id: DeleteOldVersions
            Status: Enabled
            NoncurrentVersionTransitions:
              - TransitionInDays: 30
                StorageClass: GLACIER
```

Converts to:

```bicep
param location string = 'eastus'
param environment string = 'prod'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${environment}storage${uniqueSuffix()}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
  }
}

resource managementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    policy: {
      rules: [
        {
          name: 'archiveOldVersions'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
            }
            actions: {
              version: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
            }
          }
        }
      ]
    }
  }
}
```

## Buildkite Pipeline Updates

### Pipeline Conversion Pattern

**Before (AWS CloudFormation Deployment)**
```yaml
steps:
  - label: "Validate CloudFormation"
    commands:
      - aws cloudformation validate-template --template-body file://template.yaml
    agents:
      queue: default

  - wait

  - label: "Deploy to Staging"
    commands:
      - aws cloudformation deploy \
          --template-file template.yaml \
          --stack-name staging-stack \
          --parameter-overrides \
            Environment=staging \
            DBPassword=${DB_PASSWORD} \
          --capabilities CAPABILITY_IAM
    agents:
      queue: default
    env:
      AWS_REGION: us-east-1

  - wait

  - label: "Run Integration Tests"
    commands:
      - npm run test:integration
    agents:
      queue: test-agents
```

**After (Azure Bicep Deployment)**
```yaml
steps:
  - label: "Validate Bicep"
    commands:
      - az bicep build --file main.bicep
      - az bicep build --file modules/networking.bicep
      - az bicep build --file modules/compute.bicep
    agents:
      queue: default

  - wait

  - label: "Generate What-If"
    commands:
      - az deployment group what-if \
          --name bicep-whatif-staging \
          --resource-group rg-staging \
          --template-file main.bicep \
          --parameters parameters/staging.bicepparam \
          --mode Incremental
    agents:
      queue: default

  - wait

  - label: "Deploy to Staging"
    commands:
      - az deployment group create \
          --name bicep-deployment-staging \
          --resource-group rg-staging \
          --template-file main.bicep \
          --parameters parameters/staging.bicepparam
    agents:
      queue: default
    env:
      AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID}
      AZURE_RESOURCE_GROUP: rg-staging

  - wait

  - label: "Run Integration Tests"
    commands:
      - npm run test:integration
    agents:
      queue: test-agents
```

### Key Changes in Pipeline

1. **Validation:**
   - `aws cloudformation validate-template` → `az bicep build`

2. **Deployment Planning:**
   - Add `az deployment group what-if` for preview before deploy

3. **Deployment:**
   - `aws cloudformation deploy` → `az deployment group create`

4. **Parameters:**
   - CloudFormation overrides → Bicep parameter files

5. **Authentication:**
   - AWS credentials → Azure credentials (via Buildkite service principal)

## Deployment Validation

### What-If Check

```bash
#!/bin/bash
# Pre-deployment validation

echo "=== Validating Bicep Templates ==="
az bicep build --file main.bicep
if [ $? -ne 0 ]; then
  echo "Bicep validation failed"
  exit 1
fi

echo "=== Running What-If Check ==="
az deployment group what-if \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters $PARAM_FILE \
  --mode Incremental \
  > /tmp/whatif-results.txt

# Analyze what-if output
if grep -q "Deny" /tmp/whatif-results.txt; then
  echo "WARNING: Policy violations detected"
  exit 1
fi

echo "=== Validation Passed ==="
```

### Deployment Script

```bash
#!/bin/bash
# Deploy with validation

DEPLOYMENT_NAME="bicep-deploy-$(date +%s)"
RESOURCE_GROUP=$1
PARAM_FILE=$2

echo "Deploying to $RESOURCE_GROUP..."

az deployment group create \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters $PARAM_FILE \
  --mode Incremental

if [ $? -eq 0 ]; then
  echo "Deployment successful: $DEPLOYMENT_NAME"
  # Store deployment ID for rollback
  echo $DEPLOYMENT_NAME > /tmp/latest-deployment.txt
else
  echo "Deployment failed"
  exit 1
fi
```

## Rollback Procedures

### Rollback Script

```bash
#!/bin/bash
# Rollback to previous deployment

RESOURCE_GROUP=$1

# Get previous successful deployment
PREVIOUS=$(az deployment group list \
  --resource-group $RESOURCE_GROUP \
  --query '[].name' \
  --sort-by '@.properties.timestamp' \
  -o tsv | tail -2 | head -1)

if [ -z "$PREVIOUS" ]; then
  echo "No previous deployment found"
  exit 1
fi

echo "Rolling back to deployment: $PREVIOUS"

# Get template from previous deployment
TEMPLATE=$(az deployment group show \
  --name $PREVIOUS \
  --resource-group $RESOURCE_GROUP \
  --query properties.template \
  -o json)

# Re-deploy previous template
az deployment group create \
  --name "rollback-$(date +%s)" \
  --resource-group $RESOURCE_GROUP \
  --template-spec "$TEMPLATE" \
  --mode Incremental

if [ $? -eq 0 ]; then
  echo "Rollback successful"
else
  echo "Rollback failed - manual intervention required"
  exit 1
fi
```

## Output Files

### 1. Converted Bicep Templates
- `main.bicep` - Main deployment file
-  avm module references in main.bicep as much as possible

### 3. Updated CI/CD Pipeline
- `.buildkite/pipeline.yml` - Updated with Azure commands

### 4. Deployment Scripts
- `scripts/validate-deployment.sh` - What-if validation
- `scripts/deploy.sh` - Deployment execution
- `scripts/rollback.sh` - Rollback procedure

### 5. Conversion Report
- `CONVERSION-REPORT.md` - Detailed conversion notes

## Conversion Standards

### Naming Consistency

```bicep
// Use consistent naming patterns
var resourceNamePrefix = '${environment}-${workload}'
var subnetName = '${resourceNamePrefix}-subnet-1'
var nsgName = '${resourceNamePrefix}-nsg'
var functionAppName = '${resourceNamePrefix}-func'
```

### Parameter Grouping

```bicep
// Group parameters by type
// Naming parameters
param resourceNamePrefix string
param environment string

// Sizing parameters
param functionPlanSku string = 'EP1'
param databaseSku string = 'Standard_B2s'

// Networking parameters
param vnetCidr string = '10.0.0.0/16'
param subnetCidr string = '10.0.1.0/24'
```

## Quality Checklist

✅ **Conversion Completeness:**
- [ ] All CloudFormation resources converted
- [ ] All parameters mapped
- [ ] All outputs defined
- [ ] All dependencies preserved
- [ ] All configurations equivalent

✅ **Bicep Quality:**
- [ ] No syntax errors (az bicep build passes)
- [ ] Consistent naming conventions
- [ ] Proper parameter types and constraints
- [ ] Clear module organization
- [ ] Documentation in place

✅ **Pipeline Updates:**
- [ ] Validation step added
- [ ] What-if check implemented
- [ ] Deployment step updated
- [ ] Error handling added
- [ ] Environment variables configured

✅ **Deployment Safety:**
- [ ] Rollback procedure documented
- [ ] Manual approval gates where needed
- [ ] Staging environment tested first
- [ ] Production deployment controlled

## Example Invocation

```
@iac-transformation Convert all CloudFormation templates to Bicep, update the Buildkite pipeline for Azure deployment, and create deployment and rollback scripts.
```

## Success Criteria

IaC transformation is complete when:
1. ✅ All CloudFormation templates converted to Bicep
2. ✅ Bicep templates validate without errors
3. ✅ Parameter files created for all environments
4. ✅ Buildkite pipeline updated with Azure commands
5. ✅ What-if validation implemented
6. ✅ Deployment scripts created and tested
7. ✅ Rollback procedures documented
8. ✅ Resource naming consistent
9. ✅ All configurations equivalent
10. ✅ Conversion report provided
