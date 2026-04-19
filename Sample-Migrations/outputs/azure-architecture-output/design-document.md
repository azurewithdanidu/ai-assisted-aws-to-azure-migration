# Azure Architecture Design Document

**Document Version:** 1.0  
**Date:** 2026-04-18  
**Source AWS Account:** 535002891143 (arinco-bootcamp-2025)  
**Source Region:** ap-southeast-2 (Sydney)  
**Target Azure Region:** australiaeast (Sydney — same geographic zone)  
**Prepared by:** Azure Architect Agent  

---

## 1. Executive Summary

This document specifies the complete Azure target architecture for migrating the **Image Upload Service** from AWS to Azure. The source application is a minimal serverless workload — four Python 3.11 Lambda functions fronted by API Gateway REST and backed by S3 — deployed from a single CloudFormation stack (`image-upload`) in `ap-southeast-2`. The migration is a lift-and-shift with targeted SDK refactoring: `boto3` is replaced with `azure-storage-blob`, AWS SigV4 authentication is replaced with Azure Functions HTTP triggers with CORS handled by the Function App `siteConfig.cors` setting, and S3 pre-signed URLs are replaced with Azure Blob SAS tokens. The target architecture uses Azure Functions (Consumption, Python 3.11), Azure Blob Storage, Azure Static Web Apps, Log Analytics, and Application Insights — all provisioned by Azure Bicep. Total estimated Azure cost is **~$3–5/month** versus the current AWS spend of **~$5–7.50/month**, a 30–60% reduction at demo scale.

---

## 2. AWS Discovery Summary

All facts sourced from `outputs/aws-migration-artifacts/aws-inventory.json` and `migration-assessment.md`.

**Account & Scope**
- AWS Account: `535002891143` (arinco-bootcamp-2025)
- Primary region: `ap-southeast-2`; all other enabled regions are empty
- CloudFormation stack: `image-upload` (status: CREATE_COMPLETE, created 2026-01-14)
- Total discovered resources: 30 (active application resources: 13; legacy/orphaned: 7)

**Active Application Resources**

| Service | Resource Name | Count | Config |
|---|---|---|---|
| AWS Lambda | UploadFunction | 1 | python3.11, 256 MB, 30 s, handler: `upload_handler.lambda_handler` |
| AWS Lambda | ListFilesFunction | 1 | python3.11, 256 MB, 30 s, handler: `list_handler.lambda_handler` |
| AWS Lambda | GetViewUrlFunction | 1 | python3.11, 256 MB, 30 s, handler: `view_handler.lambda_handler` |
| AWS Lambda | DeleteFileFunction | 1 | python3.11, 256 MB, 30 s, handler: `delete_handler.lambda_handler` |
| API Gateway | image-upload-api (REST, Regional) | 1 | 4 routes + 4 OPTIONS (CORS), auth: AWS_IAM (SigV4), stage: dev |
| S3 | image-upload-imagebucket-t8isnbr8sswv | 1 | Private, versioning ON, CORS ALL methods, public access block full |
| S3 | image-upload-websitebucket-vd866vxtcs1z | 1 | Public website, index: app.html, error: error.html |
| IAM Role | image-upload-LambdaExecutionRole | 1 | AWSLambdaBasicExecutionRole + inline S3Access (PutObject, GetObject, DeleteObject, ListBucket) |
| IAM Role | ApiGatewayCloudWatchLogsRole | 1 | AmazonAPIGatewayPushToCloudWatchLogs |
| IAM User | image-upload-api-user | 1 | Access key AKIAXZEFIIOD2OIWPRPK; inline policy: execute-api:Invoke |
| CloudFormation | image-upload stack | 1 | Manages all 13 application resources |
| CloudWatch | Log groups (Lambda + API GW) | 5 | Active; 0–75 KB stored |
| VPC | Default VPC | 1 | Not used by Lambda (public endpoints) |

**Lambda Environment Variables**

| Function | Variable | Value |
|---|---|---|
| Upload, List, View | `BUCKET_NAME` | `image-upload-imagebucket-t8isnbr8sswv` |
| Upload, List, View | `URL_EXPIRATION` | `3600` |
| Delete | `BUCKET_NAME` | `image-upload-imagebucket-t8isnbr8sswv` |

**API Gateway Routes**

| Method | Path | Backend Lambda | Auth |
|---|---|---|---|
| POST | /upload | UploadFunction | AWS_IAM |
| GET | /files | ListFilesFunction | AWS_IAM |
| GET | /files/{fileId}/view-url | GetViewUrlFunction | AWS_IAM |
| DELETE | /files/{fileId} | DeleteFileFunction | AWS_IAM |
| OPTIONS | /upload, /files, /files/{fileId}, /files/{fileId}/view-url | MOCK (CORS preflight) | NONE |

**Legacy / Orphaned (not migrated)**
- 2× AppStream S3 buckets (fleet decommissioned June 2025)
- 2× CloudWatch alarms (INSUFFICIENT_DATA, AppStream fleet deleted)
- 5× residual CloudWatch log groups from prior deployment iterations
- 1× KMS CMK (not used by S3 — SSE-S3 default only)

---

## 3. Azure Service Mapping

