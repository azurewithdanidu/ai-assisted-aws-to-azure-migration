# AWS to Azure Service Mapping Reference

**Document Version:** 1.0  
**Date:** December 2024  
**Purpose:** Comprehensive service translation guide

---

## Overview

This document provides detailed mappings from AWS services to Azure equivalents, including configuration guidance, pricing considerations, and migration notes.

---

## Compute Services

### AWS Lambda → Azure Functions

**Mapping:**
- AWS Lambda → Azure Functions

**Plan Selection:**
- **Consumption Plan:** For event-driven, variable workloads (equivalent to Lambda pricing model)
- **Premium Plan:** For VNet integration, longer execution times, predictable performance
- **Dedicated (App Service) Plan:** For always-on, high-throughput scenarios

**Key Differences:**
- Cold start: Similar in Consumption plan, eliminated in Premium
- Timeout: Consumption (5 min), Premium (unlimited), Lambda (15 min)
- Triggers: Both support HTTP, queue, storage, timer, event grid

**Migration Considerations:**
- Replace `aws-sdk` with `@azure/` packages
- Update IAM roles to Managed Identity
- Modify function handlers (Lambda uses `handler`, Azure uses module exports)
- Update environment variables

**Cost Comparison:**
- Lambda: $0.20 per 1M requests + $0.0000166667 per GB-second
- Azure Functions Consumption: $0.20 per 1M executions + $0.000016 per GB-second
- Generally equivalent pricing

### AWS EKS → Azure Kubernetes Service (AKS)

**Mapping:**
- AWS EKS → Azure Kubernetes Service (AKS)

**Key Differences:**
- Control plane: EKS charges $0.10/hour ($73/month), AKS control plane is free
- Networking: EKS uses AWS VPC CNI, AKS offers Azure CNI or kubenet
- Identity: EKS uses IAM roles for service accounts, AKS uses Workload Identity
- Ingress: EKS uses ALB/NLB, AKS uses Azure Load Balancer or Application Gateway

**Migration Path:**
1. Export Kubernetes manifests from EKS: `kubectl get all --all-namespaces -o yaml`
2. Update container registry references (ECR → ACR)
3. Update service type LoadBalancer annotations for Azure
4. Configure Workload Identity instead of IAM
5. Deploy to AKS

**Cost Comparison:**
- EKS: $73/month control plane + node costs
- AKS: $0 control plane + node costs
- **AKS saves $73/month on control plane**

### AWS EC2 → Azure Virtual Machines

**Mapping:**
- t3.micro → Standard_B1s
- t3.small → Standard_B2s
- t3.medium → Standard_B2ms
- m5.large → Standard_D2s_v3
- c5.xlarge → Standard_F4s_v2
- r5.large → Standard_E2s_v3

**Storage:**
- EBS GP2 → Azure Premium SSD
- EBS GP3 → Azure Premium SSD v2
- EBS SC1 → Azure Standard HDD

---

## Storage Services

### AWS S3 → Azure Blob Storage

**Mapping:**
- S3 Bucket → Storage Account + Blob Container
- S3 Standard → Hot tier
- S3 Infrequent Access → Cool tier
- S3 Glacier → Archive tier

**SDK Replacement:**
```javascript
// AWS
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
await s3.send(new PutObjectCommand({ Bucket, Key, Body }));

// Azure
const { BlobServiceClient } = require('@azure/storage-blob');
await blockBlobClient.upload(data, data.length);
```

**Features:**
- Versioning: Both support
- Lifecycle policies: Both support
- Encryption: Both default encrypt at rest
- Access tiers: S3 has 4, Azure has 3 (Hot/Cool/Archive)

**Migration Tool:**
- Use AzCopy: `azcopy copy "https://s3.amazonaws.com/bucket" "https://account.blob.core.windows.net/container" --recursive`

**Cost Comparison (per GB/month):**
- S3 Standard: $0.023 | Azure Hot: $0.0184 (20% cheaper)
- S3 IA: $0.0125 | Azure Cool: $0.01 (20% cheaper)
- S3 Glacier: $0.004 | Azure Archive: $0.00099 (75% cheaper)

### AWS EBS → Azure Managed Disks

**Mapping:**
- EBS GP2 → Premium SSD
- EBS GP3 → Premium SSD v2
- EBS IO2 → Ultra Disk
- EBS SC1 → Standard HDD
- EBS ST1 → Standard SSD

**Performance:**
- GP2 (250 MB/s) ≈ Premium SSD P30 (200 MB/s)
- GP3 (1000 MB/s) ≈ Premium SSD v2 (1200 MB/s)

### AWS EFS → Azure Files

