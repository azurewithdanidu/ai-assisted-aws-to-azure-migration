# Service Mapping: AWS → Azure — Image Upload Service

**Prepared:** 2026-06-24
**AWS Account:** 535002891143 | **Region:** ap-southeast-2
**Target:** Azure australiasoutheast
**CloudFormation Stack:** image-upload (CREATE_COMPLETE)

---

## Summary Table

| # | AWS Service | AWS Resource Name | Count | Complexity | Azure Equivalent | Azure Resource Name | Migration Notes |
|---|---|---|---|---|---|---|---|
| 1 | AWS Lambda | UploadFunction | 1 | Medium | Azure Functions (HTTP trigger) | `upload_function` in `img-upload-func` | boto3 s3.generate_presigned_post → azure-storage-blob generate_blob_sas(write) |
| 2 | AWS Lambda | ListFilesFunction | 1 | Medium | Azure Functions (HTTP trigger) | `list_function` in `img-upload-func` | 4 boto3 calls → azure-storage-blob equivalents; N+1 head+tags pattern preserved |
| 3 | AWS Lambda | GetViewUrlFunction | 1 | Medium | Azure Functions (HTTP trigger) | `view_function` in `img-upload-func` | list_objects_v2 + generate_presigned_url → list_blobs + generate_blob_sas(read) |
| 4 | AWS Lambda | DeleteFileFunction | 1 | Medium | Azure Functions (HTTP trigger) | `delete_function` in `img-upload-func` | delete_object → delete_blob; s3v4 config dropped |
| 5 | Amazon S3 | ImageBucket | 1 | Medium | Azure Blob Storage | Container `images` in `imguploadstore` | Versioning, CORS, SSE, public-block all replicated |
| 6 | Amazon S3 (static) | WebsiteBucket | 1 | Low | Azure Static Web Apps | `img-upload-swa` | HTTPS added; SPA deployment via GitHub Actions |
| 7 | Amazon API Gateway | image-upload-api | 1 | Medium | Azure Functions HTTP triggers (built-in routing) | Built into `img-upload-func` | AWS_IAM auth removed; CORS configured on Function App |
| 8 | AWS IAM Role | LambdaExecutionRole | 1 | Low | Azure Managed Identity + RBAC | System-assigned MI on `img-upload-func` | Storage Blob Data Contributor on `imguploadstore` |
| 9 | AWS IAM User | image-upload-api-user | 1 | High | Azure Entra ID App Registration (SPA) | `img-upload-spa-app` | Long-lived key must NOT be replicated; PKCE/OAuth2 flow |
| 10 | Amazon CloudWatch Logs | 5 log groups | 5 | Low | Azure Monitor Log Analytics + App Insights | `img-upload-law`, `img-upload-ai` | 30-day retention; KQL replaces CloudWatch Logs Insights |
| 11 | AWS X-Ray | Default sampling rule | 1 | Low | Azure Application Insights | `img-upload-ai` | Full end-to-end tracing (better than PassThrough X-Ray) |
| 12 | AWS CloudFormation | image-upload stack | 1 | Low | Azure Bicep | `main.bicep` + modules | Stack outputs → Bicep outputs; parameters preserved |

---

## Detailed Service Mappings

### 1–4. AWS Lambda → Azure Functions

#### Overview

| Attribute | AWS Lambda | Azure Functions |
|---|---|---|
| Runtime | Python 3.11 | Python 3.11 |
| Architecture | x86_64 | x64 |
| Memory | 256 MB | 256 MB (configurable) |
| Timeout | 30 seconds | 230 seconds (HTTP trigger) |
| Hosting model | Serverless (invocation-based) | Consumption Plan Y1 (invocation-based) |
| Trigger | API Gateway AWS_PROXY | HTTP Trigger (built-in routing) |
| Auth model | AWS_IAM (SigV4) | Anonymous / Azure AD (configurable) |
| Logging | CloudWatch Logs (Text format) | Application Insights + Log Analytics |
| Tracing | X-Ray PassThrough | Application Insights (auto-instrumented) |
| Cold start | ~100–400 ms (Python) | ~500–800 ms (Python, Consumption) |
| Pricing | $0.20/million + $0.0000166667/GB-s | $0.20/million + $0.000016/GB-s |
| Free tier | 1M req + 400K GB-s/month | 1M req + 400K GB-s/month |

