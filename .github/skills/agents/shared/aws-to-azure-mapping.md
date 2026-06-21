---
name: aws-to-azure-mapping
description: Authoritative AWS-to-Azure service equivalents for all service categories — compute, storage, database, messaging, networking, security, monitoring
---

# AWS-to-Azure Mapping Skill

## Purpose

Provide the authoritative mapping from every AWS service encountered in this migration to its Azure equivalent, including configuration differences and migration notes.

## When to Use

- Before selecting any Azure service as a replacement for an AWS service
- When populating `service-mapping.md` or `design-document.md` Section 3
- When specifying code or IaC changes that reference service-specific APIs or SDKs

## Process

1. Identify each AWS service from `outputs/aws-migration-artifacts/aws-inventory.json`.
2. Look up the Azure equivalent in the mapping tables below.
3. Note the configuration differences and migration considerations for each.
4. For any AWS service not in the tables, use `azure-mcp/documentation` to find the equivalent and cite the source in the design document under "Open Questions / Gaps".
5. Apply the service selection priority rule: **serverless-first** — prefer Azure Functions over Container Apps over AKS unless the workload requires containers or persistent state.

## Mapping Tables

### Compute

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| Lambda | Azure Functions | Consumption/Premium/Dedicated plans; Python handler signature differs (`func.HttpRequest` not `event`/`context`) |
| ECS / Fargate | Azure Container Apps | KEDA-based scaling; Dapr integration; no task definition concept |
| EKS | Azure Kubernetes Service (AKS) | Azure AD RBAC; Azure CNI networking; managed node pools |
| EC2 | Azure Virtual Machines | Availability Zones; Spot VMs (up to 90% savings); proximity placement groups |
| Elastic Beanstalk | Azure App Service | Deployment slots; auto-scale rules |
| Batch | Azure Batch | Pool and job concepts align; node agent differs |

### Storage

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| S3 | Azure Blob Storage | SAS tokens vs presigned URLs; Hot/Cool/Archive tiers; lifecycle policies |
| EFS | Azure Files | SMB 3.x / NFS 4.1; Premium (SSD) and Standard (HDD) tiers |
| FSx for Windows | Azure Files (Premium SMB) | Full SMB protocol; Active Directory integration |
| ECR | Azure Container Registry (ACR) | Basic/Standard/Premium SKUs; geo-replication in Premium |
| Glacier | Azure Blob Archive tier | Retrieval latency: Standard (hours), Expedited (minutes) |

### Database

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| RDS PostgreSQL | Azure Database for PostgreSQL Flexible Server | Burstable (B-series) / GP / Memory Optimized SKUs; Entra auth supported |
| RDS MySQL | Azure Database for MySQL Flexible Server | Same SKU pattern; HA with zone-redundant standby |
| DynamoDB | Azure Cosmos DB (NoSQL API) | Request Unit (RU) provisioning; partition key required; also MongoDB/Cassandra/Table API |
| ElastiCache Redis | Azure Cache for Redis | Basic/Standard/Premium tiers; clustering in Premium |
| Aurora | Azure SQL Database Hyperscale | Auto-scaling storage; read replicas |
| RDS SQL Server | Azure SQL Managed Instance | Full SQL Server compatibility; VNet-injected |

### Messaging

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| SQS | Azure Service Bus Queue | Sessions for FIFO; dead-letter queue; message lock duration (max 5 min) |
| SNS | Azure Event Grid | Push model; topic/subscription; event schema filtering |
| EventBridge | Azure Event Grid (Custom Topics) | Event routing rules; domain routing for multi-tenant |
| Kinesis Data Streams | Azure Event Hubs | Consumer groups; Kafka protocol compatibility in Standard+ |
| Kinesis Firehose | Azure Event Hubs + Stream Analytics | Delivery to Blob, ADLS, SQL |
| SQS FIFO | Azure Service Bus Queue (Sessions enabled) | Sessions guarantee ordering per session key |

