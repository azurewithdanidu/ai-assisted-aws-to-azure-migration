# Azure Architecture Design Document

**Project:** AWS → Azure Migration — Image Upload Service
**Source stack:** `image-upload` (AWS SAM/CloudFormation, account 535002891143, region ap-southeast-2)
**Target region:** `australiaeast` (paired with Sydney AWS for minimum cutover egress)
**Author:** azure-architect agent
**Date:** 2026-05-18
**Design priority:** **Cost optimization (Pillar 3 — primary).** No APIM. Consumption-only compute. Free-tier services preferred wherever requirements permit.

---

## 1. Executive Summary

The AWS workload is a small, stateless serverless image-upload service: a 4-route REST API (AWS API Gateway + IAM SigV4) fronting four Python 3.11 Lambda functions, backed by two S3 buckets (image storage + static SPA hosting). It is being re-platformed to Azure as a **single-region, serverless, identity-first** architecture:

- **API + compute:** Azure Functions (Python 3.11, **Consumption Y1**) with HTTP triggers — **APIM is explicitly excluded** as it adds cost without delivering features this workload uses.
- **Object storage:** Azure Blob Storage (Standard LRS, Hot tier, versioning + soft delete + lifecycle policy).
- **Static frontend:** Azure Static Web Apps (Free SKU) — provides managed TLS + global CDN that the current S3 static-site bucket lacks.
- **Identity:** User-Assigned Managed Identity + RBAC; long-lived static IAM keys are eliminated.
- **Observability:** Application Insights + Log Analytics (PerGB2018, 30-day retention).
- **IaC:** Bicep (subscription-scope main, six resource modules).
- **CI/CD:** GitHub Actions with OIDC / Workload Identity Federation (no long-lived secrets).

Estimated monthly cost is **~$10.85** vs ~$48.40 on AWS at current scale (~78% reduction); strategic wins (secret elimination, free TLS+CDN, native APM) outweigh the absolute dollar savings.

---

## 2. AWS Discovery Summary

Source: `outputs/aws-migration-artifacts/aws-inventory.json` + `migration-assessment.md`.

- **CloudFormation stack** — `image-upload` (1), region `ap-southeast-2`, 33 managed resources, 16 in scope.
- **Lambda functions (4)** — Python 3.11, 256 MB, 30 s, x86_64, Zip:
  - `UploadFunction` — `upload_handler.lambda_handler` — generates S3 presigned PUT URL.
  - `ListFilesFunction` — `list_handler.lambda_handler` — lists objects + presigned GET URLs.
  - `GetViewUrlFunction` — `view_handler.lambda_handler` — generates S3 presigned GET URL.
  - `DeleteFileFunction` — `delete_handler.lambda_handler` — deletes S3 object.
  - Env: `BUCKET_NAME`, `URL_EXPIRATION=3600`.
- **API Gateway REST (1)** — `image-upload-api` (`4lrh2l7i86`), regional, stage `dev`, IAM SigV4 auth, X-Ray on, INFO logging; 4 routes (`POST /upload`, `GET /files`, `GET /files/{fileId}/view-url`, `DELETE /files/{fileId}`) + CORS OPTIONS mocks.
- **S3 buckets (2)** —
  - `image-upload-imagebucket-t8isnbr8sswv` — SSE-S3, versioning ON, public access blocked, CORS `*`.
  - `image-upload-websitebucket-vd866vxtcs1z` — static website hosting (`app.html`), public read.
- **IAM (3)** — `LambdaExecutionRole` (S3 inline policy), `ApiGatewayCloudWatchLogsRole`, `image-upload-api-user` (long-lived access key `AKIAXZEFIIOD2OIWPRPK` — security debt).
- **CloudWatch Logs (4)** — one log group per Lambda, retention **Never expire**.
- **No DB, queues, VPC, cross-region, or cross-account dependencies.**

---

## 3. Azure Service Mapping

