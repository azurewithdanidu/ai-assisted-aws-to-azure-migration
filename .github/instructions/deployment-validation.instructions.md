---
name: deployment-validation-instructions
description: Custom instructions for Deployment Validation Agent
applyTo: deployment-validation
---

# Deployment Validation Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All inputs come from `outputs/` and all reports go to `outputs/validation-report.md`.

## Validation Requirements by Phase

Golden rule: All critical checks must pass for successful validation. Optional checks should be reviewed and addressed as needed but do not block deployment if they fail.

Golden rule: - Use the detailed design document for reference and guidance in outoputs/azure-architecture-output/ and validate code and configuration against the design specifications.

### Pre-Deployment Phase (Before `az deployment group create`)

**Critical Checks (Must Pass):**
1. Bicep template syntax validation
2. ARM template validation
3. Resource quota checks
4. Azure Policy compliance
5. Cost estimation accuracy

**Optional Checks (Should Pass):**
1. Security best practices
2. Naming convention compliance
3. Tag consistency
4. Documentation completeness

### Post-Deployment Phase (After successful deployment)

**Critical Checks (Must Pass):**
1. All resources deployed (Succeeded state)
2. Managed Identity working
3. Key Vault accessibility
4. Database connectivity
5. Security groups correct

**Optional Checks (Should Pass):**
1. Performance within baseline
2. Monitoring configured
3. Alerting rules created
4. Documentation updated

## Security Validation Criteria

### Data Protection

**Encryption at Rest:**
```
✅ PASS: Storage encrypted with Microsoft-managed or customer-managed keys
⚠️ WARN: Storage encrypted with Microsoft-managed keys (consider CMK)
❌ FAIL: Storage without encryption
```

**Encryption in Transit:**
```
✅ PASS: HTTPS enforced, TLS 1.2+
⚠️ WARN: TLS 1.1 or 1.0 supported
❌ FAIL: HTTP allowed, TLS not enforced
```

### Network Isolation

**Private Endpoints:**
```
✅ PASS: All PaaS services behind private endpoints
⚠️ WARN: Some PaaS services public (justified in docs)
❌ FAIL: Critical services publicly accessible
```

**Security Groups/NSGs:**
```
✅ PASS: Least privilege rules, specific port ranges
⚠️ WARN: Rules allow necessary broad access
❌ FAIL: Allow-all rules (0.0.0.0/0 on all ports)
```

### Access Control

**Managed Identity:**
```
✅ PASS: All services use Managed Identity, no service accounts
⚠️ WARN: Mix of Managed Identity and service accounts
❌ FAIL: Service accounts or hardcoded credentials
```

**RBAC:**
```
✅ PASS: Least privilege roles assigned
⚠️ WARN: Some broad roles assigned (justified)
❌ FAIL: Owner role on resources, overprivileged access
```

## Performance Baseline Comparison

### Methodology

**1. Establish AWS Baseline:**
```
- Actual measurement during AWS operation
- Typical production workload
- Peak usage patterns
- Representative scenarios
```

**2. Azure Measurement:**
```
- Same test scenarios
- Same data payload sizes
- Same concurrency levels
- Same geographic location
```

**3. Calculate Variance:**
```
Variance = (Azure - AWS) / AWS × 100%

✅ PASS: Variance between -10% and +10%
⚠️ WARN: Variance between -15% and +15% (investigate cause)
❌ FAIL: Variance > ±15% (may indicate configuration issue)
```

### Performance Metrics

**Web API Response Time:**
```
✅ PASS: Azure avg ≤ AWS avg + 100ms
⚠️ WARN: Azure avg ≤ AWS avg + 200ms
❌ FAIL: Azure avg > AWS avg + 200ms
```

**Database Query Performance:**
```
✅ PASS: P99 latency within ±15% of AWS
⚠️ WARN: P99 latency within ±20% of AWS
❌ FAIL: P99 latency > ±20% of AWS
```