#### Function-by-Function Mapping

##### 1. UploadFunction → upload_function

| Attribute | AWS | Azure |
|---|---|---|
| Handler | `upload_handler.lambda_handler` | `upload_function/function_app.py::upload_function` |
| HTTP method | POST | POST |
| Route | `/upload` (via API GW) | `/api/upload` (Functions routing) |
| Auth | AWS_IAM | Anonymous (CORS + optional Entra JWT) |
| Environment var: bucket | `BUCKET_NAME` | `AZURE_STORAGE_CONTAINER_NAME` |
| Environment var: expiry | `URL_EXPIRATION` (int, seconds) | `URL_EXPIRATION` (int, seconds) |
| Environment var: account | N/A (role-based) | `AZURE_STORAGE_ACCOUNT_NAME` |
| SDK import | `boto3` + `botocore.config.Config` | `azure.storage.blob` + `azure.identity` |
| Presign method | `s3.generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)` | `generate_blob_sas(account_name, container_name, blob_name, account_key=None, credential=managed_identity, permission=BlobSasPermissions(write=True, create=True), expiry=...)` |
| Tags on upload | `x-amz-tagging` field in presigned POST | NOT inline in SAS; must call `set_blob_tags()` after client upload confirmation |
| Metadata | `x-amz-meta-*` fields in presigned POST | Azure Blob user-defined metadata (`metadata={}` on BlobClient) |
| Response fields | `uploadUrl`, `uploadFields`, `fileId`, `s3Key` | `uploadUrl` (SAS URL), `fileId`, `blobName`, `expiresIn` |
| Client upload method | Browser POSTs multipart form to S3 presigned POST URL | Browser PUTs binary body directly to Blob SAS URL (`x-ms-blob-type: BlockBlob`) |

**Migration note — Critical difference:** S3 presigned POST uses a multipart HTML form with many fields. Azure Blob SAS upload uses a simple HTTP PUT with the file body. The frontend SPA upload code must be rewritten.

##### 2. ListFilesFunction → list_function

| Attribute | AWS | Azure |
|---|---|---|
| Handler | `list_handler.lambda_handler` | `list_function/function_app.py::list_function` |
| HTTP method | GET | GET |
| Route | `/files?prefix=&maxKeys=` (via API GW) | `/api/files?prefix=&maxKeys=` |
| Auth | AWS_IAM | Anonymous |
| SDK: list objects | `s3.list_objects_v2(Bucket, MaxKeys, Prefix)` | `container_client.list_blobs(name_starts_with=prefix, results_per_page=max_keys)` |
| SDK: get metadata | `s3.head_object(Bucket, Key)` → `.Metadata` | `blob_client.get_blob_properties()` → `.metadata` |
| SDK: get tags | `s3.get_object_tagging(Bucket, Key)` → `.TagSet` | `blob_client.get_blob_tags()` → `{key: value}` |
| SDK: presign read URL | `s3.generate_presigned_url('get_object', Params={Bucket, Key}, ExpiresIn)` | `generate_blob_sas(account_name, container_name, blob_name, permission=BlobSasPermissions(read=True), expiry=...) → sas_token` then `f"https://{account}.blob.core.windows.net/{container}/{blob}?{sas_token}"` |
| Tag format | `[tag['Value'] for tag in TagSet]` | `list(tags.values())` |
| Metadata keys | `originalfilename`, `uploaddate`, `description` | `originalfilename`, `uploaddate`, `description` (same keys) |

##### 3. GetViewUrlFunction → view_function