| AWS Service | AWS Config | Azure Equivalent | Azure Config | Migration Notes |
|---|---|---|---|---|
| API Gateway REST (4 routes, IAM SigV4) | Regional, X-Ray, INFO logs | **Azure Functions HTTP trigger** (Consumption Y1) | `authLevel: function`, route prefix `api` | **APIM excluded** — adds $50+/mo for no required feature. Function keys provide simple client auth parity. |
| Lambda `UploadFunction` | Python 3.11, 256 MB, 30 s | Azure Function (Consumption Y1) | Python 3.11, HTTP trigger `POST /api/upload` | Rewrite presigned PUT → User Delegation SAS write |
| Lambda `ListFilesFunction` | Python 3.11, 256 MB, 30 s | Azure Function (Consumption Y1) | Python 3.11, HTTP trigger `GET /api/files` | Rewrite `list_objects_v2` → `list_blobs` |
| Lambda `GetViewUrlFunction` | Python 3.11, 256 MB, 30 s | Azure Function (Consumption Y1) | Python 3.11, HTTP trigger `GET /api/files/{fileId}/view-url` | Rewrite presigned GET → User Delegation SAS read |
| Lambda `DeleteFileFunction` | Python 3.11, 256 MB, 30 s | Azure Function (Consumption Y1) | Python 3.11, HTTP trigger `DELETE /api/files/{fileId}` | Rewrite `delete_object` → `BlobClient.delete_blob` |
| S3 `ImageBucket` | SSE-S3, versioning, blocked public, CORS `*` | Blob Storage container `images` on Standard_LRS account | StorageV2, MS-managed encryption, blob versioning, soft delete 7d, lifecycle policy, CORS restricted to SWA origin | 1:1 functional mapping |
| S3 `WebsiteBucket` | Static website, public read | **Azure Static Web Apps — Free SKU** | Managed TLS + global CDN | Free SKU sufficient; auto-build via GH Actions |
| IAM `LambdaExecutionRole` | Lambda trust, S3 inline policy | **User-Assigned Managed Identity** | Assignments: `Storage Blob Data Contributor` (container), `Storage Blob Delegator` (account), `Key Vault Secrets User` (KV) | Identity-based, secretless |
| IAM `ApiUser` + access key | Static SigV4 key | Function host key (Phase 1) / future Easy Auth + Entra ID | Sent as `x-functions-key` header by SPA | Eliminates static AWS key |
| IAM `ApiGatewayCloudWatchLogsRole` | API GW → CW Logs | N/A — Functions ship telemetry natively | — | Not needed |
| CloudWatch Logs (4) | Never expire | Application Insights + Log Analytics workspace | Workspace-based AI, `PerGB2018`, **30-day** retention | Cost control via retention |
| X-Ray | Tracing | App Insights distributed tracing | Auto-instrumented Python worker | Sampling 100% dev / 5% prod |
| CloudFormation | SAM template | Bicep (subscription-scope `main.bicep` + 6 modules) | Modular, parameterized per env | See Section 5 |

---

## 4. Target Architecture

```mermaid
graph TB
    USER([End User / Browser])

    subgraph "Frontend"
        SWA[Azure Static Web Apps<br/>SKU: Free<br/>app.html SPA + TLS + CDN]
    end

    subgraph "Identity & Secrets"
        UAMI[User-Assigned Managed Identity<br/>id-imgupload-env]
        KV[Key Vault Standard<br/>kv-imgupload-env]
    end

    subgraph "Functions Consumption Y1 — Python 3.11"
        FUNC[Function App: func-imgupload-env]
        H1[/POST /api/upload/]
        H2[/GET /api/files/]
        H3[/GET /api/files/&#123;fileId&#125;/view-url/]
        H4[/DELETE /api/files/&#123;fileId&#125;/]
        FUNC --> H1
        FUNC --> H2
        FUNC --> H3
        FUNC --> H4
    end

    subgraph "Storage"
        ST[Storage Account stimguploadenv<br/>Standard_LRS StorageV2]
        IMGC[(images container<br/>versioning + soft-delete + lifecycle)]
        ST --- IMGC
    end

    subgraph "Observability"
        AI[Application Insights]
        LAW[Log Analytics 30d]
        AI --> LAW
    end

    USER --> SWA
    SWA -->|x-functions-key| FUNC
    H1 & H2 & H3 & H4 -->|User Delegation SAS / list / delete| IMGC
    USER -.SAS PUT/GET.-> IMGC
    FUNC -.uses.-> UAMI
    UAMI -.Blob Data Contributor + Delegator.-> ST
    UAMI -.Secrets User.-> KV
    FUNC --> AI
```

**Component flow:**
1. Browser loads SPA from SWA over HTTPS (managed TLS + CDN edge).
2. SPA calls Function App routes with `x-functions-key` header (key sourced from Key Vault into SWA at build time).
3. Function handlers use `DefaultAzureCredential` (UAMI) to call Storage: list blobs, mint User Delegation SAS, or delete blobs.
4. Browser uploads/downloads directly to/from Blob using the SAS — no compute traffic through Functions for the data plane (same pattern as S3 presigned URLs).
5. Functions emit logs & traces to App Insights → Log Analytics.

**Network boundaries:** Public endpoints only (no VNet, no Private Endpoints — cost-driven). Security enforced via Managed Identity, RBAC, function keys, and SAS short TTLs (1 h).

---

## 5. Infrastructure as Code Specification

Tooling: **Bicep**. Deployment scope: **subscription** for `main.bicep` (so resource groups are created by IaC). All modules live under `infra/modules/`.

```
infra/
  main.bicep                    # subscription-scope; creates RG + invokes modules
  main.parameters.dev.json
  main.parameters.staging.json
  main.parameters.prod.json
  modules/
    storage.bicep
    identity.bicep
    monitoring.bicep
    keyvault.bicep
    functionApp.bicep
    staticWebApp.bicep
    rbac.bicep
```

