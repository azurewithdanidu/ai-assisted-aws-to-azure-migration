---
name: aws-inventory-scan
description: Read the source AWS application and produce a structured JSON inventory of every AWS service in use, plus a Mermaid architecture diagram and dependency matrix
---

# AWS Inventory Scan Skill

## Purpose

Produce a complete, structured inventory of all AWS services used by the source application so downstream agents have accurate inputs for architecture design and code refactoring.

## When to Use

As the first action in Phase 1, before any other discovery work.

## Process

1. Read `source-app/app-code/template.yaml` (SAM/CloudFormation) — this is the primary source of truth for deployed resources.
2. Read all Lambda function source files under `source-app/app-code/lambda/` — note any AWS SDK calls that reveal implicit service dependencies not in the template.
3. Read `source-app/doc/` for architecture documentation and supplementary context.
4. For each resource in the template, extract: resource type, logical ID, key properties (runtime, memory, timeout, SKU, region), environment variables referenced, and connections to other resources.
5. Write `outputs/aws-migration-artifacts/aws-inventory.json`:

```json
{
  "scanned_at": "2026-01-01T00:00:00Z",
  "region": "us-east-1",
  "account_id": "123456789012",
  "services": [
    {
      "type": "AWS::Lambda::Function",
      "logical_id": "UploadFunction",
      "runtime": "python3.11",
      "memory_mb": 512,
      "timeout_s": 30,
      "handler": "app.handler",
      "source_path": "source-app/app-code/lambda/upload/",
      "environment_variables": ["BUCKET_NAME", "TABLE_NAME"],
      "triggers": ["API Gateway POST /upload"],
      "dependencies": ["S3BucketUploads", "DynamoDBTable"]
    }
  ],
  "implicit_dependencies": [
    {
      "service": "AWS::SecretsManager::Secret",
      "note": "Referenced in lambda/upload/app.py via boto3 secretsmanager client — not in template"
    }
  ]
}
```

6. Write `outputs/aws-migration-artifacts/architecture-diagram.mmd` — Mermaid diagram using `graph TD` with subgraphs for network zones.
7. Write `outputs/aws-migration-artifacts/dependency-matrix.csv`:

```csv
source,target,relationship,protocol
UploadFunction,S3BucketUploads,writes,HTTPS
UploadFunction,DynamoDBTable,reads/writes,HTTPS
APIGateway,UploadFunction,invokes,HTTPS
```

## Rules

- **Never modify anything in `source-app/`** — read only.
- **Never skip implicit dependencies** — scan Lambda source code for boto3 client calls that reveal services not declared in the template.
- **Never omit the `implicit_dependencies` array** — even if empty, include it as `[]`.
- **Always include `source_path`** for every Lambda function so code-refactor can locate the source.
- **Never invent resource counts** — only report what is actually in the template or code.

## Output

- `outputs/aws-migration-artifacts/aws-inventory.json` — non-empty, valid JSON
- `outputs/aws-migration-artifacts/architecture-diagram.mmd` — valid Mermaid syntax
- `outputs/aws-migration-artifacts/dependency-matrix.csv` — at least a header row plus one data row
