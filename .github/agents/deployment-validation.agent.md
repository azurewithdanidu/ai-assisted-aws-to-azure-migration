---
name: deployment-validation
description: Validate Azure deployments and ensure migration success
---

# Deployment Validation Agent

## Purpose

Comprehensive validation of Azure deployments ensuring infrastructure correctness, security compliance, performance equivalence, and cost alignment with projections.

## Responsibilities

1. **Pre-Deployment Validation** - Check readiness before deployment
2. **Post-Deployment Validation** - Verify deployment success
3. **Security Compliance** - Validate security requirements
4. **Performance Testing** - Compare against AWS baseline
5. **Cost Verification** - Validate actual vs. projected costs

## Pre-Deployment Validation Checklist

### 1. Template Validation

**Bicep Syntax Check:**
```bash
az bicep build --file main.bicep
# Expected: No errors, generates valid ARM template
```

**ARM Template Validation:**
```bash
az deployment group validate \
  --resource-group myResourceGroup \
  --template-file main.bicep \
  --parameters parameters/prod.bicepparam
# Expected: validationState: "Valid"
```

### 2. Policy Compliance Check

**Azure Policy Evaluation:**
```bash
az policy state summarize \
  --resource-group myResourceGroup
# Expected: No Deny results, all Audit passed
```

**Compliance Checks:**
- ✅ All resources have required tags
- ✅ No public IPs except load balancers
- ✅ Private endpoints configured for PaaS
- ✅ Encryption enabled for all data services
- ✅ Managed Identity used for authentication
- ✅ Network isolation enforced

### 3. Service Limit Check

**Verify Quotas:**
```bash
az provider show \
  --namespace Microsoft.Compute \
  --query "resourceTypes[?resourceType=='virtualMachines'].locations"
# Verify adequate quota for VM count

az provider show \
  --namespace Microsoft.Storage \
  --query "resourceTypes[?resourceType=='storageAccounts'].locations"
# Verify adequate quota for storage accounts
```

**Quota Requirements:**
- [ ] Sufficient compute cores for VM/AKS sizing
- [ ] Adequate storage account quota
- [ ] Database instance quota available
- [ ] Network interface quota sufficient
- [ ] Public IP quota available

### 4. Cost Estimation Check

**Azure Pricing Calculator Integration:**
```bash
# Run cost estimation before deployment
az deployment group what-if \
  --resource-group myResourceGroup \
  --template-file main.bicep \
  --parameters parameters/prod.bicepparam \
  | grep -E "Type:|Name:|Cost"
```

**Cost Verification:**
- [ ] Projected costs match estimates (within 10%)
- [ ] No unexpected paid resources
- [ ] Free tier resources not charged
- [ ] Reserved instances applied correctly

## Post-Deployment Validation Checklist

### 1. Resource Deployment Verification

**Check All Resources Deployed:**
```bash
#!/bin/bash
# Verify all resources exist with correct status

EXPECTED_RESOURCES=(
  "myFunctionApp" "Microsoft.Web/sites"
  "myDatabase" "Microsoft.DBforPostgreSQL/flexibleServers"
  "myStorageAccount" "Microsoft.Storage/storageAccounts"
)

for resource in "${EXPECTED_RESOURCES[@]}"; do
  STATUS=$(az resource show \
    --resource-group myRg \
    --name $resource \
    --query properties.provisioningState \
    -o tsv)
  
  if [ "$STATUS" != "Succeeded" ]; then
    echo "ERROR: $resource in state $STATUS"
    exit 1
  fi
done

echo "All resources deployed successfully"
```

**Deployment Status:**
- [ ] All resources: Succeeded
- [ ] No Failed or Deleting resources
- [ ] No Canceled deployments
- [ ] All properties match template

### 2. Connectivity Verification

**Network Connectivity Tests:**
```bash
#!/bin/bash
# Test connectivity between resources

# Test Function App to Database
DB_HOST=$(az resource show \
  --resource-group myRg \
  --name myDatabase \
  --query properties.fullyQualifiedDomainName \
  -o tsv)

# From inside VNet, test connection
az container create \
  --resource-group myRg \
  --name network-test \
  --image mcr.microsoft.com/azure-cli:latest \
  --restart-policy Never \
  --vnet myVNet \
  --subnet testSubnet \
  --command-line "nc -zv $DB_HOST 5432"

# Verify connection succeeded
STATUS=$(az container show \
  --resource-group myRg \
  --name network-test \
  --query instanceView.state \
  -o tsv)

if [ "$STATUS" = "Succeeded" ]; then
  echo "Database connectivity verified"
else
  echo "Database connectivity test failed"
  exit 1
fi
```