### 5.1 `main.bicep` (subscription scope)
- **Purpose:** Top-level orchestrator. Creates the resource group and invokes all child modules in correct order.
- **Scope:** `targetScope = 'subscription'`.
- **Parameters:**
  - `environmentName` — string, allowed `['dev','staging','prod']`.
  - `location` — string, default `australiaeast`.
  - `resourceNameSuffix` — string, default = `environmentName` (e.g. `dev`).
  - `tags` — object, default `{ workload: 'image-upload', env: environmentName, managedBy: 'bicep' }`.
- **Resources:** `Microsoft.Resources/resourceGroups@2024-03-01` named `rg-imgupload-${resourceNameSuffix}`.
- **Module invocation order:** `monitoring` → `identity` → `keyvault` → `storage` → `rbac` → `functionApp` → `staticWebApp`.
- **Outputs:** `resourceGroupName`, `functionAppName`, `storageAccountName`, `staticWebAppName`, `staticWebAppDefaultHostname`, `managedIdentityClientId`, `appInsightsConnectionString`.

### 5.2 `modules/monitoring.bicep` (`modules/monitoring.bicep`)
- **Purpose:** Log Analytics workspace + Application Insights (workspace-based).
- **Parameters:** `location`, `resourceNameSuffix`, `tags`, `logRetentionDays` (int, default 30).
- **Resources:**
  - `Microsoft.OperationalInsights/workspaces@2023-09-01` — `log-imgupload-${suffix}`, SKU `PerGB2018`, `retentionInDays: logRetentionDays`.
  - `Microsoft.Insights/components@2020-02-02` — `appi-imgupload-${suffix}`, kind `web`, `Application_Type: web`, `WorkspaceResourceId: workspace.id`.
- **Outputs:** `workspaceId`, `appInsightsConnectionString`, `appInsightsInstrumentationKey`.
- **Security:** None beyond default.
- **Env differences:** prod = retention 90 days; dev/staging = 30 days.

### 5.3 `modules/identity.bicep`
- **Purpose:** User-Assigned Managed Identity used by the Function App.
- **Parameters:** `location`, `resourceNameSuffix`, `tags`.
- **Resources:** `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` — `id-imgupload-${suffix}`.
- **Outputs:** `identityId` (resource ID), `principalId`, `clientId`.
- **Env differences:** none.

### 5.4 `modules/keyvault.bicep`
- **Purpose:** Key Vault to hold the Function host key and any future app secrets.
- **Parameters:** `location`, `resourceNameSuffix`, `tags`, `tenantId` (default `subscription().tenantId`), `enableRbacAuthorization` (default `true`).
- **Resources:** `Microsoft.KeyVault/vaults@2024-04-01-preview` — `kv-imgupload-${suffix}`, SKU `standard`, `enableRbacAuthorization: true`, `enableSoftDelete: true`, `softDeleteRetentionInDays: 7`, public network access enabled (cost-driven; no private endpoints).
- **Outputs:** `keyVaultName`, `keyVaultUri`, `keyVaultId`.
- **Security:** RBAC authorization (not access policies).
- **Env differences:** prod = `softDeleteRetentionInDays: 90`, `enablePurgeProtection: true`.

### 5.5 `modules/storage.bicep`
- **Purpose:** Storage account + `images` container + lifecycle policy + CORS rules. Also serves as `AzureWebJobsStorage` backing for the Function App.
- **Parameters:** `location`, `resourceNameSuffix`, `tags`, `allowedCorsOrigins` (array of strings), `skuName` (default `Standard_LRS`).
- **Resources:**
  - `Microsoft.Storage/storageAccounts@2023-05-01` — `stimgupload${suffix}`, kind `StorageV2`, `accessTier: Hot`, `minimumTlsVersion: TLS1_2`, `supportsHttpsTrafficOnly: true`, `allowBlobPublicAccess: false`, `publicNetworkAccess: Enabled`.
  - `blobServices/default` — `isVersioningEnabled: true`, `deleteRetentionPolicy.days: 7`, `containerDeleteRetentionPolicy.days: 7`, CORS rule for `allowedCorsOrigins` (methods GET, PUT, POST, HEAD, DELETE, OPTIONS; headers `*`; maxAge 3600).
  - `blobServices/default/containers@2023-05-01` — `images`, public access `None`.
  - `managementPolicies/default@2023-05-01` — Hot → Cool after 30 d; Cool → Archive after 180 d; delete previous-version blobs > 90 d.
- **Outputs:** `storageAccountName`, `storageAccountId`, `imagesContainerName`, `blobEndpoint`.
- **Security:** TLS 1.2 min, HTTPS only, public blob access disabled (Functions/Blob use RBAC + SAS).
- **Env differences:** prod uses `Standard_ZRS`; dev/staging `Standard_LRS`. Prod `allowedCorsOrigins` = SWA prod hostname only; dev permissive (`*`).

