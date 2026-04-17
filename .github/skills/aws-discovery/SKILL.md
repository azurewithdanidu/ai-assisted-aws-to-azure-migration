---
name: aws-discovery
description: >
  Comprehensive AWS account discovery using AWS CLI commands. Covers ALL resource
  types across ALL regions in an AWS account. Use this skill when performing read-only
  discovery to produce aws-inventory.json, architecture-diagram.mmd, dependency-matrix.csv
  and migration-assessment.md. DO NOT make any changes to the AWS environment.
---

# AWS Discovery Skill

## Prerequisites

Before running any commands, verify the CLI is configured and determine scope:

```bash
# Verify identity and account
aws sts get-caller-identity

# List all enabled regions (scan ALL of them, not just us-east-1)
aws ec2 describe-regions --all-regions --query "Regions[?OptInStatus!='not-opted-in'].RegionName" --output text

# Get account alias (human-readable account name)
aws iam list-account-aliases --query "AccountAliases[0]" --output text

# Get account-level contact info
aws account get-contact-information 2>/dev/null || true
```

> **IMPORTANT — Pagination:** Always use `--no-paginate` or collect all pages with `--starting-token` /
> `NextToken`. Never trust a truncated list. All commands below include the correct pagination flag.

---

## Phase 1 — Global / Account-Level Resources

These resources are global (not region-scoped). Run once per account.

### IAM

```bash
# All IAM users
aws iam list-users --no-paginate

# All IAM roles (includes service-linked roles)
aws iam list-roles --no-paginate

# For each role — get trust policy + attached managed policies + inline policies
aws iam get-role --role-name <ROLE_NAME>
aws iam list-attached-role-policies --role-name <ROLE_NAME> --no-paginate
aws iam list-role-policies --role-name <ROLE_NAME> --no-paginate

# All IAM groups and their membership
aws iam list-groups --no-paginate
aws iam list-group-policies --group-name <GROUP_NAME> --no-paginate

# All managed policies created in this account (not AWS-managed)
aws iam list-policies --scope Local --no-paginate

# Account-level password policy
aws iam get-account-password-policy

# Account summary (user count, role count, etc.)
aws iam get-account-summary
```

### Route 53

```bash
# All hosted zones (public and private)
aws route53 list-hosted-zones --no-paginate

# All records for each hosted zone
aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> --no-paginate

# Health checks
aws route53 list-health-checks --no-paginate
```

### CloudFront

```bash
# All CloudFront distributions
aws cloudfront list-distributions --no-paginate

# Full config for each distribution
aws cloudfront get-distribution --id <DIST_ID>
```

### S3 (global bucket list, per-region config)

```bash
# List all buckets (global)
aws s3api list-buckets

# For EACH bucket — get full configuration
aws s3api get-bucket-location          --bucket <BUCKET>
aws s3api get-bucket-versioning        --bucket <BUCKET>
aws s3api get-bucket-encryption        --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-lifecycle-configuration --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-replication       --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-notification-configuration --bucket <BUCKET>
aws s3api get-bucket-policy            --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-acl               --bucket <BUCKET>
aws s3api get-bucket-tagging           --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-cors              --bucket <BUCKET> 2>/dev/null || true
aws s3api get-bucket-website           --bucket <BUCKET> 2>/dev/null || true
aws s3api get-public-access-block      --bucket <BUCKET> 2>/dev/null || true

# Approximate bucket size (use Storage Lens or CloudWatch metrics — not recursive ls)
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BucketSizeBytes \
  --dimensions Name=BucketName,Value=<BUCKET> Name=StorageType,Value=StandardStorage \
  --start-time $(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 86400 --statistics Average 2>/dev/null || true
```

### ACM (Certificate Manager — us-east-1 for CloudFront)

```bash
aws acm list-certificates --region us-east-1 --no-paginate
# Also run per-region in Phase 2
```

### Organizations

```bash
aws organizations describe-organization 2>/dev/null || true
aws organizations list-accounts --no-paginate 2>/dev/null || true
```

---

## Phase 2 — Per-Region Resources

Run the entire block below for **every enabled region**. Replace `<REGION>` with each region name.

```bash
export AWS_DEFAULT_REGION=<REGION>
```

### Compute — Lambda