**Connectivity Checks:**
- [ ] Functions can connect to database
- [ ] Functions can access blob storage
- [ ] API Gateway routes to functions
- [ ] Private endpoints are accessible
- [ ] Public endpoints are blocked (where appropriate)

### 3. Managed Identity Verification

**Check Identity Permissions:**
```bash
#!/bin/bash
# Verify Managed Identity has correct permissions

FUNCTION_APP_ID=$(az resource show \
  --resource-group myRg \
  --name myFunctionApp \
  --query identity.principalId \
  -o tsv)

# Check role assignments
az role assignment list \
  --assignee $FUNCTION_APP_ID \
  --resource-group myRg

# Verify specific permissions
# Expected: Storage Blob Data Reader/Contributor role
# Expected: Database user permissions
# Expected: Key Vault Secrets User role
```

**Identity Requirements:**
- [ ] System-assigned identity exists
- [ ] Role assignments created for all services
- [ ] No access key credentials present
- [ ] Key Vault access policies configured

### 4. Key Vault Access Verification

**Test Secret Access:**
```bash
#!/bin/bash
# Verify Key Vault access from resources

# Get Key Vault reference
KV_URI=$(az resource show \
  --resource-group myRg \
  --name myKeyVault \
  --query properties.vaultUri \
  -o tsv)

# Try accessing secret (within Function App context)
az keyvault secret show \
  --vault-name myKeyVault \
  --name DbConnectionString \
  --query value

# Verify secret retrieved successfully
```

**Key Vault Checks:**
- [ ] All secrets present
- [ ] Function App can access secrets
- [ ] Database credentials in Key Vault
- [ ] No secrets in app settings
- [ ] Soft delete enabled

## Security Validation

### 1. Network Security

**Security Group Rules Validation:**
```bash
az network nsg rule list \
  --resource-group myRg \
  --nsg-name myNSG \
  --query "[?direction=='Inbound'].{priority:priority, access:access, protocol:protocol, destPort:destinationPortRange, sourcePrefix:sourceAddressPrefix}" \
  --output table
```

**Security Checks:**
- [ ] No allow-all inbound rules (0.0.0.0/0 on port 0-65535)
- [ ] SSH/RDP restricted to jump hosts only
- [ ] Outbound restricted to necessary services
- [ ] Private endpoints used for PaaS services
- [ ] DDoS protection enabled for public IPs

### 2. Encryption Validation

**Data at Rest:**
```bash
# Check storage encryption
az storage account show \
  --resource-group myRg \
  --name mystorageaccount \
  --query encryption

# Check database encryption
az postgres server show \
  --resource-group myRg \
  --name mydbserver \
  --query sslEnforcement
```

**Data in Transit:**
```bash
# Verify HTTPS enforcement
az webapp show \
  --resource-group myRg \
  --name myFunctionApp \
  --query httpsOnly

# Verify TLS version
az webapp config show \
  --resource-group myRg \
  --name myFunctionApp \
  --query minTlsVersion
```

**Encryption Requirements:**
- [ ] Storage: Encryption at rest enabled
- [ ] Database: Encryption at rest enabled
- [ ] HTTPS enforced on all web services
- [ ] TLS 1.2 minimum
- [ ] Customer-managed keys for sensitive data

### 3. Access Control (RBAC) Validation

**Role Assignment Review:**
```bash
# List all role assignments
az role assignment list \
  --resource-group myRg \
  --query "[].{roleDefinitionName:roleDefinitionName, principalName:principalName, principalType:principalType}" \
  --output table

# Verify least privilege principle
# Expected: specific role per service
# Expected: no Owner/Contributor for services
```

**RBAC Requirements:**
- [ ] No Owner roles on resources
- [ ] Service-specific roles assigned
- [ ] Managed Identity used, no service accounts
- [ ] Admin access restricted
- [ ] Guest accounts disabled

### 4. Compliance Scans

**Azure Security Center Assessment:**
```bash
az security assessment list \
  --resource-group myRg \
  --query "[].{displayName:displayName, status:status}" \
  --output table

# Expected: All assessments in "Healthy" state
```

**Compliance Standards:**
- [ ] CIS benchmark checks passed
- [ ] PCI-DSS requirements met (if applicable)
- [ ] HIPAA compliance verified (if applicable)
- [ ] SOC 2 controls evaluated
- [ ] Data residency requirements met

## Performance Validation

### 1. Baseline Performance Testing

**Function App Performance:**
```bash
#!/bin/bash
# Load test Azure Functions against baseline

# Run 1000 requests with 10 concurrent connections
ab -n 1000 -c 10 https://myfunction.azurewebsites.net/api/endpoint

# Expected results vs AWS Lambda:
# - Response time: ±10% of baseline
# - P99 latency: < baseline + 100ms
# - Error rate: < 1%
```