### 5.6 `modules/rbac.bicep`
- **Purpose:** Role assignments granting the UAMI access to Storage and Key Vault.
- **Parameters:** `principalId`, `storageAccountName`, `keyVaultName`.
- **Resources (existing references + role assignments):**
  - `Storage Blob Data Contributor` (role def `ba92f5b4-2d11-453d-a403-e96b0029c9fe`) on the storage account.
  - `Storage Blob Delegator` (role def `db58b8e5-c6ad-4a2a-8342-4190687cbf4a`) on the storage account (needed for User Delegation Key).
  - `Key Vault Secrets User` (role def `4633458b-17de-408a-b874-0445c86b69e6`) on the Key Vault.
- **Outputs:** none (or assignment IDs for debugging).
- **Security:** Least privilege; data-plane roles only.
- **Env differences:** none.

### 5.7 `modules/functionApp.bicep`
- **Purpose:** Linux Consumption Function App (Python 3.11) with UAMI, App Insights wiring, and storage backing.
- **Parameters:** `location`, `resourceNameSuffix`, `tags`, `storageAccountName`, `userAssignedIdentityId`, `appInsightsConnectionString`, `pythonVersion` (default `3.11`), `imagesContainerName`, `urlExpirationSeconds` (default 3600).
- **Resources:**
  - `Microsoft.Web/serverfarms@2023-12-01` — `plan-imgupload-${suffix}`, SKU `Y1` (Dynamic), `kind: linux`, `reserved: true`.
  - `Microsoft.Web/sites@2023-12-01` (kind `functionapp,linux`) — `func-imgupload-${suffix}`, `identity.type: UserAssigned`, `userAssignedIdentities: { [id]: {} }`, `httpsOnly: true`, `siteConfig.linuxFxVersion: Python|3.11`, `siteConfig.ftpsState: Disabled`, `siteConfig.minTlsVersion: 1.2`, `siteConfig.use32BitWorkerProcess: false`.
  - `siteConfig.cors.allowedOrigins` = SWA hostname (set post-SWA deploy via a separate deployment script or output substitution; dev = `*`).
  - **App settings:**
    - `AzureWebJobsStorage__accountName` = `<storageAccountName>` (identity-based connection)
    - `AzureWebJobsStorage__credential` = `managedidentity`
    - `AzureWebJobsStorage__clientId` = UAMI client ID
    - `FUNCTIONS_EXTENSION_VERSION` = `~4`
    - `FUNCTIONS_WORKER_RUNTIME` = `python`
    - `WEBSITE_RUN_FROM_PACKAGE` = `1`
    - `APPLICATIONINSIGHTS_CONNECTION_STRING` = passed-in value
    - `STORAGE_ACCOUNT_NAME` = `<storageAccountName>`
    - `IMAGES_CONTAINER_NAME` = `<imagesContainerName>` (default `images`)
    - `URL_EXPIRATION_SECONDS` = `<urlExpirationSeconds>`
    - `AZURE_CLIENT_ID` = UAMI client ID (so `DefaultAzureCredential` picks it deterministically)
- **Outputs:** `functionAppName`, `functionAppDefaultHostName`, `functionAppPrincipalId`, `functionAppResourceId`.
- **Security:** UAMI only (no system-assigned), HTTPS-only, TLS 1.2 min, FTPS disabled.
- **Env differences:** prod sets stricter CORS (specific SWA hostname); dev `*`.

### 5.8 `modules/staticWebApp.bicep`
- **Purpose:** Azure Static Web App (Free SKU) hosting the SPA.
- **Parameters:** `location` (SWA Free is region-constrained; default `eastasia` or `australiaeast` depending on availability — use `eastasia` for guaranteed Free SKU availability nearest AU), `resourceNameSuffix`, `tags`, `apiBaseUrl` (Function App hostname), `repositoryUrl` (optional — empty allows post-deploy upload via SWA CLI / GitHub Action token).
- **Resources:** `Microsoft.Web/staticSites@2023-12-01` — `swa-imgupload-${suffix}`, SKU `Free`, `provider: 'None'` (use deployment token via GH Actions), `appLocation: '/'`, `outputLocation: ''`.
- **Outputs:** `staticWebAppName`, `defaultHostname`, `staticWebAppId`.
- **Security:** Managed TLS, anonymous read for SPA assets; API calls protected by function key.
- **Env differences:** all envs Free SKU.

---

## 6. Application Code Changes

Target path layout (consumed by `code-refactor`):
```
outputs/azure-functions/
  function_app.py
  requirements.txt
  host.json
  local.settings.sample.json
  shared/
    blob_helpers.py
```

All four handlers consolidate into a single `function_app.py` using the **Azure Functions Python v2 programming model** (`@app.route(...)`). Shared blob/SAS logic lives in `shared/blob_helpers.py`.