```bash
# All Lambda functions
aws lambda list-functions --no-paginate --region <REGION>

# For EACH function — full configuration
aws lambda get-function --function-name <FUNCTION_NAME> --region <REGION>
aws lambda get-function-configuration --function-name <FUNCTION_NAME> --region <REGION>
aws lambda list-event-source-mappings --function-name <FUNCTION_NAME> --region <REGION>
aws lambda list-function-url-configs --function-name <FUNCTION_NAME> --region <REGION> 2>/dev/null || true
aws lambda get-policy --function-name <FUNCTION_NAME> --region <REGION> 2>/dev/null || true
aws lambda list-tags --resource <FUNCTION_ARN> --region <REGION>

# All Lambda layers
aws lambda list-layers --no-paginate --region <REGION>

# All Lambda aliases and versions for each function
aws lambda list-aliases --function-name <FUNCTION_NAME> --region <REGION>
aws lambda list-versions-by-function --function-name <FUNCTION_NAME> --region <REGION>
```

### Compute — EC2

```bash
# All instances (all states)
aws ec2 describe-instances --no-paginate --region <REGION>

# AMIs owned by this account
aws ec2 describe-images --owners self --region <REGION>

# Key pairs
aws ec2 describe-key-pairs --region <REGION>

# Security groups
aws ec2 describe-security-groups --no-paginate --region <REGION>

# Elastic IPs
aws ec2 describe-addresses --region <REGION>

# Auto Scaling groups
aws autoscaling describe-auto-scaling-groups --no-paginate --region <REGION>

# Launch templates
aws ec2 describe-launch-templates --no-paginate --region <REGION>
aws ec2 describe-launch-template-versions --launch-template-id <LT_ID> --region <REGION>

# Spot instance requests
aws ec2 describe-spot-instance-requests --region <REGION>
```

### Compute — ECS

```bash
# All clusters
aws ecs list-clusters --no-paginate --region <REGION>
aws ecs describe-clusters --clusters $(aws ecs list-clusters --region <REGION> --query clusterArns --output text) --include ATTACHMENTS SETTINGS STATISTICS TAGS --region <REGION>

# Services in each cluster
aws ecs list-services --cluster <CLUSTER_ARN> --no-paginate --region <REGION>
aws ecs describe-services --cluster <CLUSTER_ARN> --services <SERVICE_ARNS> --region <REGION>

# Task definitions (all families and revisions)
aws ecs list-task-definition-families --no-paginate --region <REGION>
aws ecs list-task-definitions --no-paginate --region <REGION>
aws ecs describe-task-definition --task-definition <TD_ARN> --include TAGS --region <REGION>

# Running tasks
aws ecs list-tasks --cluster <CLUSTER_ARN> --no-paginate --region <REGION>
aws ecs describe-tasks --cluster <CLUSTER_ARN> --tasks <TASK_ARNS> --region <REGION>
```

### Compute — EKS

```bash
# All clusters
aws eks list-clusters --no-paginate --region <REGION>
aws eks describe-cluster --name <CLUSTER_NAME> --region <REGION>

# Node groups
aws eks list-nodegroups --cluster-name <CLUSTER_NAME> --no-paginate --region <REGION>
aws eks describe-nodegroup --cluster-name <CLUSTER_NAME> --nodegroup-name <NG_NAME> --region <REGION>

# Fargate profiles
aws eks list-fargate-profiles --cluster-name <CLUSTER_NAME> --region <REGION>
aws eks describe-fargate-profile --cluster-name <CLUSTER_NAME> --fargate-profile-name <FP_NAME> --region <REGION>

# Add-ons
aws eks list-addons --cluster-name <CLUSTER_NAME> --region <REGION>
aws eks describe-addon --cluster-name <CLUSTER_NAME> --addon-name <ADDON_NAME> --region <REGION>
```

### Compute — Elastic Beanstalk

```bash
aws elasticbeanstalk describe-applications --region <REGION>
aws elasticbeanstalk describe-environments --region <REGION>
aws elasticbeanstalk describe-configuration-settings --application-name <APP_NAME> --environment-name <ENV_NAME> --region <REGION>
```

### Compute — App Runner

```bash
aws apprunner list-services --region <REGION> 2>/dev/null || true
aws apprunner describe-service --service-arn <SERVICE_ARN> --region <REGION>
```

### Storage — EBS

```bash
# All volumes
aws ec2 describe-volumes --no-paginate --region <REGION>

# All snapshots owned by this account
aws ec2 describe-snapshots --owner-ids self --no-paginate --region <REGION>
```

