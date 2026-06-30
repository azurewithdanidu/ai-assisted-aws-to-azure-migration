# Migration Task Plan
Generated: 2026-06-28T00:00:00Z
Last Updated: 2026-06-29T09:10:00Z

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
| 1 — Discovery | aws-discovery | ✅ | 2026-06-28T13:54:00Z |
| 2 — Architecture | azure-architect | ✅ | 2026-06-28T14:20:00Z |
| 3a — IaC Transformation | iac-transformation | ✅ | 2026-06-29T09:07:00Z |
| 3b — Code Refactor | code-refactor | ✅ | 2026-06-29T10:22:00Z |
| 3c — Pipeline Build | pipeline-builder-agent | ✅ | 2026-06-28T14:52:00Z |
| 3d — Deployment | azure-deployer | ⏳ | — |
| 4 — Validation | deployment-validation | ⚠️ Templates ✅; Redeploy needed | 2026-06-28T15:23:42Z |

## Detailed Task List

### Phase 1 — AWS Discovery
- [x] Discover all AWS services and regions — completed 2026-06-28T13:46:00Z
- [x] Generate aws-inventory.json — completed 2026-06-28T13:51:00Z
- [x] Generate architecture-diagram.mmd — completed 2026-06-28T13:51:00Z
- [x] Generate dependency-matrix.csv — completed 2026-06-28T13:52:00Z
- [x] Generate migration-assessment.md — completed 2026-06-28T13:53:00Z

### Phase 2 — Azure Architecture Design
- [x] Map all AWS services to Azure equivalents — completed 2026-06-28T14:20:00Z
- [x] Generate design-document.md (all 11 sections) — completed 2026-06-28T14:20:00Z
- [x] Generate architecture-diagram-azure.mmd — completed 2026-06-28T14:20:00Z
- [x] Generate cost-comparison.md — completed 2026-06-28T14:20:00Z
- [x] Generate service-mapping.md — completed 2026-06-28T14:20:00Z

### Phase 3a — IaC Transformation
- [x] Generate main.bicep — orchestrator that wires all modules together — completed 2026-06-29T09:07:00Z
- [x] Generate modules/storage.bicep — Storage Account + image container + lifecycle policies — completed 2026-06-29T09:07:00Z
- [x] Generate modules/function-app.bicep — Consumption plan, Python 3.11, system-assigned MI, app settings — completed 2026-06-29T09:07:00Z
- [x] Generate modules/static-web-app.bicep — Azure Static Web Apps Free tier, custom routing — completed 2026-06-29T09:07:00Z
- [x] Generate modules/monitoring.bicep — Application Insights + Log Analytics Workspace — completed 2026-06-29T09:07:00Z
- [x] Generate modules/rbac.bicep — Storage Blob Data Contributor RBAC for managed identity — completed 2026-06-29T09:07:00Z
- [x] Generate parameters/dev.bicepparam — dev environment parameter file — completed 2026-06-29T09:07:00Z
- [x] Generate parameters/staging.bicepparam — staging environment parameter file — completed 2026-06-29T09:07:00Z
- [x] Generate parameters/prod.bicepparam — prod environment parameter file — completed 2026-06-29T09:07:00Z

### Phase 3b — Code Refactor
- [x] Refactor upload_handler.py → upload_function: HTTP POST trigger, boto3 → azure-storage-blob, S3 presigned PUT → user delegation SAS token — completed 2026-06-29T10:22:00Z
- [x] Refactor list_handler.py → list_function: HTTP GET trigger, boto3 → azure-storage-blob, S3 ListObjectsV2 → list_blobs — completed 2026-06-29T10:22:00Z
- [x] Refactor view_handler.py → view_url_function: HTTP GET trigger, boto3 → azure-storage-blob, S3 presigned GET → user delegation SAS token — completed 2026-06-29T10:22:00Z
- [x] Refactor delete_handler.py → delete_function: HTTP DELETE trigger, boto3 → azure-storage-blob, S3 DeleteObject → delete_blob — completed 2026-06-29T10:22:00Z
- [x] Update requirements.txt — replace boto3 with azure-functions, azure-storage-blob, azure-identity — completed 2026-06-29T10:22:00Z
- [x] Update host.json — Azure Functions v2 configuration — completed 2026-06-29T10:22:00Z
- [x] Update app.html — remove AWS SDK + SigV4 auth, replace with plain fetch() and Azure Blob SAS PUT workflow — completed 2026-06-29T10:22:00Z

### Phase 3c — Pipeline Build
- [x] Create .github/workflows/deploy-infra.yml — Bicep IaC deployment (dev → staging → prod) with OIDC — completed 2026-06-28T14:50:00Z
- [x] Create .github/workflows/deploy-functions.yml — Azure Functions code deployment (dev → staging → prod) with OIDC — completed 2026-06-28T14:51:00Z
- [x] Create .github/workflows/deploy-static-web.yml — Static Web App content deployment with OIDC — completed 2026-06-28T14:51:00Z
- [x] Configure OIDC federated identity credentials (no long-lived secrets) — completed 2026-06-28T14:52:00Z
- [x] Configure GitHub environment secrets (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID) — completed 2026-06-28T14:52:00Z

### Phase 4 — Validation
- [x] Run pre-deployment checks (Bicep build, policy compliance) — completed 2026-06-28T15:23:42Z
- [ ] Run post-deployment smoke tests — pending live redeployment
- [x] Verify security compliance (templates) — completed 2026-06-28T15:23:42Z
- [x] Produce validation-report.md — completed 2026-06-28T15:23:42Z

## Phase Metrics

| Phase | Agent | Duration | Tool Calls | Files Written |
|---|---|---|---|---|
| 1 — Discovery | aws-discovery | 12m 45s | 38 | 5 |
| 2 — Architecture | azure-architect | 50m 25s | 22 | 5 |
| 3b — Code Refactor | code-refactor | 7m 00s | 18 | 5 |
| 3a — IaC Transformation | iac-transformation | 7m 00s | 22 | 1 |
| 3c — Pipeline Build | pipeline-builder-agent | 4m 27s | 15 | 4 |
| 4 — Validation | deployment-validation | 6m 02s | 19 | 1 |
| 4 — Validation (re-run) | deployment-validation | 6m 42s | 22 | 4 |

## Blockers
- Phase 4 (operational): Bicep templates and code are correct (az bicep build exits 0, zero errors). Live environment has not yet been redeployed with fixed templates. Run the following commands to complete the deployment:
  1. `az deployment group create --resource-group rg-imageupload-dev --template-file outputs/bicep-templates/main.bicep --parameters outputs/bicep-templates/parameters/dev.bicepparam`
  2. `func azure functionapp publish <function-app-name> --python` (from outputs/azure-functions/)
  3. Re-run deployment-validation agent to confirm PASSED status.

**Previously resolved blockers (all fixed 2026-06-29):**
- ✅ `rbac.bicep` BCP035/BCP134 — replaced AVM ptn module with native Microsoft.Authorization/roleAssignments@2022-04-01
- ✅ `static-web-app.bicep` BCP053 — replaced staticSite.outputs.apiKey with listSecrets(resourceId(...), '2023-01-01').properties.apiKey
- ✅ Env var name mismatch — both function_app.py and function-app.bicep already use STORAGE_ACCOUNT_NAME; stale live config will be overwritten on redeploy
- ✅ Key Vault purge protection — added AVM avm/res/key-vault/vault:0.13.3 with enablePurgeProtection: true to function-app.bicep
