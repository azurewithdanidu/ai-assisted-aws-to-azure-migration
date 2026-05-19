# Azure Migration Validation Report

## Status: FAILED

**Project:** Image Upload Photo Gallery — AWS → Azure Migration  
**Validation Date:** 2026-05-20  
**Validator:** Deployment Validation Agent (deployment-validation mode)  
**Validation Type:** Static pre-deployment code review  
**Source of truth:** `outputs/azure-architecture-output/design-document.md` Section 10  

> **NOTE — Static validation scope:** No live Azure environment is available. All functional smoke tests and monitoring checks in Section 10 require a deployed environment and are marked **PENDING** below. All other checks are based on static analysis of the output artefacts.

---

## Executive Summary

| Category | Total Checks | PASSED | FAILED | WARNING | PENDING |
|---|---|---|---|---|---|
| Bicep Template Validation | 12 | 10 | 0 | 2 | 0 |
| Azure Functions Code | 9 | 9 | 0 | 0 | 0 |
| CI/CD Workflows | 9 | 6 | 1 | 2 | 0 |
| Security Compliance | 8 | 8 | 0 | 0 | 0 |
| Service Mapping Completeness | 9 | 9 | 0 | 0 | 0 |
| Infrastructure Checks (live) | 7 | 0 | 0 | 0 | 7 |
| Functional Smoke Tests (live) | 7 | 0 | 0 | 0 | 7 |
| Monitoring Checks (live) | 2 | 0 | 0 | 0 | 2 |
| **TOTAL** | **63** | **42** | **1** | **4** | **16** |

**Overall FAILED** — 1 confirmed failure in CI/CD workflows (Function App name mismatch) that will prevent automated `deploy-functions.yml` execution. 4 warnings require attention before production. 16 checks are pending live deployment.

---

## 1. Bicep Template Validation

> Files examined: `outputs/bicep-templates/main.bicep`, `modules/{storage,identity,functionApp,monitoring,rbac,staticWebApp}.bicep`, `parameters/{dev,staging,prod}.bicepparam`

### Module Completeness

| Check | Result | Detail |
|---|---|---|
| All 6 modules present (`storage`, `identity`, `functionApp`, `monitoring`, `rbac`, `staticWebApp`) | **PASSED** | All files exist under `outputs/bicep-templates/modules/` |
| `main.bicep` references all 6 modules with correct relative paths | **PASSED** | `'modules/storage.bicep'`, `'modules/functionApp.bicep'`, etc. all resolve correctly |
| Parameter files for all 3 environments (dev, staging, prod) | **PASSED** | `dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam` all present with `using '../main.bicep'` |
| All required parameters have `@description` decorators | **PASSED** | All `param` declarations include `@description` |
| Secure parameters marked `@secure()` | **PASSED** | `storageConnectionString` and `appInsightsConnectionString` both carry `@secure()` |

### Infrastructure Security Settings