**Mapping:**
- EFS Standard → Azure Files Premium
- EFS Infrequent Access → Azure Files Standard (Cool tier)

**Protocol:**
- Both support NFS
- Azure Files also supports SMB

---

## Database Services

### AWS RDS PostgreSQL → Azure Database for PostgreSQL

**Mapping:**
- RDS PostgreSQL → Azure Database for PostgreSQL Flexible Server

**Plan Selection:**
- Burstable: Development/test
- General Purpose: Production workloads
- Memory Optimized: Memory-intensive applications

**High Availability:**
- RDS Multi-AZ → Azure Zone-redundant HA
- Both provide automatic failover

**Backup:**
- Both support automated backups (7-35 days)
- Both support point-in-time restore

**Migration:**
- Use Azure Database Migration Service
- Online migration with minimal downtime
- Schema and data migration

**Cost Comparison:**
- RDS db.t3.medium: ~$150/month
- Azure Flexible Server B2s: ~$120/month
- **Azure is 20% cheaper**

### AWS RDS MySQL → Azure Database for MySQL

**Mapping:**
- RDS MySQL → Azure Database for MySQL Flexible Server

**Similar considerations as PostgreSQL**

### AWS DynamoDB → Azure Cosmos DB

**Mapping:**
- DynamoDB → Cosmos DB (NoSQL API)

**Consistency:**
- DynamoDB: Eventual or Strong
- Cosmos DB: 5 levels (Strong, Bounded Staleness, Session, Consistent Prefix, Eventual)

**Throughput:**
- DynamoDB: Provisioned or On-Demand
- Cosmos DB: Provisioned or Serverless

**Global Distribution:**
- Both support multi-region replication
- Cosmos DB offers turnkey global distribution

**SDK Replacement:**
```javascript
// AWS
const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');

// Azure
const { CosmosClient } = require('@azure/cosmos');
await container.items.create(item);
```

---

## Messaging Services

### AWS EventBridge → Azure Event Grid

**Mapping:**
- EventBridge Event Bus → Event Grid Topic
- EventBridge Rule → Event Grid Subscription
- Event patterns → Event Grid filters

**Event Schema:**
- Both support custom schemas
- Both support CloudEvents standard

**Integration:**
- EventBridge: AWS services, SaaS partners
- Event Grid: Azure services, Microsoft services

**SDK Replacement:**
```javascript
// AWS
const { EventBridgeClient, PutEventsCommand } = require('@aws-sdk/client-eventbridge');

// Azure
const { EventGridPublisherClient } = require('@azure/eventgrid');
await client.send(events);
```

### AWS SQS → Azure Service Bus Queues

**Mapping:**
- SQS Standard → Service Bus Queue
- SQS FIFO → Service Bus Queue (with sessions)

**Features:**
- Both: Dead letter queues, message retention, visibility timeout
- Service Bus adds: Duplicate detection, scheduled messages, transactions

**Message Size:**
- SQS: 256 KB
- Service Bus: 256 KB (Standard), 100 MB (Premium)

### AWS SNS → Azure Service Bus Topics

**Mapping:**
- SNS Topic → Service Bus Topic
- SNS Subscription → Service Bus Subscription

**Filtering:**
- SNS: Filter policies
- Service Bus: SQL-like filter expressions (more powerful)

---

## Networking Services

### AWS VPC → Azure Virtual Network

**Mapping:**
- VPC → Virtual Network (VNet)
- Subnet → Subnet
- Internet Gateway → NAT Gateway + Public IP
- NAT Gateway → NAT Gateway
- Security Group → Network Security Group (NSG)
- NACL → NSG (Azure NSGs can be applied at subnet level)
- VPC Peering → VNet Peering
- Transit Gateway → Virtual WAN

**CIDR Considerations:**
- Both support RFC 1918 private ranges
- Azure reserves first 4 and last 1 IP in each subnet (5 total)
- Plan IP addressing accordingly

### AWS Route 53 → Azure DNS

**Mapping:**
- Route 53 Hosted Zone → Azure DNS Zone
- Route 53 Record Sets → Azure DNS Records

**Traffic Routing:**
- Route 53 routing policies → Azure Traffic Manager profiles

### AWS CloudFront → Azure Front Door / Azure CDN

**Mapping:**
- CloudFront → Azure Front Door (enterprise)
- CloudFront → Azure CDN (standard CDN)

**Capabilities:**
- Front Door: Global load balancing, WAF, caching
- CDN: Content delivery, caching

---

## Security & Identity Services

### AWS IAM → Azure Active Directory + RBAC