**Throughput (Requests/Sec):**
```
✅ PASS: Azure throughput ≥ 90% of AWS
⚠️ WARN: Azure throughput ≥ 80% of AWS
❌ FAIL: Azure throughput < 80% of AWS
```

## Compliance Standards

### Applicability Matrix

Use these standards based on industry/requirements:

| Standard | Applicability | Validation | Authority |
|---|---|---|---|
| CIS Azure Foundations | All organizations | Required | Center for Internet Security |
| PCI-DSS | Payment processing | Required if applicable | PCI Security Council |
| HIPAA | Healthcare data | Required if applicable | HHS |
| SOC 2 | Regulated industries | Recommended | AICPA |
| GDPR | EU customer data | Required if applicable | EU regulators |
| NIST Cybersecurity | US government | Required if applicable | NIST |

### CIS Azure Foundations Checks

**Identity and Access Management:**
- [ ] MFA enabled for privileged accounts
- [ ] Legacy authentication disabled
- [ ] Service principals have expiration dates
- [ ] Unused service principals removed
- [ ] Managed Identity used for resource auth

**Networking:**
- [ ] Network traffic filtered
- [ ] Public endpoints disabled where possible
- [ ] Private endpoints used for services
- [ ] Subnets segmented by function
- [ ] Network flow logs enabled

**Data Protection:**
- [ ] Storage encryption enabled
- [ ] Database encryption enabled
- [ ] Backup and recovery tested
- [ ] Customer-managed keys considered
- [ ] Disk encryption enabled for VMs

**Logging & Monitoring:**
- [ ] Activity Log retention: 90+ days
- [ ] Diagnostic logs enabled
- [ ] Alerts configured for anomalies
- [ ] Log analytics configured
- [ ] Audit logs protected from modification

### PCI-DSS Requirements (if applicable)

**Network Segmentation:**
```
✅ PASS: Cardholder environment isolated via VNet/NSG
⚠️ WARN: Partial isolation (document exceptions)
❌ FAIL: No network isolation
```

**Data Protection:**
```
✅ PASS: Cardholder data encrypted at rest and in transit
⚠️ WARN: Encrypted with Microsoft-managed keys
❌ FAIL: Unencrypted cardholder data
```

**Access Control:**
```
✅ PASS: Unique IDs, strong authentication, MFA for admin
⚠️ WARN: Shared accounts or weak authentication
❌ FAIL: No access logging or controls
```

## Cost Accuracy Verification

### Cost Estimation Model

**Factors Included:**
1. Compute (Functions, VMs, AKS)
2. Storage (Blob, File, Database)
3. Networking (Data transfer, Private endpoints)
4. Services (API Management, Event Grid)
5. Monitoring (Log Analytics, Application Insights)

**Factors Excluded (Usually Free or Low Cost):**
- Virtual Networks (free)
- Security Groups (free)
- Key Vault (small monthly charge)
- Azure AD (free tier)

### Cost Variance Analysis

**Acceptable Variance:**
```
Within 15% = ✅ PASS (likely pricing changes or rounding)
15-25% = ⚠️ WARN (investigate specific services)
> 25% = ❌ FAIL (configuration error likely)
```

**Investigation Steps:**
1. Compare actual usage to projected usage
2. Check for unexpected paid services
3. Verify SKU sizes match projection
4. Check for data transfer charges
5. Review reserved instance application

### Cost Breakdown Verification

| Service | Projected | Actual | Variance | Status |
|---|---|---|---|---|
| Compute | $600 | $615 | +2.5% | ✅ |
| Database | $500 | $520 | +4.0% | ✅ |
| Storage | $200 | $215 | +7.5% | ✅ |
| Network | $120 | $135 | +12.5% | ✅ |
| **Total** | **$1,420** | **$1,485** | **+4.6%** | ✅ |

## Reporting Standards

### Report Sections

**1. Executive Summary (1 page)**
- Deployment status: PASS/FAIL
- Key metrics summary
- Critical issues identified
- Recommendations summary