### 6.1 `UploadFunction` → `upload` (`outputs/azure-functions/function_app.py`)
- **Original file:** `source-app/app-code/lambda/upload/upload_handler.py`
- **Trigger:** HTTP — `route='upload'`, `methods=['POST']`, `auth_level=FUNCTION`.
- **SDK changes:**
  - Remove `boto3` / `botocore`.
  - Add `azure-storage-blob` (≥ 12.19), `azure-identity` (≥ 1.15), `azure-functions` (≥ 1.18).
  - Replace `boto3.client('s3').generate_presigned_url('put_object', ...)` with `azure.storage.blob.generate_blob_sas(...)` using a cached **User Delegation Key** (obtained via `BlobServiceClient(credential=DefaultAzureCredential()).get_user_delegation_key(...)`) and permissions `BlobSasPermissions(write=True, create=True)`.
- **Env vars:**
  - `BUCKET_NAME` → `STORAGE_ACCOUNT_NAME` + `IMAGES_CONTAINER_NAME` (Key Vault reference not needed — these are non-secret).
  - `URL_EXPIRATION` → `URL_EXPIRATION_SECONDS`.
- **Auth pattern:** `DefaultAzureCredential()` resolves to the UAMI in Azure (via `AZURE_CLIENT_ID`).
- **Config:** Add `requirements.txt` entries; `host.json` uses default `logging.applicationInsights` + `extensions.http.routePrefix = "api"`.

### 6.2 `ListFilesFunction` → `list_files` (`function_app.py`)
- **Original file:** `source-app/app-code/lambda/list/list_handler.py`
- **Trigger:** HTTP — `route='files'`, `methods=['GET']`, `auth_level=FUNCTION`.
- **SDK changes:** `boto3 list_objects_v2` → `ContainerClient.list_blobs()`; per-blob `generate_blob_sas(...)` with `read=True` for view URLs.
- **Env vars:** same as 6.1.
- **Auth pattern:** UAMI via `DefaultAzureCredential`.
- **Config:** none additional.

### 6.3 `GetViewUrlFunction` → `get_view_url` (`function_app.py`)
- **Original file:** `source-app/app-code/lambda/view/view_handler.py`
- **Trigger:** HTTP — `route='files/{fileId}/view-url'`, `methods=['GET']`, `auth_level=FUNCTION`.
- **SDK changes:** `generate_presigned_url('get_object')` → `generate_blob_sas(..., permission=BlobSasPermissions(read=True), ...)`.
- **Env vars:** same as 6.1.
- **Auth pattern:** UAMI via `DefaultAzureCredential`.

### 6.4 `DeleteFileFunction` → `delete_file` (`function_app.py`)
- **Original file:** `source-app/app-code/lambda/delete/delete_handler.py`
- **Trigger:** HTTP — `route='files/{fileId}'`, `methods=['DELETE']`, `auth_level=FUNCTION`.
- **SDK changes:** `s3.delete_object(...)` → `BlobClient.delete_blob(delete_snapshots='include')`.
- **Env vars:** `BUCKET_NAME` → `STORAGE_ACCOUNT_NAME` + `IMAGES_CONTAINER_NAME`.
- **Auth pattern:** UAMI via `DefaultAzureCredential`.

### 6.5 Shared module `shared/blob_helpers.py`
- `get_blob_service_client()` — singleton `BlobServiceClient` with `DefaultAzureCredential`.
- `get_user_delegation_key()` — cached for ~6 days; refreshes when within 1 h of expiry.
- `make_sas(blob_name, permissions, ttl_seconds)` — returns full SAS URL.
- `cors_response(body, status=200)` — adds CORS headers matching the SWA origin.

### 6.6 `requirements.txt`
```
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
azure-identity>=1.15.0
```

### 6.7 `host.json`
```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  },
  "extensions": {
    "http": { "routePrefix": "api" }
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20,
        "excludedTypes": "Request"
      }
    }
  }
}
```

---

## 7. Environment Configuration

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `environmentName` | `dev` | `staging` | `prod` |
| `location` | `australiaeast` | `australiaeast` | `australiaeast` |
| Resource group | `rg-imgupload-dev` | `rg-imgupload-staging` | `rg-imgupload-prod` |
| Function plan SKU | `Y1` (Consumption) | `Y1` | `Y1` |
| Storage SKU | `Standard_LRS` | `Standard_LRS` | `Standard_ZRS` |
| Storage CORS allowed origins | `["*"]` | `["https://<swa-staging-host>"]` | `["https://<swa-prod-host>"]` |
| Function App CORS | `["*"]` | `["https://<swa-staging-host>"]` | `["https://<swa-prod-host>"]` |
| Blob versioning | On | On | On |
| Soft delete (blobs / containers) | 7 / 7 days | 7 / 7 days | 14 / 14 days |
| Lifecycle: Hot → Cool | 30 d | 30 d | 30 d |
| Lifecycle: Cool → Archive | 180 d | 180 d | 180 d |
| Log Analytics retention | 30 d | 30 d | 90 d |
| App Insights sampling | 100% | 100% | 5% (via host.json override) |
| Key Vault SKU | `standard` | `standard` | `standard` |
| Key Vault soft-delete retention | 7 d | 7 d | 90 d |
| Key Vault purge protection | off | off | **on** |
| SWA SKU | `Free` | `Free` | `Free` |
| `URL_EXPIRATION_SECONDS` | 3600 | 3600 | 3600 |