| AWS Service | AWS Config | Azure Equivalent | Azure Config | Migration Notes |
|---|---|---|---|---|
| AWS Lambda (4 functions) | python3.11, 256 MB, 30 s, Zip | Azure Functions v4 (Consumption plan) | python3.11, single Function App, `function_app.py` | SDK rewrite: boto3 → azure-storage-blob; pre-signed URLs → SAS tokens; one `function_app.py` hosts all 4 functions as `@app.route()` decorators |
| API Gateway REST (AWS_IAM) | Regional, SigV4, 4 routes + CORS | Azure Functions HTTP Triggers (direct) | 4 HTTP-triggered functions in single `function_app.py`; CORS handled by Function App `siteConfig.cors` setting | SigV4 eliminated; no APIM layer; frontend calls `https://{resourceNamePrefix}-func.azurewebsites.net/api/{route}` directly; CORS wildcard configured in Bicep `siteConfig.cors.allowedOrigins` |
| S3 Image Bucket (private, versioned) | Standard, versioning ON, CORS ALL, public access block | Azure Blob Storage | Standard LRS, container `images`, blob versioning ON, CORS rules applied at account level | `generate_presigned_url/post` → `generate_blob_sas`; `BUCKET_NAME` env var → `BLOB_CONTAINER_NAME` (CONTAINER_NAME is reserved by Azure Functions host) |
| S3 Website Bucket (public, static) | Index: app.html | Azure Static Web Apps (Free tier) | `staticwebapp.config.json` with route `/` → `/app.html` | index.html is the SWA default — must add routes config to serve app.html as root |
| IAM Role (LambdaExecutionRole) | Managed + inline S3 policy | System-Assigned Managed Identity + RBAC | `Storage Blob Data Contributor` on `images` container | No code change for identity; managed identity is automatic on Function App |
| IAM User (image-upload-api-user) + Access Key | execute-api:Invoke | N/A — eliminated | No equivalent needed | Long-lived static credential removed; frontend calls Function App directly with no API key in the request |
| CloudWatch Logs | 5 log groups | Log Analytics Workspace + Application Insights | Auto-integrated via `APPLICATIONINSIGHTS_CONNECTION_STRING` | No code changes — Python `logging` and `print()` stream automatically to App Insights |
| CloudWatch Alarms | AppStream auto-scaling (legacy) | Azure Monitor Metric Alerts | Not migrated — AppStream resources are decommissioned | Delete in AWS post-migration |
| CloudFormation | image-upload stack | Azure Bicep | `bicep-templates/main.bicep` + modules | Bicep templates already exist in workspace; validated and ready |
| KMS CMK | Not used by active stack | Key Vault (optional) | Microsoft-managed key (default) — no CMK required | No action needed |

---

## 4. Target Architecture

```mermaid
graph TB
    subgraph Client["Client (Browser)"]
        FE["Web Browser\nSPA — app.html"]
    end

    subgraph SWA["Azure Static Web Apps (Free)"]
        STATIC["Static Web App\nimg-upload-dev-swa\naustraliaeast\nRoute: / → /app.html"]
    end

    subgraph FuncApp["Azure Functions (Consumption, Python 3.11)"]
        FUNC["Function App\nimg-upload-dev-func\nSystem-Assigned Managed Identity\nRuntime: python 3.11\nCORS: siteConfig.cors (allowedOrigins: *)\nApp Insights: connected"]
        FN_UPLOAD["upload_image()\nHTTP POST /api/upload\nGenerates Blob SAS write URL"]
        FN_LIST["list_files()\nHTTP GET /api/files\nLists blobs + SAS read URLs"]
        FN_VIEW["get_view_url()\nHTTP GET /api/files/{fileId}/view-url\nSAS read URL for specific blob"]
        FN_DELETE["delete_file()\nHTTP DELETE /api/files/{fileId}\nDeletes blob by prefix"]
        FUNC --> FN_UPLOAD
        FUNC --> FN_LIST
        FUNC --> FN_VIEW
        FUNC --> FN_DELETE
    end

    subgraph Storage["Azure Storage Account (Standard LRS)"]
        STORE["Storage Account\nimg-upload-dev-store\nVersioning: ON\nCORS: ALL methods, *"]
        CONTAINER["Blob Container: images\n(private access)"]
        STORE --> CONTAINER
    end

    subgraph KV["Azure Key Vault (Standard)"]
        VAULT["Key Vault\nimg-upload-dev-kv\nSoft-delete: ON\nPurge protection: ON\nFor future secrets"]
    end

    subgraph Monitor["Azure Monitor / Application Insights"]
        AI["Application Insights\nimg-upload-dev-ai\naustraliaeast"]
        LAW["Log Analytics Workspace\nimg-upload-dev-law\n30 day retention (dev)"]
        AI --> LAW
    end

    subgraph RBAC["Identity & Access (RBAC)"]
        MI["System-Assigned Managed Identity\nFunction App principal\nRole: Storage Blob Data Contributor\nScope: images container"]
    end

    %% User loads frontend
    FE -->|"HTTPS"| STATIC

    %% SPA calls Function App directly
    FE -->|"HTTPS — direct Function App URL"| FUNC

    %% Functions access Blob Storage via Managed Identity
    FN_UPLOAD  -->|"generate_blob_sas (write)\nBLOB_CONTAINER_NAME env var"| CONTAINER
    FN_LIST    -->|"list_blobs + generate_blob_sas (read)"| CONTAINER
    FN_VIEW    -->|"list_blobs + generate_blob_sas (read)"| CONTAINER
    FN_DELETE  -->|"delete_blob"| CONTAINER

    %% Identity
    FUNC -->|"assumes"| MI
    MI   -->|"RBAC: Storage Blob Data Contributor"| CONTAINER

    %% Key Vault
    FUNC -->|"reads secrets (if needed)"| VAULT

    %% Monitoring
    FUNC -->|"telemetry + logs"| AI
```

**Component Description**

