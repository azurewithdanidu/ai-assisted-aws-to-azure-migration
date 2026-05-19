# Migration Task Plan
Generated: 2026-05-19T00:00:00Z
Last Updated: 2026-05-20T09:20:00Z

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
| 1 — Discovery | aws-discovery | ✅ | 2026-05-19T10:27:00Z |
| 2 — Architecture | azure-architect | ✅ | 2026-05-19T09:45:00Z |
| 3a — IaC Transformation | iac-transformation | ✅ | 2026-05-19T11:10:00Z |
| 3b — Code Refactor | code-refactor | ✅ | 2026-05-19T08:05:00Z |
| 3c — Pipeline Build | pipeline-builder-agent | ✅ | 2026-05-19T05:33:00Z |
| 4 — Validation | deployment-validation | ❌ | — |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover all AWS services and regions (AWS account: 535002891143) — completed 2026-05-19T10:15:00Z
- [x] Generate aws-inventory.json — completed 2026-05-19T10:20:00Z
- [x] Generate architecture-diagram.mmd — completed 2026-05-19T10:22:00Z
- [x] Generate dependency-matrix.csv — completed 2026-05-19T10:24:00Z
- [x] Generate migration-assessment.md — completed 2026-05-19T10:27:00Z

### Phase 2 — Azure Architecture Design
- [x] Map all AWS services to Azure equivalents — completed 2026-05-19T09:05:00Z
- [x] Generate design-document.md (all 11 sections) — completed 2026-05-19T09:20:00Z
- [x] Generate architecture-diagram-azure.mmd — completed 2026-05-19T09:30:00Z
- [x] Generate cost-comparison.md — completed 2026-05-19T09:35:00Z
- [x] Generate service-mapping.md — completed 2026-05-19T09:45:00Z

### Phase 3a — IaC Transformation
<!-- Populated from design-document.md Section 5 -->
- [x] Generate modules/storage.bicep — Storage Account + blob container + lifecycle policy — completed 2026-05-19T11:02:00Z
- [x] Generate modules/identity.bicep — User-assigned Managed Identity — completed 2026-05-19T11:03:00Z
- [x] Generate modules/functionApp.bicep — Function App (Consumption plan) + App Service Plan — completed 2026-05-19T11:04:00Z
- [x] Generate modules/monitoring.bicep — Application Insights + Log Analytics workspace — completed 2026-05-19T11:05:00Z
- [x] Generate modules/rbac.bicep — Role assignments (Storage Blob Data Contributor) for Managed Identity — completed 2026-05-19T11:06:00Z
- [x] Generate modules/staticWebApp.bicep — Azure Static Web App (Free tier) — completed 2026-05-19T11:07:00Z
- [x] Generate main.bicep — root template orchestrating all 6 modules — completed 2026-05-19T11:09:00Z
- [x] Generate parameters/dev.bicepparam — completed 2026-05-19T11:10:00Z
- [x] Generate parameters/staging.bicepparam — completed 2026-05-19T11:10:00Z
- [x] Generate parameters/prod.bicepparam — completed 2026-05-19T11:10:00Z

### Phase 3b — Code Refactor
<!-- Populated from design-document.md Section 6 -->
- [x] Refactor upload_image: HTTP trigger POST /api/upload-image, SDK: azure-storage-blob BlobServiceClient (boto3 pre-signed POST → generate_blob_sas) — completed 2026-05-19T08:04:00Z
- [x] Refactor list_images: HTTP trigger GET /api/list-images, SDK: BlobServiceClient.list_blobs (boto3 S3 list_objects_v2) — completed 2026-05-19T08:04:00Z
- [x] Refactor get_view_url: HTTP trigger GET /api/get-view-url, SDK: generate_blob_sas read-only SAS URL (boto3 generate_presigned_url) — completed 2026-05-19T08:04:00Z
- [x] Refactor delete_image: HTTP trigger DELETE /api/delete-image, SDK: BlobClient.delete_blob (boto3 S3 delete_object) — completed 2026-05-19T08:04:00Z
- [x] Create shared/blob_helpers.py — BlobServiceClient init, SAS generation helpers, CORS utils — completed 2026-05-19T08:02:00Z
- [x] Update requirements.txt (azure-functions, azure-storage-blob, azure-identity) — completed 2026-05-19T08:02:00Z
- [x] Update host.json with Azure Functions v2 config — completed 2026-05-19T08:02:00Z

### Phase 3c — Pipeline Build
<!-- Populated from design-document.md Section 11 -->
- [x] Create .github/workflows/deploy-infra.yml — Bicep deployment to dev/staging/prod via OIDC — completed 2026-05-19T05:31:00Z
- [x] Create .github/workflows/deploy-functions.yml — Azure Functions Python app deployment — completed 2026-05-19T05:32:00Z
- [x] Create .github/workflows/deploy-static-web.yml — Static Web App frontend deployment — completed 2026-05-19T05:33:00Z
- [x] Configure OIDC Workload Identity Federation (federated credentials, no long-lived secrets) — completed 2026-05-19T05:33:00Z
- [x] Configure GitHub Secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, RESOURCE_GROUP — completed 2026-05-19T05:33:00Z

### Phase 4 — Validation
- [x] Run pre-deployment checks — PASS 2026-05-20T09:08:00Z
- [x] Run post-deployment smoke tests — FAIL 2026-05-20T09:15:00Z (static analysis only — live deployment blocked by Function App name mismatch; 16 live checks PENDING)
- [x] Verify security compliance — PASS 2026-05-20T09:12:00Z
- [x] Produce validation-report.md — PASS 2026-05-20T09:20:00Z

## Blockers
- Phase 4 (deployment-validation): deploy-functions.yml and deploy-static-web.yml derive Function App name as `func-photo-gallery-<env>` but Bicep provisions `photo-gallery-func-<env>`. Automated push-triggered deployments will fail. Fix: change line 70 in deploy-functions.yml and corresponding line in deploy-static-web.yml to `photo-gallery-func-${ENV_NAME}`.

## Phase Metrics

| Phase | Agent | Duration | Tool Calls | Files Written |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | 27m 00s | ~40 | 4 |

_Token usage per phase is not exposed to the agent runtime. View per-request token counts in VS Code: Command Palette → "Chat: Show Usage", or check the session debug log under `~/.config/Code/User/workspaceStorage/<workspace-id>/GitHub.copilot-chat/debug-logs/`._
