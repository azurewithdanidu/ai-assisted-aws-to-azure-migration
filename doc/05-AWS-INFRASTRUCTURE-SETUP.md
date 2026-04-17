# AWS Infrastructure Setup for Demo

**Purpose:** Deploy complete AWS reference architecture for migration demonstration  
**Deployment Time:** 45 minutes  
**Cost:** ~$50/day for demo environment

---

## Architecture Overview

```
Demo Environment Components:
- VPC with public/private subnets across 2 AZs
- EKS cluster with 3 microservices
- 3 Lambda functions (Node.js, Python, Go)
- RDS PostgreSQL database
- 3 S3 buckets with different configurations
- EventBridge for event routing
- IAM roles and security groups
```

---

## Deployment Order

**Must deploy in this sequence:**

1. VPC and Networking (5 minutes)
2. RDS Database (15 minutes) - depends on VPC
3. S3 Buckets (2 minutes) - standalone
4. Lambda Functions (5 minutes) - depends on VPC and RDS
5. EKS Cluster (20 minutes) - depends on VPC

**Total Time:** ~47 minutes

---

## Prerequisites

```bash
# AWS CLI configured
aws configure
# Verify: aws sts get-caller-identity

# Required permissions
- CloudFormation full access
- VPC, EC2, RDS, S3, Lambda, EKS full access
- IAM role creation

# Set region
export AWS_REGION=us-east-1
```

---

## Template 1: VPC and Networking

**File:** `aws-infrastructure/vpc-network.yaml`

**Creates:**
- 1 VPC (10.0.0.0/16)
- 2 public subnets (10.0.1.0/24, 10.0.2.0/24)
- 2 private subnets (10.0.10.0/24, 10.0.11.0/24)
- Internet Gateway
- NAT Gateway
- Route tables
- Security groups for EKS and RDS

**Deployment:**
```bash
aws cloudformation deploy \
  --template-file aws-infrastructure/vpc-network.yaml \
  --stack-name demo-network \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

# Verify
aws cloudformation describe-stacks \
  --stack-name demo-network \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
# Expected: CREATE_COMPLETE
```

**Outputs:**
- VPCId
- PublicSubnet1Id, PublicSubnet2Id
- PrivateSubnet1Id, PrivateSubnet2Id
- EKSSecurityGroupId
- RDSSecurityGroupId
- DBSubnetGroupName

---

## Template 2: RDS Database

**File:** `aws-infrastructure/rds-database.yaml`

**Creates:**
- RDS PostgreSQL 15.4 instance
- Multi-AZ deployment
- Encrypted at rest
- Automated backups (7 days)
- 100 GB storage with auto-scaling

**Deployment:**
```bash
aws cloudformation deploy \
  --template-file aws-infrastructure/rds-database.yaml \
  --stack-name demo-database \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides \
    VPCStackName=demo-network \
    DBUsername=postgres \
    DBPassword=YourSecurePassword123!

# Verify (takes ~15 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name demo-database \
  --region us-east-1

# Get endpoint
aws cloudformation describe-stacks \
  --stack-name demo-database \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text
```

**Outputs:**
- DBEndpoint
- DBPort
- DBName

---

## Template 3: S3 Buckets

**File:** `aws-infrastructure/s3-buckets.yaml`

**Creates:**
- order-invoices bucket (versioning enabled, private)
- product-images bucket (public read access)
- backup-archives bucket (lifecycle to Glacier after 90 days)

**Deployment:**
```bash
# Note: S3 bucket names must be globally unique
# Replace 'demo' with your unique prefix
export BUCKET_PREFIX="yourcompany-demo-$(date +%s)"

aws cloudformation deploy \
  --template-file aws-infrastructure/s3-buckets.yaml \
  --stack-name demo-storage \
  --region us-east-1 \
  --parameter-overrides BucketPrefix=${BUCKET_PREFIX}

# Verify
aws s3 ls | grep ${BUCKET_PREFIX}
```

**Outputs:**
- InvoicesBucketName
- ImagesBucketName
- BackupsBucketName

---

## Template 4: Lambda Functions

**File:** `aws-infrastructure/lambda-functions.yaml`

