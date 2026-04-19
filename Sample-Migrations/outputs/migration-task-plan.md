# Migration Task Plan
Generated: 2026-04-18T00:00:00Z
Last Updated: 2026-04-18T00:25:00Z

## AWS Account
Account ID: `535002891143`

## Status Legend
| Symbol | Meaning |
|---|---|
| ⏳ | Not started |
| 🔄 | In progress |
| ✅ | Complete |
| ❌ | Failed / Blocked |

## Phase Summary

| Phase | Agent | Status | Completed At |
|---|---|---|---|
| 1 — Discovery | aws-discovery | ✅ | 2026-04-18T00:05:00Z |
| 2 — Architecture | azure-architect | ✅ | 2026-04-18T00:10:00Z |
| 3a — IaC Transformation | iac-transformation | ✅ | 2026-04-18T00:15:00Z |
| 3b — Code Refactor | code-refactor | ✅ | 2026-04-18T00:20:00Z |
| 3c — Pipeline Build | pipeline-builder-agent | ✅ | 2026-04-18T00:20:00Z |
| 4 — Validation | deployment-validation | ✅ | 2026-04-18T00:25:00Z |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover all AWS services and regions
- [x] Generate aws-inventory.json
- [x] Generate architecture-diagram.mmd
- [x] Generate dependency-matrix.csv
- [x] Generate migration-assessment.md

### Phase 2 — Azure Architecture Design
- [x] Map all AWS services to Azure equivalents
- [x] Generate design-document.md (all 11 sections)
- [x] Generate architecture-diagram-azure.mmd
- [x] Generate cost-comparison.md
- [x] Generate service-mapping.md

### Phase 3a — IaC Transformation
- [x] Generate bicep-templates/main.bicep — subscription-scoped orchestration, deploys all modules in order
- [x] Generate modules/monitoring.bicep — Log Analytics Workspace + Application Insights
- [x] Generate modules/storage.bicep — Blob Storage account + images container (replaces S3)
- [x] Generate modules/staticweb.bicep — Azure Static Web Apps (replaces S3 website bucket)
- [x] Generate modules/keyvault.bicep — Key Vault + managed identity secret access
- [x] Generate modules/functions.bicep — Consumption plan + Function App (python 3.11, system identity, CORS via siteConfig)
- [x] ~~Generate modules/apim.bicep~~ — **REMOVED: no APIM; Function App HTTP triggers exposed directly**
- [x] Generate modules/rbac.bicep — Storage Blob Data Contributor for Function App managed identity
- [x] Generate parameters/dev.bicepparam
- [x] Generate parameters/staging.bicepparam
- [x] Generate parameters/prod.bicepparam

### Phase 3b — Code Refactor
- [x] Refactor upload_handler: HTTP POST /api/upload, boto3 presigned POST → azure-storage-blob SAS PUT URL (UserDelegationKey), env: BLOB_CONTAINER_NAME
- [x] Refactor list_handler: HTTP GET /api/files, s3.list_objects_v2 → container_client.list_blobs, env: BLOB_CONTAINER_NAME
- [x] Refactor view_handler: HTTP GET /api/files/{fileId}/view-url, s3 presigned GET → generate_blob_sas(read), env: BLOB_CONTAINER_NAME
- [x] Refactor delete_handler: HTTP DELETE /api/files/{fileId}, s3.delete_object → blob_client.delete_blob, env: BLOB_CONTAINER_NAME
- [x] Update requirements.txt: azure-functions, azure-storage-blob>=12.19.0, azure-identity>=1.15.0
- [x] Update host.json: v2, Application Insights sampling, extension bundle [4.*, 5.0.0)

### Phase 3c — Pipeline Build
- [x] Create .github/workflows/deploy-infra.yml — Bicep IaC deploy (push to main + workflow_dispatch), subscription scope
- [x] Create .github/workflows/deploy-functions.yml — Python 3.11 build + Azure Functions zip deploy + smoke test
- [x] Create .github/workflows/deploy-static-web.yml — Static Web App asset deploy via Static Web Apps Deploy action
- [x] Configure OIDC: Azure AD App Registration with federated credential for main branch
- [x] Document 6 required GitHub Secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, AZURE_FUNCTION_APP_NAME, STATIC_WEB_APP_TOKEN
- [x] Configure multi-environment approval gates: dev (auto), staging (1 reviewer), prod (2 reviewers)

### Phase 4 — Validation
- [x] Run pre-deployment checks (15/15 PASSED)
- [x] Run post-deployment smoke tests (static analysis against artifacts)
- [x] Verify security compliance (no hardcoded creds, OIDC auth, HTTPS only, no public blob access)
- [x] Produce validation-report.md — **Status: PASSED** (3 non-blocking warnings)

### Warnings (non-blocking)
- W-1: `outputs/bicep-templates/modules/apim.bicep` is orphaned — not referenced from main.bicep, safe to delete
- W-2: `listKeys()` in functions.bicep for AzureWebJobsStorage is required Consumption plan pattern, not a security issue
- W-3: architecture-diagram-azure.mmd has stale APIM nodes — documentation drift only