### Storage — EFS

```bash
aws efs describe-file-systems --region <REGION>
aws efs describe-mount-targets --file-system-id <FS_ID> --region <REGION>
aws efs describe-access-points --file-system-id <FS_ID> --region <REGION>
```

### Storage — FSx

```bash
aws fsx describe-file-systems --region <REGION> 2>/dev/null || true
```

### Storage — Glacier / S3 Glacier

```bash
aws glacier list-vaults --account-id - --region <REGION> 2>/dev/null || true
```

### Storage — Backup

```bash
aws backup list-backup-vaults --region <REGION> 2>/dev/null || true
aws backup list-backup-plans --region <REGION> 2>/dev/null || true
```

### Database — RDS

```bash
# DB instances
aws rds describe-db-instances --region <REGION>

# DB clusters (Aurora)
aws rds describe-db-clusters --region <REGION>

# Parameter groups
aws rds describe-db-parameter-groups --region <REGION>
aws rds describe-db-cluster-parameter-groups --region <REGION>

# Option groups
aws rds describe-option-groups --region <REGION>

# Snapshots (owned by this account)
aws rds describe-db-snapshots --snapshot-type manual --region <REGION>
aws rds describe-db-cluster-snapshots --snapshot-type manual --region <REGION>

# Subnet groups
aws rds describe-db-subnet-groups --region <REGION>

# Proxy
aws rds describe-db-proxies --region <REGION> 2>/dev/null || true
```

### Database — DynamoDB

```bash
# All tables
aws dynamodb list-tables --no-paginate --region <REGION>

# For EACH table
aws dynamodb describe-table --table-name <TABLE_NAME> --region <REGION>
aws dynamodb describe-time-to-live --table-name <TABLE_NAME> --region <REGION>
aws dynamodb describe-continuous-backups --table-name <TABLE_NAME> --region <REGION>
aws dynamodb list-tags-of-resource --resource-arn <TABLE_ARN> --region <REGION>

# Global tables
aws dynamodb list-global-tables --region <REGION> 2>/dev/null || true
```

### Database — ElastiCache

```bash
aws elasticache describe-cache-clusters --region <REGION>
aws elasticache describe-replication-groups --region <REGION>
aws elasticache describe-cache-subnet-groups --region <REGION>
aws elasticache describe-cache-parameter-groups --region <REGION>
```

### Database — Redshift

```bash
aws redshift describe-clusters --region <REGION> 2>/dev/null || true
aws redshift describe-cluster-subnet-groups --region <REGION> 2>/dev/null || true
```

### Database — DocumentDB

```bash
aws docdb describe-db-clusters --region <REGION> 2>/dev/null || true
aws docdb describe-db-instances --region <REGION> 2>/dev/null || true
```

### Database — Keyspaces (Cassandra)

```bash
aws keyspaces list-keyspaces --region <REGION> 2>/dev/null || true
aws keyspaces list-tables --keyspace-name <KS_NAME> --region <REGION> 2>/dev/null || true
```

### Networking — VPC

```bash
# VPCs
aws ec2 describe-vpcs --region <REGION>

# Subnets
aws ec2 describe-subnets --no-paginate --region <REGION>

# Route tables
aws ec2 describe-route-tables --no-paginate --region <REGION>

# Internet gateways
aws ec2 describe-internet-gateways --region <REGION>

# NAT gateways
aws ec2 describe-nat-gateways --no-paginate --region <REGION>

# VPC endpoints
aws ec2 describe-vpc-endpoints --no-paginate --region <REGION>

# VPC peering connections
aws ec2 describe-vpc-peering-connections --region <REGION>

# Transit gateways
aws ec2 describe-transit-gateways --region <REGION> 2>/dev/null || true
aws ec2 describe-transit-gateway-attachments --region <REGION> 2>/dev/null || true

# Network ACLs
aws ec2 describe-network-acls --region <REGION>

# Flow logs
aws ec2 describe-flow-logs --region <REGION>
```

### Networking — Load Balancers

```bash
# ALB and NLB (ELBv2)
aws elbv2 describe-load-balancers --no-paginate --region <REGION>
aws elbv2 describe-target-groups --no-paginate --region <REGION>
aws elbv2 describe-listeners --load-balancer-arn <LB_ARN> --region <REGION>
aws elbv2 describe-rules --listener-arn <LISTENER_ARN> --region <REGION>

# Classic ELB (if any)
aws elb describe-load-balancers --region <REGION> 2>/dev/null || true
```

