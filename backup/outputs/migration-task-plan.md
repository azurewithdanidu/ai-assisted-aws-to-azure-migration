# Migration Task Plan
Generated: 2026-06-24T13:05:22Z
Last Updated: 2026-06-24T15:49:52Z

## Migration Scope

| Field | Value |
|---|---|
| AWS Account ID | 535002891143 |
| AWS Region | ap-southeast-2 |

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
| 1 — Discovery | aws-discovery | ✅ | 2026-06-24T13:15:00Z |
| 2 — Architecture | azure-architect | ✅ | 2026-06-24T13:40:00Z |
| 3a — IaC Transformation | iac-transformation | ✅ | 2026-06-25T00:31:40Z |
| 3b — Code Refactor | code-refactor | ✅ | 2026-06-24T13:46:00Z |
| 3c — Pipeline Build | pipeline-builder-agent | ✅ | 2026-06-24T13:38:00Z |
| 3d — Deployment | azure-deployer | ✅ | 2026-06-24T15:35:45Z |
| 4 — Validation | deployment-validation | ❌ | 2026-06-24T15:49:52Z |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover all AWS services and regions — completed 2026-06-24T13:10:00Z
- [x] Generate aws-inventory.json — completed 2026-06-24T13:12:00Z
- [x] Generate architecture-diagram.mmd — completed 2026-06-24T13:12:30Z
- [x] Generate dependency-matrix.csv — completed 2026-06-24T13:13:00Z
- [x] Generate migration-assessment.md — completed 2026-06-24T13:14:00Z

### Phase 2 — Azure Architecture Design
- [x] Map all AWS services to Azure equivalents — completed 2026-06-24T13:40:00Z
- [x] Generate design-document.md (all 11 sections) — completed 2026-06-24T13:40:00Z
- [x] Generate architecture-diagram-azure.mmd — completed 2026-06-24T13:40:00Z
- [x] Generate cost-comparison.md — completed 2026-06-24T13:40:00Z
- [x] Generate service-mapping.md — completed 2026-06-24T13:40:00Z

### Phase 3a — IaC Transformation
<!-- Populated from design-document.md Section 5 after Phase 2 -->
- [x] Generate main.bicep — completed 2026-06-24T13:40:00Z
- [x] Generate modules/storage.bicep (StorageV2, LRS, CORS, versioning, container `images`) — completed 2026-06-24T13:42:00Z
- [x] Generate modules/function-app.bicep (Y1 Consumption, Python 3.11, system-assigned MI) — completed 2026-06-24T13:44:00Z
- [x] Generate modules/monitoring.bicep (Log Analytics workspace + Application Insights) — completed 2026-06-24T13:41:00Z
- [x] Generate modules/static-web-app.bicep (Free tier SWA) — completed 2026-06-24T13:43:00Z
- [x] Generate modules/rbac.bicep (Storage Blob Data Contributor assignment) — completed 2026-06-24T13:45:00Z
- [x] Generate parameter files: parameters/dev.bicepparam, parameters/staging.bicepparam, parameters/prod.bicepparam — completed 2026-06-24T13:50:00Z
- [x] Corrective re-run: fix BCP036/BCP037/BCP104 compile-type failures from Phase 3d what-if gate — completed 2026-06-25T00:31:40Z

### Phase 3b — Code Refactor
- [x] Rewrite upload_handler.py → upload_function (SAS write token generation) — completed 2026-06-24T13:46:00Z
- [x] Rewrite list_handler.py → list_function (list_blobs + SAS read + blob tags) — completed 2026-06-24T13:46:00Z
- [x] Rewrite view_handler.py → view_function (list prefix + SAS read) — completed 2026-06-24T13:46:00Z
- [x] Rewrite delete_handler.py → delete_function (list prefix + delete_blob) — completed 2026-06-24T13:46:00Z
- [x] Create requirements.txt (azure-functions, azure-storage-blob, azure-identity) — completed 2026-06-24T13:46:00Z
- [x] Create host.json (CORS config, extension bundle, sampling) — completed 2026-06-24T13:46:00Z
- [x] Create app.html (remove AWS SDK + SigV4, add Blob SAS PUT upload, Azure Function endpoints) — completed 2026-06-24T13:46:00Z

### Phase 3c — Pipeline Build
<!-- Populated from design-document.md Section 11 after Phase 2 -->
- [x] Create .github/workflows/deploy-infra.yml (Bicep validate + deploy, OIDC) — completed 2026-06-24T13:36:00Z
- [x] Create .github/workflows/deploy-functions.yml (Python build + Functions deploy, OIDC) — completed 2026-06-24T13:36:00Z
- [x] Create .github/workflows/deploy-static-web.yml (SWA deploy, OIDC) — completed 2026-06-24T13:36:00Z
- [x] Configure OIDC Workload Identity Federation (secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID) — completed 2026-06-24T13:37:00Z
- [x] Configure GitHub environment protection rules — completed 2026-06-24T13:37:00Z

### Phase 4 — Validation
- [x] Run pre-deployment checks — completed 2026-06-24T15:49:52Z
- [x] Run post-deployment smoke tests — completed 2026-06-24T15:49:52Z
- [x] Verify security compliance — completed 2026-06-24T15:49:52Z
- [x] Produce validation-report.md — completed 2026-06-24T15:49:52Z

## Phase Metrics

| Phase | Agent | Duration | Tool Calls | Files Written |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | 11m 34s | 26 | 5 |
| 2 — Architecture | azure-architect | 18m 00s | 22 | 5 |
| 3a — IaC Transformation | iac-transformation | 21m 53s | 29 | 17 |
| 3b — Code Refactor | code-refactor | 4m 48s | 21 | 5 |
| 3c — Pipeline Build | pipeline-builder-agent | 4m 22s | 20 | 5 |
| 3d — Deployment | azure-deployer | 9m 36s | 29 | 2 |

## Blockers
- Phase 3d (azure-deployer): Resolved on 2026-06-24T15:35:45Z. Functions deployed via Strategy C (`WEBSITE_RUN_FROM_PACKAGE` with user-delegation SAS <= 7 days) after Strategy A/B failed; Static Web App deployed successfully via `npx @azure/static-web-apps-cli` fallback due global npm install permission issue (`EACCES`). Post-deploy note: Function `/api/health` probe returned HTTP 503 while app state remained `Running`.
- Phase 4 (deployment-validation): Critical validation failed because `/api/files` and `/api/upload` returned HTTP 503 and Key Vault hardening/auth controls did not meet checklist requirements — remediate runtime/API availability and security configuration, then re-run full Phase 4 validation.