### Networking

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| VPC | Azure Virtual Network (VNet) | Address space; subnet delegation; no implicit default VPC |
| Security Groups | Network Security Groups (NSGs) | Stateful; ASG equivalent = Application Security Groups |
| VPC Peering | VNet Peering | Non-transitive; Global VNet Peering across regions |
| Transit Gateway | Azure Virtual WAN | Hub-spoke topology; SD-WAN integration |
| ALB | Azure Application Gateway | WAF v2 integration; URL-based routing; multi-site hosting |
| NLB | Azure Load Balancer (Standard) | Standard SKU required for Availability Zone support |
| CloudFront | Azure Front Door | Premium for WAF; Standard for CDN; anycast PoPs |
| Route 53 (DNS) | Azure DNS | Private DNS Zones for VNet resolution |
| Route 53 (Routing) | Azure Traffic Manager | Weighted/Priority/Performance routing policies |
| Direct Connect | Azure ExpressRoute | Partner circuits; FastPath for high-throughput |
| VPN Gateway | Azure VPN Gateway | Route-based; active-active for HA |

### Security & Identity

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| IAM Roles | Azure Managed Identity + RBAC | System-assigned (per resource) or User-assigned (shared); built-in roles |
| IAM Policies | Azure RBAC Role Definitions | JSON conditions; scope = management group/subscription/RG/resource |
| Secrets Manager | Azure Key Vault (Secrets) | Soft delete enabled by default; purge protection recommended |
| KMS | Azure Key Vault (Keys) | HSM-backed keys in Premium SKU |
| ACM | App Service Managed Certs / Key Vault Certs | Free managed certs for App Service; Key Vault for custom |
| WAF | Azure Web Application Firewall | Integrated with App Gateway or Front Door |
| Cognito | Azure Active Directory B2C | User flows (built-in) and custom policies (Identity Experience Framework) |
| Shield | Azure DDoS Protection | Basic (free, always-on); Standard (per-VNet, charged) |
| GuardDuty | Microsoft Defender for Cloud | Security posture + threat protection |
| Macie | Microsoft Purview | Data governance and sensitive data discovery |

### Monitoring & Operations

| AWS Service | Azure Equivalent | Key Differences |
|---|---|---|
| CloudWatch Logs | Azure Monitor Logs (Log Analytics) | KQL query language (not CloudWatch Insights) |
| CloudWatch Metrics | Azure Monitor Metrics | Custom metrics via App Insights SDK |
| X-Ray | Azure Application Insights | Distributed tracing; dependency maps; sampling |
| CloudTrail | Azure Monitor Activity Log | 90-day retention by default; archive to Storage |
| Systems Manager | Azure Automation | Runbooks (PowerShell/Python); DSC; patch management |
| Systems Manager Parameter Store | Azure App Configuration | Hierarchical keys; feature flags |
| CloudFormation | Azure Bicep / ARM | Bicep is preferred (transpiles to ARM) |
| CDK | Azure Developer CLI (azd) | Scaffold + provision + deploy |

## Rules

- **Never pick AKS** for a workload that fits Azure Container Apps (stateless, HTTP-driven, KEDA-scalable).
- **Never use Azure API Management** as the primary ingress router — prohibited by this project's design constraints.
- **Always default to single-region** unless `migration-assessment.md` explicitly flags multi-region requirements.
- **Serverless-first:** Functions → Container Apps → AKS. Document the reason if deviating from this order.
- **For any service not in these tables**, document it as a gap in `design-document.md` under "Open Questions / Gaps" and look it up via `azure-mcp/documentation`.

## Output

- Populated rows in `outputs/azure-architecture-output/design-document.md` Section 3 (Azure Service Mapping table)
- Populated `outputs/azure-architecture-output/service-mapping.md`
- Any gaps documented under "Open Questions / Gaps" in the design document