### Networking — Direct Connect & VPN

```bash
aws directconnect describe-connections --region <REGION> 2>/dev/null || true
aws directconnect describe-virtual-gateways 2>/dev/null || true
aws ec2 describe-vpn-connections --region <REGION>
aws ec2 describe-customer-gateways --region <REGION>
aws ec2 describe-vpn-gateways --region <REGION>
```

### Messaging & Events — SQS

```bash
# All queues (returns URLs)
aws sqs list-queues --no-paginate --region <REGION>

# For EACH queue
aws sqs get-queue-attributes --queue-url <QUEUE_URL> --attribute-names All --region <REGION>
aws sqs list-queue-tags --queue-url <QUEUE_URL> --region <REGION>
```

### Messaging & Events — SNS

```bash
aws sns list-topics --region <REGION>
aws sns list-subscriptions --region <REGION>

# For EACH topic
aws sns get-topic-attributes --topic-arn <TOPIC_ARN> --region <REGION>
aws sns list-tags-for-resource --resource-arn <TOPIC_ARN> --region <REGION>
aws sns list-subscriptions-by-topic --topic-arn <TOPIC_ARN> --region <REGION>
```

### Messaging & Events — EventBridge

```bash
# Event buses
aws events list-event-buses --no-paginate --region <REGION>

# Rules per bus
aws events list-rules --event-bus-name <BUS_NAME> --no-paginate --region <REGION>
aws events list-targets-by-rule --rule <RULE_NAME> --event-bus-name <BUS_NAME> --region <REGION>

# Schemas
aws schemas list-registries --region <REGION> 2>/dev/null || true

# Pipes
aws pipes list-pipes --region <REGION> 2>/dev/null || true
```

### Messaging & Events — Kinesis

```bash
# Data Streams
aws kinesis list-streams --no-paginate --region <REGION>
aws kinesis describe-stream-summary --stream-name <STREAM_NAME> --region <REGION>

# Firehose
aws firehose list-delivery-streams --no-paginate --region <REGION>
aws firehose describe-delivery-stream --delivery-stream-name <STREAM_NAME> --region <REGION>

# Data Analytics
aws kinesisanalytics list-applications --region <REGION> 2>/dev/null || true
aws kinesisanalyticsv2 list-applications --region <REGION> 2>/dev/null || true
```

### Messaging & Events — MQ

```bash
aws mq list-brokers --region <REGION> 2>/dev/null || true
```

### API Gateway

```bash
# REST APIs (v1)
aws apigateway get-rest-apis --region <REGION>
aws apigateway get-resources --rest-api-id <API_ID> --region <REGION>
aws apigateway get-stages --rest-api-id <API_ID> --region <REGION>
aws apigateway get-authorizers --rest-api-id <API_ID> --region <REGION>

# HTTP APIs and WebSocket APIs (v2)
aws apigatewayv2 get-apis --region <REGION>
aws apigatewayv2 get-stages --api-id <API_ID> --region <REGION>
aws apigatewayv2 get-integrations --api-id <API_ID> --region <REGION>
aws apigatewayv2 get-authorizers --api-id <API_ID> --region <REGION>

# Custom domain names
aws apigateway get-domain-names --region <REGION>
aws apigatewayv2 get-domain-names --region <REGION>
```

### Serverless — Step Functions

```bash
aws stepfunctions list-state-machines --no-paginate --region <REGION>
aws stepfunctions describe-state-machine --state-machine-arn <SM_ARN> --region <REGION>
aws stepfunctions list-tags-for-resource --resource-arn <SM_ARN> --region <REGION>
```

### Serverless — AppSync

```bash
aws appsync list-graphql-apis --region <REGION> 2>/dev/null || true
aws appsync list-data-sources --api-id <API_ID> --region <REGION>
aws appsync list-resolvers --api-id <API_ID> --type-name <TYPE> --region <REGION>
```

### Security — Secrets Manager

```bash
# All secrets (names only — NEVER retrieve values)
aws secretsmanager list-secrets --no-paginate --region <REGION>

# For EACH secret — metadata only
aws secretsmanager describe-secret --secret-id <SECRET_ARN> --region <REGION>
# DO NOT call get-secret-value
```

### Security — Systems Manager Parameter Store