**Performance Metrics:**
- [ ] Average response time within ±10% of AWS
- [ ] P99 latency acceptable
- [ ] Error rate < 1%
- [ ] Throughput meets requirements
- [ ] CPU/Memory not at limits

### 2. Database Performance

**Query Performance Testing:**
```bash
#!/bin/bash
# Run representative queries against Azure Database

# Example: Complex JOIN query
time psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
  SELECT o.id, c.name, SUM(i.amount) as total
  FROM orders o
  JOIN customers c ON o.customer_id = c.id
  JOIN invoices i ON o.id = i.order_id
  GROUP BY o.id, c.name
  LIMIT 1000
"

# Expected: Query time within 10% of AWS baseline
```

**Database Checks:**
- [ ] Query response times acceptable
- [ ] Connection pool sizing appropriate
- [ ] Replication lag minimal (if multi-region)
- [ ] Backup/restore tested and working
- [ ] No slow queries detected

### 3. Cold Start Comparison

**Function Cold Start Testing:**
```bash
#!/bin/bash
# Measure cold start times

# Clear instance cache
az functionapp deployment slot auto-swap \
  --resource-group myRg \
  --name myFunctionApp \
  --slot staging

# Measure cold start latency
for i in {1..5}; do
  time curl -X POST \
    https://myfunction.azurewebsites.net/api/endpoint \
    -H "Content-Type: application/json" \
    -d '{}'
done

# Expected: Azure Functions Premium cold start < 1s
# Expected: Consumption cold start < 2s
# Expected: Similar to AWS Lambda cold starts
```

**Cold Start Benchmarks:**
- [ ] Premium plan: < 1 second
- [ ] Consumption plan: < 2 seconds
- [ ] Comparable to AWS Lambda baseline

## Cost Validation

### 1. Actual vs. Projected Cost Comparison

**Cost Analysis:**
```bash
#!/bin/bash
# Extract actual costs from Azure Cost Management

az costmanagement query \
  --timeframe ActualCost \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourcegroups/myRg \
  --dataset '[grouping={type=Dimension,name=ResourceType}]' \
  --type Usage

# Compare with projected costs
# Expected: Within 15% of estimate
# Variance analysis if > 15% difference
```

**Cost Validation:**
- [ ] Total monthly cost within 15% of projection
- [ ] Breakdown by service matches estimate
- [ ] No unexpected charges
- [ ] Reserved instances applied
- [ ] Free tier benefits realized

### 2. Cost Optimization Recommendations

**Identify Optimization Opportunities:**
```bash
# Check for unused resources
az resource list \
  --resource-group myRg \
  --query "[].{name:name, type:type}" \
  --output table

# Check for oversized resources
az functionapp plan show \
  --resource-group myRg \
  --name myFunctionPlan \
  --query sku

# Look for cost optimization recommendations
az advisor recommendation list \
  --resource-group myRg \
  --query "[?category=='Cost'].{title:shortDescription, potentialSavings:extendedProperties.savingsAmount}" \
  --output table
```

**Optimization Actions:**
- [ ] Review and rightsize instances
- [ ] Verify autoscaling is working
- [ ] Check for reserved instance opportunities
- [ ] Archive unused data to cool tier
- [ ] Remove unused resources

## Validation Report Generation

### Report Structure