Parameter file naming: `infra/main.parameters.<env>.json`.

---

## 8. Security Requirements

### 8.1 Managed Identity & RBAC
- **Identity:** User-Assigned Managed Identity `id-imgupload-<env>` attached to the Function App.
- **Role assignments (least privilege, data-plane only):**

| Role | Scope | Justification |
|---|---|---|
| `Storage Blob Data Contributor` (`ba92f5b4-2d11-453d-a403-e96b0029c9fe`) | Storage account (or just `images` container, preferred) | Read/write blobs |
| `Storage Blob Delegator` (`db58b8e5-c6ad-4a2a-8342-4190687cbf4a`) | Storage account | Required to call `get_user_delegation_key` for SAS minting |
| `Key Vault Secrets User` (`4633458b-17de-408a-b874-0445c86b69e6`) | Key Vault | Read function host key + future app secrets |

### 8.2 Key Vault Secrets (pre-populated before deployment is considered complete)
| Secret name | Purpose | Set by |
|---|---|---|
| `function-host-key` | Function key used by SPA in `x-functions-key` header | Post-Function-deploy step in pipeline (read from Functions admin API, write to KV) |
| `swa-deployment-token` | SWA deployment token | Read from SWA resource output in pipeline |

### 8.3 Network Security
- **No NSGs / VNets** — public endpoints only (cost-driven; workload is internet-facing by design).
- **Storage account:** TLS 1.2 minimum, HTTPS only, public blob access disabled (RBAC + SAS only).
- **Function App:** HTTPS only, TLS 1.2 minimum, FTPS disabled.
- **CORS:** Restricted to SWA hostname for staging/prod; `*` only in dev.

### 8.4 Private Endpoint DNS Zones
- **None** — private endpoints are intentionally excluded for cost reasons. Re-evaluate if compliance later requires VNet integration (would add ~$7/mo per PE + Premium Function plan).

### 8.5 Eliminations vs AWS
- Long-lived static IAM access key `AKIAXZEFIIOD2OIWPRPK` is **removed**. No long-lived secrets in browser or pipelines.

---

## 9. Deployment Order

The `deployment-validation` agent must execute steps in this order:

1. **Pre-flight:** Confirm Azure subscription, region quota, and OIDC federated credential (Section 11.2) are in place.
2. **Infra deploy (workflow `deploy-infra.yml`):**
   1. `az deployment sub create` with `infra/main.bicep` + `main.parameters.<env>.json`.
   2. Wait for completion; capture outputs (`functionAppName`, `storageAccountName`, `staticWebAppName`, `staticWebAppDefaultHostname`).
3. **Function app code deploy (workflow `deploy-functions.yml`):**
   1. `pip install -r requirements.txt --target=.python_packages/lib/site-packages`.
   2. Zip package and deploy via `azure/functions-action@v1` to the Function App from step 2.
   3. Run `az functionapp keys list` to fetch the master/host key.
   4. Store host key into Key Vault secret `function-host-key`.
4. **SWA deploy (workflow `deploy-static-web.yml`):**
   1. Read `function-host-key` from Key Vault and inject as a build-time variable into the SPA bundle (or have the SPA fetch it from a `/config` endpoint — recommended; out of scope for IaC).
   2. Deploy SPA build to SWA via `Azure/static-web-apps-deploy@v1` using the deployment token from KV.
5. **Post-deploy:**
   1. Update Function App CORS + Storage CORS to the SWA hostname (a small `az functionapp cors add` and `az storage cors add` step — staging/prod only).
   2. Run smoke tests (Section 10).
6. **Data migration (one-off, cutover):** `azcopy sync s3://image-upload-imagebucket-t8isnbr8sswv https://<storage>.blob.core.windows.net/images?<SAS>` — initial pass, then delta pass at cutover.
7. **Decommission AWS:** `aws cloudformation delete-stack --stack-name image-upload` after 24-h soak.

---

## 10. Validation Checklist

- [ ] `az deployment sub validate` passes for all three environments
- [ ] `bicep build` produces zero warnings/errors
- [ ] Function App reaches `Running` state and `/api/files` returns `200` with `x-functions-key`
- [ ] Calling `/api/upload` returns a SAS URL with `sig` query param and 1-h expiry
- [ ] `PUT` to SAS URL from `curl` succeeds; object appears in `images` container with a version
- [ ] `/api/files` lists the uploaded blob and includes a SAS view URL
- [ ] `GET` of the view URL returns the blob bytes
- [ ] `DELETE /api/files/{id}` removes the blob (soft-deleted, recoverable for 7 d)
- [ ] App Insights shows request + dependency telemetry for all 4 routes
- [ ] Log Analytics workspace receives traces within 5 minutes
- [ ] SWA serves SPA over HTTPS at `https://<swa-host>`
- [ ] Browser-driven end-to-end test (upload → list → view → delete) passes
- [ ] CORS reject test: a request from `https://evil.example` is blocked by Function App + Storage in staging/prod
- [ ] Confirm no public blob access (`az storage blob list --auth-mode login` works; anonymous `curl` to blob URL returns 404/AuthFailed)
- [ ] Confirm UAMI has exactly the 3 role assignments listed in Section 8.1 and nothing more
- [ ] Confirm no IAM-style long-lived credentials exist in any GitHub secret