```bash
# All parameters (names and metadata — NOT values)
aws ssm describe-parameters --no-paginate --region <REGION>

# For each SecureString — note it's encrypted, capture the KMS key used
# DO NOT call get-parameter / get-parameters to retrieve values
```

### Security — KMS

```bash
# All customer-managed keys
aws kms list-keys --region <REGION>

# For EACH key
aws kms describe-key --key-id <KEY_ID> --region <REGION>
aws kms list-aliases --key-id <KEY_ID> --region <REGION>
aws kms get-key-rotation-status --key-id <KEY_ID> --region <REGION>
aws kms list-resource-tags --key-id <KEY_ID> --region <REGION>
```

### Security — ACM

```bash
aws acm list-certificates --region <REGION>
aws acm describe-certificate --certificate-arn <CERT_ARN> --region <REGION>
```

### Security — WAF

```bash
# WAFv2 (regional)
aws wafv2 list-web-acls --scope REGIONAL --region <REGION> 2>/dev/null || true
aws wafv2 list-rule-groups --scope REGIONAL --region <REGION> 2>/dev/null || true
```

### Security — Cognito

```bash
aws cognito-idp list-user-pools --max-results 60 --region <REGION> 2>/dev/null || true
aws cognito-idp describe-user-pool --user-pool-id <POOL_ID> --region <REGION>
aws cognito-idp list-user-pool-clients --user-pool-id <POOL_ID> --region <REGION>
aws cognito-identity list-identity-pools --max-results 60 --region <REGION> 2>/dev/null || true
```

### Monitoring & Logging — CloudWatch

```bash
# Log groups
aws logs describe-log-groups --no-paginate --region <REGION>

# For EACH log group — retention and subscriptions
aws logs describe-subscription-filters --log-group-name <LG_NAME> --region <REGION>

# Dashboards
aws cloudwatch list-dashboards --region <REGION>

# Alarms
aws cloudwatch describe-alarms --no-paginate --region <REGION>

# Metric streams
aws cloudwatch list-metric-streams --region <REGION> 2>/dev/null || true
```

### Monitoring & Logging — CloudTrail

```bash
aws cloudtrail describe-trails --include-shadow-trails true --region <REGION>
aws cloudtrail get-trail-status --name <TRAIL_ARN> --region <REGION>
aws cloudtrail get-event-selectors --trail-name <TRAIL_ARN> --region <REGION>
```

### Monitoring — X-Ray

```bash
aws xray get-groups --region <REGION> 2>/dev/null || true
aws xray get-sampling-rules --region <REGION> 2>/dev/null || true
```

### Infrastructure as Code — CloudFormation

```bash
# All stacks (all statuses)
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE --region <REGION>
aws cloudformation describe-stacks --region <REGION>

# For EACH stack — download full template
aws cloudformation get-template --stack-name <STACK_NAME> --region <REGION>

# Stack resources
aws cloudformation list-stack-resources --stack-name <STACK_NAME> --region <REGION>

# Change sets
aws cloudformation list-change-sets --stack-name <STACK_NAME> --region <REGION>
```

### Cost & Billing (run once, not per-region)

```bash
# Cost Explorer — last 3 months by service
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '90 days ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Cost forecasts
aws ce get-cost-forecast \
  --time-period Start=$(date -u +%Y-%m-%d),End=$(date -u -d '90 days' +%Y-%m-%d) \
  --metric BLENDED_COST \
  --granularity MONTHLY

# Budgets
aws budgets describe-budgets --account-id <ACCOUNT_ID> 2>/dev/null || true
```

### Miscellaneous — Other Services

```bash
# Amplify apps
aws amplify list-apps --region <REGION> 2>/dev/null || true

# AppConfig
aws appconfig list-applications --region <REGION> 2>/dev/null || true

# CodePipeline / CodeBuild / CodeDeploy
aws codepipeline list-pipelines --region <REGION> 2>/dev/null || true
aws codebuild list-projects --region <REGION> 2>/dev/null || true
aws deploy list-applications --region <REGION> 2>/dev/null || true

# SageMaker endpoints (if AI/ML workloads present)
aws sagemaker list-endpoints --region <REGION> 2>/dev/null || true

# Glue (ETL)
aws glue get-databases --region <REGION> 2>/dev/null || true
aws glue list-jobs --region <REGION> 2>/dev/null || true

# Athena
aws athena list-work-groups --region <REGION> 2>/dev/null || true

# Transfer Family
aws transfer list-servers --region <REGION> 2>/dev/null || true

# MediaConvert / MediaLive (if media workloads)
aws mediaconvert list-jobs --region <REGION> 2>/dev/null || true

# IoT Core
aws iot list-things --region <REGION> 2>/dev/null || true

# Location Service
aws location list-maps --region <REGION> 2>/dev/null || true
```