```markdown
# Azure Deployment Validation Report

**Date:** 2024-12-10  
**Environment:** Production  
**Deployment:** bicep-deploy-1702234800  
**Status:** ✅ PASSED

## Executive Summary

All validation checks passed. Deployment is ready for production use.

- Total Checks: 47
- Passed: 47
- Failed: 0
- Warnings: 0

## Pre-Deployment Validation

### Template Validation
- [x] Bicep syntax valid
- [x] ARM template valid
- [x] No validation errors
- [x] Resource definitions complete

### Policy Compliance
- [x] Azure Policies compliant
- [x] Tags on all resources
- [x] Encryption enabled
- [x] Private endpoints configured

### Service Limits
- [x] Compute cores available
- [x] Storage quota sufficient
- [x] Database instances available
- [x] Network resources quota OK

### Cost Estimation
- [x] Estimated cost: $3,420/month
- [x] Within budget: ✅ Yes
- [x] Cost optimization opportunities identified

## Post-Deployment Validation

### Resource Verification
- [x] 47/47 resources deployed
- [x] All resources: Succeeded
- [x] No Failed deployments
- [x] All properties match template

### Connectivity Tests
- [x] Function App → Database: OK
- [x] Function App → Storage: OK
- [x] API Gateway → Functions: OK
- [x] Private endpoints accessible: OK

### Identity & Access
- [x] Managed Identity created
- [x] Role assignments correct
- [x] Key Vault access working
- [x] No hardcoded credentials found

## Security Validation

### Network Security
- [x] No public endpoints (except load balancer)
- [x] Security groups properly configured
- [x] Private endpoints for PaaS services
- [x] DDoS protection enabled

### Encryption
- [x] Data at rest: Encrypted
- [x] Data in transit: TLS 1.2+
- [x] Key Vault: Configured
- [x] Database SSL: Enforced

### Compliance
- [x] Azure Security Center: Healthy
- [x] CIS benchmark: Passed
- [x] PCI-DSS (if applicable): Passed
- [x] HIPAA (if applicable): Passed

## Performance Validation

### Baseline Testing
- [x] Response time: 145ms avg (AWS: 142ms)
- [x] P99 latency: 650ms (AWS: 630ms)
- [x] Error rate: 0.2% (AWS: 0.1%)
- [x] Throughput: 850 req/s (AWS: 820 req/s)

### Cold Starts
- [x] Premium plan cold start: 680ms
- [x] Comparable to AWS baseline: ✅ Yes
- [x] Within acceptable range: ✅ Yes

### Database Performance
- [x] Query response time: ±8% of baseline
- [x] Connection pool: Optimal
- [x] Replication lag: < 100ms (if multi-region)
- [x] No slow queries detected

## Cost Validation

### Actual vs. Projected
- [x] Projected: $3,420/month
- [x] Actual (30-day): $3,510/month
- [x] Variance: 2.6% (within 15% threshold)
- [x] Cost breakdown matches projection

### Monthly Cost Breakdown
| Service | Projected | Actual | Variance |
|---|---|---|---|
| Azure Functions | $180 | $190 | +5.6% |
| AKS | $360 | $358 | -0.6% |
| Database | $650 | $655 | +0.8% |
| Storage | $140 | $142 | +1.4% |
| Monitoring | $100 | $98 | -2.0% |
| Other | $990 | $1,067 | +7.7% |
| **TOTAL** | **$3,420** | **$3,510** | **+2.6%** |

### Cost Optimization Opportunities
- Reserve instances: Potential 30% savings
- Archive old data to cool tier: $50/month savings
- Rightsize AKS nodes: $80/month savings
- **Total possible savings: $130/month (3.7%)**

## Recommendations

### Immediate Actions
1. Apply reserved instances for baseline load
2. Archive data older than 90 days
3. Rightsize AKS nodes for current workload
4. Monitor performance metrics daily

### Follow-Up Activities
1. Schedule performance optimization review (2 weeks)
2. Evaluate autoscaling metrics (4 weeks)
3. Review cost optimization opportunities (monthly)
4. Conduct disaster recovery drill (quarterly)

### Known Issues
None - deployment fully validated

## Sign-Off

| Role | Name | Date | Status |
|---|---|---|---|
| Infrastructure Lead | [Name] | 2024-12-10 | ✅ Approved |
| Security Lead | [Name] | 2024-12-10 | ✅ Approved |
| Cost Optimization | [Name] | 2024-12-10 | ✅ Approved |

**Deployment Ready:** ✅ YES - Approved for production traffic

---

**Report Generated by:** Deployment Validation Agent  
**Validation Framework:** Azure Well-Architected  
**Next Review:** 2024-12-17
```

## Output Files

1. **Validation Report** - Complete validation results
2. **Compliance Scorecard** - Security compliance summary
3. **Performance Report** - Performance baseline comparison
4. **Cost Analysis** - Actual vs projected cost breakdown
5. **Recommendations** - Optimization and improvement suggestions
6. **Smoke Test Results** - Application functionality verification

## Quality Standards

✅ **Completeness:**
- All validation checks performed
- All results documented
- All recommendations provided
- Sign-off from reviewers

✅ **Accuracy:**
- Real data from Azure APIs
- Proper baseline comparisons
- Correct cost calculations
- Verified test results

✅ **Actionability:**
- Clear recommendations
- Specific next steps
- Prioritized issues
- Rollback procedures documented

## Example Invocation

```
@deployment-validation Validate the Azure deployment. Run all security compliance checks, compare performance to AWS baseline, verify costs match projection, and generate comprehensive validation report.
```

## Success Criteria

Validation is complete when:
1. ✅ All pre-deployment checks passed
2. ✅ All resources deployed successfully
3. ✅ Connectivity tests passed
4. ✅ Security compliance verified
5. ✅ Performance within ±10% of AWS
6. ✅ Actual costs within 15% of projection
7. ✅ All recommendations documented
8. ✅ Validation report signed off
9. ✅ Ready for production traffic
10. ✅ Monitoring and alerting configured