---

## 11. CI/CD Pipeline Architecture

### 11.1 Pipeline Overview

| Workflow File | Trigger | Purpose | Target Azure Service |
|---|---|---|---|
| `.github/workflows/deploy-infra.yml` | Push to `main` touching `infra/**`; `workflow_dispatch` with `environment` input | Deploy Bicep IaC at subscription scope | Resource Group + all resources |
| `.github/workflows/deploy-functions.yml` | Push to `main` touching `outputs/azure-functions/**`; `workflow_dispatch` | Build & deploy Function App package | Azure Functions |
| `.github/workflows/deploy-static-web.yml` | Push to `main` touching `visualizer/**` or `source-app/app-code/build/**`; `workflow_dispatch` | Build & deploy SPA | Azure Static Web Apps |

### 11.2 Authentication Strategy

- **Method:** OIDC / Workload Identity Federation. No long-lived secrets in GitHub.
- **GitHub Secrets required (per environment):**

| Secret Name | Value Source | Scope | Used By |
|---|---|---|---|
| `AZURE_CLIENT_ID` | App registration client ID with federated credential | Environment (dev/staging/prod) | All workflows |
| `AZURE_TENANT_ID` | Azure AD tenant ID | Repo | All workflows |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID | Environment | All workflows |
| `AZURE_KEYVAULT_NAME` | `kv-imgupload-<env>` | Environment | `deploy-functions.yml`, `deploy-static-web.yml` |
| `AZURE_FUNCTIONAPP_NAME` | `func-imgupload-<env>` | Environment | `deploy-functions.yml` |
| `AZURE_STATIC_WEB_APP_NAME` | `swa-imgupload-<env>` | Environment | `deploy-static-web.yml` |
| `AZURE_RESOURCE_GROUP` | `rg-imgupload-<env>` | Environment | All workflows |

- **Federated credential subject filter** (on app registration):
  - `repo:<org>/ai-assisted-aws-to-azure-migration:environment:dev`
  - `repo:<org>/ai-assisted-aws-to-azure-migration:environment:staging`
  - `repo:<org>/ai-assisted-aws-to-azure-migration:environment:prod`
- **RBAC role assignments** required on the service principal:

| Role | Scope | Purpose |
|---|---|---|
| `Contributor` | Subscription (or RG `rg-imgupload-<env>`) | Create/update resources via Bicep |
| `User Access Administrator` | RG `rg-imgupload-<env>` | Create RBAC role assignments inside `modules/rbac.bicep` |
| `Key Vault Secrets Officer` | KV `kv-imgupload-<env>` | Write `function-host-key` and `swa-deployment-token` |
| `Website Contributor` | Function App | Deploy code package |

### 11.3 Per-Workflow Specification

#### 11.3.1 `.github/workflows/deploy-infra.yml`
- **Trigger conditions:**
  - `push` on `main` with `paths: ['infra/**', '.github/workflows/deploy-infra.yml']`
  - `workflow_dispatch` with input `environment` (choice: dev | staging | prod)
- **Environment protection:** GitHub environment `<env>` — staging/prod require reviewer approval.
- **Jobs and steps (single job `deploy`):**
  1. `actions/checkout@v4`
  2. `azure/login@v2` with `client-id`, `tenant-id`, `subscription-id`, `enable-AzPSSession: false` (OIDC).
  3. `azure/arm-deploy@v2` — `scope: subscription`, `region: australiaeast`, `template: infra/main.bicep`, `parameters: infra/main.parameters.${{ inputs.environment }}.json environmentName=${{ inputs.environment }}`, `deploymentMode: Incremental`, `deploymentName: imgupload-${{ inputs.environment }}-${{ github.run_id }}`.
  4. Capture deployment outputs into job outputs (`functionAppName`, `storageAccountName`, `staticWebAppName`, `defaultHostname`).
- **Commands (exact flags):**
  ```bash
  az deployment sub create \
    --name "imgupload-${ENV}-${GITHUB_RUN_ID}" \
    --location australiaeast \
    --template-file infra/main.bicep \
    --parameters infra/main.parameters.${ENV}.json \
    --parameters environmentName=${ENV}
  ```
- **Secrets / env vars:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- **Artifact handling:** Upload `bicep build` ARM JSON as artifact `arm-template-${{ inputs.environment }}` (optional, for audit).
- **Rollback:** On failure, run `az deployment sub show` for the deployment, then `az deployment group delete` is **not** triggered automatically (Azure deployments are additive; rollback = redeploy previous Git SHA via `workflow_dispatch`).

