# Azure Service Mapping — Image Upload Service

**AWS Account:** 535002891143  
**AWS Region:** ap-southeast-2 (Sydney)  
**Azure Region:** australiaeast (Sydney)  
**Generated:** 2026-04-14  

---

## Overview

This document provides a complete mapping of every AWS service and resource in the `image-upload` application to its Azure equivalent, including configuration differences and migration considerations.

---

## 1. Compute — Lambda → Azure Functions

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS Lambda |
| **Functions** | 4 (UploadFunction, ListFilesFunction, GetViewUrlFunction, DeleteFileFunction) |
| **Runtime** | Python 3.11 |
| **Memory** | 256 MB each |
| **Timeout** | 30 seconds each |
| **Architecture** | x86_64 |
| **Package type** | Zip |
| **Ephemeral storage** | 512 MB |
| **Tracing** | PassThrough (no X-Ray) |
| **Billing model** | Pay-per-invocation + GB-seconds |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Functions |
| **Resource type** | `Microsoft.Web/sites` (kind: `functionapp`) |
| **Plan** | Consumption (Serverless) — `Microsoft.Web/serverfarms` (Dynamic) |
| **Runtime** | Python 3.11 (exact match — no upgrade needed) |
| **Memory** | Up to 1.5 GB (Consumption) — 256 MB equivalent config via `FUNCTIONS_WORKER_PROCESS_COUNT` |
| **Timeout** | Default 5 min, configurable up to 10 min (Consumption) — 30s AWS timeout is well within limits |
| **Architecture** | x64 |
| **Package type** | Zip deploy or Azure Storage deployment package |
| **Temp storage** | 500 MB (Consumption) |
| **Tracing** | Application Insights (auto SDK integration — superior to AWS PassThrough) |
| **Billing model** | Pay-per-execution + GB-seconds (identical model, slightly cheaper per GB-s) |
| **Azure Resource Name** | `img-upload-func` |

### Function Name Mapping

| AWS Lambda | Azure Function | Handler Mapping |
|-----------|---------------|-----------------|
| `image-upload-UploadFunction-iIIJ7xiZECuB` | `upload_function` | `upload_handler.lambda_handler` → `upload_function/function_app.py` |
| `image-upload-ListFilesFunction-Pb0dKq9dR0Is` | `list_files_function` | `list_handler.lambda_handler` → `list_files_function/function_app.py` |
| `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` | `get_view_url_function` | `view_handler.lambda_handler` → `get_view_url_function/function_app.py` |
| `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` | `delete_file_function` | `delete_handler.lambda_handler` → `delete_file_function/function_app.py` |

### Configuration Differences

| Aspect | AWS Lambda | Azure Functions |
|--------|-----------|-----------------|
| Environment variables | `BUCKET_NAME`, `URL_EXPIRATION` | `STORAGE_ACCOUNT_NAME`, `CONTAINER_NAME`, `URL_EXPIRATION_SECONDS` |
| Execution role | IAM Role (explicit ARN) | System-Assigned Managed Identity (automatic) |
| Cold start | Yes (~200–800ms Python) | Yes (~300–600ms Python — comparable) |
| Concurrency | 1000 default (account limit) | 200 default per Function App (adjustable) |
| Triggers | API Gateway → Lambda (event proxy) | APIM → Function HTTP trigger (direct HTTP) |

### Code Changes Required

```python
# AWS (boto3) — BEFORE
import boto3
s3 = boto3.client('s3', region_name='ap-southeast-2')
url = s3.generate_presigned_url('put_object',
    Params={'Bucket': os.environ['BUCKET_NAME'], 'Key': key},
    ExpiresIn=3600)

# Azure (azure-storage-blob) — AFTER
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from datetime import datetime, timedelta, timezone

sas_token = generate_blob_sas(
    account_name=os.environ['STORAGE_ACCOUNT_NAME'],
    container_name=os.environ['CONTAINER_NAME'],
    blob_name=key,
    account_key=os.environ['STORAGE_ACCOUNT_KEY'],  # or use Managed Identity via DefaultAzureCredential
    permission=BlobSasPermissions(write=True),
    expiry=datetime.now(timezone.utc) + timedelta(seconds=int(os.environ['URL_EXPIRATION_SECONDS']))
)
url = f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net/{os.environ['CONTAINER_NAME']}/{key}?{sas_token}"
```