| Attribute | AWS | Azure |
|---|---|---|
| Handler | `view_handler.lambda_handler` | `view_function/function_app.py::view_function` |
| HTTP method | GET | GET |
| Route | `/files/{fileId}/view-url` (via API GW) | `/api/files/{fileId}/view-url` |
| Auth | AWS_IAM | Anonymous |
| SDK: resolve fileId | `s3.list_objects_v2(Bucket, Prefix=f"{file_id}/", MaxKeys=1)` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` → take first |
| SDK: get properties | `s3.head_object(Bucket, Key)` | `blob_client.get_blob_properties()` |
| SDK: presign read URL | `s3.generate_presigned_url('get_object', ...)` | `generate_blob_sas(permission=BlobSasPermissions(read=True), ...)` |
| Response fields | `fileId`, `s3Key`, `fileName`, `fileType`, `description`, `uploadDate`, `size`, `viewUrl`, `expiresIn` | Same fields, `s3Key` renamed to `blobName` |

##### 4. DeleteFileFunction → delete_function

| Attribute | AWS | Azure |
|---|---|---|
| Handler | `delete_handler.lambda_handler` | `delete_function/function_app.py::delete_function` |
| HTTP method | DELETE | DELETE |
| Route | `/files/{fileId}` (via API GW) | `/api/files/{fileId}` |
| Auth | AWS_IAM | Anonymous |
| SDK: list to find blobs | `s3.list_objects_v2(Bucket, Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| SDK: delete | `s3.delete_object(Bucket, Key)` (per object) | `blob_client.delete_blob()` (per blob) |
| s3v4 config | `Config(signature_version='s3v4', s3={'addressing_style': 'virtual'})` | **Drop entirely** — not applicable to Azure |
| Response | `message`, `fileId`, `deletedKeys` | `message`, `fileId`, `deletedBlobs` |

---

### 5. Amazon S3 ImageBucket → Azure Blob Storage

| Attribute | AWS S3 | Azure Blob Storage |
|---|---|---|
| Resource type | Amazon S3 Bucket | Azure Storage Account (StorageV2) + Blob Container |
| Name | `image-upload-imagebucket-t8isnbr8sswv` | Account: `imguploadstore`, Container: `images` |
| Region | ap-southeast-2 | australiasoutheast |
| Versioning | Enabled | Blob versioning: Enabled (on Storage Account) |
| Public access | Fully blocked | Public access: Disabled (default for StorageV2) |
| Encryption | SSE-AES256 (SSE-S3) | Azure Storage SSE (AES-256, Microsoft-managed key) — enabled by default |
| CORS | GET, PUT, POST, HEAD, DELETE from `*`, MaxAge 3000 | Storage Account CORS rule: same methods, `*` origin, maxAgeInSeconds: 3000 |
| Expose headers | ETag, Content-Type, x-amz-* | ETag, Content-Type (x-amz-* headers not applicable) |
| Lifecycle | None | None (add Cool tier lifecycle for prod: move blobs >30 days) |
| Replication | None (single region) | LRS (locally redundant, 3 copies in same datacenter) |
| Object tagging | `s3:PutObjectTagging`, `s3:GetObjectTagging` | Blob Tags (GA) — `set_blob_tags()`, `get_blob_tags()` |
| Object metadata | `x-amz-meta-*` headers | User-defined metadata (dict) — same key-value semantics |
| Presigned URLs | SigV4 presigned URLs (time-limited) | Blob SAS tokens (time-limited) |
| Soft delete | N/A (versioning used) | Blob soft delete: 7 days (recommended) |

**Configuration differences:**
- S3 presigned POST (multipart form upload) → Azure Blob SAS PUT upload (simpler binary PUT)
- S3 tagging via `x-amz-tagging` in presigned POST fields → Azure requires separate `set_blob_tags()` call after upload
- S3 `head_object` for metadata → Azure `get_blob_properties()` (similar semantics)
- S3 `list_objects_v2` with `Prefix` → Azure `list_blobs(name_starts_with=prefix)`

---

### 6. Amazon S3 WebsiteBucket → Azure Static Web Apps

| Attribute | AWS S3 Static Website | Azure Static Web Apps |
|---|---|---|
| Resource type | S3 Bucket + Website configuration | Azure Static Web Apps (Free tier) |
| Name | `image-upload-websitebucket-vd866vxtcs1z` | `img-upload-swa` |
| Index document | `app.html` | `app.html` (configurable in staticwebapp.config.json) |
| Error document | `error.html` | `error.html` |
| Protocol | HTTP only | HTTPS (built-in, free SSL cert) |
| CDN | None | Built-in Azure CDN (global PoPs) |
| Public access | Fully open (bucket policy `s3:GetObject Allow *`) | Public (default for static web apps) |
| Custom domain | No | Yes (free) |
| Auth provider | None (frontend uses IAM user key) | Built-in auth providers (Entra ID, GitHub, etc.) OR Entra App Registration |
| Deployment | `aws s3 cp` | GitHub Actions: `azure/static-web-apps-deploy@v1` |
| Website URL | `http://<bucket>.s3-website-ap-southeast-2.amazonaws.com` | `https://<auto-generated>.azurestaticapps.net` |
| Price | ~$0.50/month | **Free** (Free tier) |

---

### 7. Amazon API Gateway → Azure Functions HTTP Triggers

| Attribute | AWS API Gateway REST API | Azure Functions HTTP Triggers |
|---|---|---|
| Type | REST API (Regional) | HTTP Trigger (built-in routing per function) |
| Name | `image-upload-api (4lrh2l7i86)` | Built into `img-upload-func` Function App |
| Auth | AWS_IAM (SigV4 — all methods) | Anonymous (CORS + optional Entra JWT validation) |
| Stage | `dev` | Function app environment (dev/staging/prod) |
| Routes | `POST /upload`, `GET /files`, `GET /files/{fileId}/view-url`, `DELETE /files/{fileId}` | Same routes prefixed with `/api/` |
| CORS | MOCK OPTIONS methods per resource | `host.json` CORS config: `"allowedOrigins": ["*"]` |
| Logging | DataTrace (full request/response body) | Application Insights request telemetry |
| Tracing | X-Ray (stage-level) | Application Insights (end-to-end, per-function) |
| Throttling | Burst 5000 / Rate 10000 RPS | Consumption plan: no explicit throttle (scale-out) |
| URL format | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` | `https://img-upload-func.azurewebsites.net/api` |

**Migration note:** AWS API Gateway provides centralised auth enforcement (AWS_IAM) that automatically rejects unsigned requests. Azure Functions HTTP triggers default to `authLevel: anonymous`. For production, add Entra ID JWT validation via `azure-functions-authentication` middleware or switch to `authLevel: function` with API keys.

---

### 8. AWS IAM Role (LambdaExecutionRole) → Azure Managed Identity + RBAC

| Attribute | AWS IAM Role | Azure Managed Identity + RBAC |
|---|---|---|
| Type | IAM Role (lambda.amazonaws.com trust) | System-assigned Managed Identity (on Function App) |
| Name | `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` | Auto-created with `img-upload-func` |
| S3 permissions | PutObject, PutObjectTagging, GetObject, GetObjectTagging, DeleteObject, ListBucket | **Storage Blob Data Contributor** (built-in RBAC role) on `imguploadstore` |
| Logging permissions | CreateLogGroup, CreateLogStream, PutLogEvents | Built-in: Azure Functions automatically sends logs to App Insights |
| Scope | `arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv/*` | `/subscriptions/{sub}/resourceGroups/rg-image-upload/providers/Microsoft.Storage/storageAccounts/imguploadstore` |
| Credential type | Temporary STS token (auto-rotated) | Managed Identity token (auto-rotated by Entra ID) |
| SDK auth | `boto3.client('s3')` (uses role automatically) | `DefaultAzureCredential()` → `BlobServiceClient(account_url, credential)` |

**Architecture recommendation:** The original AWS design uses a single shared role for all 4 Lambda functions. In Azure, the Function App has one system-assigned Managed Identity shared by all functions within it. This is equivalent. For maximum least-privilege, consider deploying 4 separate Function Apps with individual MIs — not recommended for dev, but appropriate for high-security production.

---

### 9. AWS IAM User (ApiUser) → Azure Entra ID App Registration

| Attribute | AWS IAM User | Azure Entra ID |
|---|---|---|
| Type | IAM User with long-lived access key | App Registration (SPA client) |
| Name | `image-upload-api-user` | `img-upload-spa-app` |
| Purpose | Frontend SPA signs API requests with SigV4 | Frontend SPA obtains OAuth2 tokens via PKCE flow |
| Credential | Long-lived access key `AKIAXZEFIIOD2OIWPRPK` | **No long-lived secret** — PKCE flow uses short-lived tokens |
| Permission | `execute-api:Invoke` on `4lrh2l7i86/*` | API scope on Function App (or anonymous functions) |
| Security risk | **HIGH** — static key embeddable in JavaScript | **Low** — PKCE flow with short-lived tokens |
| Frontend library | AWS SDK (SigV4 signing) | MSAL.js v2 (`@azure/msal-browser`) |
| Auth flow | Request signing (all headers) | `acquireTokenSilent()` → Bearer token in Authorization header |

**Migration note — Critical:** The long-lived IAM access key `AKIAXZEFIIOD2OIWPRPK` **must not be replicated in Azure**. The frontend SPA must be refactored to use MSAL.js with PKCE. Alternatively, if simplicity is preferred, the Azure Functions can be deployed with `authLevel: anonymous` and CORS restrictions, removing client-side auth entirely (acceptable for a demo environment, not for production).

---

### 10. Amazon CloudWatch Logs → Azure Monitor + Application Insights

| Attribute | AWS CloudWatch Logs | Azure Monitor |
|---|---|---|
| Lambda log groups | 4 log groups (`/aws/lambda/...`) | Application Insights → Function App telemetry (auto) |
| API GW log group | `API-Gateway-Execution-Logs_4lrh2l7i86/dev` | Application Insights → HTTP request telemetry |
| Log format | Text (unstructured) | Structured JSON (Application Insights schema) |
| Retention | None set (unlimited = costly) | 30 days (Log Analytics workspace default) |
| Query language | CloudWatch Logs Insights | KQL (Kusto Query Language) |
| Alarms | None configured | Azure Monitor Alerts (recommend adding) |
| Log volume | ~36 KB total stored | Expected: similar low volume |
| Cost | ~$0.00 (minimal volume) | ~$0.00 (within 5 GB/month free tier) |

**CloudWatch → KQL translation examples:**

| CloudWatch Insights | KQL Equivalent |
|---|---|
| `filter @message like "Error"` | `traces \| where message contains "Error"` |
| `stats count(*) by bin(@timestamp, 5m)` | `requests \| summarize count() by bin(timestamp, 5m)` |
| `filter @type = "REPORT" \| stats avg(@duration)` | `requests \| summarize avg(duration)` |

---

### 11. AWS X-Ray → Azure Application Insights

| Attribute | AWS X-Ray | Azure Application Insights |
|---|---|---|
| Sampling | Default rule: 5% fixed + 1 reservoir | Adaptive sampling (targets ~5 traces/sec) |
| Lambda traces | PassThrough (not captured) | Auto-instrumented (full traces) |
| API GW traces | Enabled on stage `dev` | HTTP request telemetry (auto) |
| Trace propagation | X-Amzn-Trace-Id header | traceparent / W3C Trace Context header |
| Service map | X-Ray Service Map | Application Insights Application Map |
| Query | X-Ray console | Azure Portal / Log Analytics KQL |
| SDK | `aws-xray-sdk` (not in use — PassThrough) | `opencensus-ext-azure` OR `azure-monitor-opentelemetry` |
| Cost | $0.00 (minimal traces, within free tier) | $0.00 (within 5 GB/month free tier) |

---

### 12. AWS CloudFormation → Azure Bicep

| Attribute | AWS CloudFormation | Azure Bicep |
|---|---|---|
| Stack name | `image-upload` | Deployment name: `image-upload` |
| Template file | `template.yaml` | `main.bicep` |
| Modules | Single template (no nested stacks) | 5 modules: `storage.bicep`, `function-app.bicep`, `monitoring.bicep`, `static-web-app.bicep`, `rbac.bicep` |
| Parameters | `Environment` (dev/staging/prod) | `environment`, `location`, `storageAccountName`, `functionAppName`, `staticWebAppName`, `logAnalyticsRetentionDays` |
| Outputs | `ApiUrl`, `BucketName`, `WebsiteUrl`, `WebsiteBucketName`, `ApiUserName`, `ApiUserAccessKeyId` | `functionAppUrl`, `storageAccountName`, `staticWebAppUrl`, `staticWebAppDefaultHostname` |
| Region | ap-southeast-2 | australiasoutheast |
| Deployment scope | Stack (account + region) | Resource Group (`rg-image-upload`) |
| State management | CloudFormation managed | Azure Resource Manager managed |
| Drift detection | CloudFormation Drift Detection | Azure Policy / `az deployment group what-if` |

---

## SDK Package Mapping

| AWS Package | Azure Package | Install Command |
|---|---|---|
| `boto3` | `azure-storage-blob` | `pip install azure-storage-blob` |
| `botocore` | `azure-identity` | `pip install azure-identity` |
| `botocore.config.Config` | N/A (dropped) | — |
| `botocore.exceptions.ClientError` | `azure.core.exceptions.AzureError` | Included with azure-storage-blob |
| `boto3.client('s3')` | `BlobServiceClient(account_url, credential=DefaultAzureCredential())` | — |

## Environment Variable Mapping

| Lambda Variable | Value | Azure Functions Variable | Value Source |
|---|---|---|---|
| `BUCKET_NAME` | `image-upload-imagebucket-t8isnbr8sswv` | `AZURE_STORAGE_CONTAINER_NAME` | `images` (hardcoded in parameters) |
| `URL_EXPIRATION` | `3600` | `URL_EXPIRATION` | `3600` (same default) |
| N/A | N/A | `AZURE_STORAGE_ACCOUNT_NAME` | Bicep output: `storageAccountName` |
| N/A | N/A | `APPLICATIONINSIGHTS_CONNECTION_STRING` | Bicep output: App Insights connection string |

---

## Migration Risk Summary

| AWS Pattern | Risk | Azure Resolution |
|---|---|---|
| S3 presigned POST (multipart form) | **HIGH** — client upload code must change | Azure Blob SAS PUT (simpler — binary body only) |
| AWS_IAM auth (SigV4) | **HIGH** — entire auth model changes | Anonymous functions (dev) or Entra JWT (prod) |
| Long-lived IAM access key in frontend | **CRITICAL** — must not replicate | MSAL.js PKCE flow or anonymous functions |
| `x-amz-tagging` in presigned POST | **MEDIUM** — no SAS equivalent | Separate `set_blob_tags()` call post-upload |
| `botocore.config.Config(s3v4)` | **LOW** — AWS-specific, just drop | Not needed in Azure SDK |
| `x-amz-meta-*` metadata headers | **LOW** — same semantics, different keys | Azure user-defined metadata (`metadata={}`) |
| CORS OPTIONS MOCK methods | **LOW** — replicate as Function App CORS config | `host.json` CORS + Storage Account CORS |
| X-Ray PassThrough tracing | **LOW** — already incomplete | App Insights gives better tracing out of the box |
| No CloudWatch alarms | **LOW** — no alarms to migrate | Add Azure Monitor alerts as new capability |
| HTTP-only static website | **LOW** — security improvement needed | Azure Static Web Apps provides HTTPS automatically |