**Creates:**
- Order Validator (Node.js 18, API Gateway trigger)
- Email Notifier (Python 3.11, EventBridge trigger)
- Inventory Sync (Go 1.21, scheduled trigger)
- IAM execution roles
- EventBridge rules
- API Gateway

**Deployment:**
```bash
# Package Lambda code first
cd lambda-functions/order-validator
zip -r ../../order-validator.zip .
cd ../email-notifier
zip -r ../../email-notifier.zip .
cd ../inventory-sync
zip -r ../../inventory-sync.zip .
cd ../..

# Upload to S3
aws s3 mb s3://${BUCKET_PREFIX}-lambda-code
aws s3 cp order-validator.zip s3://${BUCKET_PREFIX}-lambda-code/
aws s3 cp email-notifier.zip s3://${BUCKET_PREFIX}-lambda-code/
aws s3 cp inventory-sync.zip s3://${BUCKET_PREFIX}-lambda-code/

# Deploy stack
aws cloudformation deploy \
  --template-file aws-infrastructure/lambda-functions.yaml \
  --stack-name demo-lambda \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides \
    VPCStackName=demo-network \
    DBStackName=demo-database \
    StorageStackName=demo-storage \
    LambdaCodeBucket=${BUCKET_PREFIX}-lambda-code

# Test Order Validator
VALIDATOR_URL=$(aws cloudformation describe-stacks \
  --stack-name demo-lambda \
  --query 'Stacks[0].Outputs[?OutputKey==`OrderValidatorUrl`].OutputValue' \
  --output text)

curl -X POST ${VALIDATOR_URL} \
  -H "Content-Type: application/json" \
  -d '{"orderId":"12345","items":[{"sku":"ABC","qty":2}]}'
```

**Outputs:**
- OrderValidatorFunctionArn
- OrderValidatorUrl
- EmailNotifierFunctionArn
- InventorySyncFunctionArn

---

## Template 5: EKS Cluster

**File:** `aws-infrastructure/eks-cluster.yaml`

**Creates:**
- EKS cluster (version 1.28)
- Managed node group (t3.medium, 2-5 nodes)
- Cluster IAM role
- Node IAM role
- VPC CNI and CoreDNS add-ons

**Deployment:**
```bash
aws cloudformation deploy \
  --template-file aws-infrastructure/eks-cluster.yaml \
  --stack-name demo-eks \
  --capabilities CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides VPCStackName=demo-network

# Wait for completion (~20 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name demo-eks \
  --region us-east-1

# Configure kubectl
CLUSTER_NAME=$(aws cloudformation describe-stacks \
  --stack-name demo-eks \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
  --output text)

aws eks update-kubeconfig \
  --name ${CLUSTER_NAME} \
  --region us-east-1

# Verify
kubectl get nodes
# Should show 2-5 nodes in Ready state
```

**Outputs:**
- ClusterName
- ClusterEndpoint
- ClusterArn

---

## Deploy Microservices to EKS

**Application Code Structure:**
```
application/
├── order-api/          # Node.js Express API
├── payment-service/    # Python Flask service
└── inventory-service/  # Go service
```

**Kubernetes Manifests:**
```bash
# Deploy all services
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/order-api-deployment.yaml
kubectl apply -f k8s/payment-service-deployment.yaml
kubectl apply -f k8s/inventory-service-deployment.yaml

# Verify deployments
kubectl get pods -n demo-apps
kubectl get services -n demo-apps

# Test services
kubectl port-forward -n demo-apps service/order-api 8080:80
curl http://localhost:8080/health
```

---

## Verification Checklist

After all stacks deployed:

```bash
# 1. Check all stacks
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `demo-`)].StackName'

# Expected output:
# - demo-network
# - demo-database
# - demo-storage
# - demo-lambda
# - demo-eks

# 2. Test RDS connectivity
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name demo-database \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

psql -h ${DB_ENDPOINT} -U postgres -d orders
# Enter password when prompted

# 3. Test S3 buckets
aws s3 ls | grep demo

# 4. Test Lambda functions
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `demo-`)].FunctionName'

# 5. Test EKS cluster
kubectl get nodes
kubectl get pods --all-namespaces

# 6. Check EventBridge rules
aws events list-rules \
  --query 'Rules[?contains(Name, `demo-`)].Name'
```