```python
# AWS (boto3) — list objects BEFORE
response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
files = [obj['Key'] for obj in response.get('Contents', [])]

# Azure — list blobs AFTER
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
credential = DefaultAzureCredential()
blob_service = BlobServiceClient(account_url=f"https://{account}.blob.core.windows.net", credential=credential)
container_client = blob_service.get_container_client(container)
files = [blob.name for blob in container_client.list_blobs(name_starts_with=prefix)]
```

---

## 2. API Gateway → Azure API Management

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon API Gateway (REST) |
| **API ID** | `4lrh2l7i86` |
| **Name** | `image-upload-api` |
| **Type** | Regional REST API |
| **Stage** | `dev` |
| **Endpoint** | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` |
| **Auth** | `AWS_IAM` (SigV4 signed requests) |
| **Security policy** | TLS_1_0 |
| **Tracing** | X-Ray enabled (API stage) |
| **Logging** | INFO level, data trace enabled, metrics enabled |
| **Throttling** | 5000 burst, 10000 requests/sec |
| **CORS** | OPTIONS mock integration on all routes |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure API Management |
| **Tier** | Consumption (serverless, pay-per-call) |
| **Resource type** | `Microsoft.ApiManagement/service` |
| **Resource name** | `img-upload-apim` |
| **Endpoint** | `https://img-upload-apim.azure-api.net` |
| **Auth** | Subscription key (`Ocp-Apim-Subscription-Key` header) or Entra ID JWT |
| **Security policy** | TLS 1.2+ (enforced by default — upgrade from TLS 1.0) |
| **Tracing** | Application Insights (built-in APIM diagnostic policy) |
| **Logging** | All operations → Application Insights → Log Analytics |
| **Throttling** | `rate-limit-by-key` policy + `quota-by-key` policy |
| **CORS** | APIM `cors` policy element |

### Route Mapping

| AWS Path | HTTP Method | AWS Auth | Azure Path | Azure Auth | Azure Backend |
|----------|------------|---------|-----------|-----------|---------------|
| `/upload` | POST | AWS_IAM | `/upload` | Subscription Key | `img-upload-func/upload_function` |
| `/files` | GET | AWS_IAM | `/files` | Subscription Key | `img-upload-func/list_files_function` |
| `/files/{fileId}/view-url` | GET | AWS_IAM | `/files/{fileId}/view-url` | Subscription Key | `img-upload-func/get_view_url_function` |
| `/files/{fileId}` | DELETE | AWS_IAM | `/files/{fileId}` | Subscription Key | `img-upload-func/delete_file_function` |
| `/upload` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files/{fileId}/view-url` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files/{fileId}` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |

### Configuration Differences

| Aspect | AWS API Gateway | Azure APIM |
|--------|----------------|-----------|
| Auth mechanism | AWS SigV4 (IAM) | Subscription key or Entra ID JWT |
| Frontend changes | SigV4 signing library required | Add `Ocp-Apim-Subscription-Key` header |
| CORS handling | Manual OPTIONS mock methods per route | Single `cors` policy at API level |
| TLS | TLS 1.0 (insecure) | TLS 1.2+ (secure by default) |
| Caching | Per-method TTL | Per-operation cache policy |
| Rate limiting | Account/stage throttle | Flexible: per-subscription, per-IP, per-user |
| WAF | Requires separate WAF/Shield | Integrates with Azure Front Door WAF |

### APIM CORS Policy

```xml
<cors allow-credentials="false">
    <allowed-origins>
        <origin>*</origin>
        <!-- Recommended: restrict to SWA origin in production -->
        <!-- <origin>https://img-upload-swa.azurestaticapps.net</origin> -->
    </allowed-origins>
    <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>DELETE</method>
        <method>OPTIONS</method>
    </allowed-methods>
    <allowed-headers>
        <header>content-type</header>
        <header>ocp-apim-subscription-key</header>
        <header>authorization</header>
    </allowed-headers>
    <expose-headers>
        <header>ETag</header>
        <header>Content-Type</header>
    </expose-headers>
</cors>
```