**Mapping:**
- IAM User → Azure AD User
- IAM Role → Managed Identity + RBAC Role Assignment
- IAM Policy → RBAC Role Definition
- IAM Group → Azure AD Group

**Service Authentication:**
- AWS: IAM Roles for EC2, Lambda, etc.
- Azure: Managed Identity (System or User-assigned)

**Best Practice:**
- Use Managed Identity for all Azure resources
- No credentials in code or configuration
- Assign minimal RBAC permissions

### AWS Secrets Manager → Azure Key Vault

**Mapping:**
- Secrets Manager Secret → Key Vault Secret
- Secrets Manager Rotation → Key Vault (with Logic App/Function)

**Additional Features:**
- Key Vault also stores: Keys (for encryption), Certificates

**Access:**
- AWS: IAM policies
- Azure: Key Vault access policies or RBAC

**SDK Replacement:**
```javascript
// AWS
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

// Azure
const { SecretClient } = require('@azure/keyvault-secrets');
const { DefaultAzureCredential } = require('@azure/identity');
const secret = await client.getSecret(secretName);
```

### AWS KMS → Azure Key Vault (Keys)

**Mapping:**
- KMS Customer Master Key → Key Vault Key
- KMS Encryption → Key Vault Encrypt/Decrypt operations

**Encryption at Rest:**
- AWS: KMS for service encryption
- Azure: Customer-managed keys in Key Vault

---

## Monitoring & Logging

### AWS CloudWatch → Azure Monitor

**Mapping:**
- CloudWatch Logs → Log Analytics Workspace
- CloudWatch Metrics → Azure Monitor Metrics
- CloudWatch Dashboards → Azure Monitor Dashboards
- CloudWatch Alarms → Azure Monitor Alerts

**Query Language:**
- CloudWatch: CloudWatch Insights
- Azure: Kusto Query Language (KQL)

**Log Retention:**
- Both support configurable retention
- Azure offers cheaper long-term retention with Data Collection Rules

### AWS X-Ray → Azure Application Insights

**Mapping:**
- X-Ray Traces → Application Insights Distributed Tracing
- X-Ray Service Map → Application Insights Application Map
- X-Ray Analytics → Application Insights Analytics

**Instrumentation:**
- Both support automatic instrumentation
- Both support custom spans/telemetry

**Integration:**
- Application Insights deeply integrated with Azure services
- Auto-instrumentation for Functions, AKS, App Service

---

## Cost Comparison Summary

**Sample Workload:**
- 3 microservices on Kubernetes
- 3 Lambda/Functions
- 1 PostgreSQL database
- 100 GB storage
- 1 TB data transfer

**AWS Monthly Cost: $850**
- EKS: $73 (control plane) + $200 (nodes)
- Lambda: $50
- RDS: $250
- S3: $25
- Data transfer: $90
- NAT Gateway: $45
- CloudWatch: $50
- Other: $67

**Azure Monthly Cost: $620**
- AKS: $0 (control plane) + $180 (nodes)
- Functions: $45
- PostgreSQL: $200
- Blob Storage: $18
- Data transfer: $8
- NAT Gateway: $35
- Monitor: $30
- Other: $104

**Monthly Savings: $230 (27%)**
**Annual Savings: $2,760**

---

## Migration Decision Matrix

| AWS Service | Azure Equivalent | Complexity | Effort | Notes |
|-------------|------------------|------------|--------|-------|
| Lambda | Functions | LOW | 2h/function | SDK replacement only |
| EKS | AKS | MEDIUM | 16h | Kubernetes manifests portable |
| RDS | Azure Database | MEDIUM | 8h + DMS | Use Database Migration Service |
| S3 | Blob Storage | LOW | 4h + AzCopy | AzCopy handles data migration |
| DynamoDB | Cosmos DB | MEDIUM | 12h | Schema and SDK changes |
| EventBridge | Event Grid | LOW | 4h | Event schema similar |
| SQS/SNS | Service Bus | LOW | 4h | Message format portable |
| VPC | VNet | LOW | 8h | Network topology similar |
| IAM | Managed Identity | MEDIUM | 8h | Authentication pattern change |
| Secrets Manager | Key Vault | LOW | 2h | Simple secret migration |

**Legend:**
- LOW: Direct 1:1 mapping, minimal changes
- MEDIUM: Equivalent exists, some code/config changes
- HIGH: Significant rearchitecture required

---

**This reference guide supports all AI agents in making accurate service mapping decisions.**

**See Also:**
- 02-TECHNICAL-DEEP-DIVE.md for architecture details
- 03-CUSTOM-AGENT-SPECIFICATIONS.md for how agents use these mappings