---

## Cost Estimate

**Daily Costs (approximate):**
- EKS cluster: $73/day ($0.10/hour + $15/day for nodes)
- RDS db.t3.medium Multi-AZ: $6/day
- Lambda (minimal usage): $0.50/day
- S3 storage (minimal): $0.10/day
- Data transfer: $0.50/day
- NAT Gateway: $1.08/day

**Total: ~$50-60/day**

**Monthly (if left running): ~$1,500/month**

**Recommendation:** Delete after demo to avoid costs

---

## Cleanup

**Delete all resources:**

```bash
# Delete in reverse order (dependencies)

# 1. Delete EKS (takes ~10 minutes)
aws cloudformation delete-stack \
  --stack-name demo-eks \
  --region us-east-1

aws cloudformation wait stack-delete-complete \
  --stack-name demo-eks \
  --region us-east-1

# 2. Delete Lambda
aws cloudformation delete-stack \
  --stack-name demo-lambda \
  --region us-east-1

# 3. Empty and delete S3 buckets first
INVOICES_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name demo-storage \
  --query 'Stacks[0].Outputs[?OutputKey==`InvoicesBucketName`].OutputValue' \
  --output text)

aws s3 rm s3://${INVOICES_BUCKET} --recursive
# Repeat for other buckets

aws cloudformation delete-stack \
  --stack-name demo-storage \
  --region us-east-1

# 4. Delete RDS (takes ~10 minutes)
aws cloudformation delete-stack \
  --stack-name demo-database \
  --region us-east-1

aws cloudformation wait stack-delete-complete \
  --stack-name demo-database \
  --region us-east-1

# 5. Delete VPC (must be last)
aws cloudformation delete-stack \
  --stack-name demo-network \
  --region us-east-1

# 6. Delete Lambda code bucket
aws s3 rb s3://${BUCKET_PREFIX}-lambda-code --force

# Verify all deleted
aws cloudformation list-stacks \
  --query 'StackSummaries[?contains(StackName, `demo-`)].{Name:StackName,Status:StackStatus}'
```

---

## Troubleshooting

**Issue: VPC stack fails to create**
```bash
# Check for VPC limit
aws ec2 describe-vpcs
# Default limit is 5 VPCs per region

# Solution: Delete unused VPCs or request limit increase
```

**Issue: RDS creation timeout**
```bash
# RDS takes 15-20 minutes
# Check status
aws rds describe-db-instances \
  --query 'DBInstances[?DBInstanceIdentifier==`demo-database`].DBInstanceStatus'

# If stuck, check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name demo-database \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

**Issue: EKS nodes not ready**
```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name demo-eks-cluster \
  --nodegroup-name demo-node-group

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=demo-eks-cluster"

# Check kubelet logs
kubectl logs -n kube-system -l k8s-app=kube-proxy
```

**Issue: Lambda function errors**
```bash
# Check function logs
aws logs tail /aws/lambda/demo-order-validator --follow

# Test function directly
aws lambda invoke \
  --function-name demo-order-validator \
  --payload '{"body":"{\"orderId\":\"test\"}"}' \
  response.json

cat response.json
```

---

## Next Steps After Deployment

1. **Initialize Database Schema**
```bash
# Connect to RDS
psql -h ${DB_ENDPOINT} -U postgres -d orders

# Run schema
CREATE TABLE orders (...);
CREATE TABLE payments (...);
CREATE TABLE inventory (...);
```

2. **Deploy Application Code to EKS**
```bash
# Build and push container images
# Deploy Kubernetes manifests
# Configure ingress
```

3. **Configure Buildkite Pipeline**
```yaml
# .buildkite/pipeline.yml
steps:
  - label: "Deploy to AWS"
    commands:
      - aws cloudformation deploy ...
```

4. **Ready for Migration Demo**
- GitHub repository set up with agents
- AWS environment fully deployed
- All services running and tested
- Ready to invoke @aws-discovery

---

**Demo environment is now ready for AI-assisted migration to Azure!**
