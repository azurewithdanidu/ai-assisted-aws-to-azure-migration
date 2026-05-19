# Migration Task Plan
Generated: 2026-05-18T00:00:00Z
Last Updated: 2026-05-18T05:15:00Z
Target AWS Account: 535002891143

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
| 1 — Discovery | aws-discovery | ✅ | 2026-05-18T01:45:00Z |
| 2 — Architecture | azure-architect | ✅ | 2026-05-18T02:30:00Z |
| 3a — IaC Transformation | iac-transformation | ✅ | 2026-05-18T03:05:00Z |
| 3b — Code Refactor | code-refactor | ✅ | 2026-05-18T03:35:00Z |
| 3c — Pipeline Build | pipeline-builder-agent | ✅ | 2026-05-18T04:10:00Z |
| 4 — Validation | deployment-validation | ✅ | 2026-05-18T05:15:00Z |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover all AWS services and regions in account 535002891143 — completed 2026-05-18T01:30:00Z
- [x] Generate aws-inventory.json — completed 2026-05-18T01:40:00Z
- [x] Generate architecture-diagram.mmd — completed 2026-05-18T01:42:00Z
- [x] Generate dependency-matrix.csv — completed 2026-05-18T01:43:00Z
- [x] Generate migration-assessment.md — completed 2026-05-18T01:45:00Z

### Phase 2 — Azure Architecture Design
- [x] Map all AWS services to Azure equivalents — completed 2026-05-18T02:15:00Z
- [x] Generate design-document.md (all 11 sections) — completed 2026-05-18T02:28:00Z
- [x] Generate architecture-diagram-azure.mmd — completed 2026-05-18T02:20:00Z
- [x] Generate cost-comparison.md — completed 2026-05-18T02:25:00Z
- [x] Generate service-mapping.md — completed 2026-05-18T02:18:00Z

### Phase 3a — IaC Transformation
- [x] Generate main.bicep (subscription scope) — orchestrates RG + all modules — completed 2026-05-18T03:05:00Z
- [x] Generate modules/monitoring.bicep — Log Analytics + Application Insights — completed 2026-05-18T03:05:00Z
- [x] Generate modules/identity.bicep — User-assigned managed identity — completed 2026-05-18T03:05:00Z
- [x] Generate modules/keyvault.bicep — Key Vault (Standard) for host key + SWA token — completed 2026-05-18T03:05:00Z
- [x] Generate modules/storage.bicep — Blob Storage (images container, versioning, lifecycle) — completed 2026-05-18T03:05:00Z
- [x] Generate modules/rbac.bicep — Role assignments (Storage Blob Data Contributor, Delegator, KV Secrets User) — completed 2026-05-18T03:05:00Z
- [x] Generate modules/functionApp.bicep — Function App Consumption Y1, Python 3.11 — completed 2026-05-18T03:05:00Z
- [x] Generate modules/staticWebApp.bicep — Static Web App Free SKU — completed 2026-05-18T03:05:00Z
- [x] Generate parameters/dev.bicepparam — completed 2026-05-18T03:05:00Z
- [x] Generate parameters/staging.bicepparam — completed 2026-05-18T03:05:00Z
- [x] Generate parameters/prod.bicepparam — completed 2026-05-18T03:05:00Z
- [x] Generate bicepconfig.json — completed 2026-05-18T03:05:00Z

### Phase 3b — Code Refactor
- [x] Refactor UploadFunction → `upload` HTTP trigger (boto3 → azure-storage-blob, managed identity) — completed 2026-05-18T03:35:00Z
- [x] Refactor ListFilesFunction → `list_files` HTTP trigger — completed 2026-05-18T03:35:00Z
- [x] Refactor GetViewUrlFunction → `get_view_url` HTTP trigger (S3 presigned → SAS user-delegation) — completed 2026-05-18T03:35:00Z
- [x] Refactor DeleteFileFunction → `delete_file` HTTP trigger — completed 2026-05-18T03:35:00Z
- [x] Create shared/blob_helpers.py module — completed 2026-05-18T03:35:00Z
- [x] Generate requirements.txt (azure-functions, azure-storage-blob, azure-identity) — completed 2026-05-18T03:35:00Z
- [x] Generate host.json — completed 2026-05-18T03:35:00Z
- [x] Generate local.settings.json template — completed 2026-05-18T03:35:00Z

### Phase 3c — Pipeline Build
- [x] Create .github/workflows/deploy-infra.yml — Bicep subscription-scope deployment — completed 2026-05-18T04:00:00Z
- [x] Create .github/workflows/deploy-functions.yml — Function App build & publish — completed 2026-05-18T04:05:00Z
- [x] Create .github/workflows/deploy-static-web.yml — SPA build & SWA deploy — completed 2026-05-18T04:10:00Z
- [x] Configure OIDC / Workload Identity Federation auth (azure/login@v2) — completed 2026-05-18T04:10:00Z
- [x] Document required environment secrets (AZURE_CLIENT_ID, TENANT_ID, SUBSCRIPTION_ID, RG, KV, FUNC, SWA names) — completed 2026-05-18T04:10:00Z
- [x] Configure multi-env protection (dev/staging/prod with approval gates) — completed 2026-05-18T04:10:00Z

### Phase 4 — Validation
- [x] Run pre-deployment checks — PASS 2026-05-18T05:10:00Z (Bicep structural review, YAML lint, secret scan, RBAC review, route cross-check)
- [ ] Run post-deployment smoke tests — deferred until first `dev` deploy (no live Azure context)
- [x] Verify security compliance — PASS 2026-05-18T05:12:00Z (MI only, OIDC pipelines, KV-based secrets, least-privilege RBAC)
- [x] Produce validation-report.md — PASS 2026-05-18T05:15:00Z (outputs/validation-report.md, Status: PASSED)

## Blockers
None