---

## 3. S3 (Image Store) → Azure Blob Storage

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon S3 |
| **Bucket** | `image-upload-imagebucket-t8isnbr8sswv` |
| **Region** | ap-southeast-2 |
| **Access** | Private (all public access blocked) |
| **Versioning** | Enabled |
| **CORS** | Enabled — all methods, `*` origins, 3000s max-age |
| **Encryption** | SSE-S3 (AES-256, default) |
| **Lifecycle** | Not configured |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Blob Storage |
| **Resource type** | `Microsoft.Storage/storageAccounts` |
| **Storage account name** | `imguploadstore<unique>` |
| **Container name** | `images` |
| **Account kind** | StorageV2 (General Purpose v2) |
| **Access tier** | Hot |
| **Replication** | LRS (dev) / ZRS (production recommended) |
| **Access** | No public blob access (`allowBlobPublicAccess: false`) |
| **Versioning** | Enabled (`isVersioningEnabled: true`) |
| **Soft delete** | 7 days (blobs + containers) |
| **CORS** | Configured on Blob service — mirrors AWS CORS config |
| **Encryption** | Microsoft-managed keys (equivalent to SSE-S3); optional CMK via Key Vault |
| **Lifecycle** | Hot → Cool (90 days) → Archive (365 days) |
| **TLS** | Minimum TLS 1.2 |

### CORS Configuration

| Property | AWS Value | Azure Value |
|----------|----------|------------|
| Allowed methods | GET, PUT, POST, HEAD, DELETE | GET, PUT, POST, HEAD, DELETE |
| Allowed origins | `*` | `*` (restrict to SWA URL in production) |
| Allowed headers | `*` | `*` |
| Exposed headers | ETag, Content-Type, x-amz-* | ETag, Content-Type (x-amz-* not applicable) |
| Max age (seconds) | 3000 | 3000 |

### Pre-signed URL → SAS Token Mapping

| AWS Concept | Azure Equivalent |
|-------------|-----------------|
| `generate_presigned_url('put_object')` | `generate_blob_sas(permission=BlobSasPermissions(write=True))` |
| `generate_presigned_url('get_object')` | `generate_blob_sas(permission=BlobSasPermissions(read=True))` |
| `ExpiresIn=3600` | `expiry=datetime.now(utc) + timedelta(seconds=3600)` |
| S3 Object Key | Blob Name |
| S3 Bucket | Blob Container |

### Data Migration Command

```bash
# Using AzCopy from S3 to Azure Blob Storage
azcopy copy \
  "https://image-upload-imagebucket-t8isnbr8sswv.s3.ap-southeast-2.amazonaws.com" \
  "https://imguploadstore.blob.core.windows.net/images" \
  --recursive \
  --s2s-preserve-access-tier=false
```

---

## 4. S3 Static Website → Azure Static Web Apps

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon S3 Static Website Hosting |
| **Bucket** | `image-upload-websitebucket-vd866vxtcs1z` |
| **Index document** | `app.html` |
| **Error document** | `error.html` |
| **Public access** | Enabled (bucket policy: public read on `s3:GetObject`) |
| **HTTPS** | Not enforced (HTTP endpoint) |
| **CDN** | None |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Static Web Apps |
| **Resource type** | `Microsoft.Web/staticSites` |
| **Resource name** | `img-upload-swa` |
| **Tier** | Free tier (custom domain, SSL, CDN included) |
| **Index document** | `app.html` |
| **Error document** | `error.html` (configured via `staticwebapp.config.json`) |
| **Public access** | HTTPS only (enforced) |
| **HTTPS** | Built-in SSL certificate (auto-managed) |
| **CDN** | Azure CDN included at no extra cost |
| **Custom domain** | Supported (free SSL) |
| **Deployment** | GitHub Actions, Azure DevOps, or `az staticwebapp deploy` |

### Configuration Differences

