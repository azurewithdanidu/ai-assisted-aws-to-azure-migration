---
name: discovery-instructions
description: Custom instructions for AWS Discovery Agent
applyTo: aws-discovery
---

# AWS Discovery Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All output must go to `outputs/aws-migration-artifacts/`.

IMPORTANT: This agent is focused on discovery and analysis only. It does not perform any migration actions. The output is intended for human architects and engineers to review and use for planning the migration to Azure. DO NOT MAKE ANY CHANGE TO THE AWS ENVIRONMENT. THIS IS A READ-ONLY DISCOVERY AGENT.

## Naming Conventions

### Resource Naming
- **Use original AWS names** - Do not rename resources during discovery
- **Preserve tags** - Capture all tags without modification
- **Full ARNs** - Always use complete Amazon Resource Names
- **Region specification** - Always note region for each resource

### Output File Names
- `aws-inventory.json` - Complete resource inventory
- `architecture-diagram.mmd` - Mermaid architecture diagram
- `dependency-matrix.csv` - Dependency mapping
- `migration-assessment.md` - Complexity and effort assessment

### JSON Key Names
- Use snake_case for all JSON keys: `resource_arn`, `instance_class`, `allocated_storage_gb`
- Use lowercase for service names: `lambda`, `rds`, `s3`, `eventbridge`
- Use consistent boolean naming: `multi_az`, `encryption_enabled`, `versioning_enabled`

## Security & IAM Documentation

### IAM Role Mapping

For every Lambda function, ECS task, or EC2 instance, document:
```json
{
  "resource_name": "order-processor",
  "iam_role": "arn:aws:iam::123456789012:role/order-processor-lambda-role",
  "permissions": {
    "s3": ["GetObject", "PutObject"],
    "rds": ["Connect"],
    "dynamodb": ["GetItem", "PutItem", "Query"]
  },
  "external_account_permissions": [],
  "cross_service_permissions": ["sns:Publish"]
}
```

### Secrets & Credentials
- **DO NOT** capture actual secret values
- Capture that Secrets Manager is used
- Document secret name and resource accessing it
- List secret rotation policy if configured
- Note if secrets are encrypted with KMS key

### VPC & Network Security
- Document security group rules (inbound/outbound)
- Capture VPC endpoints (private access)
- Note allowed IP ranges
- Document IAM service restrictions (S3, DynamoDB)

### Compliance & Tags

Document these required tags:
- `Environment` - development, staging, production
- `Application` - service/component name
- `Owner` - team or person responsible
- `CostCenter` - for cost allocation
- `Compliance` - any compliance requirements (PCI, HIPAA, SOC2)
- `DataClassification` - public, internal, confidential, restricted

## Complexity Assessment Guidelines

### Effort Scoring

**Lambda Functions:**
- Basic (reads S3 only): 2 days
- Standard (reads S3, writes DynamoDB): 3-4 days
- Complex (multiple services, VPC): 5-7 days
- Very Complex (EKS integration, custom libraries): 8-10 days

**RDS Databases:**
- Small (< 10 GB): 2-3 days
- Medium (10-100 GB): 4-7 days
- Large (> 100 GB): 8-14 days
- Add 2-3 days for Multi-AZ or read replicas
- Add 1-2 days per custom parameter group

**EKS/ECS:**
- Small cluster (1-3 nodes, 1-3 pods): 5-7 days
- Medium cluster (4-10 nodes, 4-10 pods): 10-15 days
- Large cluster (10+ nodes, 10+ pods): 15-20 days

**S3 Buckets:**
- Simple bucket: 1-2 days
- With versioning and replication: 3-5 days
- With lifecycle policies: 4-6 days
- With public access: 2-3 days

**EventBridge/SQS/SNS:**
- 1-2 rules/queues/topics: 1-2 days
- 3-5 rules/queues/topics: 2-4 days
- 6-10 rules/queues/topics: 4-6 days
- Complex routing (10+ rules): 6-8 days

### Complexity Rating

```
LOW (1-2 weeks):
- Simple CRUD operations
- Single Lambda function
- Standard RDS database
- No complex integrations
- <5 dependencies per resource

MEDIUM (3-5 weeks):
- Multiple Lambda functions
- Custom business logic
- Medium database size
- 5-15 dependencies
- EventBridge integration

HIGH (6-10 weeks):
- EKS/ECS clusters
- Complex event-driven architecture
- Large databases with replication
- 15+ dependencies per resource
- Custom networking (VPC, Direct Connect)
- Multiple regions or accounts

CRITICAL (10+ weeks):
- Multi-region deployments
- Cross-account access
- Custom CloudFormation resources
- Legacy application modernization required
```

## Documentation Standards

### Resource Documentation Template

For each resource discovered, provide:

```markdown
## [Service Type] - [Resource Name]

**Type:** [AWS service]  
**ARN:** [full ARN]  
**Region:** [region]  
**Criticality:** CRITICAL | HIGH | MEDIUM | LOW  

### Configuration
- Key setting 1: value
- Key setting 2: value

### Dependencies
**Uses:**
- [dependent resource] (reason)

**Used By:**
- [dependent resource] (reason)

### Security
- IAM Role: [role name]
- VPC: [VPC ID]
- Security Groups: [sg-id]
- Encryption: [Yes/No] with [KMS key]

### Costs
- Monthly Estimate: $XX.XX
- Usage-based: [metric]

### Migration Notes
- [Special considerations for migration]
```

