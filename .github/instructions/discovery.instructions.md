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

> See the `aws-discovery` skill for the IAM Role Mapping JSON format and examples.

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


> Refer to the `aws-discovery` skill for complexity scoring guidelines (effort tables per service), resource documentation templates, the validation checklist, and common issue resolution patterns.