---

## Phase 3 — Cross-Service Dependency Mapping

After collecting raw data, perform these correlation steps to build the dependency graph:

1. **Lambda → Triggers**: Match `list-event-source-mappings` EventSourceArn to SQS/Kinesis/DynamoDB ARNs collected
2. **Lambda → IAM Roles**: Match `Role` field from function config to IAM roles collected; extract S3/DynamoDB/SQS permissions from role policies
3. **Lambda → Environment Variables**: Scan env vars for ARNs, names, or URLs referencing other resources
4. **API Gateway → Lambda**: Match integration URIs to function ARNs
5. **ECS/EKS → Secrets Manager / SSM**: Match task definition secrets to secret ARNs collected
6. **RDS → Security Groups**: Match DB security groups to EC2 security groups; find EC2 instances / Lambda in same groups
7. **S3 → Notifications**: Match S3 notification configs to Lambda ARNs, SQS queue ARNs, SNS topic ARNs
8. **EventBridge → Targets**: Match rule targets to Lambda ARNs, SQS, Step Functions, ECS
9. **CloudFormation → Resources**: Use `list-stack-resources` to map stacks to all resources they manage

---

## Phase 4 — Output Files

Write all output to `outputs/aws-migration-artifacts/`. Never overwrite existing files without confirmation.

### `aws-inventory.json`

Top-level structure:
```json
{
  "account_id": "",
  "account_alias": "",
  "discovery_timestamp": "",
  "regions_scanned": [],
  "summary": {
    "total_resources": 0,
    "by_service": {},
    "by_region": {}
  },
  "resources": {
    "lambda": [],
    "ec2": [],
    "ecs": [],
    "eks": [],
    "s3": [],
    "rds": [],
    "dynamodb": [],
    "elasticache": [],
    "sqs": [],
    "sns": [],
    "eventbridge": [],
    "kinesis": [],
    "api_gateway": [],
    "step_functions": [],
    "cloudformation": [],
    "iam_roles": [],
    "secrets_manager": [],
    "kms": [],
    "vpc": [],
    "load_balancers": [],
    "cloudwatch": [],
    "other": []
  },
  "dependencies": []
}
```

### `architecture-diagram.mmd`

Mermaid diagram using `graph TD`. Group resources into subgraphs by tier:
- `subgraph Frontend` — CloudFront, S3 static, API Gateway
- `subgraph Compute` — Lambda, ECS, EKS, EC2
- `subgraph Data` — RDS, DynamoDB, ElastiCache, S3 data
- `subgraph Messaging` — SQS, SNS, EventBridge, Kinesis
- `subgraph Security` — IAM, Secrets Manager, KMS, Cognito
- `subgraph Networking` — VPC, subnets, LBs, Route 53

### `dependency-matrix.csv`

```csv
source_resource,source_type,source_arn,relationship,target_resource,target_type,target_arn,criticality,notes
```

### `migration-assessment.md`

Sections:
1. Executive Summary
2. Resource Count by Service
3. Service Complexity Matrix (LOW / MEDIUM / HIGH / CRITICAL)
4. Dependency Map (narrative, referencing diagram)
5. Effort Estimates (days per resource, total timeline)
6. Migration Risks
7. Recommended Migration Order (waves)
8. Next Steps

---

## Security Rules

- **NEVER** call `get-secret-value` on any Secrets Manager secret
- **NEVER** call `get-parameter` or `get-parameters` on SSM Parameter Store for SecureString parameters
- **NEVER** call `kms decrypt` or any KMS operation that processes data
- **NEVER** modify, create, delete, or update any AWS resource
- **NEVER** call any `put-*`, `create-*`, `delete-*`, `update-*`, `start-*`, `stop-*` commands
- All commands must be `describe-*`, `list-*`, `get-*` (metadata only) commands

## Error Handling

Service not available in a region returns `UnsupportedOperation` or `InvalidRequestException`.  
Always use `2>/dev/null || true` on commands for services that may not be enabled in all regions.  
Log skipped regions and services in the final report.