**2. Validation Results (detailed)**
- Each validation check
- Pass/Fail/Warning status
- Evidence/screenshot
- Remediation if failed

**3. Security Assessment (1-2 pages)**
- Security scorecard
- Compliance status
- Recommendations

**4. Performance Report (1-2 pages)**
- Baseline comparison
- Benchmarks
- Recommendations

**5. Cost Analysis (1 page)**
- Actual vs projected
- Breakdown by service
- Optimization opportunities

**6. Recommendations (1-2 pages)**
- Immediate actions (do first)
- Short-term improvements (1-2 weeks)
- Long-term optimizations (1-3 months)
- Monitoring strategy

### Evidence Requirements

**For Each Failed Check:**
- [ ] Clear description of failure
- [ ] Root cause analysis
- [ ] Specific remediation step
- [ ] Estimated time to fix
- [ ] Verification method

**For Each Warning:**
- [ ] Clear description of finding
- [ ] Risk assessment
- [ ] Recommended action
- [ ] Timeline for resolution

**For Each Success:**
- [ ] Brief confirmation
- [ ] Screenshots or logs (if helpful)
- [ ] No action required

## Monitoring & Alerting Setup

### Post-Deployment Monitoring

**Application Performance:**
```
- Response Time: Alert if p99 > baseline + 100ms
- Error Rate: Alert if > 1%
- Throughput: Alert if < expected ± 20%
```

**Infrastructure Health:**
```
- CPU: Alert if > 80% sustained
- Memory: Alert if > 85% sustained
- Disk: Alert if > 90% utilized
- Network: Alert if > 80% bandwidth
```

**Security Events:**
```
- Failed authentication: Alert on spike
- Unauthorized access attempts: Alert immediately
- Policy violations: Alert immediately
- Encryption failures: Alert immediately
```

### Alert Configuration Example

```bicep
// Create Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2021-09-01' = {
  name: 'alertActionGroup'
  location: 'global'
  properties: {
    groupShortName: 'alerts'
    enabled: true
    emailReceivers: [
      {
        name: 'engineeringTeam'
        emailAddress: 'engineering@company.com'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Create metric alert
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'functionResponseTimeAlert'
  location: 'global'
  properties: {
    description: 'Alert when response time exceeds baseline'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Response Time'
          metricName: 'FunctionExecutionTimeAvg'
          operator: 'GreaterThan'
          threshold: 200
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
```

## Tips & Best Practices

✅ **Do:**
- Validate before deployment
- Test against real workload
- Document all assumptions
- Track baseline metrics
- Review recommendations
- Monitor continuously
- Adjust alerts based on history
- Schedule regular reviews

❌ **Don't:**
- Skip validation steps
- Use synthetic test data
- Assume Azure = AWS performance
- Ignore variance > 15%
- Deploy without monitoring
- Set static thresholds
- Skip security validation
- Forget cost tracking

## Troubleshooting Validation Issues

### Issue: Validation Script Fails Due to Permissions

**Cause:** Service principal missing permissions

**Resolution:**
```bash
# Verify role assignments
az role assignment list \
  --assignee $AZURE_CLIENT_ID \
  --resource-group $AZURE_RESOURCE_GROUP

# Add required role if missing
az role assignment create \
  --assignee $AZURE_CLIENT_ID \
  --role "Contributor" \
  --resource-group $AZURE_RESOURCE_GROUP
```

### Issue: Performance Tests Show High Latency

**Cause:** Multiple possible causes

**Investigation Steps:**
1. Check if Azure resource is under load
2. Verify network latency to Azure
3. Check database query performance
4. Verify no throttling occurring
5. Compare resource sizing to AWS

### Issue: Cost Actual > Projected by > 25%

**Cause:** Unexpected charges

**Investigation Steps:**
1. Check for unused resources
2. Verify autoscaling not over-provisioning
3. Check data transfer charges
4. Review premium features enabled
5. Compare pricing regions

---

**Last Updated:** December 2024  
**Version:** 1.0