#### 11.3.2 `.github/workflows/deploy-functions.yml`
- **Trigger conditions:** `push` on `main` with `paths: ['outputs/azure-functions/**', '.github/workflows/deploy-functions.yml']`; `workflow_dispatch` with input `environment`.
- **Environment protection:** Requires `deploy-infra` success for that env (uses `workflow_run` dependency or `needs: deploy-infra` if combined).
- **Jobs and steps:**
  1. `actions/checkout@v4`.
  2. `actions/setup-python@v5` with `python-version: '3.11'`.
  3. `pip install --target=".python_packages/lib/site-packages" -r outputs/azure-functions/requirements.txt`.
  4. `azure/login@v2` (OIDC).
  5. `azure/functions-action@v1` with `app-name: ${{ secrets.AZURE_FUNCTIONAPP_NAME }}`, `package: outputs/azure-functions`, `scm-do-build-during-deployment: false`, `enable-oryx-build: false`.
  6. Fetch host key and store in Key Vault:
     ```bash
     KEY=$(az functionapp keys list -n "$FUNCTIONAPP_NAME" -g "$RG" --query functionKeys.default -o tsv)
     az keyvault secret set --vault-name "$KV_NAME" --name function-host-key --value "$KEY"
     ```
- **Secrets / env vars:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_FUNCTIONAPP_NAME`, `AZURE_RESOURCE_GROUP`, `AZURE_KEYVAULT_NAME`.
- **Artifact handling:** Build artifact `function-package-${{ inputs.environment }}.zip` retained for 14 days.
- **Rollback:** Redeploy previous successful artifact via `workflow_dispatch` + `run_id` input that downloads the prior artifact.

#### 11.3.3 `.github/workflows/deploy-static-web.yml`
- **Trigger conditions:** `push` on `main` with `paths: ['visualizer/**', 'source-app/app-code/build/**', '.github/workflows/deploy-static-web.yml']`; `workflow_dispatch` with `environment`.
- **Environment protection:** Requires `deploy-functions` success (so `function-host-key` exists in KV).
- **Jobs and steps:**
  1. `actions/checkout@v4`.
  2. `actions/setup-node@v4` with `node-version: '20'`.
  3. Build SPA: `cd visualizer && npm ci && npm run build`.
  4. `azure/login@v2` (OIDC).
  5. Fetch SWA deployment token + Function key:
     ```bash
     SWA_TOKEN=$(az staticwebapp secrets list -n "$SWA_NAME" -g "$RG" --query properties.apiKey -o tsv)
     FUNC_KEY=$(az keyvault secret show --vault-name "$KV_NAME" --name function-host-key --query value -o tsv)
     echo "::add-mask::$SWA_TOKEN"
     echo "::add-mask::$FUNC_KEY"
     ```
  6. Write SPA config file with `VITE_API_BASE_URL` and `VITE_FUNCTION_KEY` (latter only if not using a runtime `/config` endpoint).
  7. `Azure/static-web-apps-deploy@v1` with `azure_static_web_apps_api_token: $SWA_TOKEN`, `repo_token: ${{ secrets.GITHUB_TOKEN }}`, `action: 'upload'`, `app_location: 'visualizer/dist'`, `output_location: ''`, `skip_app_build: true`.
- **Secrets / env vars:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_STATIC_WEB_APP_NAME`, `AZURE_RESOURCE_GROUP`, `AZURE_KEYVAULT_NAME`.
- **Artifact handling:** Upload `visualizer/dist` as artifact `spa-build-${{ inputs.environment }}`.
- **Rollback:** SWA supports staging slots; redeploy previous Git SHA to swap.

### 11.4 Multi-Environment Strategy

- **Branch / tag strategy:** Single `main` branch; environment progression via `workflow_dispatch` (and optionally tag-based for prod: `v*.*.*` triggers prod deploy).
- **Environment secrets separation:** Secrets bound to GitHub environments `dev`, `staging`, `prod`. Each environment has its own `AZURE_CLIENT_ID` (federated credential subject filter constrains which env each app registration can deploy to).
- **Approval gates:**
  - `dev` — no approval (auto-deploy on push to `main`).
  - `staging` — 1 reviewer required.
  - `prod` — 2 reviewers required + 10-minute wait timer + restricted to `main` branch.

### 11.5 Pipeline Dependency Order

```
deploy-infra.yml   ──►   deploy-functions.yml   ──►   deploy-static-web.yml
   (Bicep)              (code + KV host key)            (SPA + reads KV)
```

1. **`deploy-infra.yml`** must succeed first (creates Function App, Storage, KV, SWA shells).
2. **`deploy-functions.yml`** runs after infra; deploys code and writes `function-host-key` into KV.
3. **`deploy-static-web.yml`** runs last; reads `function-host-key` from KV and the SWA deployment token, then publishes the SPA.

A failure in any step halts downstream stages for that environment.