| Aspect | AWS S3 Website | Azure Static Web Apps |
|--------|---------------|----------------------|
| HTTP support | HTTP + HTTPS | HTTPS only (secure by default) |
| CDN | Requires CloudFront | Built-in (global CDN) |
| SSL certificate | Requires ACM + CloudFront | Built-in, auto-renewed |
| Custom domain | Route 53 + CloudFront required | Direct in Azure portal |
| Cost | $0.023/GB storage + data transfer | Free tier (100GB bandwidth/month) |
| CORS | N/A (static files) | `staticwebapp.config.json` headers |

### staticwebapp.config.json

```json
{
  "routes": [
    { "route": "/", "rewrite": "/app.html" },
    { "route": "/*", "rewrite": "/app.html" }
  ],
  "responseOverrides": {
    "404": { "rewrite": "/error.html", "statusCode": 404 }
  },
  "globalHeaders": {
    "content-security-policy": "default-src https: 'self'; script-src 'self' 'unsafe-inline'",
    "x-frame-options": "SAMEORIGIN",
    "x-content-type-options": "nosniff"
  }
}
```

---

## 5. IAM Role → Azure Managed Identity + RBAC

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS IAM |
| **Role name** | `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` |
| **Trusted principal** | `lambda.amazonaws.com` |
| **Managed policies** | `AWSLambdaBasicExecutionRole` (CloudWatch Logs write) |
| **Inline policy** | S3Access: `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket` on ImageBucket |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Managed Identity + Azure RBAC |
| **Identity type** | System-Assigned Managed Identity (on Function App) |
| **Logging permissions** | Built-in — Application Insights handles all Function telemetry |
| **Storage permissions** | `Storage Blob Data Contributor` role on `images` container |
| **Scope** | Container-level (not entire storage account — principle of least privilege) |
| **Credentials** | None required — automatic token exchange via Azure AD |

### IAM User → Entra ID App Registration

| Property | AWS | Azure |
|----------|-----|-------|
| **Service** | IAM User | Entra ID App Registration |
| **Resource** | `image-upload-api-user` | `img-upload-app-registration` |
| **Auth method** | Long-lived Access Key + Secret Key | Client Secret or Certificate (short-lived) |
| **Token lifetime** | Permanent (until rotated) | 1 hour (auto-refreshed) |
| **Usage** | SigV4 signing for API Gateway | Bearer token for APIM |
| **Security improvement** | N/A | Eliminates long-lived credential risk |

### Permission Mapping

| AWS IAM Permission | Azure RBAC Role | Scope |
|-------------------|----------------|-------|
| `s3:PutObject` + `s3:GetObject` + `s3:DeleteObject` | `Storage Blob Data Contributor` | `images` container |
| `s3:ListBucket` | `Storage Blob Data Reader` (subset of above) | `images` container |
| `logs:CreateLogGroup` + `logs:PutLogEvents` | Built-in via Application Insights (no role needed) | Function App telemetry |
| `execute-api:Invoke` | APIM Subscription Key or Entra ID scope | APIM product |

---

## 6. CloudWatch → Azure Monitor + Application Insights

### AWS Resources

| Property | Value |
|----------|-------|
| **Service** | Amazon CloudWatch |
| **Log groups** | 8 (4 Lambda + 2 API GW active + 2 legacy) |
| **Alarms** | 2 (AppStream remnants — INSUFFICIENT_DATA, not relevant to app) |
| **X-Ray** | Enabled on API Gateway stage |
| **Metrics** | Default Lambda + API GW metrics |

### Azure Equivalent

| AWS Resource | Azure Equivalent | Notes |
|-------------|-----------------|-------|
| CloudWatch Logs (Lambda) | Application Insights — Traces table | Automatic via Function App host configuration |
| CloudWatch Logs (API GW execution) | APIM Diagnostic Policy → App Insights | Config: `<log-to-eventhub>` or App Insights direct |
| CloudWatch Metrics | Azure Monitor Metrics | Auto-populated for all Azure resources |
| X-Ray traces | Application Insights — Dependencies + Requests | End-to-end distributed tracing |
| CloudWatch Alarms | Azure Monitor Alerts | Action groups → email/Teams/webhook |
| CloudWatch Dashboards | Azure Monitor Workbooks | KQL-based interactive dashboards |