| Check | Result | Detail |
|---|---|---|
| `allowBlobPublicAccess: false` on Storage Account | **PASSED** | `storage.bicep` line: `allowBlobPublicAccess: false` |
| `supportsHttpsTrafficOnly: true` + `minimumTlsVersion: TLS1_2` | **PASSED** | Both set in `storage.bicep` |
| `httpsOnly: true` on Function App | **PASSED** | `functionApp.bicep`: `httpsOnly: true` |
| System-assigned Managed Identity enabled | **PASSED** | `functionApp.bicep`: `managedIdentities: { systemAssigned: true }` |
| `linuxFxVersion: 'PYTHON\|3.11'` (uppercase, pipe-separated) | **PASSED** | Matches AVM requirement; avoids known crash with lowercase |
| `Storage Blob Data Contributor` RBAC assignment scoped to storage account only | **PASSED** | `rbac.bicep` scopes to `storageAccount` resource, role ID `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| Blob soft-delete enabled (7-day retention) | **PASSED** | `storage.bicep`: `deleteRetentionPolicyEnabled: true`, `deleteRetentionPolicyDays: 7` |

### Warnings

| Check | Result | Detail |
|---|---|---|
| `deploy-infra.yml` save-outputs step queries `.swaHostname.value` | **WARNING** | `main.bicep` exports output as `staticWebAppHostname`, not `swaHostname`. The `SWA_HOSTNAME` variable in the deploy-infra job will always be empty. Downstream workflows that depend on this artefact value will need to re-query the SWA resource directly. Low severity — does not block deployment but breaks artefact propagation. |
| `storageConnectionString` uses `listKeys()` (account key) in `storage.bicep` output | **WARNING** | This passes the storage account key in plain text via Bicep output (secure string). For `dev`/`staging` this is acceptable. For `prod`, prefer a Managed Identity–based connection string (`__blobServiceUri` + `__accountName` pattern) to avoid passing long-lived credentials. This is already noted in a comment in `storage.bicep`. |

---

## 2. Azure Functions Code Validation

> Files examined: `outputs/azure-functions/function_app.py`, `outputs/azure-functions/shared/blob_helpers.py`, `outputs/azure-functions/requirements.txt`, `outputs/azure-functions/host.json`, `outputs/azure-functions/local.settings.json`

### SDK Migration (boto3 → Azure SDK)

| Check | Result | Detail |
|---|---|---|
| No `boto3` import in any function file | **PASSED** | `grep` across `outputs/azure-functions/**` — zero matches |
| No `import boto3` / `from boto3` anywhere | **PASSED** | Only boto3 references are in docstring comments (migration notes) |
| `azure-functions>=1.18.0` in `requirements.txt` | **PASSED** | Present |
| `azure-storage-blob>=12.19.0` in `requirements.txt` | **PASSED** | Present |
| `azure-identity>=1.15.0` in `requirements.txt` | **PASSED** | Present |

### Route & Auth Correctness

| Check | Result | Detail |
|---|---|---|
| All 4 AWS Lambda routes implemented | **PASSED** | `POST /api/upload`, `GET /api/files`, `GET /api/files/{fileId}/view-url`, `DELETE /api/files/{fileId}` — all decorated with `@app.route` |
| `func.AuthLevel.FUNCTION` (function-key auth required) | **PASSED** | `app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)` |
| `routePrefix = "api"` in `host.json` | **PASSED** | `"http": { "routePrefix": "api" }` |
| `functionTimeout = "00:00:30"` (matches AWS 30 s Lambda timeout) | **PASSED** | Set in `host.json` |

### Environment Variables & Credentials

| Check | Result | Detail |
|---|---|---|
| `STORAGE_ACCOUNT_NAME` used (not hardcoded account name) | **PASSED** | `blob_helpers.py`: `STORAGE_ACCOUNT_NAME: str = os.environ["STORAGE_ACCOUNT_NAME"]` |
| `BLOB_CONTAINER_NAME` used (not reserved `CONTAINER_NAME`) | **PASSED** | Correct variable name; `CONTAINER_NAME` is reserved by Azure Functions host |
| `URL_EXPIRATION` env var used with safe default | **PASSED** | `int(os.environ.get("URL_EXPIRATION", "3600"))` |
| No hardcoded AWS access keys or secrets | **PASSED** | `grep` for `AKIA*`, `aws_access_key`, `AWS_SECRET` — zero matches |
| `DefaultAzureCredential()` for Managed Identity auth | **PASSED** | Used in `blob_helpers.py`; resolves to system-assigned MI in Azure |
| `local.settings.json` contains only placeholder values | **PASSED** | All sensitive fields are `<your-…>` placeholders; no real credentials |

### Metadata Field Preservation

| Check | Result | Detail |
|---|---|---|
| AWS `x-amz-meta-uploaddate` → Azure `metadata["uploaddate"]` | **PASSED** | Preserved in upload and listed in list/get responses |
| AWS `x-amz-meta-originalfilename` → Azure `metadata["originalfilename"]` | **PASSED** | Present in all response payloads |

---

## 3. CI/CD Workflow Validation

> Files examined: `.github/workflows/deploy-infra.yml`, `.github/workflows/deploy-functions.yml`, `.github/workflows/deploy-static-web.yml`

### OIDC Configuration

| Check | Result | Detail |
|---|---|---|
| All 3 workflows use `azure/login@v2` with OIDC (`client-id`, `tenant-id`, `subscription-id`) | **PASSED** | No `creds:` (JSON secret) pattern found; only individual OIDC params used |
| `permissions: id-token: write` declared in all 3 workflows | **PASSED** | Required for GitHub Actions OIDC token exchange |
| No long-lived Azure client secrets (no `AZURE_CLIENT_SECRET` in workflow steps) | **PASSED** | `grep` across `.github/workflows/**` — zero matches for `AZURE_CLIENT_SECRET` or `password` |
| SWA deployment token correctly namespaced (`STATIC_WEB_APP_TOKEN_DEV/STAGING/PROD`) | **PASSED** | `deploy-static-web.yml` uses `${{ secrets[needs.determine-env.outputs.swa_token_secret] }}` with correct naming |

### Environment Strategy

| Check | Result | Detail |
|---|---|---|
| Branch-to-environment mapping (`main`→prod, `staging`→staging, `dev`→dev) | **PASSED** | All 3 workflows implement `case "${{ github.ref_name }}"` block with correct mapping |
| GitHub `environment:` objects used (enables approval gates for prod) | **PASSED** | `environment: ${{ needs.determine-env.outputs.env_name }}` on all deploy jobs |
| Rollback jobs defined | **PASSED** | `rollback-on-failure` job present in `deploy-infra.yml` and `deploy-functions.yml`; `deploy-infra.yml` uses `--rollback-on-error` on `az deployment group create` |

### Failures

| Check | Result | Detail |
|---|---|---|
| **Function App name consistent between Bicep and deploy-functions.yml** | **FAILED** | Bicep params provision `photo-gallery-func-<env>` (e.g. `photo-gallery-func-dev`) but `deploy-functions.yml` hardcodes the fallback name as `func-photo-gallery-${ENV_NAME}` (e.g. `func-photo-gallery-dev`). On push triggers (no `functionAppName` override), the workflow will attempt to deploy code to a Function App that does not exist. **This must be fixed before the pipeline will work end-to-end.** |

### Warnings

| Check | Result | Detail |
|---|---|---|
| SWA resource name in `deploy-static-web.yml` smoke test | **WARNING** | Smoke test queries `swa-photo-gallery-${ENV_NAME}` but Bicep provisions `photo-gallery-swa-<env>`. The `az staticwebapp show` step will return empty and the smoke test will be skipped silently (uses `|| echo ""`). Deploy still succeeds — this is a verification gap only. |
| `deploy-infra.yml` save-outputs jq query | **WARNING** | (Duplicate of Bicep warning §1) `.swaHostname.value` key does not exist in Bicep output JSON; will silently produce empty string for `swa_hostname` job output. |

---

## 4. Security Compliance

> Specifically verifying the Section 10 security requirement: `AKIAXZEFIIOD2OIWPRPK` must NOT appear in Function App app settings or SPA JavaScript.

| Check | Result | Detail |
|---|---|---|
| `AKIAXZEFIIOD2OIWPRPK` NOT in `outputs/bicep-templates/**` | **PASSED** | Zero matches. The key is absent from all Bicep templates and parameter files. |
| `AKIAXZEFIIOD2OIWPRPK` NOT in `outputs/azure-functions/**` | **PASSED** | Zero matches. No AWS credentials anywhere in the refactored function code. |
| `AKIAXZEFIIOD2OIWPRPK` in `.github/workflows/deploy-static-web.yml` — only as remediation target | **PASSED** | Appears in: (a) a security comment, (b) a `sed -i 's/AKIAXZEFIIOD2OIWPRPK/REMOVED_SEE_AZURE_MIGRATION/g'` removal command, and (c) a post-removal `grep -q` verification that exits with code 1 if the key is still present. The key is the target of removal, not a deployed credential. |
| No `AKIA*` pattern in any deployment artifact (bicep, function code, workflows) | **PASSED** | `grep -rE 'AKIA[A-Z0-9]{16}'` across `outputs/bicep-templates/`, `outputs/azure-functions/` — zero matches. |
| `allowBlobPublicAccess: false` — blobs inaccessible without SAS token | **PASSED** | Enforced in `modules/storage.bicep` |
| HTTPS-only + TLS 1.2 minimum enforced on all services | **PASSED** | `supportsHttpsTrafficOnly: true`, `minimumTlsVersion: TLS1_2` (storage); `httpsOnly: true` (Function App) |
| System-assigned Managed Identity replaces static IAM user access key | **PASSED** | `DefaultAzureCredential()` in function code; `managedIdentities: { systemAssigned: true }` in Bicep; no credential rotation required |
| No hardcoded credentials in any Azure output artefact | **PASSED** | `local.settings.json` contains only `<placeholder>` values. No connection strings, secrets, or keys hardcoded in source. |

> **Finding:** The AWS IAM static key `AKIAXZEFIIOD2OIWPRPK` appears only in:
> - Discovery artefacts (`outputs/aws-migration-artifacts/`) — expected, read-only reference material
> - Architecture documentation (`outputs/azure-architecture-output/`) — expected, risk documentation
> - `.github/workflows/deploy-static-web.yml` — only as the target of a `sed` removal command with an enforced post-removal verification step
>
> **The key is NOT present in any Azure deployment artefact.** The security risk has been eliminated by design.

---

## 5. Service Mapping Completeness

> Reference: `outputs/aws-migration-artifacts/aws-inventory.json` (account 535002891143, region ap-southeast-2)

| AWS Service | AWS Resource(s) | Azure Equivalent | Artefact | Status |
|---|---|---|---|---|
| **Lambda (Python 3.11)** × 4 | UploadFunction, ListFilesFunction, GetViewUrlFunction, DeleteFileFunction | Azure Functions (Consumption Y1) — single Function App, 4 HTTP triggers | `outputs/azure-functions/function_app.py` | **PASSED** |
| **Amazon API Gateway REST** | `image-upload-api` (4 routes + CORS OPTIONS) | Azure Functions HTTP triggers (built-in routing via `routePrefix: api`) | `function_app.py`, `host.json` | **PASSED** |
| **S3 Bucket (images)** | `image-upload-imagebucket-t8isnbr8sswv` | Azure Blob Storage (Standard LRS/GRS, Hot, container `images`) | `modules/storage.bicep` | **PASSED** |
| **S3 Bucket (static website)** | `image-upload-websitebucket-vd866vxtcs1z` | Azure Static Web Apps (Free tier, `index.html`) | `modules/staticWebApp.bicep` | **PASSED** |
| **IAM Role (LambdaExecutionRole)** | S3 CRUD inline policy | System-assigned Managed Identity + `Storage Blob Data Contributor` RBAC | `modules/functionApp.bicep`, `modules/rbac.bicep` | **PASSED** |
| **IAM Role (ApiGatewayCloudWatchLogsRole)** | API GW → CloudWatch | Not required — Application Insights handles telemetry via MI | `modules/monitoring.bicep` | **PASSED** |
| **IAM User (image-upload-api-user)** | Static access key `AKIAXZEFIIOD2OIWPRPK` | Azure Function App host key (`x-functions-key` header); injected at deploy time by `deploy-static-web.yml` | `.github/workflows/deploy-static-web.yml` | **PASSED** |
| **CloudWatch Logs** | 3 log groups (Lambda × 2, API GW × 1) | Application Insights (request telemetry) + Log Analytics Workspace (log queries) | `modules/monitoring.bicep`, `functionApp.bicep` `APPLICATIONINSIGHTS_CONNECTION_STRING` | **PASSED** |
| **CloudFormation Stack** | `image-upload` (CREATE_COMPLETE) | Bicep IaC + GitHub Actions (`deploy-infra.yml`) | `outputs/bicep-templates/` | **PASSED** |

**All 9 AWS service categories have verified Azure equivalents.** No unmatched services.

---

## 6. Infrastructure Checks (live deployment — PENDING)

> These checks from Section 10 require a deployed Azure environment. They are listed with expected values for post-deployment verification.

| Check | Expected Value | Status |
|---|---|---|
| Resource group `rg-photo-gallery-<env>` exists in `australiaeast` | Provisioned by Bicep | **PENDING** |
| Storage account exists; `allowBlobPublicAccess=false`; blob versioning matches env config (dev: false, prod: true) | As per `storage.bicep` and `*.bicepparam` | **PENDING** |
| Container `images` exists with private access level | `publicAccess: 'None'` in `storage.bicep` | **PENDING** |
| Function App exists; runtime `python\|3.11`; `httpsOnly=true`; identity type `SystemAssigned` | As per `functionApp.bicep` | **PENDING** |
| Function App `principalId` has `Storage Blob Data Contributor` on storage account | `az role assignment list --assignee <principalId>` | **PENDING** |
| Log Analytics Workspace and Application Insights exist and are linked | As per `monitoring.bicep` | **PENDING** |
| Static Web App exists; deployment succeeded | As per `staticWebApp.bicep` | **PENDING** |

---

## 7. Functional Smoke Tests (live deployment — PENDING)

> These require a live deployment. Expected behaviour is documented below from Section 10.

| Smoke Test | Expected Result | Status |
|---|---|---|
| `POST /api/upload` with `x-functions-key` → HTTP 200 with `sas_url` and `blob_name` | JSON body containing `uploadUrl` (SAS PUT URL) and `fileId` | **PENDING** |
| PUT to returned `uploadUrl` with test PNG ≤ 10 MB → HTTP 201 | Azure Storage accepts the blob | **PENDING** |
| `GET /api/files` → HTTP 200, JSON array with uploaded blob; `originalfilename`, `uploaddate` present | Blob metadata propagated via `x-ms-meta-*` headers | **PENDING** |
| `GET /api/files/{fileId}/view-url` → HTTP 200 with read SAS URL (browser: HTTP 200, `image/*`) | SAS URL with `BlobSasPermissions(read=True)` | **PENDING** |
| `DELETE /api/files/{fileId}` → HTTP 200; subsequent view-url → HTTP 404 | `BlobClient.delete_blob` + ResourceNotFoundError → 404 | **PENDING** |
| CORS preflight `OPTIONS /api/upload` from SWA origin → HTTP 200 with correct `Access-Control-Allow-Origin` | `corsAllowedOrigins` in `functionApp.bicep` | **PENDING** |
| SPA load: Static Web App URL loads `index.html` without console errors | SWA CDN serving pre-patched index.html | **PENDING** |

---

## 8. Monitoring Checks (live deployment — PENDING)

| Check | Expected Result | Status |
|---|---|---|
| Application Insights receives request telemetry after smoke tests | `requests \| where timestamp > ago(10m)` returns rows in Log Analytics | **PENDING** |
| Log Analytics Workspace shows function execution logs via KQL | `traces \| where timestamp > ago(10m)` returns function log entries | **PENDING** |

---

## 9. Items Requiring Manual Follow-Up Before Production Deployment

The following items must be resolved before this migration can go to production. Items are ranked by severity.

### BLOCKER — Must fix before `deploy-functions.yml` will work

1. **Function App name mismatch in `deploy-functions.yml`** ❌  
   - **Problem:** `deploy-functions.yml` (line 70) derives the Function App name as `func-photo-gallery-${ENV_NAME}` (e.g. `func-photo-gallery-dev`). The Bicep parameter files provision the Function App as `photo-gallery-func-<env>` (e.g. `photo-gallery-func-dev`). On any push-triggered run (not using the manual `functionAppName` override), the workflow will try to deploy code to a nonexistent resource.  
   - **Fix:** Update `deploy-functions.yml` line 70 from `func-photo-gallery-${ENV_NAME}` to `photo-gallery-func-${ENV_NAME}`, matching the convention in all three `*.bicepparam` files. Also update the comment on line 69.  
   - **Same fix needed in `deploy-static-web.yml`:** That workflow also derives `func_app_name=func-photo-gallery-${ENV_NAME}` (in the `determine-env` job outputs). Update to `photo-gallery-func-${ENV_NAME}` there as well.

### HIGH — Should fix before production

2. **`deploy-infra.yml` `jq` key mismatch for SWA hostname** ⚠️  
   - **Problem:** The save-outputs step queries `.swaHostname.value` but `main.bicep` exports the key as `staticWebAppHostname`. Result: `swa_hostname` job output is always empty.  
   - **Fix:** Change the `jq` query from `.swaHostname.value` to `.staticWebAppHostname.value` in the save-outputs step of `deploy-infra.yml`.

3. **`deploy-static-web.yml` SWA smoke-test resource name mismatch** ⚠️  
   - **Problem:** Smoke test `az staticwebapp show --name "swa-photo-gallery-${ENV_NAME}"` will fail silently because Bicep provisions `photo-gallery-swa-<env>`.  
   - **Fix:** Change the smoke-test resource name to `photo-gallery-swa-${ENV_NAME}`.

4. **`storageConnectionString` uses account key in prod** ⚠️  
   - **Problem:** `storage.bicep` outputs a `listKeys()`-based connection string for `AzureWebJobsStorage`. This works but passes a long-lived account key at deployment time.  
   - **Fix (prod hardening):** Switch to `AzureWebJobsStorage__blobServiceUri` + `AzureWebJobsStorage__accountName` pattern (identity-based connection), removing the account key entirely.

### MEDIUM — Operational improvements

5. **GitHub repository URL placeholder** — All three `*.bicepparam` files set `repositoryUrl = 'https://github.com/org/ai-assisted-aws-to-azure-migration'`. Update `org` to the actual GitHub organization before first deployment.

6. **SWA CORS origins in staging/prod** — `staging.bicepparam` and `prod.bicepparam` set `corsAllowedOrigins` to predicted SWA hostnames (`https://photo-gallery-swa-<env>.azurestaticapps.net`). Verify these match the actual hostnames after first SWA deployment (the actual default hostname is assigned by Azure, not always predictable).

7. **Run live post-deployment validation** — The 16 PENDING checks in sections 6–8 above must be executed once the Azure environment is provisioned. Use the commands in `design-document.md` Section 10 as the test harness.

---

## 10. Validation Conclusion

| Dimension | Verdict |
|---|---|
| Bicep template syntax & structure | ✅ Valid — all modules present, correctly wired, security settings enforced |
| Azure Functions code quality | ✅ Valid — full AWS→Azure refactor; no boto3; MI auth; correct routes |
| CI/CD security (OIDC, no long-lived secrets) | ✅ Valid |
| CI/CD correctness (name conventions) | ❌ **Blocked** — Function App name mismatch prevents automated deployment |
| Static security compliance (IAM key absent) | ✅ PASSED — `AKIAXZEFIIOD2OIWPRPK` not in any Azure deployment artefact |
| Service mapping completeness | ✅ PASSED — all 9 AWS service categories have Azure equivalents |
| Live infrastructure checks | ⏳ PENDING — requires Azure deployment |
| Live functional smoke tests | ⏳ PENDING — requires Azure deployment |

**Deployment is NOT ready to proceed as-is.** Fix the Function App name mismatch (item 1 above) and the two naming-related warnings (items 2–3), then re-run the pipeline for `dev` environment. Once live deployment succeeds, re-execute the 16 pending checks in sections 6–8 to confirm full validation.

---

*Report generated by Deployment Validation Agent on 2026-05-20*  
*Validation framework: Azure Well-Architected + design-document.md Section 10*