- **Azure Static Web Apps (Free):** Replaces the S3 website bucket. Serves `app.html` as the SPA. A `staticwebapp.config.json` file routes `/` to `/app.html`. HTTPS is enforced automatically.
- **Azure Functions (Consumption, Python 3.11):** Four functions in a single `function_app.py` replace the four Lambda functions. HTTP trigger replaces API Gateway + Lambda proxy integration. CORS is handled by the Function App `siteConfig.cors` setting (no APIM layer). System-Assigned Managed Identity replaces IAM role. Frontend calls the Function App directly at `https://{resourceNamePrefix}-func.azurewebsites.net/api/{route}`.
- **Azure Blob Storage (Standard LRS):** Replaces the S3 image bucket. Container `images` is private. Blob versioning is enabled. CORS allows all methods and origins, matching the S3 configuration. SAS tokens replace S3 pre-signed URLs.
- **Azure Key Vault (Standard):** Available for storing application secrets. Managed Identity on Function App has `Key Vault Secrets User` RBAC role.
- **Log Analytics + Application Insights:** Replace CloudWatch Logs and X-Ray. Connected automatically via `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting on the Function App.

---

## 5. Infrastructure as Code Specification

All Bicep modules are in `bicep-templates/modules/`. The root template is `bicep-templates/main.bicep`. The templates are already drafted in the workspace and validated.

---

### 5.1 Root Template (`bicep-templates/main.bicep`)

- **Purpose:** Subscription-scoped orchestration; deploys all modules in dependency order; assigns RBAC.
- **Parameters:**

| Name | Type | Allowed Values | Default | Description |
|---|---|---|---|---|
| `location` | string | any Azure region | `australiaeast` | Azure region for all resources |
| `environment` | string | `dev`, `staging`, `prod` | `dev` | Controls resource sizing and naming |
| `workloadName` | string | — | `img-upload` | Prefix for all resource names |
| `storageSkuName` | string | `Standard_LRS`, `Standard_ZRS`, `Standard_GRS`, `Standard_RAGRS` | `Standard_LRS` | Blob storage replication |
| `logRetentionDays` | int | 7–730 | `30` | Log Analytics retention |
| `urlExpirationSeconds` | string | — | `3600` | SAS token TTL (mirrors `URL_EXPIRATION`) |

- **Modules deployed (in order):** `monitoring` → `storage` + `staticWebApp` (parallel) → `keyvault` → `functions` → RBAC assignment
- **Resources:** `Microsoft.Authorization/roleAssignments@2022-04-01` — Storage Blob Data Contributor on images container
- **Outputs:** `functionAppUrl`, `staticWebAppUrl`, `storageAccountName`

---

### 5.2 Monitoring Module (`bicep-templates/modules/monitoring.bicep`)

- **Purpose:** Deploys Log Analytics Workspace and Application Insights. Must deploy first — `appInsightsConnectionString` is consumed by the functions module.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `location` | string | Azure region |
| `environment` | string | dev / staging / prod |
| `resourceNamePrefix` | string | e.g. `img-upload-dev` |
| `logRetentionDays` | int | Retention days for Log Analytics |

- **Resources:**
  - `Microsoft.OperationalInsights/workspaces@2022-10-01` — `${resourceNamePrefix}-law`
  - `Microsoft.Insights/components@2020-02-02` — `${resourceNamePrefix}-ai` (kind: web, Application_Type: web, linked to LAW)
- **Outputs:** `appInsightsConnectionString` (string), `appInsightsInstrumentationKey` (string), `logAnalyticsWorkspaceId` (string)
- **Security requirements:** N/A (monitoring-only)
- **Environment differences:** `logRetentionDays` — dev: 30, staging: 60, prod: 90

---

### 5.3 Storage Module (`bicep-templates/modules/storage.bicep`)

- **Purpose:** Deploys Azure Blob Storage account and `images` container. Replaces the S3 image bucket.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `location` | string | Azure region |
| `environment` | string | dev / staging / prod |
| `resourceNamePrefix` | string | e.g. `img-upload-dev` |
| `skuName` | string | Storage SKU (`Standard_LRS`, `Standard_ZRS`, etc.) |

- **Resources:**
  - `Microsoft.Storage/storageAccounts@2023-01-01` — `${take(toLower(replace(resourceNamePrefix, '-', '')), 24)}store` (max 24 chars, alphanumeric only)
    - kind: `StorageV2`, sku: `{name: skuName}`
    - enableBlobVersioning: `true` (mirrors S3 versioning)
    - allowBlobPublicAccess: `false`
    - minimumTlsVersion: `TLS1_2`
    - supportsHttpsTrafficOnly: `true`
    - cors rules: AllowedOrigins `['*']`, AllowedMethods `['GET','PUT','POST','HEAD','DELETE','OPTIONS']`, AllowedHeaders `['*']`, ExposedHeaders `['*']`, MaxAgeInSeconds `3000` (mirrors S3 CORS config)
  - `Microsoft.Storage/storageAccounts/blobServices@2023-01-01` — `default` (with versioning enabled)
  - `Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01` — `images` (publicAccess: None)
- **Outputs:** `storageAccountName` (string), `storageAccountResourceId` (string), `containerName` (string = `'images'`), `blobEndpoint` (string)
- **Security requirements:** `allowBlobPublicAccess: false`; no anonymous read access; HTTPS only; TLS 1.2 minimum
- **Environment differences:** SKU — dev: `Standard_LRS`, staging: `Standard_ZRS`, prod: `Standard_GRS`

---

### 5.4 Static Web App Module (`bicep-templates/modules/staticweb.bicep`)

- **Purpose:** Deploys Azure Static Web Apps. Replaces the S3 website bucket.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `location` | string | Azure region (SWA supports limited regions; use `eastasia` or `eastus2` if `australiaeast` not available) |
| `environment` | string | dev / staging / prod |
| `resourceNamePrefix` | string | e.g. `img-upload-dev` |

- **Resources:**
  - `Microsoft.Web/staticSites@2022-09-01` — `${resourceNamePrefix}-swa`
    - sku: `{name: 'Free', tier: 'Free'}`
    - properties: `{}`
- **Outputs:** `staticWebAppUrl` (string), `staticWebAppDefaultHostname` (string), `staticWebAppId` (string)
- **Security requirements:** HTTPS enforced by default; no additional config required
- **Environment differences:** All environments use Free tier for this workload

---

### 5.5 Key Vault Module (`bicep-templates/modules/keyvault.bicep`)

- **Purpose:** Deploys Azure Key Vault for storing application secrets and future sensitive configuration.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `location` | string | Azure region |
| `environment` | string | dev / staging / prod |
| `resourceNamePrefix` | string | e.g. `img-upload-dev` |
| `functionAppPrincipalId` | string | Object ID of Function App managed identity |

- **Resources:**
  - `Microsoft.KeyVault/vaults@2023-07-01` — `${take(resourceNamePrefix, 18)}-kv`
    - sku: `{family: 'A', name: 'standard'}`
    - enableSoftDelete: `true`, softDeleteRetentionInDays: `7` (dev), `90` (prod)
    - enablePurgeProtection: `true`
    - enableRbacAuthorization: `true`
  - `Microsoft.Authorization/roleAssignments@2022-04-01` — Key Vault Secrets User on vault, principal: `functionAppPrincipalId`
- **Outputs:** `keyVaultName` (string), `keyVaultUri` (string), `keyVaultResourceId` (string)
- **Security requirements:** RBAC authorization mode (not access policies); purge protection enabled; soft-delete enabled; no public network restrictions needed for demo (add private endpoint for prod)
- **Environment differences:** `softDeleteRetentionInDays` — dev: 7, staging: 7, prod: 90

---

### 5.6 Functions Module (`bicep-templates/modules/functions.bicep`)

- **Purpose:** Deploys App Service Plan (Consumption Y1), storage account for Function App internals, and the Function App. Replaces all 4 Lambda functions.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `location` | string | Azure region |
| `environment` | string | dev / staging / prod |
| `resourceNamePrefix` | string | e.g. `img-upload-dev` |
| `imagesStorageAccountName` | string | Name of the images blob storage account (from storage module output) |
| `imagesContainerName` | string | Blob container name (= `'images'`) |
| `urlExpirationSeconds` | string | SAS token TTL in seconds (= `'3600'`) |
| `appInsightsConnectionString` | string | From monitoring module output |

- **Resources:**
  - `Microsoft.Storage/storageAccounts@2023-01-01` — `${take(toLower(replace(resourceNamePrefix, '-', '')), 20)}funcst` (Function App internal storage — distinct from images storage)
  - `Microsoft.Web/serverfarms@2022-09-01` — `${resourceNamePrefix}-asp` (kind: `functionapp`, sku: `{name: 'Y1', tier: 'Dynamic'}`)
  - `Microsoft.Web/sites@2022-09-01` — `${resourceNamePrefix}-func`
    - kind: `functionapp,linux`
    - identity: `{type: 'SystemAssigned'}`
    - siteConfig:
      - `linuxFxVersion: 'Python|3.11'`
      - `pythonVersion: '3.11'`
      - appSettings:
        - `AzureWebJobsStorage`: func storage account connection string
        - `FUNCTIONS_EXTENSION_VERSION`: `~4`
        - `FUNCTIONS_WORKER_RUNTIME`: `python`
        - `APPLICATIONINSIGHTS_CONNECTION_STRING`: from monitoring output
        - `BLOB_STORAGE_ACCOUNT_NAME`: images storage account name (**NOT** `CONTAINER_NAME`)
        - `BLOB_CONTAINER_NAME`: `images` (**NOT** `CONTAINER_NAME` — reserved by host)
        - `URL_EXPIRATION`: value of `urlExpirationSeconds` parameter
        - `AZURE_STORAGE_ACCOUNT_NAME`: images storage account name (for `DefaultAzureCredential` Blob client)
        - `cors`: `siteConfig.cors.allowedOrigins: ['*']` — CORS handled at Function App host level (no manual `Access-Control-Allow-Origin` headers needed in function code)
- **Outputs:** `functionAppName` (string), `functionAppPrincipalId` (string — managed identity object ID), `functionAppHostname` (string), `functionAppResourceId` (string)
- **Security requirements:** System-Assigned Managed Identity enabled; no long-lived storage connection strings for data plane (managed identity used for blob access); HTTPS only
- **Environment differences:** SKU `Y1` (Consumption) for all environments in this workload; `linuxFxVersion` always `Python|3.11`

---

### 5.8 RBAC Module (`bicep-templates/modules/rbac.bicep`)

- **Purpose:** Assigns `Storage Blob Data Contributor` RBAC role to the Function App managed identity on the `images` blob container. Replaces the IAM inline S3Access policy.
- **Parameters:**

| Name | Type | Description |
|---|---|---|
| `storageAccountName` | string | Images storage account name |
| `containerName` | string | Container name (`images`) |
| `functionAppPrincipalId` | string | Object ID of Function App managed identity |

- **Resources:**
  - `Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01` (existing reference)
  - `Microsoft.Authorization/roleAssignments@2022-04-01`
    - roleDefinitionId: `ba92f5b4-2d11-453d-a403-e96b0029c9fe` (Storage Blob Data Contributor)
    - principalId: `functionAppPrincipalId`
    - principalType: `ServicePrincipal`
    - scope: container resource ID
- **Outputs:** `roleAssignmentId` (string)
- **Security requirements:** Scoped to container (not storage account) — principle of least privilege
- **Environment differences:** Same role assignment for all environments

---

## 6. Application Code Changes

All four Lambda functions must be rewritten as Azure Functions in a single `function_app.py` in `outputs/azure-functions/`. The Azure Functions v2 programming model is used (decorator-based HTTP triggers, suitable for Python 3.11 + Functions runtime v4).

---

### 6.1 UploadFunction → `upload_image()` (`outputs/azure-functions/function_app.py`)

- **Original file:** `app-code/lambda/upload/upload_handler.py`
- **Trigger type:** HTTP trigger — `POST /upload`
- **SDK changes:**

| AWS (boto3) | Azure (azure-storage-blob) |
|---|---|
| `import boto3` | `from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions` |
| `import botocore` | `from azure.identity import DefaultAzureCredential` |
| `boto3.client('s3', config=s3_config)` | `BlobServiceClient(account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net", credential=DefaultAzureCredential())` |
| `s3_client.generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)` | `generate_blob_sas(account_name, container_name, blob_name, account_key=None, credential=udk, permission=BlobSasPermissions(write=True, create=True), expiry=datetime.utcnow()+timedelta(seconds=URL_EXPIRATION))` — returns SAS token; full URL = `https://{account}.blob.core.windows.net/{container}/{blob}?{sas}` |
| `generate_presigned_post` (returns `url` + `fields` dict) | SAS URL (single URL, PUT method, no form fields) — **client integration changes**: frontend must PUT directly to SAS URL instead of POST multipart to pre-signed POST URL |
| `BUCKET_NAME = os.environ['BUCKET_NAME']` | `BLOB_CONTAINER_NAME = os.environ['BLOB_CONTAINER_NAME']` |
| `event.get('body')` | `req.get_body().decode()` → `json.loads(...)` |
| `return { 'statusCode': 200, 'headers': {...}, 'body': json.dumps(...) }` | `return func.HttpResponse(json.dumps(...), status_code=200, headers={'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'})` |

- **Environment variables:**

| Old Name | New Name | Value Source |
|---|---|---|
| `BUCKET_NAME` | `BLOB_CONTAINER_NAME` | App setting (Bicep parameter `imagesContainerName` = `'images'`) |
| `URL_EXPIRATION` | `URL_EXPIRATION` | App setting (Bicep parameter `urlExpirationSeconds` = `'3600'`) |
| N/A | `AZURE_STORAGE_ACCOUNT_NAME` | App setting (images storage account name) |

- **Auth pattern:** `DefaultAzureCredential()` — picks up System-Assigned Managed Identity automatically in Azure; uses `AZURE_CLIENT_ID/TENANT_ID/CLIENT_SECRET` from environment when running locally.
- **SAS generation note:** Use `UserDelegationKey` (obtained from `BlobServiceClient.get_user_delegation_key()`) for SAS tokens — avoids need for storage account key in code. Alternatively use `generate_sas` with `DefaultAzureCredential` via the account key retrieved from Key Vault. For simplest implementation: retrieve account key from storage account via ARM or Key Vault secret, and use `generate_blob_sas(account_name=..., account_key=..., ...)`.
- **Configuration changes:**
  - `requirements.txt`: add `azure-functions`, `azure-storage-blob`, `azure-identity`
  - `host.json`: `{ "version": "2.0", "logging": { "applicationInsights": { "samplingSettings": { "isEnabled": true } } } }`

---

### 6.2 ListFilesFunction → `list_files()` (`outputs/azure-functions/function_app.py`)

- **Original file:** `app-code/lambda/list/list_handler.py`
- **Trigger type:** HTTP trigger — `GET /files`
- **SDK changes:**

| AWS (boto3) | Azure (azure-storage-blob) |
|---|---|
| `s3_client.list_objects_v2(Bucket=BUCKET_NAME, MaxKeys=max_keys, Prefix=prefix)` | `container_client.list_blobs(name_starts_with=prefix)` — returns an iterable of `BlobProperties` |
| `s3_client.head_object(Bucket, Key)` → metadata dict | `blob_client.get_blob_properties()` → `.metadata` dict |
| `s3_client.generate_presigned_url('get_object', Params={...}, ExpiresIn=...)` | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), expiry=...)` → SAS URL |
| `s3_client.get_object_tagging(Bucket, Key)` → `TagSet` | Azure Blob tags (key-value): `blob_client.get_blob_tags()` → dict |
| `response['Contents']` — check for key existence | Check `list(blobs)` is non-empty |
| `obj['LastModified'].isoformat()` | `blob.last_modified.isoformat()` |
| `obj['Size']` | `blob.size` |
| `event.get('queryStringParameters')` | `req.params.get('prefix', '')`, `req.params.get('maxKeys', '50')` |

- **Environment variables:** Same as UploadFunction — `BLOB_CONTAINER_NAME`, `URL_EXPIRATION`, `AZURE_STORAGE_ACCOUNT_NAME`
- **Auth pattern:** `DefaultAzureCredential()` via `BlobServiceClient`
- **Configuration changes:** Same `requirements.txt` additions as above

---

### 6.3 GetViewUrlFunction → `get_view_url()` (`outputs/azure-functions/function_app.py`)

- **Original file:** `app-code/lambda/view/view_handler.py`
- **Trigger type:** HTTP trigger — `GET /files/{fileId}/view-url`
- **SDK changes:**

| AWS (boto3) | Azure (azure-storage-blob) |
|---|---|
| `s3_client.list_objects_v2(Bucket, Prefix=f"{file_id}/", MaxKeys=1)` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` — take first result |
| `s3_client.head_object(Bucket, Key)` | `blob_client.get_blob_properties()` |
| `s3_client.generate_presigned_url('get_object', ...)` | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), ...)` |
| `event.get('pathParameters', {}).get('fileId')` | `req.route_params.get('fileId')` |

- **Environment variables:** Same as above
- **Auth pattern:** `DefaultAzureCredential()`
- **Route registration:** `@app.route(route="files/{fileId}/view-url", methods=["GET"])` — Azure Functions v2 decorator model

---

### 6.4 DeleteFileFunction → `delete_file()` (`outputs/azure-functions/function_app.py`)

- **Original file:** `app-code/lambda/delete/delete_handler.py`
- **Trigger type:** HTTP trigger — `DELETE /files/{fileId}`
- **SDK changes:**

| AWS (boto3) | Azure (azure-storage-blob) |
|---|---|
| `s3_client.list_objects_v2(Bucket, Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| `s3_client.delete_object(Bucket=BUCKET_NAME, Key=obj['Key'])` | `container_client.get_blob_client(blob_name).delete_blob()` |
| `event.get('pathParameters', {}).get('fileId')` | `req.route_params.get('fileId')` |
| Returns `deletedKeys` list with S3 key names | Returns `deletedBlobs` list with blob names |

- **Environment variables:** `BLOB_CONTAINER_NAME`, `AZURE_STORAGE_ACCOUNT_NAME` (`URL_EXPIRATION` not needed for delete)
- **Auth pattern:** `DefaultAzureCredential()`
- **Route registration:** `@app.route(route="files/{fileId}", methods=["DELETE"])`

---

**`requirements.txt` (complete)**

```
azure-functions
azure-storage-blob>=12.19.0
azure-identity>=1.15.0
```

**`host.json` (complete)**

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

---

## 7. Environment Configuration

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `location` | `australiaeast` | `australiaeast` | `australiaeast` |
| `environment` | `dev` | `staging` | `prod` |
| `workloadName` | `img-upload` | `img-upload` | `img-upload` |
| `storageSkuName` | `Standard_LRS` | `Standard_ZRS` | `Standard_GRS` |
| `logRetentionDays` | `30` | `60` | `90` |
| `urlExpirationSeconds` | `3600` | `3600` | `3600` |
| Functions SKU | Consumption (Y1) | Consumption (Y1) | Premium (EP1) — if low cold-start needed |
| Key Vault soft-delete days | `7` | `7` | `90` |

**Parameter files:** `bicep-templates/parameters/dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam`

---

## 8. Security Requirements

**Managed Identity**
- System-Assigned Managed Identity on `${resourceNamePrefix}-func` (Function App)
- RBAC assignment: `Storage Blob Data Contributor` (role ID `ba92f5b4-2d11-453d-a403-e96b0029c9fe`) on `images` container (not at storage account level — least privilege)
- RBAC assignment: `Key Vault Secrets User` on Key Vault (for reading secrets if needed)

**CORS Configuration**
- CORS is handled by the Function App `siteConfig.cors` setting in Bicep. Set `allowedOrigins: ['*']` for dev/staging; restrict to Static Web Apps hostname in prod.
- Do NOT add `Access-Control-Allow-Origin` headers manually in function responses — the Function App host injects them automatically when `siteConfig.cors` is configured.

**Environment Variables — CRITICAL CONSTRAINT**
- `CONTAINER_NAME` is **reserved** by the Azure Functions host. Do **NOT** use it. Use `BLOB_CONTAINER_NAME` instead.
- `WEBSITE_*` prefix is reserved. Do not use it for custom app settings.
- `FUNCTIONS_*` prefix is reserved (except `FUNCTIONS_WORKER_RUNTIME` which is intentional).

**Storage Security**
- `allowBlobPublicAccess: false` — all blob access via SAS tokens only
- `minimumTlsVersion: TLS1_2`
- `supportsHttpsTrafficOnly: true`
- CORS wildcard is acceptable for demo; restrict to Static Web Apps hostname in prod

**Python Runtime**
- Azure Functions v4 supports Python **3.9, 3.10, 3.11 ONLY**
- Do NOT use Python 3.12 or 3.13 — crashes worker with `0xC0000005` Access Violation
- `linuxFxVersion` must be `Python|3.11`

**Network Security Groups**
- No VNet integration required for Consumption plan Functions
- For prod hardening: consider Functions Premium with VNet integration + private endpoint on storage

**Actions after migration**
- Rotate/invalidate AWS IAM access key `AKIAXZEFIIOD2OIWPRPK` (currently exposed in CloudFormation stack outputs)
- Delete CloudFormation stack `image-upload` to remove all AWS resources
- Delete AppStream orphaned S3 buckets and CloudWatch alarms

---

## 9. Deployment Order

1. **Create Resource Group** — `az group create --name img-upload-dev-rg --location australiaeast`
2. **Deploy monitoring module** — Log Analytics Workspace and Application Insights (all other modules depend on App Insights connection string)
3. **Deploy storage module** (parallel with step 4) — Blob Storage account + `images` container
4. **Deploy Static Web App module** (parallel with step 3) — `${resourceNamePrefix}-swa`
5. **Deploy Key Vault module** — Requires Function App principal ID; deploy after functions OR deploy vault first then assign role post-functions
6. **Deploy Functions module** — Depends on storage account name (step 3 output) and App Insights connection string (step 2 output); emits `functionAppPrincipalId`
7. **Assign RBAC** — Storage Blob Data Contributor on `images` container, principal = `functionAppPrincipalId` from step 6
8. **Upload frontend** — Deploy `app.html` + `staticwebapp.config.json` to Static Web Apps using SWA CLI or GitHub Actions
9. **Update frontend API URL** — Replace AWS API Gateway URL with the Function App URL (`https://{resourceNamePrefix}-func.azurewebsites.net/api/{route}`) in `app.html`; rebuild and redeploy to SWA

> **Root Bicep orchestrates steps 2–7 automatically** when deployed via `az deployment group create`. Steps 1, 8–9 are manual or handled by CI/CD.

---

## 10. Validation Checklist

Post-deployment smoke tests the deployment-validation agent must run:

- [ ] `curl -X POST https://{resourceNamePrefix}-func.azurewebsites.net/api/upload -H "Content-Type: application/json" -d '{"fileName":"test.jpg","fileType":"image/jpeg"}' → HTTP 200, body contains `uploadUrl`
- [ ] PUT a test file to the `uploadUrl` SAS URL → HTTP 201 (Azure Blob PUT success)
- [ ] `curl https://{resourceNamePrefix}-func.azurewebsites.net/api/files` → HTTP 200, body contains `files` array with at least 1 item including `viewUrl`
- [ ] `curl https://{resourceNamePrefix}-func.azurewebsites.net/api/files/{fileId}/view-url` → HTTP 200, body contains `viewUrl` with SAS token
- [ ] GET to `viewUrl` (no auth header needed — SAS is in query string) → HTTP 200, image bytes returned
- [ ] `curl -X DELETE https://{resourceNamePrefix}-func.azurewebsites.net/api/files/{fileId}` → HTTP 200, body contains `deletedBlobs`
- [ ] `curl https://{resourceNamePrefix}-func.azurewebsites.net/api/files` → HTTP 200, deleted file no longer appears in `files` array
- [ ] Application Insights `requests` table in Log Analytics shows traces for all 4 function invocations (KQL: `requests | where timestamp > ago(30m) | project name, resultCode, duration`)
- [ ] Static Web App URL loads `app.html` over HTTPS without redirect errors
- [ ] Confirm `CONTAINER_NAME` app setting does NOT exist on the Function App (reserved variable)
- [ ] Confirm Function App runtime is Python 3.11 (Azure Portal → Function App → Configuration → `linuxFxVersion` = `Python|3.11`)
- [ ] Confirm no storage account keys are present in Function App app settings (all blob access via managed identity)
- [ ] Confirm CORS preflight `OPTIONS` requests to Function App return `Access-Control-Allow-Origin: *` (from `siteConfig.cors` setting)

---

## 11. CI/CD Pipeline Architecture

### 11.1 Pipeline Overview

| Workflow File | Trigger | Purpose | Target Azure Service |
|---|---|---|---|
| `.github/workflows/deploy-infra.yml` | Push to `main` / manual `workflow_dispatch` | Deploy Bicep IaC (resource group + all modules) | Resource Group, Storage, Functions, Key Vault, SWA, Monitoring |
| `.github/workflows/deploy-functions.yml` | Push to `main` (changes under `outputs/azure-functions/**`) / manual | Build Python package and deploy to Azure Functions | Azure Functions App |
| `.github/workflows/deploy-static-web.yml` | Push to `main` (changes under `outputs/static-web-app/**` or `app-code/build/**`) / manual | Deploy static frontend assets | Azure Static Web Apps |

### 11.2 Authentication Strategy

- **Method:** OIDC / Workload Identity Federation — no long-lived credentials stored as GitHub secrets
- **Setup:** Create an Azure AD App Registration with a federated credential for each environment / branch combination

**GitHub Secrets Required**

| Secret Name | Value Source | Used By |
|---|---|---|
| `AZURE_CLIENT_ID` | App Registration Application (client) ID | All workflows |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | All workflows |
| `AZURE_SUBSCRIPTION_ID` | Target Azure Subscription ID | All workflows |
| `AZURE_RESOURCE_GROUP` | Target Resource Group name (e.g. `img-upload-dev-rg`) | deploy-infra.yml, deploy-functions.yml |
| `STATIC_WEB_APP_TOKEN` | Azure Static Web Apps deployment token (from portal or `az staticwebapp secrets list`) | deploy-static-web.yml |

**Federated Credential Subject Filter** (configure on the App Registration):
```
repo:arinco-bootcamp-2025/ai-assisted-aws-to-azure-migration:ref:refs/heads/main
```
For PR validation (if used):
```
repo:arinco-bootcamp-2025/ai-assisted-aws-to-azure-migration:pull_request
```

**RBAC Role Assignments for the Service Principal**
- `Contributor` on Resource Group `img-upload-dev-rg` — for Bicep deployments
- `Role Based Access Control Administrator` on Resource Group — for assigning managed identity RBAC roles (alternatively use `--assign-identity` scoped flag)
- `Storage Blob Data Contributor` — NOT needed for CI/CD principal; this is for the Function App managed identity only

### 11.3 Per-Workflow Specification

#### 11.3.1 `.github/workflows/deploy-infra.yml`

- **Trigger conditions:**
  ```yaml
  on:
    push:
      branches: [main]
      paths:
        - 'bicep-templates/**'
        - '.github/workflows/deploy-infra.yml'
    workflow_dispatch:
      inputs:
        environment:
          description: 'Target environment'
          required: true
          default: 'dev'
          type: choice
          options: [dev, staging, prod]
  ```
- **Environment protection rules:** `dev` — no approval; `staging` — 1 required reviewer; `prod` — 2 required reviewers
- **Jobs and Steps:**
  1. **Checkout** — `actions/checkout@v4`
  2. **Azure Login (OIDC)** — `azure/login@v2` with `client-id: ${{ secrets.AZURE_CLIENT_ID }}`, `tenant-id: ${{ secrets.AZURE_TENANT_ID }}`, `subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}`
  3. **Bicep What-If (validation)** — `az deployment group what-if --resource-group ${{ secrets.AZURE_RESOURCE_GROUP }} --template-file bicep-templates/main.bicep --parameters bicep-templates/parameters/dev.bicepparam`
  4. **Bicep Deploy** — `az deployment group create --resource-group ${{ secrets.AZURE_RESOURCE_GROUP }} --template-file bicep-templates/main.bicep --parameters bicep-templates/parameters/dev.bicepparam --name deploy-${{ github.run_number }}`
  5. **Output Function App URL** — capture `az deployment group show` output (`functionAppUrl`), set as step output for downstream workflows
- **Secrets and env vars:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`
- **Artifact handling:** No build artifacts; Bicep files read directly from repo
- **Rollback strategy:** Re-run previous successful deployment by re-running the workflow at a prior commit SHA; Bicep is idempotent — re-deploying the previous tag restores the prior state

#### 11.3.2 `.github/workflows/deploy-functions.yml`

- **Trigger conditions:**
  ```yaml
  on:
    push:
      branches: [main]
      paths:
        - 'outputs/azure-functions/**'
        - '.github/workflows/deploy-functions.yml'
    workflow_dispatch:
  ```
- **Environment protection rules:** Same as deploy-infra.yml
- **Jobs and Steps:**
  1. **Checkout** — `actions/checkout@v4`
  2. **Setup Python 3.11** — `actions/setup-python@v5` with `python-version: '3.11'`
  3. **Install dependencies** — `pip install -r outputs/azure-functions/requirements.txt --target outputs/azure-functions/.python_packages/lib/site-packages`
  4. **Azure Login (OIDC)** — `azure/login@v2`
  5. **Deploy to Azure Functions** — `azure/functions-action@v1` with `app-name: img-upload-dev-func`, `package: outputs/azure-functions`, `scm-do-build-during-deployment: false`  
     OR use `az functionapp deployment source config-zip` with a zipped package
  6. **Smoke test** — `curl -f https://img-upload-dev-func.azurewebsites.net/api/files` (expect 200 or 401 if auth enabled)
- **Secrets and env vars:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`
- **Artifact handling:** Package `outputs/azure-functions/` directory; upload as artifact after install step for debugging
- **Rollback strategy:** Re-run workflow at prior commit SHA; Azure Function deployment is atomic — prior version restorable via deployment slots (if Premium) or re-deploy

#### 11.3.3 `.github/workflows/deploy-static-web.yml`

- **Trigger conditions:**
  ```yaml
  on:
    push:
      branches: [main]
      paths:
        - 'outputs/static-web-app/**'
        - 'app-code/build/**'
        - '.github/workflows/deploy-static-web.yml'
    workflow_dispatch:
  ```
- **Environment protection rules:** No approval gate for dev (SWA deployment is instant and reversible)
- **Jobs and Steps:**
  1. **Checkout** — `actions/checkout@v4`
  2. **Deploy to Azure Static Web Apps** — `Azure/static-web-apps-deploy@v1` with:
     - `azure_static_web_apps_api_token: ${{ secrets.STATIC_WEB_APP_TOKEN }}`
     - `repo_token: ${{ secrets.GITHUB_TOKEN }}`
     - `action: upload`
     - `app_location: outputs/static-web-app` (or `app-code/build` — whichever contains `app.html` + `staticwebapp.config.json`)
     - `skip_app_build: true`
     - `output_location: ''`
  3. **Verify deployment** — `curl -f https://{swa-hostname}.azurestaticapps.net/app.html → HTTP 200`
- **Secrets and env vars:** `STATIC_WEB_APP_TOKEN`
- **Artifact handling:** No build step — static HTML/JS deployed as-is
- **Rollback strategy:** Azure Static Web Apps keeps prior deployments in history; revert via portal or re-run workflow at prior commit
- **Important:** `staticwebapp.config.json` must exist in the deployed folder with content:
  ```json
  {
    "navigationFallback": {
      "rewrite": "/app.html"
    },
    "routes": [
      { "route": "/", "rewrite": "/app.html" }
    ]
  }
  ```

### 11.4 Multi-Environment Strategy

**Branch / Tag Strategy**
- `main` branch → deploys to **dev** environment automatically on push
- `release/*` tags → deploys to **staging** (via `workflow_dispatch` with `environment: staging` or dedicated branch trigger)
- `v*` release tags (e.g. `v1.0.0`) → deploys to **prod** (requires 2 approvals via GitHub Environments)

**Environment Secrets Separation**
- Each GitHub Environment (`dev`, `staging`, `prod`) has its own secrets:
  - `AZURE_CLIENT_ID` — separate App Registration per environment (recommended) or federated credential per environment on a single registration
  - `AZURE_RESOURCE_GROUP` — `img-upload-dev-rg` / `img-upload-staging-rg` / `img-upload-prod-rg`
  - `STATIC_WEB_APP_TOKEN` — separate SWA instance per environment

**Approval Gates**
- `dev`: No approval — auto-deploys on push to `main`
- `staging`: 1 required reviewer (any team member)
- `prod`: 2 required reviewers (must include team lead)

**Bicep Parameter Files**
- Dev: `bicep-templates/parameters/dev.bicepparam`
- Staging: `bicep-templates/parameters/staging.bicepparam`
- Prod: `bicep-templates/parameters/prod.bicepparam`

The workflow selects the parameter file based on the `environment` input:
```yaml
- name: Deploy Bicep
  run: |
    az deployment group create \
      --resource-group ${{ secrets.AZURE_RESOURCE_GROUP }} \
      --template-file bicep-templates/main.bicep \
      --parameters bicep-templates/parameters/${{ inputs.environment }}.bicepparam
```

### 11.5 Pipeline Dependency Order

1. **`deploy-infra.yml`** must succeed first — provisions all Azure resources including Function App and SWA
2. **`deploy-functions.yml`** must run after `deploy-infra.yml` — requires Function App to exist; can run in parallel with `deploy-static-web.yml`
3. **`deploy-static-web.yml`** must run after `deploy-infra.yml` — requires Static Web App to exist; can run parallel with `deploy-functions.yml`
4. Manual step: after all three workflows succeed, confirm the Function App URL (`https://{resourceNamePrefix}-func.azurewebsites.net/api`) is referenced in `app.html`; re-run `deploy-static-web.yml` if the URL was updated

> For initial setup, trigger in order: infra → functions → static web. Subsequent deployments can trigger individual workflows independently based on which paths changed.