### Azure Observability Stack

| Component | Resource Name | Purpose |
|-----------|--------------|---------|
| Log Analytics Workspace | `img-upload-law` | Central log store for all resources |
| Application Insights | `img-upload-appins` | APM — requests, dependencies, failures, tracing |
| Azure Monitor Alerts | (via LAW) | Error rate, latency, availability alerts |

### Recommended Alerts

```
Alert 1: Function Error Rate
  Condition: exceptions/count > 5 in 5 minutes
  Severity: 2 (Warning)

Alert 2: APIM 5xx Errors
  Condition: ApiManagementRequests (ResponseCode≥500) > 5 in 1 minute
  Severity: 1 (Error)

Alert 3: Storage Latency
  Condition: SuccessE2ELatency > 2000ms average over 5 minutes
  Severity: 3 (Informational)
```

---

## 7. KMS → Azure Key Vault

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS KMS |
| **Key ID** | `6c852b32-93c4-4049-91fe-050814d33c10` |
| **Usage** | Likely AppStream-related (not used by image-upload app directly) |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Key Vault |
| **Resource type** | `Microsoft.KeyVault/vaults` |
| **Resource name** | `img-upload-kv` |
| **SKU** | Standard |
| **Soft delete** | Enabled (90 days) |
| **Purge protection** | Enabled |
| **Access policy** | RBAC (Key Vault Secrets User for Function App Managed Identity) |

### Secrets Stored in Key Vault

| Secret Name | Value Source | Used By |
|------------|-------------|---------|
| `storage-account-key` | Storage Account key | Functions (SAS generation fallback) |
| `apim-subscription-key` | APIM subscription | Frontend / test clients |
| `app-registration-client-secret` | Entra ID App Reg | API consumers |

---

## 8. CloudFormation → Bicep

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS CloudFormation |
| **Stack name** | `image-upload` |
| **Status** | CREATE_COMPLETE |
| **Template size** | ~18,954 bytes |
| **Resources managed** | ~20 resources |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Resource Manager (Bicep) |
| **Main template** | `main.bicep` |
| **Modules** | 6 (storage, functions, apim, staticweb, keyvault, monitoring) |
| **Parameters** | `environment` (dev/staging/prod), `location`, `uniqueSuffix` |
| **Deployment** | `az deployment group create` or GitHub Actions |

### CloudFormation → Bicep Parameter Mapping

| CloudFormation Parameter | Bicep Parameter | Type | Default |
|-------------------------|----------------|------|---------|
| `Environment` (dev/staging/prod) | `environment` | string | `'dev'` |
| `AWS::Region` (implicit) | `location` | string | `resourceGroup().location` |
| `AWS::StackName` (implicit for naming) | `appName` | string | `'img-upload'` |
| `AWS::AccountId` (implicit) | N/A (Bicep uses subscription ID) | — | — |

### Bicep Module Structure

```
bicep-templates/
├── main.bicep                    # Orchestrates all modules
├── parameters/
│   ├── dev.bicepparam            # Dev environment params
│   ├── staging.bicepparam        # Staging params
│   └── prod.bicepparam           # Production params
└── modules/
    ├── storage.bicep             # Replaces: ImageBucket + versioning + CORS + lifecycle
    ├── functions.bicep           # Replaces: 4x Lambda + LambdaExecutionRole + permissions
    ├── apim.bicep                # Replaces: ImageUploadApi + all routes/methods/stage/auth
    ├── staticweb.bicep           # Replaces: WebsiteBucket + WebsiteBucketPolicy
    ├── keyvault.bicep            # Replaces: KMS key (partially)
    └── monitoring.bicep          # Replaces: CloudWatch log groups + alarms
```

---

## 9. Services Not Migrated (No Azure Equivalent Needed)