### Dependency Documentation

For each dependency, document:
```
Source → Relationship → Target

Example:
order-processor-lambda --[reads/writes]→ s3-invoices-bucket --[Criticality: HIGH]-- [Issue: permission mapping]
```

**Relationship Types:**
- `reads` - Source reads from target
- `writes` - Source writes to target
- `queries` - Source queries target (database)
- `calls` - Source calls target (function/API)
- `authenticates` - Source authenticates via target
- `encrypts` - Source encrypted by target (KMS)
- `depends-on` - Generic dependency
- `network` - Network-level dependency (VPC, subnet)

## Validation Checklist

Before marking discovery complete, verify:

### Completeness
- [ ] All AWS regions scanned
- [ ] All 20+ AWS services checked
- [ ] No resources left in "Unknown" category
- [ ] All tags documented
- [ ] All configurations captured

### Accuracy
- [ ] All ARNs valid and current
- [ ] All regions correct
- [ ] All counts verified
- [ ] No duplicate resources
- [ ] All relationships bidirectional

### Dependencies
- [ ] All forward dependencies documented
- [ ] All reverse dependencies documented
- [ ] Circular dependencies identified
- [ ] Critical path identified
- [ ] No orphaned resources

### Output Quality
- [ ] JSON valid and well-formatted
- [ ] Mermaid diagram renders correctly
- [ ] CSV properly escaped and formatted
- [ ] Markdown renders correctly
- [ ] All required fields present

### Assessment Quality
- [ ] Complexity scores justified
- [ ] Effort estimates realistic
- [ ] Risk assessment complete
- [ ] Migration phases logical
- [ ] Next steps clear

## Common Issues & Resolution

### Missing Resources
**Issue:** Some resources not appearing in inventory

**Resolution:**
1. Check IAM permissions on discovery credentials
2. Verify all regions are scanned
3. Check for resources in unexpected regions
4. Look for resources created outside of standard naming patterns
5. Check for resources in different AWS accounts

### Inaccurate Costs
**Issue:** Cost estimates seem too high/low

**Resolution:**
1. Verify pricing model (on-demand, reserved, spot)
2. Check data transfer costs
3. Include backup storage costs
4. Account for RI discounts if in use
5. Include monitoring and logging costs

### Unclear Dependencies
**Issue:** Dependencies seem incomplete or incorrect

**Resolution:**
1. Check IAM policies for implicit dependencies
2. Review security group rules
3. Check for network dependencies (VPC, subnet)
4. Look for event-based dependencies
5. Verify CloudFormation templates

## Processing Errors

### Error: "Unable to list resources in region X"
- Check AWS credentials and permissions
- Verify service is available in that region
- Check if service requires specific IAM permission

### Error: "Dependency not found"
- Resource may have been deleted
- Resource may be in different account
- Check cross-account permissions

### Error: "Configuration incomplete"
- Some properties may be in separate API calls
- May require additional IAM permissions
- Some properties may not be exposed in Cloud Control API

## Output Verification

### JSON Validation
```bash
# Verify JSON is valid
jq '.' migration-artifacts/aws-inventory.json > /dev/null && echo "Valid JSON"

# Check for required fields
jq '.summary' migration-artifacts/aws-inventory.json
jq '.services | keys' migration-artifacts/aws-inventory.json
```

### Mermaid Verification
- Diagram renders without errors in VS Code
- All resources visible
- Dependencies clearly shown
- Layout is readable

### CSV Verification
- Headers present and correct
- All fields populated
- Proper escaping of special characters
- No extra blank rows

### Markdown Verification
- All headers properly formatted
- Tables render correctly
- Code blocks properly formatted
- Links work correctly

## Tips & Best Practices

✅ **Do:**
- Use AWS CLI or SDKs for accurate data
- Capture full configurations
- Document assumptions made
- Include examples in assessment
- Validate costs with AWS Calculator
- Ask clarifying questions about criticality

❌ **Don't:**
- Skip any service without checking
- Assume resource configuration
- Capture sensitive data (credentials, keys)
- Round estimates without noting it
- Miss tags or metadata
- Forget to validate with human architect

## Customization for Organization

### Add Organization-Specific Rules

Enhance the discovery by adding:

1. **Mandatory Tags Check**
   - Verify all resources have required tags
   - Flag resources missing tags
   - Report on tag compliance

2. **Compliance Requirements**
   - Document PCI-DSS requirements
   - Check HIPAA compliance
   - Verify SOC2 controls

3. **Cost Center Tracking**
   - Group resources by cost center
   - Calculate costs per team
   - Identify unused resources

4. **Performance Baselines**
   - Capture current performance metrics
   - Document latency SLAs
   - Note throughput requirements

---

**Last Updated:** December 2024  
**Version:** 1.0