| AWS Resource | Reason |
|-------------|--------|
| AppStream 2.0 buckets, IAM roles, CW alarms | Service decommissioned — delete from AWS, no Azure equivalent required |
| AWS Organizations service-linked role | Account-level AWS construct — no migration needed |
| AWS Resource Explorer service-linked role | AWS-specific service — no equivalent required |
| AWS Trusted Advisor / Support roles | AWS-specific managed services — no migration needed |
| API Gateway CloudWatch logging role | Not needed in Azure — APIM diagnostics use built-in integration |
| IAM Access Key for API User | Eliminated entirely — replaced with short-lived Entra ID tokens |

---

## 10. Security Improvement Summary

| # | AWS Weakness | Azure Improvement | Priority |
|---|-------------|------------------|----------|
| 1 | IAM User + long-lived access key for API auth | Entra ID Service Principal with client secret (1hr tokens) | **HIGH** |
| 2 | TLS 1.0 security policy on API Gateway | TLS 1.2+ enforced by default on APIM | **HIGH** |
| 3 | CORS `*` wildcard on ImageBucket (`AllowedOrigins: *`) | Restrict to SWA endpoint URL only | **MEDIUM** |
| 4 | No WAF on API Gateway | Azure APIM with Azure Front Door WAF (optional, low cost) | **MEDIUM** |
| 5 | Static website S3 bucket with public read policy | Azure Static Web Apps — HTTPS enforced, no public bucket | **MEDIUM** |
| 6 | Lambda functions not in VPC | Azure Functions can be VNet-integrated (optional for dev) | **LOW** |
| 7 | No soft-delete on S3 | Azure Blob soft delete (7 days) enabled by default | **LOW** |
| 8 | No lifecycle policy on S3 | Azure Blob lifecycle: Hot→Cool→Archive | **LOW** |

---

## Azure Resource Naming Convention

| Resource | Name | Pattern |
|----------|------|---------|
| Resource Group | `img-upload-rg` | `{app}-{env}-rg` |
| Storage Account | `imguploadstore{uid}` | `{app}store{uniqueSuffix}` (max 24 chars, lowercase) |
| Function App | `img-upload-func-{uid}` | `{app}-func-{uniqueSuffix}` |
| App Service Plan | `img-upload-asp` | `{app}-asp` |
| API Management | `img-upload-apim` | `{app}-apim` |
| Static Web App | `img-upload-swa` | `{app}-swa` |
| Key Vault | `img-upload-kv` | `{app}-kv` |
| Log Analytics WS | `img-upload-law` | `{app}-law` |
| Application Insights | `img-upload-appins` | `{app}-appins` |
| User-Assigned MI | `img-upload-mi` | `{app}-mi` |

---

## Migration Checklist Summary

| Step | AWS Resource | Azure Target | Status |
|------|-------------|-------------|--------|
| 1 | S3 `imagebucket` | Azure Blob Storage `imguploadstore/images` | ☐ |
| 2 | S3 `websitebucket` | Azure Static Web Apps `img-upload-swa` | ☐ |
| 3 | Lambda `UploadFunction` (Python) | Azure Function `upload_function` | ☐ |
| 4 | Lambda `ListFilesFunction` (Python) | Azure Function `list_files_function` | ☐ |
| 5 | Lambda `GetViewUrlFunction` (Python) | Azure Function `get_view_url_function` | ☐ |
| 6 | Lambda `DeleteFileFunction` (Python) | Azure Function `delete_file_function` | ☐ |
| 7 | API Gateway `image-upload-api` | Azure APIM `img-upload-apim` | ☐ |
| 8 | IAM Role `LambdaExecutionRole` | System-Assigned Managed Identity + RBAC | ☐ |
| 9 | IAM User `image-upload-api-user` | Entra ID App Registration | ☐ |
| 10 | KMS Key | Azure Key Vault `img-upload-kv` | ☐ |
| 11 | CloudWatch Logs | Application Insights + Log Analytics | ☐ |
| 12 | CloudFormation stack | Bicep templates | ☐ |
| 13 | AppStream remnants | DELETE (no migration) | ☐ |

---

*Generated by: Azure Architect Agent | Source: Live AWS API discovery of account 535002891143*
